## AC-19, AC-25 to AC-28: movement along paths.
extends GutTest


func test_ac_25_worker_15_steps_in_100_ticks_melee_in_120() -> void:
	# 15 cells = 15,000 milli-cells. Worker: 15,000 / 150 = 100 ticks.
	# Melee soldier: 15,000 / 125 = 120 ticks.
	for case: Array in [["worker", 100], ["melee", 120]]:
		var sim: Simulation = TestMaps.sim(TestMaps.open(24, 12))
		var id: int = sim.spawn_unit(case[0], "player", Vector2i(3, 6))
		assert_eq(sim.submit(TestMaps.move("player", [id], Vector2i(18, 6))), "ok")
		var goal: Vector2i = MapGrid.cell_center(Vector2i(18, 6))
		for t: int in case[1] - 1:
			sim.step()
		assert_ne(sim.entity(id).pos, goal, "%s not there after %d ticks" % [case[0], case[1] - 1])
		assert_eq(sim.entity(id).order_type, "move")
		sim.step()
		assert_eq(sim.entity(id).pos, goal, "%s arrives after exactly %d ticks" % case)
		assert_eq(sim.entity(id).order_type, "idle")


func test_ac_27_two_units_sent_to_one_cell_stand_side_by_side() -> void:
	# AC-27 as changed by D-42: both arrive, in different cells. The unit
	# nearer the goal (a: 4² + 2² = 20; b: 4² + 2² = 20, tie, lower id) takes
	# the goal (8, 6); b takes the ring-1 cell nearest to itself, (9, 7)
	# (3² + 1² = 10; next is (9, 6) at 3² + 2² = 13).
	var sim: Simulation = TestMaps.sim(TestMaps.open(20, 12))
	var a: int = sim.spawn_unit("worker", "player", Vector2i(4, 4))
	var b: int = sim.spawn_unit("ranged", "player", Vector2i(12, 8))
	assert_eq(sim.submit(TestMaps.move("player", [a, b], Vector2i(8, 6))), "ok")
	for t: int in 200:
		sim.step()
	assert_eq(sim.entity(a).pos, MapGrid.cell_center(Vector2i(8, 6)))
	assert_eq(sim.entity(b).pos, MapGrid.cell_center(Vector2i(9, 7)))
	assert_eq(sim.entity(a).order_type, "idle")
	assert_eq(sim.entity(b).order_type, "idle")


func test_d42_group_of_nine_fills_the_goal_and_its_ring() -> void:
	var sim: Simulation = TestMaps.sim(TestMaps.open(24, 16))
	var ids: Array[int] = []
	for i: int in 9:
		# Workers: soldiers would leave to attack the enemy HQ of the test map.
		ids.append(sim.spawn_unit("worker", "player", Vector2i(5 + i % 3, 5 + i / 3)))
	assert_eq(sim.submit(TestMaps.move("player", ids, Vector2i(14, 9))), "ok")
	for t: int in 400:
		sim.step()
	var cells: Dictionary = {}
	for id: int in ids:
		var c: Vector2i = sim.entity(id).unit_cell()
		cells[c] = true
		assert_lte(maxi(absi(c.x - 14), absi(c.y - 9)), 1, "within one ring of the goal")
	assert_eq(cells.size(), 9, "nine units, nine different cells")


func test_d42_units_on_one_cell_step_apart() -> void:
	var sim: Simulation = TestMaps.sim(TestMaps.open(16, 10))
	var ids: Array[int] = []
	for i: int in 3:
		ids.append(sim.spawn_unit("worker", "player", Vector2i(4, 5)))
	# Within two step-aside rounds (Spacing.INTERVAL ticks each) plus the
	# walk of one cell (1,000 / 150 = 7 ticks), all three stand apart.
	for t: int in 2 * Spacing.INTERVAL + 10:
		sim.step()
	var cells: Dictionary = {}
	for id: int in ids:
		var e: Entity = sim.entity(id)
		cells[e.unit_cell()] = true
		assert_eq(e.pos, MapGrid.cell_center(e.unit_cell()), "standing on a cell centre")
	assert_eq(cells.size(), 3)
	assert_eq(sim.entity(ids[0]).unit_cell(), Vector2i(4, 5), "the lowest id keeps the cell")


func test_d42_melee_attackers_surround_their_target() -> void:
	var sim: Simulation = TestMaps.sim(TestMaps.open(20, 12))
	var target: int = sim.spawn_unit("melee", "ai", Vector2i(10, 6))
	var attackers: Array[int] = []
	for i: int in 3:
		attackers.append(sim.spawn_unit("melee", "player", Vector2i(5, 5 + i)))
	sim.update_fog()
	assert_eq(sim.submit(Commands.attack("player", attackers, target)), "ok")
	for t: int in 120:
		sim.step()
		if sim.entity(target) == null:
			break
	var cells: Dictionary = {}
	for id: int in attackers:
		var e: Entity = sim.entity(id)
		var c: Vector2i = e.unit_cell()
		assert_ne(c, Vector2i(10, 6), "never on the target's cell")
		cells[c] = true
	assert_eq(cells.size(), 3, "three attackers, three different cells")


func test_ac_28_unreachable_destination_one_message() -> void:
	# Goal (10, 5) is walled in on all four sides.
	var walls: Array[Vector2i] = [Vector2i(10, 4), Vector2i(11, 5), Vector2i(10, 6), Vector2i(9, 5)]
	var sim: Simulation = TestMaps.sim(TestMaps.open(16, 10, walls))
	var id: int = sim.spawn_unit("worker", "player", Vector2i(4, 5))
	var start_pos: Vector2i = sim.entity(id).pos
	assert_eq(sim.submit(TestMaps.move("player", [id], Vector2i(10, 5))), "no_path")
	var events: Array[Dictionary] = sim.take_events()
	for t: int in 50:
		sim.step()
		events.append_array(sim.take_events())
	assert_eq(sim.entity(id).order_type, "idle")
	assert_eq(sim.entity(id).pos, start_pos, "did not move")
	assert_eq(TestMaps.count_messages(events, "no_path", id), 1, "one message, not one per tick")


func test_ac_28_blocked_and_out_of_bounds_destinations() -> void:
	var sim: Simulation = TestMaps.sim(TestMaps.open(16, 10, [Vector2i(8, 8)]))
	var id: int = sim.spawn_unit("worker", "player", Vector2i(4, 5))
	assert_eq(sim.submit(TestMaps.move("player", [id], Vector2i(8, 8))), "no_path", "blocked cell")
	assert_eq(sim.submit(TestMaps.move("player", [id], Vector2i(40, 2))), "no_path", "outside the map")
	assert_eq(sim.submit(TestMaps.move("player", [id], Vector2i(1, 1))), "no_path", "inside the HQ")


## Steps until the unit stops moving; checks every tick that it never stands
## on a blocked cell or inside a building or node. Returns the events seen.
func _run_checked(sim: Simulation, id: int, ticks: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for t: int in ticks:
		sim.step()
		events.append_array(sim.take_events())
		var cell: Vector2i = sim.entity(id).unit_cell()
		assert_false(sim.is_solid(cell), "tick %d: unit at %s is on a solid cell" % [sim.tick, cell])
		if sim.entity(id).order_type == "idle":
			break
	return events


func test_ac_19_replans_around_a_new_building() -> void:
	var sim: Simulation = TestMaps.sim(TestMaps.open(20, 9))
	var id: int = sim.spawn_unit("worker", "player", Vector2i(2, 4))
	assert_eq(sim.submit(TestMaps.move("player", [id], Vector2i(16, 4))), "ok")
	for t: int in 20:
		sim.step()
	# After 20 ticks the worker has moved 3 cells; a barracks now covers (9..10, 3..4).
	var b: int = sim.place_building_unchecked("barracks", "ai", Vector2i(9, 3), true)
	assert_true(sim.is_solid(Vector2i(9, 4)), "footprint blocks movement")
	var events: Array[Dictionary] = _run_checked(sim, id, 400)
	assert_eq(sim.entity(id).pos, MapGrid.cell_center(Vector2i(16, 4)), "arrives by another route")
	assert_eq(TestMaps.count_messages(events, "no_path", id), 0)
	assert_true(sim.entities.has(b))


func test_ac_19_no_route_after_building_goes_idle_with_one_message() -> void:
	# A corridor (rows 3-4, x 12..19) closed above and below by walls; a
	# barracks at (14, 3) then seals the goal (18, 3) off.
	var walls: Array[Vector2i] = []
	for x: int in range(12, 20):
		walls.append(Vector2i(x, 2))
		walls.append(Vector2i(x, 5))
	var sim: Simulation = TestMaps.sim(TestMaps.open(20, 9, walls))
	var id: int = sim.spawn_unit("worker", "player", Vector2i(2, 3))
	assert_eq(sim.submit(TestMaps.move("player", [id], Vector2i(18, 3))), "ok")
	for t: int in 10:
		sim.step()
	sim.place_building_unchecked("barracks", "ai", Vector2i(14, 3), true)
	var events: Array[Dictionary] = _run_checked(sim, id, 100)
	assert_eq(sim.entity(id).order_type, "idle")
	assert_eq(TestMaps.count_messages(events, "no_path", id), 1)
	# Still responsive: more ticks run and a new order is accepted.
	for t: int in 30:
		sim.step()
	assert_eq(sim.submit(TestMaps.move("player", [id], Vector2i(5, 6))), "ok")


func test_ac_26_no_unit_ever_on_a_blocked_cell() -> void:
	var cmd_rng: SimRng = SimRng.new(26)
	for s: int in TestCounts.pick(4, 40):
		var m: MapGrid = MapGenerator.generate(500 + s).map
		var sim: Simulation = Simulation.new(m, s, {})
		var units: Array[int] = sim.unit_ids()
		for t: int in TestCounts.pick(400, 1500):
			if t % 25 == 0:
				var f: String = Consts.FACTIONS[cmd_rng.range_int(2)]
				var mine: Array = units.filter(func(u: int) -> bool: return sim.entity(u).faction == f)
				var target: Vector2i = Vector2i(cmd_rng.range_int(m.width), cmd_rng.range_int(m.height))
				sim.submit(Commands.move(f, mine, target))
			sim.step()
			for u: int in units:
				var cell: Vector2i = sim.entity(u).unit_cell()
				assert_true(m.is_walkable(cell) and not sim.is_solid(cell),
					"map %d tick %d: unit %d on blocked cell %s" % [s, sim.tick, u, cell])
