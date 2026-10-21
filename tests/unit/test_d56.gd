## AC-106 (peace time and a gentler Easy) and AC-107 (easier controls),
## decision D-56.
extends GutTest


# --- AC-106 -----------------------------------------------------------------

func test_ac_106_peace_time_only_in_games_from_the_menu() -> void:
	# 6, 3 and 1.5 minutes at 20 ticks per second.
	assert_eq(AIConfig.for_game("balanced:easy").peace_ticks, 6 * 60 * 20)
	assert_eq(AIConfig.for_game("balanced").peace_ticks, 3 * 60 * 20)
	assert_eq(AIConfig.for_game("aggressive:hard").peace_ticks, 90 * 20)
	for name: String in ["balanced", "aggressive", "economy_first", "balanced:hard", "balanced:easy"]:
		assert_eq(AIConfig.preset(name).peace_ticks, 0, name + ": presets (experiment, tests) have no peace time")


func test_ac_106_easy_queues_one_item_at_a_time() -> void:
	assert_eq(AIConfig.preset("balanced:easy").max_queue, 1)
	assert_eq(AIConfig.preset("balanced").max_queue, 2)


func test_ac_106_no_attack_during_peace_time() -> void:
	# Aggressive with Normal's 3-minute peace against a passive player: its
	# army is ready long before tick 3600, but it may not attack (or scout and
	# fight at the player's base) until then.
	for s: int in TestCounts.pick(2, 10):
		var sim: Simulation = Simulation.new(MapGenerator.generate(7400 + s).map, s, {})
		var c: AIConfig = AIConfig.for_game("aggressive")
		var ai: AIController = AIController.new("ai", c)
		var first_attack: int = -1
		while sim.tick < 9000 and sim.match_result == "":
			ai.before_step(sim)
			sim.step()
			for ev: Dictionary in sim.take_events():
				if ev.type == "attack" and first_attack < 0 and sim.entity(ev.attacker) != null and sim.entity(ev.attacker).faction == "ai":
					first_attack = sim.tick
		var attack_states: Array = ai.ai.history.filter(func(h: Dictionary) -> bool: return h.to == EnemyAI.ATTACK)
		gut.p("AC-106 measured: seed %d: first ATTACK state at %s, first AI hit at tick %d" % [s, attack_states[0].tick if not attack_states.is_empty() else "never", first_attack])
		for h: Dictionary in attack_states:
			assert_gte(int(h.tick), c.peace_ticks, "seed %d: no ATTACK state before tick %d" % [s, c.peace_ticks])
		# Not even a scout hits the player before peace time ends.
		assert_true(first_attack < 0 or first_attack >= c.peace_ticks, "seed %d: first AI hit at tick %d" % [s, first_attack])
		assert_false(attack_states.is_empty(), "seed %d: it does attack once peace is over" % s)


# --- AC-107 -----------------------------------------------------------------

func test_ac_107_auto_gather_prefers_the_finished_farm_then_the_nearest_known_node() -> void:
	var m: MapGrid = TestMaps.open(30, 12, [], [{"type": "wood", "cell": Vector2i(9, 5), "amount": 500},
		{"type": "gold", "cell": Vector2i(6, 8), "amount": 300}, {"type": "wood", "cell": Vector2i(25, 5), "amount": 500}])
	var sim: Simulation = Simulation.new(m, 1, {"start_workers": 0})
	var w: int = sim.spawn_unit("worker", "player", Vector2i(5, 5))
	sim.update_fog()
	# Distances from (5, 5): gold (6, 8) = 1 + 9 = 10 cells², wood (9, 5) = 16.
	var g: Dictionary = CommandAids.auto_gather(sim, "player", w)
	assert_eq(g.command, "harvest")
	assert_eq(g.args.node_id, sim.node_at(Vector2i(6, 8)), "the nearest node the player knows")
	var farm: int = sim.place_building_unchecked("farm", "player", Vector2i(3, 6), true)
	assert_eq(CommandAids.auto_gather(sim, "player", w, farm).args.node_id, farm, "a farm's builder farms it")
	var enemy_farm: int = sim.place_building_unchecked("farm", "ai", Vector2i(12, 8), true)
	assert_ne(CommandAids.auto_gather(sim, "player", w, enemy_farm).args.node_id, enemy_farm, "never an enemy farm")
	assert_eq(sim.submit(g), "ok")


func test_ac_107_auto_gather_ignores_unknown_nodes() -> void:
	var m: MapGrid = TestMaps.open(30, 12, [], [{"type": "wood", "cell": Vector2i(25, 5), "amount": 500}])
	var sim: Simulation = Simulation.new(m, 1, {"start_workers": 0})
	var w: int = sim.spawn_unit("worker", "player", Vector2i(5, 5))
	sim.update_fog()
	assert_eq(CommandAids.auto_gather(sim, "player", w), {}, "the only node is in unexplored fog")


func test_ac_107_double_click_and_select_all_soldiers() -> void:
	var sim: Simulation = Simulation.new(TestMaps.open(30, 12), 1, {"start_workers": 0})
	var m1: int = sim.spawn_unit("melee", "player", Vector2i(5, 5))
	var m2: int = sim.spawn_unit("melee", "player", Vector2i(7, 5))
	var far: int = sim.spawn_unit("melee", "player", Vector2i(25, 5))
	var r: int = sim.spawn_unit("ranged", "player", Vector2i(6, 5))
	sim.spawn_unit("melee", "ai", Vector2i(8, 5))
	sim.spawn_unit("worker", "player", Vector2i(6, 6))
	# A view of cells 0..15 x 0..11 (32 px per cell).
	var view: Rect2 = Rect2(0, 0, 16 * 32, 12 * 32)
	assert_eq(CommandAids.same_kind_in(sim, "player", "melee", view), [m1, m2], "own melee in view only")
	assert_eq(CommandAids.all_soldiers(sim, "player"), [m1, m2, far, r], "every own soldier, no workers")


func test_ac_107_units_are_easier_to_click() -> void:
	var sim: Simulation = Simulation.new(TestMaps.open(30, 12), 1, {"start_workers": 0})
	var u: int = sim.spawn_unit("melee", "player", Vector2i(5, 5))
	# The unit stands at (5500, 5500); a click 550 milli-cells away now picks
	# it (the old radius was 420), 650 away does not.
	assert_eq(Selection.pick(sim, "player", Vector2i(5500 + 550, 5500)), u)
	assert_ne(Selection.pick(sim, "player", Vector2i(5500 + 650, 5500)), u)
