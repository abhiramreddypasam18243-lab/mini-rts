## AC-43 to AC-50: combat, removal of the dead, auto-acquire.
extends GutTest


## 30 x 12 open map; player HQ (0..2, 0..2), AI HQ (27..29, 9..11).
func _sim() -> Simulation:
	return TestMaps.sim(TestMaps.open(30, 12))


func _hits(events: Array[Dictionary], attacker: int) -> int:
	var n: int = 0
	for e: Dictionary in events:
		if e.type == "attack" and e.attacker == attacker:
			n += 1
	return n


func test_ac_43_melee_out_of_range_at_2_cells() -> void:
	# 2.0 cells = 2,000 milli-cells > melee range 1,500.
	var sim: Simulation = _sim()
	var a: int = sim.spawn_unit("melee", "player", Vector2i(5, 5))
	var t: int = sim.spawn_unit("melee", "ai", Vector2i(7, 5))
	sim.entity(t).hp = 100
	assert_eq(sim.submit(Commands.attack("player", [a], t)), "ok")
	sim.step()
	assert_eq(sim.entity(t).hp, 100, "no damage at 2.0 cells")


func test_ac_43_melee_at_1_cell_hits_then_every_20_ticks() -> void:
	var sim: Simulation = _sim()
	var a: int = sim.spawn_unit("melee", "player", Vector2i(5, 5))
	var t: int = sim.spawn_unit("worker", "ai", Vector2i(6, 5))
	sim.entity(t).hp = 1000  # survives the whole test
	assert_eq(sim.submit(Commands.attack("player", [a], t)), "ok")
	sim.step()
	assert_eq(sim.entity(t).hp, 990, "10 damage on the first tick")
	for _i: int in 19:
		sim.step()
	assert_eq(sim.entity(t).hp, 990, "no hit during the 20-tick cooldown")
	sim.step()
	assert_eq(sim.entity(t).hp, 980, "second hit exactly 20 ticks after the first")


func test_ac_44_ranged_hits_at_5_0_not_at_5_1() -> void:
	for case: Array in [[2500, 50 - 8], [2400, 50]]:
		var sim: Simulation = _sim()
		var a: int = sim.spawn_unit("ranged", "player", Vector2i(2, 5))
		var t: int = sim.spawn_unit("ranged", "ai", Vector2i(7, 5))
		# Target centre (7,500, 5,500); attacker x = 2,500 -> 5.0 cells, 2,400 -> 5.1 cells.
		sim.entity(a).pos = Vector2i(case[0], 5500)
		sim.entity(t).order_type = "idle"
		sim.submit(Commands.attack("player", [a], t))
		# Stop the target fighting back, then resolve one tick.
		sim.entity(t).cooldown = 1000
		sim.step()
		assert_eq(sim.entity(t).hp, case[1], "attacker at x = %d" % case[0])


func test_ac_45_tenth_hit_kills_and_removes_in_same_tick() -> void:
	var sim: Simulation = _sim()
	var a: int = sim.spawn_unit("melee", "player", Vector2i(5, 5))
	var t: int = sim.spawn_unit("melee", "ai", Vector2i(6, 5))
	sim.entity(t).cooldown = 100000  # the target never strikes back
	sim.submit(Commands.attack("player", [a], t))
	var events: Array[Dictionary] = []
	# Hits land on ticks 1, 21, ..., 181: the 10th is on tick 181.
	for _i: int in 180:
		sim.step()
		events.append_array(sim.take_events())
	assert_eq(_hits(events, a), 9)
	assert_eq(sim.entity(t).hp, 10)
	sim.step()
	events.append_array(sim.take_events())
	assert_eq(_hits(events, a), 10)
	assert_false(sim.entities.has(t), "removed in the tick it dies")
	assert_eq(sim.entity(a).order_type, "idle")


func test_ac_45_not_damaged_twice_in_the_tick_it_dies() -> void:
	var sim: Simulation = _sim()
	var a: int = sim.spawn_unit("melee", "player", Vector2i(5, 5))
	var b: int = sim.spawn_unit("melee", "player", Vector2i(5, 6))
	var t: int = sim.spawn_unit("worker", "ai", Vector2i(6, 5))
	sim.entity(t).hp = 10
	sim.submit(Commands.attack("player", [a, b], t))
	sim.step()
	var events: Array[Dictionary] = sim.take_events()
	assert_false(sim.entities.has(t))
	assert_eq(_hits(events, a) + _hits(events, b), 1, "only the first hit lands")
	assert_eq(sim.entity(b).cooldown, 0, "the second soldier did not use its cooldown")


func test_ac_46_two_lethal_hits_in_one_tick_both_die() -> void:
	var sim: Simulation = _sim()
	var a: int = sim.spawn_unit("melee", "player", Vector2i(5, 5))
	var b: int = sim.spawn_unit("melee", "ai", Vector2i(6, 5))
	sim.entity(a).hp = 10
	sim.entity(b).hp = 10
	sim.submit(Commands.attack("player", [a], b))
	sim.submit(Commands.attack("ai", [b], a))
	sim.step()
	assert_false(sim.entities.has(a), "a died")
	assert_false(sim.entities.has(b), "b died")


func test_ac_47_cannot_attack_friends_nodes_or_with_workers() -> void:
	var m: MapGrid = TestMaps.open(30, 12, [], [{"type": "wood", "cell": Vector2i(10, 5), "amount": 500}])
	var sim: Simulation = TestMaps.sim(m)
	var a: int = sim.spawn_unit("melee", "player", Vector2i(5, 5))
	var friend: int = sim.spawn_unit("worker", "player", Vector2i(6, 5))
	var worker: int = sim.spawn_unit("worker", "player", Vector2i(5, 6))
	var enemy: int = sim.spawn_unit("worker", "ai", Vector2i(7, 5))
	var before: int = sim.state_hash()
	assert_eq(sim.submit(Commands.attack("player", [a], friend)), "invalid_target", "friendly unit")
	assert_eq(sim.submit(Commands.attack("player", [a], sim.hq_of("player"))), "invalid_target", "friendly building")
	assert_eq(sim.submit(Commands.attack("player", [a], sim.node_at(Vector2i(10, 5)))), "invalid_target", "resource node")
	assert_eq(sim.submit(Commands.attack("player", [worker], enemy)), "invalid_target", "workers cannot attack")
	assert_eq(sim.state_hash(), before)


func test_ac_48_every_order_on_a_dead_target_is_cleared() -> void:
	var sim: Simulation = _sim()
	var soldiers: Array = []
	for y: int in [4, 5, 6]:
		soldiers.append(sim.spawn_unit("melee", "player", Vector2i(5, y)))
	var t: int = sim.spawn_unit("worker", "ai", Vector2i(6, 5))
	sim.submit(Commands.attack("player", soldiers, t))
	for _i: int in 100:
		sim.step()
		assert_eq(Invariants.check(sim), PackedStringArray(), "tick %d" % sim.tick)
	assert_false(sim.entities.has(t))
	for s: int in soldiers:
		assert_eq(sim.entity(s).order_type, "idle")
		assert_eq(sim.entity(s).order_target, 0)


func test_ac_49_thirty_melee_hits_destroy_a_barracks() -> void:
	var sim: Simulation = _sim()
	var b: int = sim.place_building_unchecked("barracks", "ai", Vector2i(10, 5), true)
	var a: int = sim.spawn_unit("melee", "player", Vector2i(9, 5))
	sim.submit(Commands.attack("player", [a], b))
	var events: Array[Dictionary] = []
	# 300 health / 10 damage = 30 hits, on ticks 1, 21, ..., 581.
	for _i: int in 580:
		sim.step()
		events.append_array(sim.take_events())
	assert_eq(_hits(events, a), 29)
	assert_true(sim.entities.has(b), "still standing after 29 hits")
	sim.step()
	events.append_array(sim.take_events())
	assert_eq(_hits(events, a), 30)
	assert_false(sim.entities.has(b), "destroyed by the 30th")
	assert_false(sim.is_solid(Vector2i(10, 5)), "footprint walkable again")


func test_ac_49_soldier_walks_to_a_distant_target() -> void:
	var sim: Simulation = _sim()
	var a: int = sim.spawn_unit("ranged", "player", Vector2i(3, 6))
	var t: int = sim.spawn_unit("worker", "ai", Vector2i(20, 6))
	assert_eq(sim.submit(Commands.attack("player", [a], t)), "ok")
	for _i: int in 400:
		sim.step()
		if not sim.entities.has(t):
			break
	assert_false(sim.entities.has(t), "chased and killed")


func test_ac_50_idle_soldier_auto_acquires_and_returns_to_idle() -> void:
	var sim: Simulation = _sim()
	var a: int = sim.spawn_unit("melee", "player", Vector2i(5, 5))
	# Squared distance (9-5)^2 = 16 <= vision 6^2 = 36: in vision.
	var t: int = sim.spawn_unit("worker", "ai", Vector2i(9, 5))
	sim.step()
	assert_eq(sim.entity(a).order_type, "attack", "acquired the enemy in vision")
	assert_eq(sim.entity(a).order_target, t)
	for _i: int in 200:
		sim.step()
		if not sim.entities.has(t):
			break
	assert_false(sim.entities.has(t), "chased and killed it")
	sim.step()
	assert_eq(sim.entity(a).order_type, "idle", "idle once the target is dead")


func test_ac_50_returns_to_idle_when_target_leaves_vision() -> void:
	var sim: Simulation = _sim()
	var a: int = sim.spawn_unit("melee", "player", Vector2i(5, 5))
	var t: int = sim.spawn_unit("worker", "ai", Vector2i(10, 5))
	sim.step()
	assert_eq(sim.entity(a).order_target, t)
	# The worker (150 per tick) outruns the melee soldier (125 per tick).
	sim.submit(Commands.move("ai", [t], Vector2i(26, 5)))
	var went_idle: bool = false
	for _i: int in 200:
		sim.step()
		if sim.entity(a).order_type == "idle":
			went_idle = true
			break
	assert_true(went_idle, "gave up when the target left its vision")
	assert_true(sim.entities.has(t), "the worker escaped")


func test_ac_50_far_enemy_is_ignored() -> void:
	var sim: Simulation = _sim()
	var a: int = sim.spawn_unit("melee", "player", Vector2i(5, 5))
	# Squared distance 7^2 = 49 > 36: outside vision.
	sim.spawn_unit("worker", "ai", Vector2i(12, 5))
	sim.step()
	assert_eq(sim.entity(a).order_type, "idle")
