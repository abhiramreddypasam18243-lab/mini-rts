## AC-97 to AC-101 (stretch, decision D-51): food and farms, the guard tower,
## the stable and cavalry, upgrades, and the AI using all of them.
extends GutTest


## 16 x 10 open map; player HQ (0..2, 0..2), AI HQ (13..15, 7..9).
func _sim(config: Dictionary = {}) -> Simulation:
	var cfg: Dictionary = {"start_workers": 0}
	cfg.merge(config, true)
	return Simulation.new(TestMaps.open(16, 10), 1, cfg)


func _rich() -> Simulation:
	return Simulation.new(TestMaps.open(16, 10), 1, {"start_workers": 0, "start_wood": 5000, "start_gold": 5000, "start_food": 5000})


func _assert_clean(sim: Simulation) -> void:
	assert_eq(Invariants.check(sim), PackedStringArray())


# --- AC-97: food and farms ----------------------------------------------------

func test_ac_97_each_faction_starts_with_100_food() -> void:
	var sim: Simulation = _sim()
	assert_eq(sim.resources.player.food, 100)
	assert_eq(sim.resources.ai.food, 100)


func test_ac_97_worker_carries_10_food_per_trip_from_a_farm() -> void:
	# The farm covers (4..5, 0..1); the worker at (3, 1) touches it and the HQ
	# (0..2, 0..2), so a trip is 40 ticks of gathering plus the deposit.
	var sim: Simulation = _sim()
	var farm: int = sim.place_building_unchecked("farm", "player", Vector2i(4, 0), true)
	assert_eq(sim.entity(farm).amount, 400, "a finished farm holds 400 food")
	var w: int = sim.spawn_unit("worker", "player", Vector2i(3, 1))
	assert_eq(sim.submit(Commands.harvest("player", [w], farm)), "ok")
	for _t: int in 39:
		sim.step()
	assert_eq(sim.resources.player.food, 100, "nothing yet after 39 ticks")
	sim.step()
	sim.step()
	assert_eq(sim.resources.player.food, 110, "+10 food within 41 ticks")
	assert_eq(sim.entity(farm).amount, 390)
	_assert_clean(sim)


func test_ac_97_empty_farm_is_removed_and_worker_goes_idle() -> void:
	var sim: Simulation = _sim()
	var farm: int = sim.place_building_unchecked("farm", "player", Vector2i(4, 0), true)
	sim.entity(farm).amount = 10
	sim.node_added.food -= 390  # keep the conservation ledger true for the test's edit
	var w: int = sim.spawn_unit("worker", "player", Vector2i(3, 1))
	sim.submit(Commands.harvest("player", [w], farm))
	for _t: int in 45:
		sim.step()
	assert_null(sim.entity(farm), "the empty farm is removed")
	assert_eq(sim.resources.player.food, 110)
	assert_eq(sim.entity(w).order_type, "idle", "no other farm to go to")
	assert_false(sim.is_solid(Vector2i(4, 0)), "its cells are free again")
	_assert_clean(sim)


func test_ac_97_only_own_finished_farms_can_be_harvested() -> void:
	var sim: Simulation = _sim()
	var enemy_farm: int = sim.place_building_unchecked("farm", "ai", Vector2i(8, 4), true)
	var unfinished: int = sim.place_building_unchecked("farm", "player", Vector2i(4, 4), false)
	var w: int = sim.spawn_unit("worker", "player", Vector2i(6, 7))
	assert_eq(sim.submit(Commands.harvest("player", [w], enemy_farm)), "invalid_target", "enemy farm")
	assert_eq(sim.submit(Commands.harvest("player", [w], unfinished)), "invalid_target", "farm under construction")
	assert_eq(sim.entity(unfinished).amount, 0, "an unfinished farm holds no food yet")


func test_ac_97_food_is_conserved_when_a_farm_is_destroyed() -> void:
	var sim: Simulation = _sim()
	var farm: int = sim.place_building_unchecked("farm", "player", Vector2i(4, 0), true)
	var w: int = sim.spawn_unit("worker", "player", Vector2i(3, 1))
	sim.submit(Commands.harvest("player", [w], farm))
	for _t: int in 50:
		sim.step()
	sim.entity(farm).hp = 0
	sim.step()
	assert_null(sim.entity(farm))
	_assert_clean(sim)


# --- AC-98: building farms, towers and stables; cavalry ---------------------

func test_ac_98_farm_tower_and_stable_are_paid_and_built_like_a_barracks() -> void:
	# kind, anchor touching the worker at (4, 5), wood, gold, build time.
	for c: Array in [["farm", Vector2i(5, 5), 80, 0, 150], ["tower", Vector2i(5, 5), 80, 60, 250], ["stable", Vector2i(5, 5), 150, 40, 300]]:
		var sim: Simulation = _sim()
		var w: int = sim.spawn_unit("worker", "player", Vector2i(4, 5))
		assert_eq(sim.submit(Commands.build("player", w, c[0], c[1])), "ok", c[0])
		assert_eq(sim.resources.player.wood, 200 - int(c[2]), "%s wood paid at placement" % c[0])
		assert_eq(sim.resources.player.gold, 100 - int(c[3]), "%s gold paid at placement" % c[0])
		var b: Entity = sim.entity(sim.occupant_at(c[1]))
		assert_eq(b.kind, c[0])
		for _t: int in int(c[4]) - 2:
			sim.step()
		assert_false(b.complete, "%s not finished before its build time" % c[0])
		for _t: int in 4:
			sim.step()
		assert_true(b.complete, "%s finished at its build time" % c[0])
		_assert_clean(sim)


func test_ac_98_cavalry_only_at_a_finished_stable() -> void:
	var sim: Simulation = _rich()
	var barracks: int = sim.place_building_unchecked("barracks", "player", Vector2i(5, 1), true)
	var building: int = sim.place_building_unchecked("stable", "player", Vector2i(9, 1), false)
	var stable: int = sim.place_building_unchecked("stable", "player", Vector2i(5, 5), true)
	assert_eq(sim.submit(Commands.train("player", barracks, "cavalry")), "invalid_unit_for_building")
	assert_eq(sim.submit(Commands.train("player", building, "cavalry")), "not_ready")
	assert_eq(sim.submit(Commands.train("player", stable, "melee")), "invalid_unit_for_building")
	assert_eq(sim.submit(Commands.train("player", stable, "cavalry")), "ok")
	assert_eq(sim.resources.player.gold, 5000 - 70)
	assert_eq(sim.resources.player.food, 5000 - 60)
	assert_eq(sim.resources.player.wood, 5000, "cavalry costs no wood")
	for _t: int in 260:
		sim.step()
	var cavalry: int = 0
	for id: int in sim.entities:
		if sim.entity(id).kind == "cavalry":
			cavalry += 1
			assert_true(sim.entity(id).is_soldier())
	assert_eq(cavalry, 1, "trained after 260 ticks")


func test_ac_98_cavalry_needs_food() -> void:
	var sim: Simulation = _sim({"start_gold": 500, "start_food": 59})
	var stable: int = sim.place_building_unchecked("stable", "player", Vector2i(5, 5), true)
	assert_eq(sim.submit(Commands.train("player", stable, "cavalry")), "insufficient_resources")
	assert_eq(sim.resources.player.gold, 500, "nothing deducted")


# --- AC-99: the guard tower ---------------------------------------------------

func _tower_sim() -> Simulation:
	# 30 x 12 open map; the tower at (10, 5) has its centre at (10500, 5500).
	return Simulation.new(TestMaps.open(30, 12), 1, {"start_workers": 0})


func test_ac_99_tower_hits_every_30_ticks_within_6_cells() -> void:
	var sim: Simulation = _tower_sim()
	sim.place_building_unchecked("tower", "player", Vector2i(10, 5), true)
	# Exactly 6 cells away: 6,000 milli-cells = the range.
	var t: int = sim.spawn_unit("worker", "ai", Vector2i(16, 5))
	sim.entity(t).hp = 1000
	sim.step()
	assert_eq(sim.entity(t).hp, 994, "6 damage on the first tick")
	for _i: int in 29:
		sim.step()
	assert_eq(sim.entity(t).hp, 994, "nothing during the 30-tick cooldown")
	sim.step()
	assert_eq(sim.entity(t).hp, 988, "second hit 30 ticks after the first")


func test_ac_99_tower_ignores_units_out_of_range_and_friends() -> void:
	var sim: Simulation = _tower_sim()
	sim.place_building_unchecked("tower", "player", Vector2i(10, 5), true)
	var far: int = sim.spawn_unit("worker", "ai", Vector2i(17, 5))  # 7 cells
	var friend: int = sim.spawn_unit("worker", "player", Vector2i(11, 5))
	for _i: int in 40:
		sim.step()
	assert_eq(sim.entity(far).hp, 40)
	assert_eq(sim.entity(friend).hp, 40)


func test_ac_99_tower_picks_the_nearest_enemy_lowest_id_on_ties() -> void:
	var sim: Simulation = _tower_sim()
	sim.place_building_unchecked("tower", "player", Vector2i(10, 5), true)
	var farther: int = sim.spawn_unit("worker", "ai", Vector2i(14, 5))
	var nearer: int = sim.spawn_unit("worker", "ai", Vector2i(10, 8))
	var tie: int = sim.spawn_unit("worker", "ai", Vector2i(10, 2))
	sim.step()
	assert_eq(sim.entity(nearer).hp, 34, "3 cells away, lower id than the other one at 3 cells")
	assert_eq(sim.entity(tie).hp, 40)
	assert_eq(sim.entity(farther).hp, 40)


func test_ac_99_unfinished_tower_does_nothing() -> void:
	var sim: Simulation = _tower_sim()
	sim.place_building_unchecked("tower", "player", Vector2i(10, 5), false)
	var t: int = sim.spawn_unit("worker", "ai", Vector2i(12, 5))
	for _i: int in 40:
		sim.step()
	assert_eq(sim.entity(t).hp, 40)


# --- AC-100: upgrades ---------------------------------------------------------

func test_ac_100_forging_is_researched_once_through_the_transaction() -> void:
	var sim: Simulation = _rich()
	var b: int = sim.place_building_unchecked("barracks", "player", Vector2i(5, 5), true)
	var pop: int = sim.population("player")
	assert_eq(sim.submit(Commands.research("player", b, "forging")), "ok")
	assert_eq(sim.resources.player.gold, 5000 - 80)
	assert_eq(sim.resources.player.food, 5000 - 100)
	assert_eq(sim.population("player"), pop, "research does not count towards the population")
	assert_eq(sim.submit(Commands.research("player", b, "forging")), "already_researched", "already in progress")
	for _t: int in 399:
		sim.step()
	assert_false(sim.has_upgrade("player", "forging"), "not done after 399 ticks")
	sim.step()
	assert_true(sim.has_upgrade("player", "forging"), "done after 400 ticks")
	assert_false(sim.has_upgrade("ai", "forging"), "only for the faction that researched it")
	assert_eq(sim.submit(Commands.research("player", b, "forging")), "already_researched")
	_assert_clean(sim)


func test_ac_100_research_rules_and_refund() -> void:
	var sim: Simulation = _rich()
	var hq: int = sim.hq_of("player")
	var unfinished: int = sim.place_building_unchecked("barracks", "player", Vector2i(9, 1), false)
	var b: int = sim.place_building_unchecked("barracks", "player", Vector2i(5, 5), true)
	assert_eq(sim.submit(Commands.research("player", hq, "forging")), "invalid_target", "only at a barracks")
	assert_eq(sim.submit(Commands.research("player", unfinished, "forging")), "not_ready")
	assert_eq(sim.submit(Commands.research("player", b, "wings")), "invalid_target", "unknown upgrade")
	assert_eq(sim.submit(Commands.research("player", b, "armour")), "ok")
	assert_eq(sim.resources.player.gold, 5000 - 100)
	assert_eq(sim.submit(Commands.cancel_train("player", b, 0)), "ok")
	assert_eq(sim.resources.player.gold, 5000, "cancelling refunds the research")
	assert_eq(sim.resources.player.food, 5000)
	# Forging needs 100 food: 99 is not enough.
	var poor: Simulation = _sim({"start_food": 99})
	var pb: int = poor.place_building_unchecked("barracks", "player", Vector2i(5, 5), true)
	assert_eq(poor.submit(Commands.research("player", pb, "forging")), "insufficient_resources")
	assert_eq(poor.resources.player.gold, 100, "nothing deducted")


func test_ac_100_damage_with_forging_and_armour() -> void:
	var sim: Simulation = Simulation.new(TestMaps.open(30, 12), 1, {"start_workers": 0})
	sim.upgrades.player.forging = true
	var a: int = sim.spawn_unit("melee", "player", Vector2i(5, 5))
	var plain: int = sim.spawn_unit("melee", "ai", Vector2i(6, 5))
	assert_eq(sim.submit(Commands.attack("player", [a], plain)), "ok")
	sim.step()
	assert_eq(sim.entity(plain).hp, 100 - 12, "10 + 2 forging against no armour")
	var sim2: Simulation = Simulation.new(TestMaps.open(30, 12), 1, {"start_workers": 0})
	sim2.upgrades.player.forging = true
	sim2.upgrades.ai.armour = true
	var a2: int = sim2.spawn_unit("melee", "player", Vector2i(5, 5))
	var armoured: int = sim2.spawn_unit("melee", "ai", Vector2i(6, 5))
	sim2.submit(Commands.attack("player", [a2], armoured))
	sim2.step()
	assert_eq(sim2.entity(armoured).hp, 100 - 10, "10 + 2 forging - 2 armour")
	# The formula, including the floor of 1 per hit.
	assert_eq(Simulation.hit_damage(10, true, false), 12)
	assert_eq(Simulation.hit_damage(10, false, true), 8)
	assert_eq(Simulation.hit_damage(2, false, true), 1, "never less than 1")
	assert_eq(Simulation.hit_damage(1, false, true), 1)


func test_ac_100_armour_does_not_protect_workers_and_towers_are_not_forged() -> void:
	var sim: Simulation = Simulation.new(TestMaps.open(30, 12), 1, {"start_workers": 0})
	sim.upgrades.player.forging = true
	sim.upgrades.ai.armour = true
	sim.place_building_unchecked("tower", "player", Vector2i(10, 5), true)
	var w: int = sim.spawn_unit("worker", "ai", Vector2i(12, 5))
	sim.step()
	assert_eq(sim.entity(w).hp, 40 - 6, "a tower is not a soldier and a worker is not armoured")


# --- AC-101: the AI uses the additions ------------------------------------

func test_ac_101_ai_builds_farms_tower_stable_trains_cavalry_and_researches() -> void:
	# AI against AI (Balanced v Aggressive) on generated maps; matches are
	# short, so the counts are summed over both factions and every match.
	var total: Dictionary = {"farm": 0, "tower": 0, "stable": 0, "cavalry": 0, "researched": 0}
	for s: int in TestCounts.pick(2, 20):
		var m: MapGrid = MapGenerator.generate(6600 + s).map
		var r: Dictionary = MatchRunner.run(m, s, {"player": "balanced", "ai": "aggressive"}, 18000)
		for f: String in Consts.FACTIONS:
			assert_eq(r[f].violations, 0, "seed %d %s: firewall" % [s, f])
			for k: String in ["farm", "tower", "stable"]:
				total[k] += int(r[f].built.get(k, 0))
			total.cavalry += r[f].cavalry_trained
			total.researched += r[f].researched
		var sim_ok: bool = r.result != ""
		assert_true(sim_ok, "seed %d finished" % s)
	gut.p("AC-101 measured: %s" % total)
	for k: String in total:
		assert_gt(int(total[k]), 0, k)
