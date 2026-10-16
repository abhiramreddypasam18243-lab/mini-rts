## AC-07, AC-29 to AC-35: harvesting, drop-off, depletion and spending.
extends GutTest


func _wood(cell: Vector2i, amount: int = 500) -> Dictionary:
	return {"type": "wood", "cell": cell, "amount": amount}


func _messages(events: Array[Dictionary], code: String) -> int:
	var n: int = 0
	for e: Dictionary in events:
		if e.type == "message" and e.code == code:
			n += 1
	return n


func _assert_clean(sim: Simulation) -> void:
	var problems: PackedStringArray = Invariants.check(sim)
	assert_eq(problems, PackedStringArray(), "tick %d" % sim.tick)


func test_ac_29_trip_next_to_node_and_hq() -> void:
	# Player HQ covers (0..2, 0..2). The worker at (3, 1) touches the HQ and the
	# wood node at (4, 1), so a trip is 40 ticks of gathering plus the deposit.
	var sim: Simulation = TestMaps.sim(TestMaps.open(16, 10, [], [_wood(Vector2i(4, 1))]))
	var node: int = sim.node_at(Vector2i(4, 1))
	var w: int = sim.spawn_unit("worker", "player", Vector2i(3, 1))
	assert_eq(sim.submit(Commands.harvest("player", [w], node)), "ok")
	for t: int in 39:
		sim.step()
	assert_eq(sim.resources.player.wood, 200, "nothing yet after 39 ticks")
	sim.step()
	sim.step()
	assert_eq(sim.resources.player.wood, 210, "+10 wood within 41 ticks")
	assert_eq(sim.entity(node).amount, 490, "node -10")
	assert_eq(sim.entity(w).carry, 0)
	_assert_clean(sim)


func test_ac_30_node_of_15_yields_10_then_5_then_worker_moves_on() -> void:
	# Second wood node at (7, 3): squared distance from (4, 1) is 9 + 4 = 13 <= 100.
	var sim: Simulation = TestMaps.sim(TestMaps.open(16, 10, [], [_wood(Vector2i(4, 1), 15), _wood(Vector2i(7, 3))]))
	var small: int = sim.node_at(Vector2i(4, 1))
	var other: int = sim.node_at(Vector2i(7, 3))
	var w: int = sim.spawn_unit("worker", "player", Vector2i(3, 1))
	sim.submit(Commands.harvest("player", [w], small))
	var deposits: Array[int] = []
	var last: int = sim.resources.player.wood
	for t: int in 120:
		sim.step()
		if sim.resources.player.wood != last:
			deposits.append(sim.resources.player.wood - last)
			last = sim.resources.player.wood
		_assert_clean(sim)
	assert_eq(deposits.slice(0, 2), [10, 5], "trips of 10 and 5")
	assert_false(sim.entities.has(small), "exhausted node disappears")
	assert_false(sim.is_solid(Vector2i(4, 1)), "its cell becomes walkable")
	assert_eq(sim.entity(w).order_type, "harvest")
	assert_eq(sim.entity(w).order_target, other, "moves on to the other wood node")


func test_ac_30_no_other_node_goes_idle_with_message() -> void:
	# The only other wood node (15, 9) is at squared distance 121 + 64 > 100.
	var sim: Simulation = TestMaps.sim(TestMaps.open(20, 12, [], [_wood(Vector2i(4, 1), 15), _wood(Vector2i(15, 9))]))
	var small: int = sim.node_at(Vector2i(4, 1))
	var w: int = sim.spawn_unit("worker", "player", Vector2i(3, 1))
	sim.submit(Commands.harvest("player", [w], small))
	var events: Array[Dictionary] = []
	for t: int in 120:
		sim.step()
		events.append_array(sim.take_events())
	assert_eq(sim.resources.player.wood, 215, "exactly 15 gathered")
	assert_eq(sim.entity(w).order_type, "idle")
	assert_eq(_messages(events, "no_node"), 1)


func test_ac_31_deposits_at_nearer_hq_by_path_length() -> void:
	# A wall at x = 5 (y = 0..10) puts the home HQ (0..2, 0..2) 7 cells away in a
	# straight line but more than 18 steps by path; a second HQ at (16..18, 1..3)
	# is 6 steps away. The worker must choose the second one.
	var walls: Array[Vector2i] = []
	for y: int in 11:
		walls.append(Vector2i(5, y))
	var sim: Simulation = TestMaps.sim(TestMaps.open(24, 14, walls, [_wood(Vector2i(8, 2))]))
	var near_hq: int = sim.place_building_unchecked("hq", "player", Vector2i(16, 1), true)
	var w: int = sim.spawn_unit("worker", "player", Vector2i(9, 2))
	sim.submit(Commands.harvest("player", [w], sim.node_at(Vector2i(8, 2))))
	var deposited_next_to: int = 0
	for t: int in 80:
		var before: int = sim.resources.player.wood
		sim.step()
		if sim.resources.player.wood > before:
			deposited_next_to = sim.building_adjacent_to(sim.entity(w).unit_cell(), "player")
			break
	assert_eq(deposited_next_to, near_hq)


func test_ac_31_hq_destroyed_keeps_carry_and_idles() -> void:
	# Node at (8, 5) is far from the HQ, so the worker is walking home with 10 wood.
	var sim: Simulation = TestMaps.sim(TestMaps.open(16, 10, [], [_wood(Vector2i(8, 5))]))
	var w: int = sim.spawn_unit("worker", "player", Vector2i(9, 5))
	sim.submit(Commands.harvest("player", [w], sim.node_at(Vector2i(8, 5))))
	for t: int in 45:
		sim.step()
	assert_eq(sim.entity(w).carry, 10)
	sim.take_events()
	sim.destroy_entity(sim.hq_of("player"))
	var events: Array[Dictionary] = sim.take_events()
	assert_eq(sim.entity(w).order_type, "idle")
	assert_eq(sim.entity(w).carry, 10, "keeps what it carries")
	assert_eq(_messages(events, "no_dropoff"), 1)
	_assert_clean(sim)


func test_ac_32_train_melee_then_cannot_afford_second() -> void:
	var sim: Simulation = Simulation.new(TestMaps.open(16, 10), 1, {"start_workers": 0, "start_wood": 100, "start_gold": 100})
	var barracks: int = sim.place_building_unchecked("barracks", "player", Vector2i(6, 4), true)
	assert_eq(sim.submit(Commands.train("player", barracks, "melee")), "ok")
	assert_eq(sim.resources.player, {"wood": 40, "gold": 80})
	assert_eq(sim.submit(Commands.train("player", barracks, "melee")), "insufficient_resources")
	assert_eq(sim.resources.player, {"wood": 40, "gold": 80})
	assert_eq(sim.entity(barracks).queue.size(), 1)


func test_ac_33_queue_two_workers_cancel_second_once() -> void:
	var sim: Simulation = Simulation.new(TestMaps.open(16, 10), 1, {"start_workers": 0, "start_wood": 200, "start_gold": 0})
	var hq: int = sim.hq_of("player")
	assert_eq(sim.submit(Commands.train("player", hq, "worker")), "ok")
	assert_eq(sim.submit(Commands.train("player", hq, "worker")), "ok")
	assert_eq(sim.resources.player.wood, 100, "200 - 2 x 50")
	assert_eq(sim.submit(Commands.cancel_train("player", hq, 1)), "ok")
	assert_eq(sim.resources.player.wood, 150, "refund of 50")
	assert_ne(sim.submit(Commands.cancel_train("player", hq, 1)), "ok", "the same item cannot be cancelled again")
	assert_eq(sim.resources.player.wood, 150, "no second refund")
	assert_eq(sim.entity(hq).queue.size(), 1)
	_assert_clean(sim)


func test_ac_34_changing_order_keeps_carried_resources() -> void:
	var sim: Simulation = TestMaps.sim(TestMaps.open(16, 10, [], [_wood(Vector2i(8, 5))]))
	var node: int = sim.node_at(Vector2i(8, 5))
	var w: int = sim.spawn_unit("worker", "player", Vector2i(9, 5))
	sim.submit(Commands.harvest("player", [w], node))
	for t: int in 45:
		sim.step()
		_assert_clean(sim)
	assert_eq(sim.entity(w).carry, 10, "walking home with 10 wood")
	assert_eq(sim.submit(Commands.move("player", [w], Vector2i(12, 8))), "ok")
	for t: int in 40:
		sim.step()
		_assert_clean(sim)
	assert_eq(sim.entity(w).carry, 10, "a move order keeps the load")
	assert_eq(sim.resources.player.wood, 200)
	sim.submit(Commands.harvest("player", [w], node))
	var deposited: int = 0
	for t: int in 200:
		var before: int = sim.resources.player.wood
		sim.step()
		_assert_clean(sim)
		if sim.resources.player.wood > before:
			deposited = sim.resources.player.wood - before
			break
	assert_eq(deposited, 10, "the old load is deposited first, not lost or doubled")


func test_ac_35_hud_counters_show_same_tick_stockpile() -> void:
	var sim: Simulation = TestMaps.sim(TestMaps.open(16, 10, [], [_wood(Vector2i(4, 1))]))
	var w: int = sim.spawn_unit("worker", "player", Vector2i(3, 1))
	sim.submit(Commands.harvest("player", [w], sim.node_at(Vector2i(4, 1))))
	for t: int in 100:
		sim.step()
		var hud: Dictionary = HudModel.resources(sim, "player")
		assert_eq(hud.wood, sim.resources.player.wood, "tick %d" % sim.tick)
		assert_eq(hud.gold, sim.resources.player.gold, "tick %d" % sim.tick)
	assert_eq(HudModel.resources(sim, "player").wood, 220, "two deposits in 100 ticks")


func test_ac_07_conservation_under_heavy_harvesting() -> void:
	var rng: SimRng = SimRng.new(7)
	for s: int in TestCounts.pick(3, 50):
		var m: MapGrid = MapGenerator.generate(700 + s).map
		var sim: Simulation = Simulation.new(m, s, {})
		for t: int in 2000:
			if t % 40 == 0:
				sim.submit(FuzzCommands.valid(rng, sim))
			sim.step()
			var problems: PackedStringArray = Invariants.check(sim)
			if not problems.is_empty():
				assert_eq(problems, PackedStringArray(), "map %d tick %d" % [s, sim.tick])
				return
		var gathered: int = 0
		for f: String in Consts.FACTIONS:
			gathered += sim.bank.deposited[f].wood + sim.bank.deposited[f].gold
		assert_gt(gathered, 0, "map %d: the economy actually ran (wood or gold deposited)" % s)
