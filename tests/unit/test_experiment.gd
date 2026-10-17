## AC-04, AC-68 to AC-70: replays of real matches, the headless runner,
## its CSV output, its speed, and the Wilson interval.
extends GutTest


func test_ac_04_replay_of_an_ai_match_reproduces_hash_and_result() -> void:
	var m: MapGrid = MapGenerator.generate(404).map
	var r: Dictionary = MatchRunner.run(m, 404, {"player": "aggressive", "ai": "balanced"}, TestCounts.pick(4000, 36000), true)
	assert_gt(r.commands, 50, "the AIs issued real commands")
	var played: Dictionary = Replay.play(r.replay, Replay.map_for(m.map_name))
	assert_eq(played.error, "")
	var sim: Simulation = played.sim
	assert_eq(sim.state_hash(), r.hash, "same final state")
	assert_eq(sim.match_result, r.result, "same result")
	assert_eq(sim.tick, r.ticks)


func test_ac_04_map_for_rebuilds_generated_and_tutorial_maps() -> void:
	assert_eq(Replay.map_for("generated-77").fingerprint(), MapGenerator.generate(77).map.fingerprint())
	assert_eq(Replay.map_for("tutorial").map_name, "tutorial")


func test_ac_68_runner_swaps_sides_and_writes_csv_columns() -> void:
	var rows: Array[Dictionary] = Experiment.run_batch([5, 6], "aggressive", "balanced", 3000)
	assert_eq(rows.size(), 4, "2 seeds x 2 side assignments")
	assert_eq(rows.map(func(r: Dictionary) -> int: return r.seed), [5, 5, 6, 6])
	assert_eq(rows.map(func(r: Dictionary) -> bool: return r.a_is_player_start), [true, false, true, false])
	for r: Dictionary in rows:
		assert_eq(r.side_a_policy, "aggressive")
		assert_eq(r.side_b_policy, "balanced")
		assert_true(r.winner in ["A", "B", ""], "winner")
		assert_true(r.outcome in ["victory", "draw", "timeout"], "outcome")
		assert_lte(r.duration_ticks, 3000)
	var csv: String = Experiment.to_csv(rows)
	var lines: PackedStringArray = csv.strip_edges().split("\n")
	assert_eq(lines[0], "seed,map,side_a_policy,side_b_policy,a_is_player_start,winner,outcome,duration_ticks,first_attack_tick,wood_gathered_a,gold_gathered_a,units_lost_a,wood_gathered_b,gold_gathered_b,units_lost_b")
	assert_eq(lines.size(), 5, "header + one row per match")
	assert_eq(lines[1].split(",").size(), 15)
	# Reading the CSV back gives the same rows.
	assert_eq(Experiment.from_csv(csv), rows.map(func(r: Dictionary) -> Dictionary: return Experiment.csv_fields(r)))


func test_ac_68_side_swap_puts_each_policy_on_each_start() -> void:
	var rows: Array[Dictionary] = Experiment.run_batch([9], "aggressive", "balanced", 600)
	# Match 1: A plays from the player start; match 2: A plays from the AI start.
	assert_eq(rows[0].slots, {"player": "aggressive", "ai": "balanced"})
	assert_eq(rows[1].slots, {"player": "balanced", "ai": "aggressive"})


func test_ac_68_winner_is_the_side_whose_policy_won() -> void:
	var side: Dictionary = {"wood": 0, "gold": 0, "units_lost": 0}
	var r: Dictionary = {"result": "victory_ai", "ticks": 100, "first_attack_tick": 50, "player": side, "ai": side}
	# A started on the AI's start position, and the AI start won: A won.
	assert_eq(Experiment.make_row(r, 1, "m", "x", "y", "ai").winner, "A")
	assert_eq(Experiment.make_row(r, 1, "m", "x", "y", "player").winner, "B")
	r.result = "victory_player"
	assert_eq(Experiment.make_row(r, 1, "m", "x", "y", "player").winner, "A")
	r.result = "draw"
	var d: Dictionary = Experiment.make_row(r, 1, "m", "x", "y", "player")
	assert_eq([d.winner, d.outcome], ["", "draw"])
	r.result = "timeout"
	assert_eq(Experiment.make_row(r, 1, "m", "x", "y", "ai").outcome, "timeout")


func test_ac_69_full_match_runs_at_least_60_times_real_time() -> void:
	# A 36,000-tick match is 30 minutes of game time; the target is 30 s of
	# real time. Balanced vs Balanced, measured per tick and scaled to 36,000.
	var m: MapGrid = MapGenerator.generate(69).map
	var ticks: int = TestCounts.pick(6000, 36000)
	var t0: int = Time.get_ticks_usec()
	var r: Dictionary = MatchRunner.run(m, 69, {"player": "balanced", "ai": "balanced"}, ticks)
	var usec: int = Time.get_ticks_usec() - t0
	var per_36000_ms: int = usec * 36000 / maxi(r.ticks, 1) / 1000
	gut.p("AC-69 measured: %d ticks in %d ms -> %d ms per 30-minute match (result %s)" % [r.ticks, usec / 1000, per_36000_ms, r.result])
	assert_lte(per_36000_ms, 30000, "initial target: at most 30 s")


func test_ac_70_wilson_interval_120_of_200() -> void:
	var ci: Vector2 = Stats.wilson(120, 200)
	assert_almost_eq(ci.x, 0.531, 0.002)
	assert_almost_eq(ci.y, 0.665, 0.002)


func test_ac_70_wilson_edge_cases() -> void:
	var zero: Vector2 = Stats.wilson(0, 10)
	assert_eq(zero.x, 0.0, "never below 0")
	assert_gt(zero.y, 0.0, "unlike the normal approximation, not a zero-width interval")
	var all: Vector2 = Stats.wilson(10, 10)
	assert_almost_eq(all.y, 1.0, 1e-9, "never above 1")
	assert_eq(Stats.wilson(0, 0), Vector2(0.0, 1.0), "no data: no information")
