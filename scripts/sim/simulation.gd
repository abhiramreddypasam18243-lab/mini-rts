## The deterministic match simulation (SPEC 6.2). It knows nothing about
## graphics or real time: the presentation calls step() at 20 ticks per second,
## headless tools call it as fast as they like, and both get the same result.
##
## Rules owned here: entity creation, the command interface (validation order
## and result codes), orders, movement and re-planning, the state hash.
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
## Faction -> {"wood": int, "gold": int}.
var resources: Dictionary = {}
## 1 where a unit cannot stand: blocked terrain, a building or a resource node.
var solid: PackedByteArray
## Building or node id covering each cell; 0 = none.
var occupant: PackedInt32Array
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
	solid = map.blocked.duplicate()
	occupant = PackedInt32Array()
	occupant.resize(map.width * map.height)
	for f: String in Consts.FACTIONS:
		resources[f] = {"wood": Consts.START_WOOD, "gold": Consts.START_GOLD}
	for node: Dictionary in map.nodes:
		_add_node(node.type, node.cell, node.amount)
	var workers: int = int(p_config.get("start_workers", Consts.START_WORKERS))
	for f: String in Consts.FACTIONS:
		var hq: int = place_building_unchecked("hq", f, map.starts[f], true)
		# Starting workers take the first free spawn cells, one per cell.
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
	for id: int in entities:
		var e: Entity = entities[id]
		if e.is_unit() and e.order_type == "move":
			if Movement.advance(e, stats[e.kind].speed):
				e.set_idle()
	tick += 1


## AC-19: a unit whose remaining path crosses a newly solid cell re-plans; if
## no route is left it stops, goes idle and raises `no_path` once.
func _replan_blocked_paths() -> void:
	for id: int in entities:
		var e: Entity = entities[id]
		if e.is_unit() and e.order_type == "move" and Movement.path_blocked(e, solid, map.width):
			if not _set_path(e, e.order_cell):
				e.set_idle()
				_message(e.faction, "no_path", e.id)


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
## then the command's own rules.
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
	# harvest, build, attack, train and cancel_train arrive in build steps 3 to 5.
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
			any_ok = true
		else:
			e.set_idle()
			_message(e.faction, "no_path", e.id)
	return "ok" if any_ok else "no_path"


## Plans a path from the unit's cell to `goal` and starts it. False if none.
func _set_path(e: Entity, goal: Vector2i) -> bool:
	var r: Dictionary = Pathfinder.find_path(map.width, map.height, solid, e.unit_cell(), goal)
	if (r.path as Array).is_empty():
		return false
	e.path = r.path
	e.path_i = Movement.start_index(e)
	return true


# --- entity creation (internal: used by setup, production and tests) -------

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
	for f: String in Consts.FACTIONS:
		h.add_int(resources[f].wood)
		h.add_int(resources[f].gold)
	map.add_to_hash(h)
	h.add_bytes(solid)
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
