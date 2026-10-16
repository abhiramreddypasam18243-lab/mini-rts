## AC-51 to AC-53: end of match and restart.
extends GutTest


func _results(events: Array[Dictionary]) -> Array:
	var out: Array = []
	for e: Dictionary in events:
		if e.type == "match_ended":
			out.append(e.result)
	return out


func _run(sim: Simulation, ticks: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for _i: int in ticks:
		sim.step()
		events.append_array(sim.take_events())
	return events


func test_ac_51_hq_destroyed_in_combat_raises_one_victory() -> void:
	var sim: Simulation = TestMaps.sim(TestMaps.open(20, 12))
	var ai_hq: int = sim.hq_of("ai")  # covers (17..19, 9..11)
	sim.entity(ai_hq).hp = 10
	var a: int = sim.spawn_unit("melee", "player", Vector2i(16, 10))
	sim.submit(Commands.attack("player", [a], ai_hq))
	var events: Array[Dictionary] = _run(sim, 100)
	assert_eq(_results(events), ["victory_player"], "exactly one result")
	assert_eq(sim.match_result, "victory_player")
	assert_eq(sim.results_raised, 1)


func test_ac_51_player_hq_lost_is_defeat() -> void:
	var sim: Simulation = TestMaps.sim(TestMaps.open(20, 12))
	sim.destroy_entity(sim.hq_of("player"))
	assert_eq(_results(_run(sim, 50)), ["victory_ai"])


func test_ac_51_both_hqs_in_same_tick_is_draw() -> void:
	var sim: Simulation = TestMaps.sim(TestMaps.open(20, 12))
	var a: int = sim.spawn_unit("melee", "player", Vector2i(16, 10))
	var b: int = sim.spawn_unit("melee", "ai", Vector2i(3, 1))
	sim.entity(sim.hq_of("ai")).hp = 10
	sim.entity(sim.hq_of("player")).hp = 10
	sim.submit(Commands.attack("player", [a], sim.hq_of("ai")))
	sim.submit(Commands.attack("ai", [b], sim.hq_of("player")))
	assert_eq(_results(_run(sim, 20)), ["draw"])


func test_ac_51_tick_limit_is_timeout() -> void:
	var sim: Simulation = Simulation.new(TestMaps.open(20, 12), 1, {"max_ticks": 50})
	var events: Array[Dictionary] = _run(sim, 49)
	assert_eq(_results(events), [], "still running at tick 49")
	events = _run(sim, 10)
	assert_eq(_results(events), ["timeout"])
	assert_eq(sim.tick, 50)


func test_ac_52_after_the_end_commands_fail_and_state_freezes() -> void:
	var sim: Simulation = TestMaps.sim(TestMaps.open(20, 12))
	var w: int = sim.spawn_unit("worker", "player", Vector2i(8, 6))
	var hq: int = sim.hq_of("player")
	sim.destroy_entity(sim.hq_of("ai"))
	sim.step()
	assert_eq(sim.match_result, "victory_player")
	var frozen: int = sim.state_hash()
	assert_eq(sim.submit(Commands.move("player", [w], Vector2i(10, 6))), "match_over")
	assert_eq(sim.submit(Commands.train("player", hq, "worker")), "match_over")
	assert_eq(sim.submit(Commands.cancel_train("player", hq, -1)), "match_over")
	assert_eq(sim.submit(Commands.move("player", [9999], Vector2i(1, 1))), "match_over")
	for _i: int in 100:
		sim.step()
	assert_eq(sim.state_hash(), frozen)


func test_ac_53_restart_with_same_seed_is_a_fresh_match() -> void:
	var m: MapGrid = MapGenerator.generate(53).map
	var map_before: String = m.fingerprint()
	var fresh_hash: int = Simulation.new(m, 53, {}).state_hash()
	# Play a match with commands until it has changed a lot.
	var rng: SimRng = SimRng.new(53)
	var first: Simulation = Simulation.new(m, 53, {})
	for t: int in 1500:
		if t % 20 == 0:
			first.submit(FuzzCommands.valid(rng, first))
		first.step()
	assert_ne(first.state_hash(), fresh_hash, "the first match changed state")
	# Restart: a new simulation from the same map and seed.
	var restarted: Simulation = Simulation.new(m, 53, {})
	assert_eq(m.fingerprint(), map_before, "the match did not modify the map")
	assert_eq(restarted.state_hash(), fresh_hash, "same hash as a fresh process")
	assert_eq(restarted.tick, 0)
	assert_eq(restarted.command_log.size(), 0, "no commands carried over")
	assert_eq(restarted.take_events().size(), 0, "no messages carried over")
	for id: int in restarted.entities:
		var e: Entity = restarted.entities[id]
		assert_eq(e.order_type, "idle", "no orders carried over")
		assert_eq(e.cooldown, 0, "no timers carried over")
