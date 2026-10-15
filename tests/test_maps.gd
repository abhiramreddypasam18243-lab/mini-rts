## Small hand-made maps for tests. HQs sit in two corners, out of the way:
## the player HQ covers (0..2, 0..2) and the AI HQ the bottom-right 3 x 3.
class_name TestMaps
extends RefCounted


static func open(w: int, h: int, walls: Array[Vector2i] = []) -> MapGrid:
	var m: MapGrid = MapGrid.new(w, h)
	m.map_name = "test"
	for c: Vector2i in walls:
		m.set_blocked(c, true)
	m.starts = {"player": Vector2i(0, 0), "ai": Vector2i(w - 3, h - 3)}
	m.possible_starts = [Vector2i(0, 0), Vector2i(w - 3, h - 3)]
	return m


## A simulation with no starting workers, so tests control every unit.
static func sim(m: MapGrid, p_seed: int = 1) -> Simulation:
	return Simulation.new(m, p_seed, {"start_workers": 0})


static func move(faction: String, ids: Array, cell: Vector2i) -> Dictionary:
	return Commands.move(faction, ids, cell)


## Number of message events with the given code for one entity, drained from the sim.
static func count_messages(events: Array[Dictionary], code: String, entity_id: int) -> int:
	var n: int = 0
	for e: Dictionary in events:
		if e.type == "message" and e.code == code and e.get("entity_id", 0) == entity_id:
			n += 1
	return n
