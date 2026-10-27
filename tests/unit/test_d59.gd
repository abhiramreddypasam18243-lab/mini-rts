## AC-110 (idle soldiers come to help when something of the player's is hit),
## decision D-59.
extends GutTest


func _sim() -> Simulation:
	return Simulation.new(TestMaps.open(30, 12), 1, {"start_workers": 0})


func _hit(attacker: int, target: int) -> Dictionary:
	return {"type": "attack", "attacker": attacker, "target": target}


func test_ac_110_idle_soldiers_within_10_cells_join_the_fight() -> void:
	var sim: Simulation = _sim()
	var victim: int = sim.spawn_unit("melee", "player", Vector2i(10, 5))
	# Squared cell distances from the victim at (10, 5); the limit is 10² = 100.
	var near: int = sim.spawn_unit("ranged", "player", Vector2i(14, 5))  # 16
	var edge: int = sim.spawn_unit("cavalry", "player", Vector2i(20, 5))  # 100
	sim.spawn_unit("melee", "player", Vector2i(21, 5))  # 121: too far
	var busy: int = sim.spawn_unit("melee", "player", Vector2i(12, 8))  # 13, but has an order
	sim.spawn_unit("worker", "player", Vector2i(11, 5))  # workers are never sent
	sim.spawn_unit("melee", "ai", Vector2i(16, 9))  # an enemy soldier is never sent
	var foe: int = sim.spawn_unit("ranged", "ai", Vector2i(5, 5))  # 5 cells away: the victim sees it
	sim.update_fog()
	assert_eq(sim.submit(Commands.move("player", [busy], Vector2i(12, 10))), "ok")
	var c: Dictionary = CommandAids.help_command(sim, "player", _hit(foe, victim))
	assert_eq(c.get("command", ""), "attack_move")
	assert_eq(c.args.unit_ids, [near, edge], "idle own soldiers within 10 cells, not the victim itself")
	assert_eq(c.args.cell, [5, 5], "to the attacker, whom the player sees")
	assert_eq(sim.submit(c), "ok")


func test_ac_110_an_unseen_or_building_attacker_sends_them_to_the_victim() -> void:
	# A guard tower is a building: the helpers go to the victim's cell, and
	# meet the tower there through ordinary auto-acquire.
	var sim: Simulation = _sim()
	var victim: int = sim.spawn_unit("worker", "player", Vector2i(8, 5))
	var helper: int = sim.spawn_unit("melee", "player", Vector2i(12, 6))
	var tower: int = sim.place_building_unchecked("tower", "ai", Vector2i(3, 5), true)
	sim.update_fog()
	var c: Dictionary = CommandAids.help_command(sim, "player", _hit(tower, victim))
	assert_eq(c.args.unit_ids, [helper])
	assert_eq(c.args.cell, [8, 5], "the victim's cell")


func test_ac_110_nobody_is_sent_for_the_enemy_or_when_no_one_is_idle() -> void:
	var sim: Simulation = _sim()
	var mine: int = sim.spawn_unit("melee", "player", Vector2i(10, 5))
	var helper: int = sim.spawn_unit("melee", "player", Vector2i(12, 5))
	var foe: int = sim.spawn_unit("melee", "ai", Vector2i(14, 5))
	sim.update_fog()
	assert_eq(CommandAids.help_command(sim, "player", _hit(mine, foe)), {}, "an attack on the AI's unit")
	assert_eq(sim.submit(Commands.move("player", [helper], Vector2i(12, 8))), "ok")
	assert_eq(CommandAids.help_command(sim, "player", _hit(foe, mine)), {}, "the only soldier nearby is busy")
	assert_eq(CommandAids.help_command(sim, "player", _hit(foe, 999)), {}, "a victim already removed")
