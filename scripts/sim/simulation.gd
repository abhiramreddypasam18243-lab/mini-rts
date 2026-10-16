## The deterministic match simulation (SPEC 6.2). It knows nothing about
## graphics or real time: the presentation calls step() at 20 ticks per second,
## headless tools call it as fast as they like, and both get the same result.
##
## Rules owned here: entity creation and removal, the command interface
## (validation order and result codes), orders, movement and re-planning,
## harvesting and drop-off, building placement and construction, production
## queues and spawning, the state hash.
## Every spend goes through ResourceManager.spend() (the one transaction).
## Determinism: `entities` is a Dictionary filled in increasing id order and
## GDScript dictionaries keep insertion order, so every loop over it runs in id
## order on every platform.
class_name Simulation
extends RefCounted

const REPLAY_VERSION: int = 1
## Each command and the argument that names the acting entity or entities.
const COMMAND_SUBJECT: Dictionary = {
	"move": "unit_ids",
	"harvest": "unit_ids",
	"attack": "unit_ids",
	"build": "worker_id",
	"train": "building_id",
	"cancel_train": "building_id",
}
## Which units each building trains (SPEC 4).
const TRAINS: Dictionary = {"hq": ["worker"], "barracks": ["melee", "ranged"]}
## A replacement node must be within 10 cells of the exhausted one
## (squared Euclidean distance in cells, decision D-28).
const REPLACEMENT_RADIUS_SQ: int = 100

var map: MapGrid
var seed_value: int
var config: Dictionary
var rng: SimRng
var stats: Dictionary
var tick: int = 0
var max_ticks: int
## "" while the match runs; later "victory_player", "victory_ai", "draw", "timeout".
var match_result: String = ""
## How many match results have been raised (the invariant allows at most one).
var results_raised: int = 0
## Events for the UI, appended during a tick; drained with take_events().
var events: Array[Dictionary] = []
## Every submitted command with its result, for replays (SPEC 8).
var command_log: Array[Dictionary] = []
## Entity id -> Entity, in increasing id order.
var entities: Dictionary = {}
var next_id: int = 1
## Stockpiles and the transaction.
var bank: ResourceManager
## Shortcut to bank.stock: faction -> {"wood": int, "gold": int}. Read-only for callers.
var resources: Dictionary
## Resource left in nodes at the start, per type (for the conservation check).
var initial_node_total: Dictionary = {"wood": 0, "gold": 0}
## 1 where a unit cannot stand: blocked terrain, a building or a resource node.
var solid: PackedByteArray
## Building or node id covering each cell; 0 = none.
var occupant: PackedInt32Array
## Explored cells per faction (placement needs explored cells).
var fog: Fog
var _solid_changed: bool = false


func _init(p_map: MapGrid, p_seed: int, p_config: Dictionary = {}) -> void:
	map = p_map
	seed_value = p_seed
	config = p_config
	rng = SimRng.new(p_seed)
	max_ticks = int(p_config.get("max_ticks", Consts.DEFAULT_MAX_TICKS))
	var loaded: Dictionary = UnitStats.load_file(str(p_config.get("units_path", "res://data/units.json")))
	assert(loaded.error == "", loaded.error)
	stats = loaded.stats
	var start: Dictionary = {}
	for f: String in Consts.FACTIONS:
		start[f] = {
			"wood": int(p_config.get("start_wood", Consts.START_WOOD)),
			"gold": int(p_config.get("start_gold", Consts.START_GOLD)),
		}
	bank = ResourceManager.new(start)
	resources = bank.stock
	solid = map.blocked.duplicate()
	occupant = PackedInt32Array()
	occupant.resize(map.width * map.height)
	fog = Fog.new(map.width, map.height, Consts.FACTIONS)
	fog.reveal_all()  # until build step 6 adds vision (D-29)
	for node: Dictionary in map.nodes:
		_add_node(node.type, node.cell, node.amount)
		initial_node_total[node.type] += int(node.amount)
	var workers: int = int(p_config.get("start_workers", Consts.START_WORKERS))
	for f: String in Consts.FACTIONS:
		var hq: int = place_building_unchecked("hq", f, map.starts[f], true)
		# Starting workers take the first free spawn cells, one per cell (D-27).
		for c: Vector2i in spawn_cells(entity(hq), workers):
			spawn_unit("worker", f, c)
	_solid_changed = false
	events.clear()


# --- the tick ---------------------------------------------------------------

## Advances exactly one tick (AC-01). Does nothing once the match is over.
func step() -> void:
	if match_result != "":
		return
	if _solid_changed:
		_replan_blocked_paths()
		_solid_changed = false
	for id: int in entities.keys():
		var e: Entity = entities.get(id)
		if e == null or not e.is_unit():
			continue
		if e.order_type == "move":
			if Movement.advance(e, stats[e.kind].speed):
				e.set_idle()
		elif e.order_type == "harvest":
			_tick_harvest(e)
		elif e.order_type == "build":
			_tick_build(e)
	_tick_buildings()
	tick += 1


## AC-19: a unit whose remaining path crosses a newly solid cell re-plans; if
## no route is left it stops, goes idle and raises `no_path` once.
func _replan_blocked_paths() -> void:
	for id: int in entities:
		var e: Entity = entities[id]
		if not e.is_unit() or not Movement.path_blocked(e, solid, map.width):
			continue
		if e.order_type == "move":
			if not _set_path(e, e.order_cell):
				e.set_idle()
				_message(e.faction, "no_path", e.id)
		elif e.order_type == "harvest" and e.phase == "to_node":
			_start_to_node(e)
		elif e.order_type == "harvest" and e.phase == "to_dropoff":
			_start_dropoff(e)
		elif e.order_type == "build" and e.phase == "to_site":
			_assign_builder(e, entity(e.order_target))


# --- harvesting (SPEC 5.3) --------------------------------------------------

## One tick of a harvest order. A worker walks to a cell touching the node,
## gathers for 40 ticks, takes up to 10, walks to the nearest friendly HQ by
## path length, deposits on arrival, and goes back. Phase changes happen in
## the same tick (arrive and start gathering; fill up and deposit if the HQ
## is already next to it), so a trip next to both takes 40 ticks (AC-29).
func _tick_harvest(e: Entity) -> void:
	var speed: int = stats[e.kind].speed
	for change: int in 3:
		match e.phase:
			"to_node":
				if not Movement.advance(e, speed):
					return
				var node: Entity = entity(e.order_target)
				if node == null or node.chebyshev_to(e.unit_cell()) != 1:
					_start_to_node(e)
					return
				e.phase = "gathering"
				e.timer = 0
				e.path.clear()
				e.path_i = 0
			"gathering":
				e.timer += 1
				if e.timer < Consts.HARVEST_TICKS:
					return
				var node: Entity = entity(e.order_target)
				var take: int = mini(Consts.CARRY_CAPACITY, node.amount)
				node.amount -= take
				e.carry += take
				e.carry_type = node.kind
				e.timer = 0
				bank.record_removed(e.faction, node.kind, take)
				# Switch phase before a possible removal, so the removal treats
				# this worker as walking home with its load.
				e.phase = "to_dropoff"
				if node.amount == 0:
					destroy_entity(node.id)
				if not _start_dropoff(e):
					return
			"to_dropoff":
				if not Movement.advance(e, speed):
					return
				var hq: Entity = entity(e.dropoff_id)
				if hq == null or hq.chebyshev_to(e.unit_cell()) != 1:
					_start_dropoff(e)
					return
				bank.deposit(e.faction, e.carry_type, e.carry)
				events.append({"type": "deposit", "tick": tick, "entity_id": e.id, "faction": e.faction, "resource": e.carry_type, "amount": e.carry})
				e.carry = 0
				e.carry_type = ""
				e.dropoff_id = 0
				if entity(e.order_target) == null and not _find_replacement(e):
					e.set_idle()
					_message(e.faction, "no_node", e.id)
					return
				if not _start_to_node(e):
					return
			_:
				return


## Heads for a cell touching the harvested node. False (and idle) if unreachable.
func _start_to_node(e: Entity) -> bool:
	var node: Entity = entity(e.order_target)
	var r: Dictionary = Pathfinder.find_path_to_any(map.width, map.height, solid, e.unit_cell(), _touching_mask([node], solid))
	if (r.path as Array).is_empty():
		e.set_idle()
		_message(e.faction, "no_path", e.id)
		return false
	e.phase = "to_node"
	e.timer = 0
	e.path = r.path
	e.path_i = Movement.start_index(e)
	return true


## Heads for the nearest friendly HQ by path length. If there is none, the
## worker goes idle holding its load (`no_dropoff`, AC-31).
func _start_dropoff(e: Entity) -> bool:
	var hqs: Array[Entity] = []
	for id: int in entities:
		var b: Entity = entities[id]
		if b.kind == "hq" and b.faction == e.faction and b.complete:
			hqs.append(b)
	var r: Dictionary = {"path": []}
	if not hqs.is_empty():
		r = Pathfinder.find_path_to_any(map.width, map.height, solid, e.unit_cell(), _touching_mask(hqs, solid))
	if (r.path as Array).is_empty():
		e.set_idle()
		_message(e.faction, "no_dropoff" if hqs.is_empty() else "no_path", e.id)
		return false
	e.phase = "to_dropoff"
	e.path = r.path
	e.path_i = Movement.start_index(e)
	e.dropoff_id = building_adjacent_to(e.path[e.path.size() - 1], e.faction)
	return true


## Nearest node of the same type within 10 cells of the exhausted one
## (ties: lowest id). Sets it as the new target; false if none.
func _find_replacement(e: Entity) -> bool:
	var best: Entity = null
	var best_d: int = REPLACEMENT_RADIUS_SQ + 1
	for id: int in entities:
		var n: Entity = entities[id]
		if n.kind != e.harvest_type:
			continue
		var d: Vector2i = n.cell - e.harvest_cell
		var dsq: int = d.x * d.x + d.y * d.y
		if dsq < best_d:
			best = n
			best_d = dsq
	if best == null:
		e.order_target = 0
		return false
	e.order_target = best.id
	e.harvest_cell = best.cell
	return true


## Mask of cells touching (8-neighbour) any of the given footprints that are
## free in `grid`.
func _touching_mask(targets: Array, grid: PackedByteArray) -> PackedByteArray:
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(map.width * map.height)
	for t: Entity in targets:
		_mark_touching(mask, t.cell, t.size, grid)
	return mask


func _mark_touching(mask: PackedByteArray, anchor: Vector2i, size: Vector2i, grid: PackedByteArray) -> void:
	for y: int in range(anchor.y - 1, anchor.y + size.y + 1):
		for x: int in range(anchor.x - 1, anchor.x + size.x + 1):
			if map.in_bounds(Vector2i(x, y)) and grid[y * map.width + x] == 0:
				mask[y * map.width + x] = 1


# --- construction and production (SPEC 5.4) -------------------------------

## Whether `faction` may place a `kind` building at `anchor`, as a result code.
## Every footprint cell must be inside the map, on walkable terrain, free of
## buildings, nodes and units, and explored by the faction; then the cost must
## be affordable. Changes nothing (the UI also uses it for the ghost preview).
func placement_check(faction: String, kind: String, anchor: Vector2i) -> String:
	var size: Vector2i = stats[kind].footprint
	var cells: Array[Vector2i] = MapGenerator.footprint(anchor, size.x, size.y)
	for c: Vector2i in cells:
		if not map.in_bounds(c) or not map.is_walkable(c) or solid[c.y * map.width + c.x] == 1:
			return "invalid_placement"
	for id: int in entities:
		var u: Entity = entities[id]
		if u.is_unit() and cells.has(u.unit_cell()):
			return "invalid_placement"
	for c: Vector2i in cells:
		if not fog.is_explored(faction, c):
			return "not_explored"
	return bank.check(faction, {"wood": stats[kind].wood, "gold": stats[kind].gold})


## Sends a worker to build or resume `b`. False (and idle) if it cannot reach it.
func _assign_builder(w: Entity, b: Entity) -> bool:
	w.set_idle()
	var r: Dictionary = Pathfinder.find_path_to_any(map.width, map.height, solid, w.unit_cell(), _touching_mask([b], solid))
	if (r.path as Array).is_empty():
		_message(w.faction, "no_path", w.id)
		return false
	w.order_type = "build"
	w.order_target = b.id
	w.phase = "to_site"
	w.path = r.path
	w.path_i = Movement.start_index(w)
	return true


## A builder walks to a cell touching its building, then stays "building".
func _tick_build(e: Entity) -> void:
	if e.phase != "to_site" or not Movement.advance(e, stats[e.kind].speed):
		return
	var b: Entity = entity(e.order_target)
	if b.chebyshev_to(e.unit_cell()) != 1:
		_assign_builder(e, b)
		return
	e.phase = "building"
	e.path.clear()
	e.path_i = 0


## Runs after the units each tick, in id order:
## - an unfinished building gains 1 progress if a builder is beside it, and
##   completes at its build time (its builders are released);
## - a finished building counts down the first item of its queue and spawns it
##   at 0, in the first free spawn cell; with none free the item waits as
##   `spawn_blocked` (one message) and spawns on the first tick a cell frees.
func _tick_buildings() -> void:
	for id: int in entities.keys():
		var b: Entity = entities.get(id)
		if b == null or not b.is_building():
			continue
		if not b.complete:
			var builders: Array[Entity] = _builders_of(b)
			if builders.is_empty():
				continue
			b.progress += 1
			if b.progress >= stats[b.kind].build_time:
				b.complete = true
				for w: Entity in builders:
					w.set_idle()
				events.append({"type": "completed", "tick": tick, "entity_id": b.id, "faction": b.faction})
			continue
		if b.queue.is_empty():
			continue
		var item: Dictionary = b.queue[0]
		if item.remaining > 0:
			item.remaining -= 1
		if item.remaining > 0:
			continue
		var cells: Array[Vector2i] = spawn_cells(b, 1)
		if cells.is_empty():
			if item.status != "spawn_blocked":
				item.status = "spawn_blocked"
				_message(b.faction, "spawn_blocked", b.id)
			continue
		b.queue.remove_at(0)
		var u: int = spawn_unit(item.type, b.faction, cells[0])
		events.append({"type": "trained", "tick": tick, "entity_id": u, "building_id": b.id, "faction": b.faction})


func _builders_of(b: Entity) -> Array[Entity]:
	var out: Array[Entity] = []
	for id: int in entities:
		var w: Entity = entities[id]
		if w.order_type == "build" and w.order_target == b.id and w.phase == "building":
			out.append(w)
	return out


# --- commands ---------------------------------------------------------------

## Validates and applies a command; returns a result code (SPEC 6.2).
## Command: {"faction": String, "command": String, "args": Dictionary}.
func submit(cmd: Dictionary) -> String:
	var result: String = _apply(cmd)
	command_log.append({
		"tick": tick,
		"faction": cmd.get("faction", ""),
		"command": cmd.get("command", ""),
		"args": cmd.get("args", {}),
		"result": result,
	})
	return result


## Checks run in a fixed order, and nothing changes until all have passed:
## match_over, unknown command, unknown_entity, not_owner, invalid_amount,
## then the command's own rules (decision D-27).
func _apply(cmd: Dictionary) -> String:
	if match_result != "":
		return "match_over"
	var name: String = str(cmd.get("command", ""))
	var faction: String = str(cmd.get("faction", ""))
	if not COMMAND_SUBJECT.has(name) or typeof(cmd.get("args")) != TYPE_DICTIONARY:
		return "invalid_target"
	var args: Dictionary = cmd.args
	var ids: Array[int] = _subject_ids(args.get(COMMAND_SUBJECT[name]))
	if ids.is_empty():
		return "unknown_entity"
	for id: int in ids:
		if not entities.has(id):
			return "unknown_entity"
	for id: int in ids:
		if (entities[id] as Entity).faction != faction:
			return "not_owner"
	if name == "cancel_train" and (not JsonUtil.is_whole(args.get("index")) or int(args.index) < 0):
		return "invalid_amount"
	match name:
		"move":
			return _cmd_move(ids, args.get("cell"))
		"harvest":
			return _cmd_harvest(ids, args.get("node_id"))
		"build":
			return _cmd_build(entities[ids[0]], str(args.get("building_type", "")), args.get("cell"))
		"train":
			return _cmd_train(entities[ids[0]], str(args.get("unit_type", "")))
		"cancel_train":
			return _cmd_cancel_train(entities[ids[0]], int(args.index))
	# attack arrives in build step 5.
	return "invalid_target"


## The acting ids, de-duplicated in their given order; [] if malformed.
func _subject_ids(raw: Variant) -> Array[int]:
	var out: Array[int] = []
	var list: Array = raw if typeof(raw) == TYPE_ARRAY else [raw]
	for v: Variant in list:
		if not JsonUtil.is_whole(v):
			return []
		if not out.has(int(v)):
			out.append(int(v))
	return out


func _cmd_move(ids: Array[int], raw_cell: Variant) -> String:
	var cell: Variant = JsonUtil.to_cell(raw_cell)
	if cell == null:
		return "invalid_target"
	for id: int in ids:
		if not (entities[id] as Entity).is_unit():
			return "invalid_target"
	var any_ok: bool = false
	for id: int in ids:
		var e: Entity = entities[id]
		if _set_path(e, cell):
			e.order_type = "move"
			e.order_target = 0
			e.order_cell = cell
			e.phase = ""
			e.timer = 0
			e.dropoff_id = 0
			any_ok = true
		else:
			e.set_idle()
			_message(e.faction, "no_path", e.id)
	return "ok" if any_ok else "no_path"


func _cmd_harvest(ids: Array[int], raw_node: Variant) -> String:
	if not JsonUtil.is_whole(raw_node):
		return "invalid_target"
	var node: Entity = entity(int(raw_node))
	if node == null:
		return "unknown_entity"
	if not node.is_node():
		return "invalid_target"
	for id: int in ids:
		if (entities[id] as Entity).kind != "worker":
			return "invalid_target"
	var any_ok: bool = false
	for id: int in ids:
		var e: Entity = entities[id]
		e.set_idle()
		e.order_type = "harvest"
		e.order_target = node.id
		e.harvest_type = node.kind
		e.harvest_cell = node.cell
		# A worker that is still carrying something deposits it first (AC-34).
		var ok: bool = _start_dropoff(e) if e.carry > 0 else _start_to_node(e)
		any_ok = any_ok or ok
	return "ok" if any_ok else "no_path"


## Build: place a building under construction and send the worker to it.
## The cost is paid once, at placement, through the one transaction (D-06).
## `build` on the anchor of one's own unfinished building of that type
## resumes it at no cost (decision D-29).
func _cmd_build(w: Entity, kind: String, raw_cell: Variant) -> String:
	if w.kind != "worker" or kind != "barracks":
		return "invalid_target"
	var cell: Variant = JsonUtil.to_cell(raw_cell)
	if cell == null:
		return "invalid_target"
	var existing: Entity = entity(occupant_at(cell))
	if existing != null and existing.kind == kind and existing.faction == w.faction \
			and existing.cell == cell and not existing.complete:
		return "ok" if _assign_builder(w, existing) else "no_path"
	var check: String = placement_check(w.faction, kind, cell)
	if check != "ok":
		return check
	# The builder must be able to reach the site once its footprint is solid.
	var size: Vector2i = stats[kind].footprint
	var trial: PackedByteArray = solid.duplicate()
	for c: Vector2i in MapGenerator.footprint(cell, size.x, size.y):
		trial[c.y * map.width + c.x] = 1
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(map.width * map.height)
	_mark_touching(mask, cell, size, trial)
	if (Pathfinder.find_path_to_any(map.width, map.height, trial, w.unit_cell(), mask).path as Array).is_empty():
		return "no_path"
	var paid: String = bank.spend(w.faction, {"wood": stats[kind].wood, "gold": stats[kind].gold})
	if paid != "ok":
		return paid
	var b: int = place_building_unchecked(kind, w.faction, cell, false)
	_assign_builder(w, entity(b))
	return "ok"


## Training: the cost is paid at enqueue through the one transaction (D-06).
func _cmd_train(b: Entity, unit_type: String) -> String:
	if not b.is_building():
		return "invalid_target"
	if not unit_type in TRAINS[b.kind]:
		return "invalid_unit_for_building"
	if not b.complete:
		return "not_ready"
	if b.queue.size() >= Consts.QUEUE_CAPACITY:
		return "queue_full"
	if population(b.faction) >= Consts.POPULATION_CAP:
		return "population_cap"
	var cost: Dictionary = {"wood": stats[unit_type].wood, "gold": stats[unit_type].gold}
	var paid: String = bank.spend(b.faction, cost)
	if paid != "ok":
		return paid
	b.queue.append({"type": unit_type, "remaining": stats[unit_type].build_time, "cost": cost, "status": ""})
	return "ok"


## Cancelling removes the item and refunds its full cost. The item is gone
## afterwards, so the same item can never be refunded twice (AC-33).
func _cmd_cancel_train(b: Entity, index: int) -> String:
	if not b.is_building() or index >= b.queue.size():
		return "invalid_target"
	var item: Dictionary = b.queue[index]
	b.queue.remove_at(index)
	bank.refund(b.faction, item.cost)
	return "ok"


## Plans a path from the unit's cell to `goal` and starts it. False if none.
func _set_path(e: Entity, goal: Vector2i) -> bool:
	var r: Dictionary = Pathfinder.find_path(map.width, map.height, solid, e.unit_cell(), goal)
	if (r.path as Array).is_empty():
		return false
	e.path = r.path
	e.path_i = Movement.start_index(e)
	return true


# --- entity creation and removal (internal: setup, production, combat, tests) -

func spawn_unit(kind: String, faction: String, cell: Vector2i) -> int:
	var e: Entity = Entity.new(next_id, kind, faction)
	e.pos = MapGrid.cell_center(cell)
	e.hp = stats[kind].health
	return _register(e)


## Places a building without any placement checks; the build command checks
## first (build step 4). Its footprint becomes solid from this tick.
func place_building_unchecked(kind: String, faction: String, anchor: Vector2i, is_complete: bool) -> int:
	var e: Entity = Entity.new(next_id, kind, faction)
	e.cell = anchor
	e.size = stats[kind].footprint
	e.hp = stats[kind].health
	e.complete = is_complete
	for c: Vector2i in e.footprint():
		solid[c.y * map.width + c.x] = 1
		occupant[c.y * map.width + c.x] = e.id
	_solid_changed = true
	return _register(e)


func _add_node(type: String, cell: Vector2i, amount: int) -> int:
	var e: Entity = Entity.new(next_id, type, "")
	e.cell = cell
	e.amount = amount
	solid[cell.y * map.width + cell.x] = 1
	occupant[cell.y * map.width + cell.x] = e.id
	return _register(e)


func _register(e: Entity) -> int:
	entities[e.id] = e
	next_id += 1
	events.append({"type": "created", "tick": tick, "entity_id": e.id})
	return e.id


## Removes an entity at once and clears every reference to it: its footprint
## becomes walkable, workers bound for it find another node or HQ, and other
## orders on it end (the unit goes idle).
func destroy_entity(id: int) -> void:
	var dead: Entity = entity(id)
	if dead == null:
		return
	entities.erase(id)
	if dead.is_building() or dead.is_node():
		for c: Vector2i in dead.footprint():
			var i: int = c.y * map.width + c.x
			occupant[i] = 0
			solid[i] = map.blocked[i]
	events.append({"type": "destroyed", "tick": tick, "entity_id": id, "kind": dead.kind, "faction": dead.faction})
	for oid: int in entities:
		var e: Entity = entities[oid]
		if not e.is_unit():
			continue
		if e.dropoff_id == id:
			e.dropoff_id = 0
			if e.phase == "to_dropoff":
				_start_dropoff(e)
		if e.order_target != id:
			continue
		if e.order_type == "harvest":
			if _find_replacement(e):
				if e.phase != "to_dropoff":
					_start_to_node(e)
			elif e.phase != "to_dropoff":
				# A worker walking home keeps going and goes idle after depositing.
				e.set_idle()
				_message(e.faction, "no_node", e.id)
		else:
			e.set_idle()


## Spawn cells around a building (SPEC 5.4): rings at distance 1, 2, 3 around
## the footprint, each scanned in row-major order; a cell qualifies if it is
## inside the map and not solid. Returns at most `count` cells.
func spawn_cells(b: Entity, count: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d: int in range(1, 4):
		for y: int in range(b.cell.y - d, b.cell.y + b.size.y + d):
			for x: int in range(b.cell.x - d, b.cell.x + b.size.x + d):
				var on_ring: bool = y == b.cell.y - d or y == b.cell.y + b.size.y - 1 + d \
					or x == b.cell.x - d or x == b.cell.x + b.size.x - 1 + d
				if out.size() < count and on_ring and not is_solid(Vector2i(x, y)):
					out.append(Vector2i(x, y))
	return out


# --- queries ----------------------------------------------------------------

func entity(id: int) -> Entity:
	return entities.get(id)


func is_solid(cell: Vector2i) -> bool:
	return not map.in_bounds(cell) or solid[cell.y * map.width + cell.x] == 1


func unit_ids() -> Array[int]:
	var out: Array[int] = []
	for id: int in entities:
		if (entities[id] as Entity).is_unit():
			out.append(id)
	return out


func hq_of(faction: String) -> int:
	for id: int in entities:
		var e: Entity = entities[id]
		if e.kind == "hq" and e.faction == faction:
			return id
	return 0


## The building or node covering a cell, or 0.
func occupant_at(cell: Vector2i) -> int:
	return occupant[cell.y * map.width + cell.x] if map.in_bounds(cell) else 0


## The resource node on a cell, or 0.
func node_at(cell: Vector2i) -> int:
	if not map.in_bounds(cell):
		return 0
	var id: int = occupant[cell.y * map.width + cell.x]
	return id if id != 0 and (entities[id] as Entity).is_node() else 0


## The lowest-id friendly HQ touching `cell` (diagonals included), or 0.
func building_adjacent_to(cell: Vector2i, faction: String) -> int:
	for id: int in entities:
		var b: Entity = entities[id]
		if b.kind == "hq" and b.faction == faction and b.chebyshev_to(cell) == 1:
			return id
	return 0


## Units alive plus units queued (SPEC 4: the cap counts queued units).
func population(faction: String) -> int:
	var n: int = 0
	for id: int in entities:
		var e: Entity = entities[id]
		if e.faction != faction:
			continue
		if e.is_unit():
			n += 1
		elif e.is_building():
			n += e.queue.size()
	return n


## Returns the events raised since the last call and clears the list.
func take_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = events
	events = []
	return out


func _message(faction: String, code: String, entity_id: int) -> void:
	events.append({"type": "message", "tick": tick, "faction": faction, "code": code, "entity_id": entity_id})


# --- hashing and replays ----------------------------------------------------

## A hash of the whole simulation state, for determinism tests (AC-01, AC-03).
func state_hash() -> int:
	var h: StateHasher = StateHasher.new()
	h.add_int(tick)
	h.add_int(max_ticks)
	h.add_int(rng.state)
	h.add_string(match_result)
	h.add_int(results_raised)
	h.add_int(next_id)
	bank.add_to_hash(h)
	map.add_to_hash(h)
	h.add_bytes(solid)
	fog.add_to_hash(h)
	for id: int in entities:
		(entities[id] as Entity).add_to_hash(h)
	return h.h


func replay_header() -> Dictionary:
	return {
		"version": REPLAY_VERSION,
		"seed": seed_value,
		"map": map.map_name,
		"ai_configs": config.get("ai_configs", {}),
		"max_ticks": max_ticks,
	}
