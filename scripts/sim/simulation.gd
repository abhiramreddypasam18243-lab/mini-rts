## The deterministic match simulation (SPEC 6.2). It knows nothing about
## graphics or real time: the presentation calls step() at 20 ticks per second,
## headless tools call it as fast as they like, and both get the same result.
##
## Rules owned here: entity creation and removal, the command interface
## (validation order and result codes), orders, movement and re-planning,
## harvesting and drop-off, building placement and construction, production
## queues and spawning, combat and removal of the dead, the end of the match,
## fog of war and each faction's observation, the state hash.
##
## One tick, in this order (decision D-30):
##   re-plan blocked paths -> auto-acquire -> combat (judged on the state at
##   the start of the tick) -> unit orders and movement -> construction and
##   production -> remove the dead -> end-of-match check -> tick + 1
##   -> fog recomputed when the new tick is a multiple of 5 (decision D-31).
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
	"attack_move": "unit_ids",
	"build": "worker_id",
	"train": "building_id",
	"cancel_train": "building_id",
	"research": "building_id",
}
## Orders that may be queued with "queue": true (D-44), and how many.
const QUEUEABLE: Array[String] = ["move", "attack_move", "attack", "harvest"]
const MAX_ORDERS: int = 8
const NO_CELL: Vector2i = Vector2i(-1, -1)
## Which units each building trains (SPEC 4).
const TRAINS: Dictionary = {"hq": ["worker"], "barracks": ["melee", "ranged"], "farm": [], "tower": [], "stable": ["cavalry"]}
## Buildings a worker may build (D-51 adds farm, tower and stable).
const BUILDABLE: Array[String] = ["barracks", "farm", "tower", "stable"]
## A replacement node must be within 10 cells of the exhausted one
## (squared Euclidean distance in cells, decision D-28).
const REPLACEMENT_RADIUS_SQ: int = 100
## Fog of war is recomputed every this many ticks (SPEC 5.6: at least every 5).
const FOG_INTERVAL: int = 5

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
## AI commands rejected for naming an entity outside their observation (SPEC 7.2).
var firewall_violations: int = 0
## Events for the UI, appended during a tick; drained with take_events().
var events: Array[Dictionary] = []
## Every submitted command with its result, for replays (SPEC 8).
var command_log: Array[Dictionary] = []
## Entity id -> Entity, in increasing id order.
var entities: Dictionary = {}
var next_id: int = 1
## Stockpiles and the transaction.
var bank: ResourceManager
## Shortcut to bank.stock: faction -> {"wood": int, "gold": int, "food": int}. Read-only for callers.
var resources: Dictionary
## Resource left in nodes at the start, per type (for the conservation check).
var initial_node_total: Dictionary = {"wood": 0, "gold": 0, "food": 0}
## Food put into finished farms, and food lost when a farm is destroyed
## before it is empty (D-51; for the conservation check).
var node_added: Dictionary = {"wood": 0, "gold": 0, "food": 0}
var node_razed: Dictionary = {"wood": 0, "gold": 0, "food": 0}
## Faction -> {upgrade name -> true} once researched (D-51).
var upgrades: Dictionary = {"player": {}, "ai": {}}
## 1 where a unit cannot stand: blocked terrain, a building or a resource node.
var solid: PackedByteArray
## Building or node id covering each cell; 0 = none.
var occupant: PackedInt32Array
## Fog of war and remembered buildings and nodes, per faction.
var fog: Fog
## Tick of the last full fog recompute.
var fog_tick: int = 0
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
			"food": int(p_config.get("start_food", Consts.START_FOOD)),
		}
	bank = ResourceManager.new(start)
	resources = bank.stock
	solid = map.blocked.duplicate()
	occupant = PackedInt32Array()
	occupant.resize(map.width * map.height)
	fog = Fog.new(map.width, map.height, Consts.FACTIONS)
	for node: Dictionary in map.nodes:
		_add_node(node.type, node.cell, node.amount)
		initial_node_total[node.type] += int(node.amount)
	var workers: int = int(p_config.get("start_workers", Consts.START_WORKERS))
	for f: String in Consts.FACTIONS:
		var hq: int = place_building_unchecked("hq", f, map.starts[f], true)
		# Starting workers take the first free spawn cells, one per cell (D-27).
		for c: Vector2i in spawn_cells(entity(hq), workers):
			spawn_unit("worker", f, c)
	update_fog()
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
	_run_orders()
	_auto_acquire()
	_resolve_combat()
	for id: int in entities.keys():
		var e: Entity = entities.get(id)
		if e == null or not e.is_unit():
			continue
		var before: Vector2i = e.pos
		_tick_unit(e)
		# Cavalry builds up a charge while it moves (D-57).
		if e.kind == "cavalry" and entities.has(id):
			var d: Vector2i = e.pos - before
			e.charge = mini(e.charge + absi(d.x) + absi(d.y), Consts.CHARGE_DIST)
	if tick % Spacing.INTERVAL == 0:
		Spacing.step_aside(self)
	_tick_buildings()
	_remove_dead()
	_check_match_end()
	tick += 1
	if match_result == "" and tick >= max_ticks:
		_end_match("timeout")
	if tick % FOG_INTERVAL == 0:
		update_fog()


## One unit's order for this tick.
func _tick_unit(e: Entity) -> void:
	if e.order_type == "move" or e.order_type == "attack_move":
		if Movement.advance(e, stats[e.kind].speed):
			e.set_idle()
			e.am_cell = NO_CELL  # an attack-move that arrived is over
	elif e.order_type == "harvest":
		_tick_harvest(e)
	elif e.order_type == "build":
		_tick_build(e)
	elif e.order_type == "attack":
		_tick_attack(e)


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
		elif e.order_type == "attack":
			e.path.clear()  # re-planned on its next move
			e.path_i = 0


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
				e.carry_type = node.resource()
				e.timer = 0
				bank.record_removed(e.faction, node.resource(), take)
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
## (ties: lowest id); for a farm, the faction's own finished farms only.
## Sets it as the new target; false if none.
func _find_replacement(e: Entity) -> bool:
	var best: Entity = null
	var best_d: int = REPLACEMENT_RADIUS_SQ + 1
	for id: int in entities:
		var n: Entity = entities[id]
		if n.kind != e.harvest_type or not n.is_harvestable() or n.is_building() and n.faction != e.faction:
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
	return bank.check(faction, cost_of(kind))


## What an entity costs. Food appears only when it is not 0, so the costs of
## the original entities keep their two-resource shape (D-51).
func cost_of(kind: String) -> Dictionary:
	var c: Dictionary = {"wood": stats[kind].wood, "gold": stats[kind].gold}
	if stats[kind].food > 0:
		c["food"] = stats[kind].food
	return c


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
				_on_complete(b)
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
		if Consts.UPGRADES.has(item.type):
			_finish_research(b, item)
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


## A finished farm is filled with food; a tower aims from its centre (D-51).
func _on_complete(b: Entity) -> void:
	if b.kind == "farm":
		b.amount = Consts.FARM_FOOD
		node_added.food += Consts.FARM_FOOD
	elif b.kind == "tower":
		b.pos = MapGrid.cell_center(b.cell)


## A research item finishes (D-51): the upgrade is the faction's from now on.
func _finish_research(b: Entity, item: Dictionary) -> void:
	b.queue.remove_at(0)
	upgrades[b.faction][item.type] = true
	events.append({"type": "researched", "tick": tick, "building_id": b.id, "faction": b.faction, "upgrade": item.type})


func _builders_of(b: Entity) -> Array[Entity]:
	var out: Array[Entity] = []
	for id: int in entities:
		var w: Entity = entities[id]
		if w.order_type == "build" and w.order_target == b.id and w.phase == "building":
			out.append(w)
	return out


# --- combat (SPEC 5.5) ------------------------------------------------------

## Idle soldiers attack the nearest enemy unit or building within their own
## vision (ties: lowest id). An auto-acquired attack ends when the target
## leaves that vision (or dies: destroy_entity clears the order).
func _auto_acquire() -> void:
	for id: int in entities:
		var e: Entity = entities[id]
		if e.kind == "tower":
			_tower_acquire(e)
			continue
		if not e.is_soldier():
			continue
		if e.order_type == "attack" and e.auto and not _in_vision(e, entity(e.order_target)):
			e.set_idle()
		# Idle soldiers, and soldiers on an attack-move (D-44), look for enemies.
		if e.order_type != "idle" and e.order_type != "attack_move":
			continue
		var best: Entity = null
		var best_d: int = 0
		for tid: int in entities:
			var t: Entity = entities[tid]
			if t.faction == e.faction or t.is_node() or not _in_vision(e, t):
				continue
			var d: int = _cell_dist_sq(e.unit_cell(), t)
			if best == null or d < best_d:
				best = t
				best_d = d
		if best != null:
			_start_attack(e, best, true)


## A finished guard tower keeps its target while it stays in range, else
## takes the nearest enemy unit in range (ties: lowest id; D-51).
func _tower_acquire(e: Entity) -> void:
	if not e.complete:
		return
	var cur: Entity = entity(e.order_target)
	if cur != null and _in_range(e, cur):
		return
	e.order_type = "idle"
	e.order_target = 0
	var best: Entity = null
	var best_d: int = 0
	for tid: int in entities:
		var t: Entity = entities[tid]
		if not t.is_unit() or t.faction == e.faction or not _in_range(e, t):
			continue
		var d: Vector2i = t.pos - e.pos
		var dsq: int = d.x * d.x + d.y * d.y
		if best == null or dsq < best_d:
			best = t
			best_d = dsq
	if best != null:
		e.order_type = "attack"
		e.order_target = best.id


## Squared distance in cells from `c` to the nearest cell of t's footprint.
func _cell_dist_sq(c: Vector2i, t: Entity) -> int:
	var near: Vector2i = t.unit_cell() if t.is_unit() else Vector2i(
		clampi(c.x, t.cell.x, t.cell.x + t.size.x - 1), clampi(c.y, t.cell.y, t.cell.y + t.size.y - 1))
	var d: Vector2i = near - c
	return d.x * d.x + d.y * d.y


func _in_vision(e: Entity, t: Entity) -> bool:
	var v: int = stats[e.kind].vision
	return t != null and _cell_dist_sq(e.unit_cell(), t) <= v * v


## In attack range: distance from the attacker's position to the nearest cell
## centre of the target's footprint, compared as squared integers.
func _in_range(a: Entity, t: Entity) -> bool:
	return in_range_at(a, t, a.pos)


## As _in_range, with the attacker standing at `p` (milli-cells).
func in_range_at(a: Entity, t: Entity, p: Vector2i) -> bool:
	var r: int = stats[a.kind].range
	var cells: Array[Vector2i] = t.footprint()
	if t.is_unit():
		cells = [t.unit_cell()]
	for c: Vector2i in cells:
		var d: Vector2i = MapGrid.cell_center(c) - p
		if d.x * d.x + d.y * d.y <= r * r:
			return true
	return false


func _start_attack(e: Entity, t: Entity, is_auto: bool) -> void:
	e.set_idle()
	e.order_type = "attack"
	e.order_target = t.id
	e.auto = is_auto


## Every soldier whose cooldown has run out and whose target is in range at
## the start of the tick attacks, in id order. Damage is applied after all
## attackers are chosen, so two soldiers can kill each other (AC-46). A target
## already at 0 health this tick takes no more hits, and a hit that does not
## land does not use up the attacker's cooldown (AC-45).
func _resolve_combat() -> void:
	var hits: Array[Array] = []
	for id: int in entities:
		var e: Entity = entities[id]
		if not e.is_soldier() and not (e.kind == "tower" and e.complete):
			continue
		if e.cooldown > 0:
			e.cooldown -= 1
		if e.order_type != "attack" or e.cooldown > 0:
			continue
		var t: Entity = entity(e.order_target)
		if t != null and _in_range(e, t):
			hits.append([e, t])
	for h: Array in hits:
		var a: Entity = h[0]
		var t: Entity = h[1]
		if t.hp <= 0:
			continue
		var dmg: int = hit_damage(stats[a.kind].damage, a.is_soldier() and has_upgrade(a.faction, "forging"),
			t.is_soldier() and has_upgrade(t.faction, "armour"))
		# A full charge doubles a cavalry hit (D-57); any hit spends it.
		var charged: bool = a.kind == "cavalry" and a.charge >= Consts.CHARGE_DIST
		if charged:
			dmg *= 2
		a.charge = 0
		t.hp -= dmg
		a.cooldown = stats[a.kind].cooldown
		events.append({"type": "attack", "tick": tick, "attacker": a.id, "target": t.id, "damage": dmg, "charge": charged})


## Damage of one hit (D-51): Forging adds 2, Armour takes 2 off, at least 1.
static func hit_damage(base: int, forged: bool, armoured: bool) -> int:
	var d: int = base + (Consts.UPGRADE_BONUS if forged else 0) - (Consts.UPGRADE_BONUS if armoured else 0)
	return maxi(d, 1)


func has_upgrade(faction: String, upgrade: String) -> bool:
	return upgrades.has(faction) and (upgrades[faction] as Dictionary).has(upgrade)


## Movement for an attack order: stand still while in range, otherwise walk
## towards the target, re-planning when a unit target changes cell.
func _tick_attack(e: Entity) -> void:
	var t: Entity = entity(e.order_target)
	if t == null:
		e.set_idle()
		return
	if e.stepping:
		# Stepping aside (D-42): finish the step, still attacking meanwhile.
		if Movement.advance(e, stats[e.kind].speed):
			e.stepping = false
			e.path.clear()
			e.path_i = 0
		return
	if _in_range(e, t):
		e.path.clear()
		e.path_i = 0
		return
	# A melee soldier heads for a free cell next to a unit target (D-42);
	# it re-plans when the target moves to another cell.
	var tc: Vector2i = t.unit_cell() if t.is_unit() else t.cell
	if e.path.is_empty() or e.path_i >= e.path.size() or e.target_cell != tc:
		var ok: bool
		var goal: Vector2i = tc
		if t.is_unit():
			if e.is_melee():
				goal = Spacing.melee_slot(self, e, t)
			ok = _set_path(e, goal) or (goal != tc and _set_path(e, tc))
		else:
			# A building: walk to a touching cell no other unit holds, if any.
			var mask: PackedByteArray = _touching_mask([t], solid)
			var free_mask: PackedByteArray = mask.duplicate()
			var held: Dictionary = Spacing.held_cells(self, {e.id: true})
			var any_free: bool = false
			for c: Vector2i in held:
				if map.in_bounds(c):
					free_mask[c.y * map.width + c.x] = 0
			for v: int in free_mask:
				if v == 1:
					any_free = true
					break
			var r: Dictionary = Pathfinder.find_path_to_any(map.width, map.height, solid, e.unit_cell(), free_mask if any_free else mask)
			ok = not (r.path as Array).is_empty()
			if ok:
				e.path = r.path
				e.path_i = Movement.start_index(e)
		if not ok:
			e.set_idle()
			_message(e.faction, "no_path", e.id)
			return
		e.order_cell = goal
		e.target_cell = tc
	Movement.advance(e, stats[e.kind].speed)


func _cmd_attack(ids: Array[int], raw_target: Variant) -> String:
	if not JsonUtil.is_whole(raw_target):
		return "invalid_target"
	var t: Entity = entity(int(raw_target))
	if t == null:
		return "unknown_entity"
	for id: int in ids:
		if not (entities[id] as Entity).is_soldier():
			return "invalid_target"
	var faction: String = (entities[ids[0]] as Entity).faction
	if t.is_node() or t.faction == faction:
		return "invalid_target"
	if not fog.any_visible(faction, t.unit_cell() if t.is_unit() else t.cell, t.size):
		return "target_not_visible"
	for id: int in ids:
		_start_attack(entities[id], t, false)
	return "ok"


## Deaths are removed at the end of the tick, in id order.
func _remove_dead() -> void:
	var dead: Array[int] = []
	for id: int in entities:
		var e: Entity = entities[id]
		if (e.is_unit() or e.is_building()) and e.hp <= 0:
			dead.append(id)
	for id: int in dead:
		destroy_entity(id)


## A faction is defeated when it has no HQ left; both at once is a draw (SPEC 5.7).
func _check_match_end() -> void:
	var has_hq: Dictionary = {"player": false, "ai": false}
	for id: int in entities:
		var e: Entity = entities[id]
		if e.kind == "hq":
			has_hq[e.faction] = true
	if not has_hq.player and not has_hq.ai:
		_end_match("draw")
	elif not has_hq.player:
		_end_match("victory_ai")
	elif not has_hq.ai:
		_end_match("victory_player")


## Raised exactly once: step() does nothing after a result exists.
func _end_match(result: String) -> void:
	match_result = result
	results_raised += 1
	events.append({"type": "match_ended", "tick": tick, "result": result})


# --- fog of war and observations (SPEC 5.6, 7.2) ---------------------------

## Recomputes both factions' fog and their memory of enemy buildings and nodes.
func update_fog() -> void:
	var vision: Dictionary = {}
	for kind: String in stats:
		vision[kind] = stats[kind].vision
	for f: String in Consts.FACTIONS:
		var viewers: Array[Entity] = []
		var remembered: Array[Entity] = []
		for id: int in entities:
			var e: Entity = entities[id]
			if e.faction == f:
				viewers.append(e)
			elif e.is_node() or e.is_building():
				remembered.append(e)
		fog.update(f, viewers, remembered, vision)
	fog_tick = tick


## What `faction` may know (SPEC 7.2): copies only, nothing hidden.
func observation(faction: String) -> Observation:
	var o: Observation = Observation.new()
	o.tick = tick
	o.faction = faction
	o.resources = (resources[faction] as Dictionary).duplicate()
	for id: int in entities:
		var e: Entity = entities[id]
		if e.faction == faction and e.is_unit():
			o.own_units.append(_snapshot_unit(e))
		elif e.faction == faction and e.is_building():
			var s: Dictionary = Fog.snapshot(e)
			s["progress"] = e.progress
			s["queue"] = e.queue.duplicate(true)
			o.own_buildings.append(s)
		elif e.is_unit() and fog.is_visible(faction, e.unit_cell()):
			o.enemy_units.append(_snapshot_unit(e))
	for id: int in fog.memory[faction]:
		var m: Dictionary = (fog.memory[faction][id] as Dictionary).duplicate()
		if m.faction == "":
			o.nodes.append(m)
		else:
			o.ghosts.append(m)
	o.width = map.width
	o.height = map.height
	o.terrain = map.blocked.duplicate()
	o.possible_starts = map.possible_starts.duplicate()
	o.fog = fog.grid(faction)
	o.stats = stats.duplicate(true)
	o.upgrades = (upgrades[faction] as Dictionary).duplicate()
	return o


func _snapshot_unit(e: Entity) -> Dictionary:
	return {
		"id": e.id, "kind": e.kind, "faction": e.faction, "cell": e.unit_cell(), "pos": e.pos,
		"hp": e.hp, "order_type": e.order_type, "order_target": e.order_target,
		"carry": e.carry, "carry_type": e.carry_type,
	}


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


## The observation firewall (SPEC 7.2): an AI command may only name entities
## that were in the observation it was decided from (`known`: id -> true).
## A command naming anything else is rejected and counted as a violation;
## it is logged with "unknown_entity" and nothing changes. Returns "firewall"
## for a violation, else the normal result code.
func submit_observed(cmd: Dictionary, known: Dictionary) -> String:
	for id: int in referenced_ids(cmd):
		if not known.has(id):
			firewall_violations += 1
			command_log.append({"tick": tick, "faction": cmd.get("faction", ""), "command": cmd.get("command", ""),
				"args": cmd.get("args", {}), "result": "unknown_entity", "firewall": true})
			return "firewall"
	return submit(cmd)


## Every entity id a command names: the acting units or building, and its
## target node, enemy or building.
static func referenced_ids(cmd: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var args: Dictionary = cmd.get("args", {})
	for key: String in ["unit_ids", "worker_id", "building_id", "node_id", "target_id"]:
		if not args.has(key):
			continue
		var v: Variant = args[key]
		for x: Variant in (v if typeof(v) == TYPE_ARRAY else [v]):
			if JsonUtil.is_whole(x):
				out.append(int(x))
	return out


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
	if name in QUEUEABLE and args.get("queue", false) == true:
		return _queue_order(name, ids, args)
	var result: String = _dispatch(name, ids, args)
	# A plain (not queued) order replaces everything the units were going to
	# do, as D-14 says: their queue is cleared, and an attack-move ends.
	if result == "ok" and COMMAND_SUBJECT[name] == "unit_ids":
		for id: int in ids:
			var e: Entity = entities[id]
			e.orders.clear()
			if name != "attack_move":
				e.am_cell = NO_CELL
	return result


func _dispatch(name: String, ids: Array[int], args: Dictionary) -> String:
	match name:
		"move":
			return _cmd_move(ids, args.get("cell"))
		"attack_move":
			return _cmd_attack_move(ids, args.get("cell"))
		"harvest":
			return _cmd_harvest(ids, args.get("node_id"))
		"attack":
			return _cmd_attack(ids, args.get("target_id"))
		"build":
			return _cmd_build(entities[ids[0]], str(args.get("building_type", "")), args.get("cell"))
		"train":
			return _cmd_train(entities[ids[0]], str(args.get("unit_type", "")))
		"cancel_train":
			return _cmd_cancel_train(entities[ids[0]], int(args.index))
		"research":
			return _cmd_research(entities[ids[0]], str(args.get("upgrade", "")))
	return "invalid_target"


## Queues an order for later (D-44). It is checked now as far as it can be
## (a cell, or an existing node / enemy), and fully when it runs; nothing
## changes if any unit's queue is full.
func _queue_order(name: String, ids: Array[int], args: Dictionary) -> String:
	var entry: Dictionary = {"command": name}
	if name == "move" or name == "attack_move":
		var cell: Variant = JsonUtil.to_cell(args.get("cell"))
		if cell == null:
			return "invalid_target"
		entry.cell = cell
	else:
		var key: String = "target_id" if name == "attack" else "node_id"
		if not JsonUtil.is_whole(args.get(key)):
			return "invalid_target"
		var t: Entity = entity(int(args.get(key)))
		if t == null:
			return "unknown_entity"
		if (name == "harvest" and not t.is_node()) or (name == "attack" and (t.is_node() or t.faction == entities[ids[0]].faction)):
			return "invalid_target"
		entry.target = t.id
	for id: int in ids:
		if (entities[id] as Entity).orders.size() >= MAX_ORDERS:
			return "queue_full"
	for id: int in ids:
		(entities[id] as Entity).orders.append(entry.duplicate())
	return "ok"


## At the start of a tick, each idle unit takes up its next order: first an
## interrupted attack-move (it fought something on the way), else the next
## queued order. An order that cannot run any more (its target died, no
## path) is dropped and the next one is tried (D-44).
func _run_orders() -> void:
	for id: int in entities.keys():
		var e: Entity = entities.get(id)
		if e == null or not e.is_unit() or e.order_type != "idle" or e.path_i < e.path.size():
			continue
		if e.am_cell != NO_CELL:
			if _start_attack_move(e, e.am_cell):
				continue
			e.am_cell = NO_CELL
		while not e.orders.is_empty():
			var o: Dictionary = e.orders.pop_front()
			var one: Array[int] = [e.id]
			var r: String
			match o.command:
				"move":
					r = _cmd_move(one, [o.cell.x, o.cell.y])
				"attack_move":
					r = _cmd_attack_move(one, [o.cell.x, o.cell.y])
				"attack":
					r = _cmd_attack(one, o.target) if entities.has(o.target) else "unknown_entity"
				"harvest":
					r = _cmd_harvest(one, o.target) if entities.has(o.target) else "unknown_entity"
			if r == "ok":
				break


## Attack-move (D-44): like move (with the same formation), but soldiers
## fight enemies they meet on the way and then carry on; workers just move.
func _cmd_attack_move(ids: Array[int], raw_cell: Variant) -> String:
	var cell: Variant = JsonUtil.to_cell(raw_cell)
	if cell == null:
		return "invalid_target"
	for id: int in ids:
		if not (entities[id] as Entity).is_unit():
			return "invalid_target"
	var units: Array[Entity] = []
	for id: int in ids:
		units.append(entities[id])
	var slots: Dictionary = Spacing.formation(self, units, cell)
	var any_ok: bool = false
	for e: Entity in units:
		if _start_attack_move(e, slots[e.id]) or (slots[e.id] != cell and _start_attack_move(e, cell)):
			any_ok = true
		else:
			e.set_idle()
			e.am_cell = NO_CELL
			_message(e.faction, "no_path", e.id)
	return "ok" if any_ok else "no_path"


func _start_attack_move(e: Entity, dest: Vector2i) -> bool:
	if not _set_path(e, dest):
		return false
	var soldier: bool = e.is_soldier()
	e.order_type = "attack_move" if soldier else "move"
	e.order_target = 0
	e.order_cell = dest
	e.phase = ""
	e.timer = 0
	e.dropoff_id = 0
	e.auto = false
	e.stepping = false
	e.am_cell = dest if soldier else NO_CELL
	return true


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
	# D-42: the group spreads over distinct cells around the goal.
	var units: Array[Entity] = []
	for id: int in ids:
		units.append(entities[id])
	var slots: Dictionary = Spacing.formation(self, units, cell)
	var any_ok: bool = false
	for id: int in ids:
		var e: Entity = entities[id]
		if _set_path(e, slots[id]) or (slots[id] != cell and _set_path(e, cell)):
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
	# A node, or one of the workers' own finished farms (D-51).
	if not node.is_harvestable() or node.is_building() and node.faction != (entities[ids[0]] as Entity).faction:
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
	if w.kind != "worker" or not kind in BUILDABLE:
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
	var paid: String = bank.spend(w.faction, cost_of(kind))
	if paid != "ok":
		return paid
	var b: int = place_building_unchecked(kind, w.faction, cell, false)
	_assign_builder(w, entity(b))
	return "ok"


## Whether `b` could train `unit_type` now, as a result code. Changes nothing
## (the HUD uses it to disable buttons and show the reason).
func train_check(b: Entity, unit_type: String) -> String:
	if match_result != "":
		return "match_over"
	if not b.is_building():
		return "invalid_target"
	if not unit_type in TRAINS.get(b.kind, []):
		return "invalid_unit_for_building"
	if not b.complete:
		return "not_ready"
	if b.queue.size() >= Consts.QUEUE_CAPACITY:
		return "queue_full"
	if population(b.faction) >= Consts.POPULATION_CAP:
		return "population_cap"
	return bank.check(b.faction, cost_of(unit_type))


## Whether `b` could research `upgrade` now, as a result code (D-51).
## Changes nothing; the HUD uses it too.
func research_check(b: Entity, upgrade: String) -> String:
	if match_result != "":
		return "match_over"
	if b.kind != "barracks" or not Consts.UPGRADES.has(upgrade):
		return "invalid_target"
	if not b.complete:
		return "not_ready"
	if has_upgrade(b.faction, upgrade) or _researching(b.faction, upgrade):
		return "already_researched"
	if b.queue.size() >= Consts.QUEUE_CAPACITY:
		return "queue_full"
	return bank.check(b.faction, upgrade_cost(upgrade))


func upgrade_cost(upgrade: String) -> Dictionary:
	var u: Dictionary = Consts.UPGRADES[upgrade]
	return {"wood": u.wood, "gold": u.gold, "food": u.food}


## True while any of the faction's buildings has the upgrade queued.
func _researching(faction: String, upgrade: String) -> bool:
	for id: int in entities:
		var b: Entity = entities[id]
		if b.faction == faction and b.is_building():
			for item: Dictionary in b.queue:
				if item.type == upgrade:
					return true
	return false


## Research: paid at enqueue through the one transaction, like training.
func _cmd_research(b: Entity, upgrade: String) -> String:
	var allowed: String = research_check(b, upgrade)
	if allowed != "ok":
		return allowed
	var cost: Dictionary = upgrade_cost(upgrade)
	var paid: String = bank.spend(b.faction, cost)
	if paid != "ok":
		return paid
	b.queue.append({"type": upgrade, "remaining": Consts.UPGRADES[upgrade].time, "cost": cost, "status": ""})
	return "ok"


## Training: the cost is paid at enqueue through the one transaction (D-06).
func _cmd_train(b: Entity, unit_type: String) -> String:
	var allowed: String = train_check(b, unit_type)
	if allowed != "ok":
		return allowed
	var cost: Dictionary = cost_of(unit_type)
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
	fog.reveal(faction, e, stats[kind].vision)
	return _register(e)


## Places a building without any placement checks; the build command checks
## first (build step 4). Its footprint becomes solid from this tick.
func place_building_unchecked(kind: String, faction: String, anchor: Vector2i, is_complete: bool) -> int:
	var e: Entity = Entity.new(next_id, kind, faction)
	e.cell = anchor
	e.size = stats[kind].footprint
	e.hp = stats[kind].health
	e.complete = is_complete
	if is_complete:
		_on_complete(e)
	for c: Vector2i in e.footprint():
		solid[c.y * map.width + c.x] = 1
		occupant[c.y * map.width + c.x] = e.id
	_solid_changed = true
	fog.reveal(faction, e, stats[kind].vision)
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
	if dead.is_unit() and dead.carry > 0:
		bank.record_lost(dead.faction, dead.carry_type, dead.carry)
	if dead.kind == "farm":
		node_razed.food += dead.amount
	events.append({"type": "destroyed", "tick": tick, "entity_id": id, "kind": dead.kind, "faction": dead.faction,
		"pos": dead.pos, "cell": dead.cell, "size": dead.size})
	for oid: int in entities:
		var e: Entity = entities[oid]
		if not e.is_unit():
			continue
		# Queued orders naming the dead entity are dropped (D-44).
		for i: int in range(e.orders.size() - 1, -1, -1):
			if int(e.orders[i].get("target", 0)) == id:
				e.orders.remove_at(i)
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


## Units alive plus units queued (SPEC 4: the cap counts queued units;
## research items are not units, D-51).
func population(faction: String) -> int:
	var n: int = 0
	for id: int in entities:
		var e: Entity = entities[id]
		if e.faction != faction:
			continue
		if e.is_unit():
			n += 1
		elif e.is_building():
			for item: Dictionary in e.queue:
				if not Consts.UPGRADES.has(item.type):
					n += 1
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
	h.add_int(firewall_violations)
	h.add_int(next_id)
	bank.add_to_hash(h)
	for f: String in Consts.FACTIONS:
		for u: String in Consts.UPGRADES:
			h.add_int(1 if has_upgrade(f, u) else 0)
	for r: String in ResourceManager.TYPES:
		h.add_int(node_added[r])
		h.add_int(node_razed[r])
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
