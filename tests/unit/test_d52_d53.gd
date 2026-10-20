## AC-102 (difficulty, decision D-52) and AC-103 (map styles, D-53).
extends GutTest


# --- AC-102: difficulty --------------------------------------------------------

func test_ac_102_normal_is_the_policy_unchanged() -> void:
	for name: String in AIConfig.PRESETS:
		var plain: AIConfig = AIConfig.preset(name)
		var normal: AIConfig = AIConfig.preset(name + ":normal")
		var p: Array = AIConfig.PRESETS[name]
		assert_eq([plain.worker_target, plain.build_worker_min, plain.army_threshold, plain.retreat_pct, plain.mix_melee, plain.mix_ranged], p, name)
		assert_eq([normal.worker_target, normal.army_threshold, normal.decide_every, normal.max_towers, normal.focus_fire, normal.wounded_pct, normal.raid],
			[plain.worker_target, plain.army_threshold, 1, 1, false, 0, false], name + ":normal")


func test_ac_102_easy_and_hard_settings() -> void:
	var easy: AIConfig = AIConfig.preset("balanced:easy")
	assert_eq(easy.decide_every, 3)
	assert_eq(easy.worker_target, 4, "min(6, 4)")
	assert_eq(easy.army_threshold, 4, "6 - 2")
	assert_eq(easy.max_towers, 0)
	assert_false(easy.research)
	var hard: AIConfig = AIConfig.preset("balanced:hard")
	assert_true(hard.focus_fire)
	assert_eq(hard.wounded_pct, 30)
	assert_eq(hard.max_towers, 2)
	assert_eq(hard.army_threshold, 8, "6 + 2")


func test_ac_102_easy_decides_on_every_third_decision_tick() -> void:
	var sim: Simulation = Simulation.new(MapGenerator.generate(3).map, 3, {})
	var easy: AIController = AIController.new("ai", AIConfig.preset("balanced:easy"))
	var normal: AIController = AIController.new("player", AIConfig.preset("balanced"))
	for _t: int in 60:
		easy.before_step(sim)
		normal.before_step(sim)
		sim.step()
	# Decision ticks 0, 10, ..., 50: Normal uses all 6, Easy ticks 0 and 30.
	assert_eq(normal.decisions, 6)
	assert_eq(easy.decisions, 2)


## A Hard AI melee soldier at (10, 5) with two player soldiers in reach: a
## healthy one at (11, 5) (lower id) and a wounded one at (10, 6).
func _focus_case(level: String) -> Dictionary:
	var sim: Simulation = Simulation.new(TestMaps.open(30, 12), 1, {"start_workers": 0})
	var healthy: int = sim.spawn_unit("melee", "player", Vector2i(11, 5))
	var wounded: int = sim.spawn_unit("melee", "player", Vector2i(10, 6))
	sim.entity(wounded).hp = 20
	var me: int = sim.spawn_unit("melee", "ai", Vector2i(10, 5))
	sim.update_fog()
	var ai: EnemyAI = EnemyAI.new("ai", AIConfig.preset("balanced" + level))
	var obs: Observation = sim.observation("ai")
	ai._read(obs)
	var s: Dictionary = {}
	for u: Dictionary in obs.own_units:
		if u.id == me:
			s = u
	return {"pick": ai._pick_enemy(s, obs.enemy_units).id, "healthy": healthy, "wounded": wounded}


func test_ac_102_hard_focuses_the_weakest_enemy_in_reach() -> void:
	var hard: Dictionary = _focus_case(":hard")
	assert_eq(hard.pick, hard.wounded, "Hard finishes the wounded soldier")
	var normal: Dictionary = _focus_case("")
	assert_eq(normal.pick, normal.healthy, "Normal takes the nearest (tie: first seen, lower id)")


func test_ac_102_hard_pulls_back_a_wounded_soldier() -> void:
	var sim: Simulation = Simulation.new(TestMaps.open(30, 12), 1, {"start_workers": 0})
	sim.spawn_unit("melee", "player", Vector2i(20, 5))
	# The first AI soldier scouts while no enemy building is known, so the
	# healthy one is spawned first; the wounded one belongs to the army.
	var fine: int = sim.spawn_unit("melee", "ai", Vector2i(18, 6))
	var hurt: int = sim.spawn_unit("melee", "ai", Vector2i(18, 5))
	sim.entity(hurt).hp = 29  # below 30 % of 100
	sim.update_fog()
	var ai: EnemyAI = EnemyAI.new("ai", AIConfig.preset("balanced:hard"))
	ai._read(sim.observation("ai"))
	var out: Array[Dictionary] = []
	var used: Dictionary = {}
	ai._do_tactics(out, used)
	assert_eq(out.size(), 1)
	assert_eq(out[0].command, "move")
	assert_eq(out[0].args.unit_ids, [hurt], "only the wounded soldier walks back")
	assert_false(used.has(fine))


func test_ac_102_easy_loses_to_normal() -> void:
	# Seeds played twice with sides swapped; measured, and Easy must win less.
	var easy_wins: int = 0
	var normal_wins: int = 0
	var hard_wins: int = 0
	var normal_vs_hard: int = 0
	for s: int in TestCounts.pick(3, 20):
		var m: MapGrid = MapGenerator.generate(7100 + s).map
		for swap: bool in [false, true]:
			var a: String = "ai" if swap else "player"
			var b: String = "player" if swap else "ai"
			var r: Dictionary = MatchRunner.run(m, s, {a: "balanced:easy", b: "balanced"}, 36000)
			easy_wins += 1 if r.result == "victory_" + a else 0
			normal_wins += 1 if r.result == "victory_" + b else 0
			var h: Dictionary = MatchRunner.run(m, s, {a: "balanced:hard", b: "balanced"}, 36000)
			hard_wins += 1 if h.result == "victory_" + a else 0
			normal_vs_hard += 1 if h.result == "victory_" + b else 0
	gut.p("AC-102 measured: Easy %d - %d Normal; Hard %d - %d Normal" % [easy_wins, normal_wins, hard_wins, normal_vs_hard])
	assert_lt(easy_wins, normal_wins, "Easy is weaker than Normal")


# --- AC-103: map styles ----------------------------------------------------

func _symmetric(m: MapGrid) -> bool:
	for y: int in m.height:
		for x: int in m.width:
			var mc: Vector2i = MapGenerator.mirror(Vector2i(x, y), m.width)
			if m.blocked[y * m.width + x] != m.blocked[mc.y * m.width + mc.x]:
				return false
	var cells: Dictionary = {}
	for n: Dictionary in m.nodes:
		cells[n.cell] = n.type
	for n: Dictionary in m.nodes:
		if cells.get(MapGenerator.mirror(n.cell, m.width), "") != n.type:
			return false
	return true


func test_ac_103_river_and_highlands_are_symmetric_and_valid() -> void:
	for style: String in ["river", "highlands"]:
		for s: int in TestCounts.pick(6, 50):
			var r: Dictionary = MapGenerator.generate(s, 48, style)
			assert_eq(r.error, "", "%s %d generated" % [style, s])
			var m: MapGrid = r.map
			assert_eq(m.map_name, "%s-%d" % [style, s])
			assert_true(_symmetric(m), "%s %d is point-symmetric" % [style, s])
			# The generator only accepts maps whose HQs are connected and have
			# 2 wood + 1 gold within 15 steps (AC-10's check).
			assert_true(MapGenerator._acceptable(m), "%s %d is acceptable" % [style, s])


func test_ac_103_river_is_crossed_only_at_three_fords() -> void:
	var m: MapGrid = MapGenerator.generate(5, 48, "river").map
	var crossings: Array[int] = []
	# Walk along the river's middle line x + y = 47; a ford is a run of walkable cells.
	var in_ford: bool = false
	for x: int in 48:
		var c: Vector2i = Vector2i(x, 47 - x)
		var open: bool = m.is_walkable(c)
		if open and not in_ford:
			crossings.append(x - c.y)
		in_ford = open
		if not open:
			assert_eq(m.look.get(c, ""), "water", "%s is drawn as water" % c)
	assert_eq(crossings.size(), 3, "three fords")
	for f: int in MapGenerator.FORDS:
		assert_true(m.is_walkable(Vector2i((47 + f) / 2, 47 - (47 + f) / 2)), "ford at x - y = %d" % f)


func test_ac_103_highlands_has_ridges_and_extra_gold() -> void:
	for s: int in TestCounts.pick(4, 30):
		var m: MapGrid = MapGenerator.generate(s, 48, "highlands").map
		var gold: int = 0
		for n: Dictionary in m.nodes:
			gold += 1 if n.type == "gold" else 0
		# 1 guaranteed + at least 3 extra pairs: 8 gold nodes at least
		# (an extra pair is skipped only if 30 random tries all fail).
		assert_gte(gold, 6, "seed %d gold nodes" % s)
		assert_gt(m.look.values().count("rock"), 20, "seed %d has ridges" % s)


func test_ac_103_classic_maps_are_unchanged() -> void:
	for s: int in [1, 7, 42]:
		var a: MapGrid = MapGenerator.generate(s).map
		var b: MapGrid = MapGenerator.generate(s, 48, "classic").map
		assert_eq(a.blocked, b.blocked)
		assert_eq(a.nodes, b.nodes)
		assert_true(a.look.is_empty(), "classic maps have no drawing hints")
