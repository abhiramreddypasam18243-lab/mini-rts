## AC-61, AC-63 to AC-66: whole headless matches with the Balanced AI against
## an opponent that issues no commands. Fast suite: a few matches; long
## suite: the full counts of the spec (decision D-20).
extends GutTest

static var _vs_passive: Array[Dictionary] = []


## AC-66 set-up, shared by AC-61, AC-63 and AC-64: generated maps, 18,000 ticks.
func _passive_matches() -> Array[Dictionary]:
	if _vs_passive.is_empty():
		for s: int in TestCounts.pick(3, 100):
			var m: MapGrid = MapGenerator.generate(6600 + s).map
			_vs_passive.append(MatchRunner.run(m, s, {"ai": "balanced"}, 18000))
	return _vs_passive


func test_ac_61_zero_firewall_violations() -> void:
	var total: int = 0
	for r: Dictionary in _passive_matches():
		total += r.ai.violations
	assert_eq(total, 0, "AI commands naming unobserved entities over %d matches" % _passive_matches().size())


func test_ac_63_no_decision_commands_a_unit_twice() -> void:
	var total: int = 0
	for r: Dictionary in _passive_matches():
		total += r.ai.multi_command_decisions
	assert_eq(total, 0)


func test_ac_64_never_quiet_for_more_than_200_ticks_and_stuck_triggers_fallback() -> void:
	var longest: int = 0
	for r: Dictionary in _passive_matches():
		longest = maxi(longest, r.ai.longest_quiet)
		assert_eq(r.ai.stuck, r.ai.fallbacks, "seed %d: every stuck event triggers the fallback" % r.seed)
	gut.p("AC-64 measured: longest quiet stretch %d ticks" % longest)
	assert_lte(longest, 200)


func test_ac_66_balanced_beats_a_passive_opponent() -> void:
	var results: Array[Dictionary] = _passive_matches()
	var wins: int = 0
	var slowest: int = 0
	for r: Dictionary in results:
		if r.result == "victory_ai":
			wins += 1
			slowest = maxi(slowest, r.ticks)
	# At least 95 % of the matches, rounded up.
	var needed: int = (95 * results.size() + 99) / 100
	gut.p("AC-66 measured: %d / %d wins, slowest win at tick %d" % [wins, results.size(), slowest])
	assert_gte(wins, needed)


func test_ac_65_tutorial_barracks_and_three_soldiers_by_6000_ticks() -> void:
	var map: MapGrid = MapGrid.load_file("res://data/maps/tutorial.json").map
	var n: int = TestCounts.pick(3, 20)
	var ok: int = 0
	for s: int in n:
		var r: Dictionary = MatchRunner.run(map, s, {"ai": "balanced"}, 6000)
		var built: bool = r.ai.first_barracks_tick >= 0 and r.ai.first_barracks_tick <= 6000
		if built and r.ai.soldiers_trained >= 3:
			ok += 1
		else:
			gut.p("seed %d: barracks at %d, %d soldiers, states %s" % [s, r.ai.first_barracks_tick, r.ai.soldiers_trained, r.ai.history])
	assert_eq(ok, n, "%d of %d seeds" % [ok, n])
