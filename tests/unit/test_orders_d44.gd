## Attack-move and Shift-queued orders (build step 11, decision D-44).
extends GutTest


## An open 30 x 12 map; the AI HQ sits at (27, 9) to (29, 11), out of sight
## of row 6 west of x = 21.
func _sim() -> Simulation:
	return TestMaps.sim(TestMaps.open(30, 12))


func _run(sim: Simulation, ticks: int) -> void:
	for t: int in ticks:
		sim.step()


func _attacks_by(sim: Simulation, id: int) -> int:
	var n: int = 0
	for e: Dictionary in sim.take_events():
		if e.type == "attack" and e.attacker == id:
			n += 1
	return n


func test_d44_attack_move_fights_on_the_way_then_arrives() -> void:
	var sim: Simulation = _sim()
	var knight: int = sim.spawn_unit("melee", "player", Vector2i(3, 6))
	var enemy: int = sim.spawn_unit("worker", "ai", Vector2i(12, 6))
	sim.update_fog()
	assert_eq(sim.submit(Commands.attack_move("player", [knight], Vector2i(20, 6))), "ok")
	assert_eq(sim.entity(knight).order_type, "attack_move")
	# The worker (40 health) takes 4 hits of 10, 20 ticks apart; the walk is
	# 17 cells at 125 milli-cells per tick (136 ticks) plus the fight.
	_run(sim, 400)
	assert_null(sim.entity(enemy), "the enemy met on the way was killed")
	var k: Entity = sim.entity(knight)
	assert_eq(k.unit_cell(), Vector2i(20, 6), "then it carried on to the destination")
	assert_eq(k.order_type, "idle")
	assert_eq(k.am_cell, Simulation.NO_CELL, "the attack-move is over")


func test_d44_plain_move_walks_past_enemies() -> void:
	var sim: Simulation = _sim()
	var knight: int = sim.spawn_unit("melee", "player", Vector2i(3, 6))
	var enemy: int = sim.spawn_unit("worker", "ai", Vector2i(12, 7))
	sim.update_fog()
	sim.take_events()
	assert_eq(sim.submit(Commands.move("player", [knight], Vector2i(20, 6))), "ok")
	# 17 cells at 125 per tick = 136 ticks; stop on arrival, before an idle
	# knight would auto-acquire the worker behind it.
	_run(sim, 136)
	assert_eq(sim.entity(knight).unit_cell(), Vector2i(20, 6))
	assert_not_null(sim.entity(enemy), "a plain move does not stop to fight")
	assert_eq(_attacks_by(sim, knight), 0)


func test_d44_queued_moves_run_in_order() -> void:
	var sim: Simulation = _sim()
	var w: int = sim.spawn_unit("worker", "player", Vector2i(3, 3))
	assert_eq(sim.submit(Commands.move("player", [w], Vector2i(8, 3))), "ok")
	assert_eq(sim.submit(Commands.move("player", [w], Vector2i(8, 8), true)), "ok")
	assert_eq(sim.submit(Commands.move("player", [w], Vector2i(3, 8), true)), "ok")
	assert_eq(sim.entity(w).orders.size(), 2)
	# Each leg is 5 cells at 150 per tick: 34 ticks (rounded up), plus one
	# tick to pick up the next order.
	_run(sim, 35)
	assert_eq(sim.entity(w).unit_cell(), Vector2i(8, 3), "first leg done")
	_run(sim, 35)
	assert_eq(sim.entity(w).unit_cell(), Vector2i(8, 8), "second leg done")
	_run(sim, 40)
	assert_eq(sim.entity(w).unit_cell(), Vector2i(3, 8), "third leg done")
	assert_eq(sim.entity(w).orders.size(), 0)
	assert_eq(sim.entity(w).order_type, "idle")


func test_d44_a_plain_order_clears_the_queue() -> void:
	var sim: Simulation = _sim()
	var w: int = sim.spawn_unit("worker", "player", Vector2i(3, 3))
	sim.submit(Commands.move("player", [w], Vector2i(8, 3)))
	sim.submit(Commands.move("player", [w], Vector2i(8, 8), true))
	assert_eq(sim.submit(Commands.move("player", [w], Vector2i(3, 9))), "ok")
	assert_eq(sim.entity(w).orders.size(), 0, "D-14 still holds for plain orders")
	_run(sim, 80)
	assert_eq(sim.entity(w).unit_cell(), Vector2i(3, 9))


func test_d44_full_queue_is_rejected_and_changes_nothing() -> void:
	var sim: Simulation = _sim()
	var w: int = sim.spawn_unit("worker", "player", Vector2i(3, 3))
	for i: int in Simulation.MAX_ORDERS:
		assert_eq(sim.submit(Commands.move("player", [w], Vector2i(4 + i, 3), true)), "ok")
	var before: int = sim.state_hash()
	assert_eq(sim.submit(Commands.move("player", [w], Vector2i(15, 3), true)), "queue_full")
	assert_eq(sim.state_hash(), before)


func test_d44_queued_attack_on_a_dead_target_is_dropped() -> void:
	var sim: Simulation = _sim()
	var knight: int = sim.spawn_unit("melee", "player", Vector2i(3, 6))
	var enemy: int = sim.spawn_unit("worker", "ai", Vector2i(6, 6))
	sim.update_fog()
	sim.submit(Commands.move("player", [knight], Vector2i(3, 9)))
	assert_eq(sim.submit(Commands.attack("player", [knight], enemy, true)), "ok")
	sim.destroy_entity(enemy)
	assert_eq(sim.entity(knight).orders.size(), 0, "no queued order names a dead entity")


func test_d44_replay_reproduces_queued_and_attack_move_orders() -> void:
	var sim: Simulation = _sim()
	var knight: int = sim.spawn_unit("melee", "player", Vector2i(3, 6))
	sim.spawn_unit("worker", "ai", Vector2i(12, 6))
	sim.update_fog()
	sim.submit(Commands.attack_move("player", [knight], Vector2i(20, 6)))
	sim.submit(Commands.move("player", [knight], Vector2i(20, 2), true))
	_run(sim, 300)
	# The same set-up and commands again give the same state (determinism).
	var again: Simulation = _sim()
	var k2: int = again.spawn_unit("melee", "player", Vector2i(3, 6))
	again.spawn_unit("worker", "ai", Vector2i(12, 6))
	again.update_fog()
	again.submit(Commands.attack_move("player", [k2], Vector2i(20, 6)))
	again.submit(Commands.move("player", [k2], Vector2i(20, 2), true))
	_run(again, 300)
	assert_eq(again.state_hash(), sim.state_hash())
	assert_eq(sim.entity(knight).unit_cell(), Vector2i(20, 2), "both orders done")


func test_d44_f_then_click_gives_an_attack_move() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(main)
	main.start_match({"map": "generated", "seed": 42, "ai_policy": "balanced"})
	var game: Game = main.game
	var sim: Simulation = game.sim
	var worker: int = sim.unit_ids().filter(func(id: int) -> bool: return sim.entity(id).faction == "player")[0]
	game.select_only(worker)
	game.start_aiming()
	assert_true(game.aiming, "F arms attack-move")
	var cell: Vector2i = sim.entity(worker).unit_cell() + Vector2i(0, 3)
	game.attack_move_to((Vector2(cell) + Vector2(0.5, 0.5)) * Consts.PIXELS_PER_CELL)
	assert_false(game.aiming, "one click, then disarmed (Shift not held)")
	# A worker cannot fight, so its attack-move is a plain move.
	assert_eq(sim.entity(worker).order_type, "move")
	assert_eq(sim.entity(worker).order_cell, cell)
