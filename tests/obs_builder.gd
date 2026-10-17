## Builds synthetic AI observations for tests (AC-62): a 30 x 30 open map,
## everything explored and visible, the AI's HQ at (20, 20) (covers 20..22).
class_name ObsBuilder
extends RefCounted

var obs: Observation
var _next_id: int = 100


func _init(tick: int = 100, wood: int = 0, gold: int = 0) -> void:
	obs = Observation.new()
	obs.tick = tick
	obs.faction = "ai"
	obs.resources = {"wood": wood, "gold": gold}
	obs.width = 30
	obs.height = 30
	obs.terrain = PackedByteArray()
	obs.terrain.resize(900)
	obs.fog = PackedByteArray()
	obs.fog.resize(900)
	obs.fog.fill(Fog.VISIBLE)
	obs.possible_starts = [Vector2i(3, 3), Vector2i(20, 20)]
	obs.stats = UnitStats.load_file("res://data/units.json").stats
	building("hq", Vector2i(20, 20))


func _id() -> int:
	_next_id += 1
	return _next_id


func unit(kind: String, cell: Vector2i, order: String = "idle") -> int:
	var id: int = _id()
	obs.own_units.append({"id": id, "kind": kind, "faction": "ai", "cell": cell, "pos": MapGrid.cell_center(cell),
		"hp": obs.stats[kind].health, "order_type": order, "order_target": 0, "carry": 0, "carry_type": ""})
	return id


func units(kind: String, n: int, near: Vector2i = Vector2i(18, 18)) -> Array[int]:
	var out: Array[int] = []
	for i: int in n:
		out.append(unit(kind, near + Vector2i(i % 5, -(i / 5))))
	return out


func building(kind: String, cell: Vector2i, complete: bool = true) -> int:
	var id: int = _id()
	obs.own_buildings.append({"id": id, "kind": kind, "faction": "ai", "cell": cell,
		"size": obs.stats[kind].footprint, "hp": obs.stats[kind].health, "complete": complete,
		"amount": 0, "progress": 0, "queue": []})
	return id


func enemy_unit(kind: String, cell: Vector2i) -> int:
	var id: int = _id()
	obs.enemy_units.append({"id": id, "kind": kind, "faction": "player", "cell": cell, "pos": MapGrid.cell_center(cell),
		"hp": obs.stats[kind].health, "order_type": "idle", "order_target": 0, "carry": 0, "carry_type": ""})
	return id


func ghost(kind: String, cell: Vector2i) -> int:
	var id: int = _id()
	obs.ghosts.append({"id": id, "kind": kind, "faction": "player", "cell": cell,
		"size": obs.stats[kind].footprint, "hp": obs.stats[kind].health, "complete": true, "amount": 0})
	return id


func node(kind: String, cell: Vector2i) -> int:
	var id: int = _id()
	obs.nodes.append({"id": id, "kind": kind, "faction": "", "cell": cell, "size": Vector2i.ONE,
		"hp": 0, "complete": true, "amount": 300})
	return id
