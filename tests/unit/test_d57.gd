## AC-108 (the cavalry charge rule) and AC-109 (battle summaries and the
## battle camera's target), decision D-57.
extends GutTest


# --- AC-108 -----------------------------------------------------------------

## 30 x 12 open map; an AI worker with plenty of health at (14, 5).
func _sim() -> Simulation:
	return Simulation.new(TestMaps.open(30, 12), 1, {"start_workers": 0})


func _damage_events(sim: Simulation, attacker: int) -> Array[int]:
	var out: Array[int] = []
	for ev: Dictionary in sim.take_events():
		if ev.type == "attack" and ev.attacker == attacker:
			out.append(int(ev.damage))
	return out


func test_ac_108_a_charge_doubles_the_first_hit() -> void:
	# The cavalry rides from (8, 5) (6 cells away: just inside its vision)
	# to the worker at (14, 5); it is in range from x = 12.5, a run of 4
	# cells, more than the 3 a charge needs. First hit 9 x 2 = 18, then 9 per
	# hit while it stands still.
	var sim: Simulation = _sim()
	var c: int = sim.spawn_unit("cavalry", "player", Vector2i(8, 5))
	var t: int = sim.spawn_unit("worker", "ai", Vector2i(14, 5))
	sim.entity(t).hp = 1000
	assert_eq(sim.submit(Commands.attack("player", [c], t)), "ok")
	var hits: Array[int] = []
	for _i: int in 120:
		sim.step()
		hits.append_array(_damage_events(sim, c))
	assert_gte(hits.size(), 3)
	assert_eq(hits[0], 18, "charged first hit")
	assert_eq(hits[1], 9, "the charge is spent")
	assert_eq(hits[2], 9)


func test_ac_108_no_charge_from_standing() -> void:
	# Already beside the target: it has not moved, so no charge.
	var sim: Simulation = _sim()
	var c: int = sim.spawn_unit("cavalry", "player", Vector2i(13, 5))
	var t: int = sim.spawn_unit("worker", "ai", Vector2i(14, 5))
	sim.entity(t).hp = 1000
	sim.submit(Commands.attack("player", [c], t))
	sim.step()
	assert_eq(_damage_events(sim, c), [9])


func test_ac_108_charge_needs_three_cells() -> void:
	# From (11, 5) the cavalry is in range after 1.5 cells: 1500 milli-cells
	# < 3000, so no charge.
	var sim: Simulation = _sim()
	var c: int = sim.spawn_unit("cavalry", "player", Vector2i(11, 5))
	var t: int = sim.spawn_unit("worker", "ai", Vector2i(14, 5))
	sim.entity(t).hp = 1000
	sim.submit(Commands.attack("player", [c], t))
	var hits: Array[int] = []
	for _i: int in 40:
		sim.step()
		hits.append_array(_damage_events(sim, c))
	assert_eq(hits[0], 9, "too short a run for a charge")


func test_ac_108_only_cavalry_charges() -> void:
	var sim: Simulation = _sim()
	var m: int = sim.spawn_unit("melee", "player", Vector2i(8, 5))
	var t: int = sim.spawn_unit("worker", "ai", Vector2i(14, 5))
	sim.entity(t).hp = 1000
	sim.submit(Commands.attack("player", [m], t))
	var hits: Array[int] = []
	for _i: int in 120:
		sim.step()
		hits.append_array(_damage_events(sim, m))
	assert_eq(hits[0], 10, "a melee soldier's first hit is normal")
	assert_eq(sim.entity(m).charge, 0)


func test_ac_108_charge_is_in_the_state_hash() -> void:
	var a: Simulation = _sim()
	var b: Simulation = _sim()
	a.spawn_unit("cavalry", "player", Vector2i(5, 5))
	var cb: int = b.spawn_unit("cavalry", "player", Vector2i(5, 5))
	assert_eq(a.state_hash(), b.state_hash())
	b.entity(cb).charge = 1000
	assert_ne(a.state_hash(), b.state_hash())


# --- AC-109 -----------------------------------------------------------------

func test_ac_109_a_quiet_battle_is_summarised() -> void:
	var t: BattleTracker = BattleTracker.new()
	var p: Vector2 = Vector2(500, 500)
	for i: int in 5:
		t.add_hit(p + Vector2(i * 10, 0), 1.0 + i * 0.2)
	t.add_death(p, "ai", 2.0)
	t.add_death(p + Vector2(20, 0), "ai", 2.1)
	t.add_death(p + Vector2(-20, 0), "player", 2.2)
	assert_eq(t.update(5.0), [], "4 s have not passed since the last event (2.2 s)")
	var out: Array[Dictionary] = t.update(6.3)
	assert_eq(out.size(), 1)
	assert_eq([out[0].ai_lost, out[0].player_lost], [2, 1])
	assert_eq(BattleTracker.summary_text(out[0]), "Battle won: 2 enemies killed, 1 of yours lost")
	assert_true(t.battles.is_empty())


func test_ac_109_small_skirmishes_and_far_fights_are_separate() -> void:
	var t: BattleTracker = BattleTracker.new()
	t.add_death(Vector2(100, 100), "ai", 1.0)
	t.add_death(Vector2(100, 120), "player", 1.0)
	# 1,000 px away: more than 8 cells (256 px), a second battle.
	t.add_hit(Vector2(1100, 100), 1.0)
	assert_eq(t.battles.size(), 2)
	assert_eq(t.update(10.0), [], "2 deaths is a skirmish, not reported")


func test_ac_109_battle_camera_targets_the_hottest_fight() -> void:
	var t: BattleTracker = BattleTracker.new()
	for i: int in 3:
		t.add_hit(Vector2(100, 100), 10.0)
	for i: int in 6:
		t.add_hit(Vector2(2000, 900), 10.0)
	var hot: Variant = t.hottest(10.5)
	assert_not_null(hot)
	assert_lt((hot as Vector2).distance_to(Vector2(2000, 900)), 1.0, "the fight with 6 hits")
	assert_null(t.hottest(14.0), "nothing in the last 3 s")
