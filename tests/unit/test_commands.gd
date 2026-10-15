## AC-20 and AC-24: the command interface.
extends GutTest


func _setup() -> Array:
	var sim: Simulation = TestMaps.sim(TestMaps.open(20, 12))
	var mine: int = sim.spawn_unit("worker", "player", Vector2i(5, 5))
	var theirs: int = sim.spawn_unit("worker", "ai", Vector2i(12, 6))
	return [sim, mine, theirs]


func test_ac_20_unknown_entity() -> void:
	var s: Array = _setup()
	var sim: Simulation = s[0]
	var before: int = sim.state_hash()
	assert_eq(sim.submit(Commands.move("player", [9999], Vector2i(8, 8))), "unknown_entity")
	assert_eq(sim.submit(Commands.move("player", [s[1], 9999], Vector2i(8, 8))), "unknown_entity", "one bad id rejects all")
	assert_eq(sim.state_hash(), before)


func test_ac_20_not_owner() -> void:
	var s: Array = _setup()
	var sim: Simulation = s[0]
	var before: int = sim.state_hash()
	assert_eq(sim.submit(Commands.move("player", [s[2]], Vector2i(8, 8))), "not_owner")
	assert_eq(sim.submit(Commands.move("player", [s[1], s[2]], Vector2i(8, 8))), "not_owner", "one enemy unit rejects all")
	assert_eq(sim.state_hash(), before)


func test_ac_20_negative_amount() -> void:
	var s: Array = _setup()
	var sim: Simulation = s[0]
	var hq: int = sim.hq_of("player")
	var before: int = sim.state_hash()
	assert_eq(sim.submit(Commands.cancel_train("player", hq, -1)), "invalid_amount")
	assert_eq(sim.state_hash(), before)


func test_ac_20_wrong_entity_kind() -> void:
	var s: Array = _setup()
	var sim: Simulation = s[0]
	var before: int = sim.state_hash()
	assert_eq(sim.submit(Commands.move("player", [sim.hq_of("player")], Vector2i(8, 8))), "invalid_target", "buildings cannot move")
	assert_eq(sim.state_hash(), before)


func test_ac_20_empty_selection_changes_nothing() -> void:
	var s: Array = _setup()
	var sim: Simulation = s[0]
	var before: int = sim.state_hash()
	assert_eq(sim.submit(Commands.move("player", [], Vector2i(8, 8))), "unknown_entity")
	assert_eq(sim.state_hash(), before)


func test_ac_24_new_order_replaces_current_order() -> void:
	var s: Array = _setup()
	var sim: Simulation = s[0]
	var id: int = s[1]
	sim.submit(Commands.move("player", [id], Vector2i(15, 5)))
	for t: int in 5:
		sim.step()
	sim.submit(Commands.move("player", [id], Vector2i(5, 10)))
	var e: Entity = sim.entity(id)
	assert_eq(e.order_type, "move")
	assert_eq(e.order_cell, Vector2i(5, 10))
	assert_eq(e.path[e.path.size() - 1], Vector2i(5, 10), "only the new destination remains")
	for t: int in 200:
		sim.step()
	assert_eq(e.pos, MapGrid.cell_center(Vector2i(5, 10)))


func test_ac_24_same_order_twice_equals_once() -> void:
	var once: Array = _setup()
	var twice: Array = _setup()
	var sa: Simulation = once[0]
	var sb: Simulation = twice[0]
	for t: int in 7:
		sa.step()
		sb.step()
	sa.submit(Commands.move("player", [once[1]], Vector2i(15, 9)))
	sb.submit(Commands.move("player", [twice[1]], Vector2i(15, 9)))
	sb.submit(Commands.move("player", [twice[1]], Vector2i(15, 9)))
	assert_eq(sa.state_hash(), sb.state_hash(), "same state right after")
	sb.submit(Commands.move("player", [twice[1], twice[1]], Vector2i(15, 9)))
	assert_eq(sa.state_hash(), sb.state_hash(), "a repeated id in one command counts once")
	for t: int in 60:
		sa.step()
		sb.step()
	assert_eq(sa.state_hash(), sb.state_hash(), "same state later")
