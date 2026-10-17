## AC-59, AC-60, AC-62, AC-63, AC-67: the AI state machine and its firewall.
extends GutTest


func _ai(policy: String = "balanced") -> EnemyAI:
	return EnemyAI.new("ai", AIConfig.preset(policy))


# --- AC-59: static firewall check --------------------------------------------

func test_ac_59_ai_code_never_references_the_simulation() -> void:
	var banned: RegEx = RegEx.new()
	banned.compile("\\b(Simulation|Entity|Fog\\.new|ResourceManager|Invariants|MapGenerator|AIController|MatchRunner|entities|sim)\\b")
	var dir: DirAccess = DirAccess.open("res://scripts/sim/ai")
	var files: PackedStringArray = dir.get_files()
	var checked: int = 0
	for f: String in files:
		if not f.ends_with(".gd"):
			continue
		checked += 1
		var lines: PackedStringArray = FileAccess.get_file_as_string("res://scripts/sim/ai".path_join(f)).split("\n")
		for i: int in lines.size():
			var code: String = lines[i].split("#")[0]
			assert_null(banned.search(code), "%s:%d references the world: %s" % [f, i + 1, lines[i].strip_edges()])
	assert_gte(checked, 2, "enemy_ai.gd and ai_config.gd checked")


func test_ac_59_decide_takes_only_an_observation() -> void:
	var script: Script = load("res://scripts/sim/ai/enemy_ai.gd")
	for m: Dictionary in script.get_script_method_list():
		if m.name == "decide":
			assert_eq(m.args.size(), 1)
			assert_eq(m.args[0].class_name, &"Observation")
			return
	fail_test("no decide() method")


# --- AC-62: one test per row of the priority list ---------------------------

func test_ac_62_row1_visible_enemy_near_hq_gives_defend() -> void:
	var b: ObsBuilder = ObsBuilder.new(100)
	b.units("worker", 3)
	# Squared distance from (16, 21) to the HQ footprint (20..22): 4^2 = 16 <= 8^2.
	b.enemy_unit("melee", Vector2i(16, 21))
	var ai: EnemyAI = _ai()
	assert_eq(ai.next_state(b.obs), EnemyAI.DEFEND)


func test_ac_62_row1_enemy_workers_are_no_threat() -> void:
	# Decision D-34: only soldiers can attack, so only soldiers are threats.
	var b: ObsBuilder = ObsBuilder.new(100)
	b.enemy_unit("worker", Vector2i(17, 21))
	b.enemy_unit("worker", Vector2i(18, 19))
	assert_eq(_ai().next_state(b.obs), EnemyAI.ECONOMY)


func test_ac_62_row1_far_enemy_is_no_threat() -> void:
	var b: ObsBuilder = ObsBuilder.new(100)
	# (11, 21): 9^2 = 81 > 64 from the HQ.
	b.enemy_unit("melee", Vector2i(11, 21))
	assert_eq(_ai().next_state(b.obs), EnemyAI.ECONOMY)


func test_ac_62_row1_enemy_near_another_building_gives_defend() -> void:
	var b: ObsBuilder = ObsBuilder.new(100)
	b.building("barracks", Vector2i(5, 5))
	# (5, 11) to the barracks (5..6, 5..6): 5^2 = 25 <= 6^2.
	b.enemy_unit("ranged", Vector2i(5, 11))
	assert_eq(_ai().next_state(b.obs), EnemyAI.DEFEND)


func test_ac_62_row2_defend_returns_after_100_quiet_ticks() -> void:
	var ai: EnemyAI = _ai()
	var b: ObsBuilder = ObsBuilder.new(100)
	b.enemy_unit("melee", Vector2i(17, 21))
	assert_eq(ai.next_state(b.obs), EnemyAI.DEFEND)
	assert_eq(ai.next_state(ObsBuilder.new(190).obs), EnemyAI.DEFEND, "90 quiet ticks: hold")
	assert_eq(ai.next_state(ObsBuilder.new(200).obs), EnemyAI.ECONOMY, "100 quiet ticks: back")


func test_ac_62_row2_defend_returns_to_the_previous_state() -> void:
	var ai: EnemyAI = _ai()
	ai.state = EnemyAI.ATTACK
	ai.attack_start_army = 6
	var b: ObsBuilder = ObsBuilder.new(100)
	b.units("melee", 6)
	b.ghost("hq", Vector2i(2, 2))
	b.enemy_unit("melee", Vector2i(17, 21))
	assert_eq(ai.next_state(b.obs), EnemyAI.DEFEND)
	var later: ObsBuilder = ObsBuilder.new(200)
	later.units("melee", 6)
	later.ghost("hq", Vector2i(2, 2))
	assert_eq(ai.next_state(later.obs), EnemyAI.ATTACK)


func test_ac_62_row3_army_of_2_after_6_gives_recover() -> void:
	# Balanced: retreat at 40 %. 2 * 100 = 200 < 40 * 6 = 240.
	var ai: EnemyAI = _ai()
	ai.state = EnemyAI.ATTACK
	ai.attack_start_army = 6
	var b: ObsBuilder = ObsBuilder.new(500)
	b.units("melee", 2)
	b.ghost("hq", Vector2i(2, 2))
	assert_eq(ai.next_state(b.obs), EnemyAI.RECOVER)


func test_ac_62_row3_army_of_3_after_6_keeps_attacking() -> void:
	# 3 * 100 = 300 >= 240.
	var ai: EnemyAI = _ai()
	ai.state = EnemyAI.ATTACK
	ai.attack_start_army = 6
	var b: ObsBuilder = ObsBuilder.new(500)
	b.units("melee", 3)
	b.ghost("hq", Vector2i(2, 2))
	assert_eq(ai.next_state(b.obs), EnemyAI.ATTACK)


func test_ac_62_row3_no_known_target_gives_recover() -> void:
	var ai: EnemyAI = _ai()
	ai.state = EnemyAI.ATTACK
	ai.attack_start_army = 6
	var b: ObsBuilder = ObsBuilder.new(500)
	b.units("melee", 6)
	assert_eq(ai.next_state(b.obs), EnemyAI.RECOVER)


func test_ac_62_row4_six_soldiers_and_known_target_gives_attack() -> void:
	var ai: EnemyAI = _ai()
	var b: ObsBuilder = ObsBuilder.new(500)
	b.units("melee", 4)
	b.units("ranged", 2, Vector2i(18, 15))
	b.ghost("hq", Vector2i(2, 2))
	assert_eq(ai.next_state(b.obs), EnemyAI.ATTACK)
	assert_eq(ai.attack_start_army, 6)


func test_ac_62_row4_five_soldiers_is_not_enough() -> void:
	var b: ObsBuilder = ObsBuilder.new(500)
	b.units("melee", 5)
	b.ghost("hq", Vector2i(2, 2))
	assert_eq(_ai().next_state(b.obs), EnemyAI.ECONOMY)


func test_ac_62_row5_five_workers_and_barracks_money_gives_build() -> void:
	var b: ObsBuilder = ObsBuilder.new(500, 120, 60)
	b.units("worker", 5)
	assert_eq(_ai().next_state(b.obs), EnemyAI.BUILD)


func test_ac_62_row5_needs_all_three_conditions() -> void:
	var few: ObsBuilder = ObsBuilder.new(500, 120, 60)
	few.units("worker", 4)
	assert_eq(_ai().next_state(few.obs), EnemyAI.ECONOMY, "4 workers")
	var poor: ObsBuilder = ObsBuilder.new(500, 119, 60)
	poor.units("worker", 5)
	assert_eq(_ai().next_state(poor.obs), EnemyAI.ECONOMY, "119 wood")
	var has: ObsBuilder = ObsBuilder.new(500, 120, 60)
	has.units("worker", 5)
	has.building("barracks", Vector2i(10, 10), false)
	assert_eq(_ai().next_state(has.obs), EnemyAI.ECONOMY, "a barracks is being built")


func test_ac_62_row6_otherwise_economy() -> void:
	var b: ObsBuilder = ObsBuilder.new(100, 50, 0)
	b.units("worker", 3)
	assert_eq(_ai().next_state(b.obs), EnemyAI.ECONOMY)


func test_ac_62_build_issues_a_placement_then_returns_to_economy() -> void:
	var ai: EnemyAI = _ai()
	var b: ObsBuilder = ObsBuilder.new(500, 120, 60)
	var workers: Array[int] = b.units("worker", 5)
	var cmds: Array[Dictionary] = ai.decide(b.obs)
	assert_eq(ai.state, EnemyAI.BUILD)
	var builds: Array = cmds.filter(func(c: Dictionary) -> bool: return c.command == "build")
	assert_eq(builds.size(), 1, "one barracks placement")
	assert_true(workers.has(builds[0].args.worker_id))
	# Next decision: the barracks exists (being built), so back to ECONOMY.
	var after: ObsBuilder = ObsBuilder.new(510, 0, 0)
	after.units("worker", 5)
	after.building("barracks", Vector2i(builds[0].args.cell[0], builds[0].args.cell[1]), false)
	ai.next_state(after.obs)
	assert_eq(ai.state, EnemyAI.ECONOMY)


# --- AC-63: one command per unit per decision ----------------------------------

func test_ac_63_no_unit_gets_two_commands_in_one_decision() -> void:
	var b: ObsBuilder = ObsBuilder.new(100, 1000, 1000)
	b.units("worker", 8)
	b.units("melee", 7, Vector2i(10, 12))
	b.units("ranged", 3, Vector2i(10, 8))
	b.building("barracks", Vector2i(14, 20))
	b.node("wood", Vector2i(24, 18))
	b.node("gold", Vector2i(25, 25))
	b.ghost("hq", Vector2i(2, 2))
	b.enemy_unit("melee", Vector2i(18, 22))
	for state: String in [EnemyAI.ECONOMY, EnemyAI.BUILD, EnemyAI.DEFEND, EnemyAI.ATTACK, EnemyAI.RECOVER]:
		var ai: EnemyAI = _ai()
		ai.state = state
		ai.attack_start_army = 10
		var counts: Dictionary = {}
		for c: Dictionary in ai.decide(b.obs):
			for id: int in EnemyAI.unit_ids_of(c):
				counts[id] = counts.get(id, 0) + 1
		for id: int in counts:
			assert_eq(counts[id], 1, "%s: unit %d commanded once" % [state, id])


# --- AC-67: the decision log -----------------------------------------------------

func test_ac_67_every_state_change_is_logged_with_tick_and_reason() -> void:
	var ai: EnemyAI = _ai()
	var seen: Array[String] = [ai.state]
	var b1: ObsBuilder = ObsBuilder.new(100, 120, 60)
	b1.units("worker", 5)
	ai.next_state(b1.obs)                  # BUILD
	seen.append(ai.state)
	var b2: ObsBuilder = ObsBuilder.new(110)
	b2.units("worker", 5)
	b2.enemy_unit("melee", Vector2i(17, 21))
	ai.next_state(b2.obs)                  # DEFEND
	seen.append(ai.state)
	ai.next_state(ObsBuilder.new(300).obs)  # back to BUILD (the previous state)
	seen.append(ai.state)
	assert_eq(seen, [EnemyAI.ECONOMY, EnemyAI.BUILD, EnemyAI.DEFEND, EnemyAI.BUILD])
	assert_eq(ai.history.size(), 3, "three changes, three log entries")
	for i: int in ai.history.size():
		var h: Dictionary = ai.history[i]
		assert_eq(h.from, seen[i])
		assert_eq(h.to, seen[i + 1])
		assert_true(h.tick in [100, 110, 300])
		assert_gt((h.reason as String).length(), 5, "has a reason")


# --- AC-60: metamorphic test --------------------------------------------------------

func test_ac_60_hidden_player_units_do_not_change_ai_commands() -> void:
	var m: MapGrid = MapGenerator.generate(60).map
	var a: Simulation = Simulation.new(m, 60, {})
	var b: Simulation = Simulation.new(m, 60, {})
	# The two worlds differ only in where three player units stand, all far
	# from anything the AI can see.
	var hq: Vector2i = m.starts["player"]
	for i: int in 3:
		a.spawn_unit("melee", "player", _free_near(a, hq + Vector2i(4 + i, 4)))
		b.spawn_unit("melee", "player", _free_near(b, hq + Vector2i(i, 7)))
	assert_ne(a.state_hash(), b.state_hash(), "the worlds really differ")
	var ca: AIController = AIController.new("ai", AIConfig.preset("balanced"))
	var cb: AIController = AIController.new("ai", AIConfig.preset("balanced"))
	for t: int in TestCounts.pick(600, 1200):
		var cmds_a: Array[Dictionary] = ca.before_step(a)
		var cmds_b: Array[Dictionary] = cb.before_step(b)
		assert_eq(cmds_a, cmds_b, "tick %d: identical AI commands" % a.tick)
		if cmds_a != cmds_b:
			return
		a.step()
		b.step()
	for id: int in a.entities:
		var e: Entity = a.entities[id]
		if e.faction == "player" and e.is_unit():
			assert_false(a.fog.is_visible("ai", e.unit_cell()), "player units stayed hidden from the AI")


func _free_near(sim: Simulation, c: Vector2i) -> Vector2i:
	for r: int in 6:
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				if not sim.is_solid(c + Vector2i(dx, dy)):
					return c + Vector2i(dx, dy)
	return c
