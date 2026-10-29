## AC-115 (a moving soldier that is hit fights back, unless the player has
## ordered it to retreat), decision D-61.
extends GutTest


func _sim() -> Simulation:
	return Simulation.new(TestMaps.open(30, 12), 1, {"start_workers": 0})


func _hit(attacker: int, target: int) -> Dictionary:
	return {"type": "attack", "attacker": attacker, "target": target}


func test_ac_115_a_moving_soldier_that_is_hit_attacks_the_attacker() -> void:
	var sim: Simulation = _sim()
	var mine: int = sim.spawn_unit("melee", "player", Vector2i(10, 5))
	var foe: int = sim.spawn_unit("ranged", "ai", Vector2i(10, 9))  # 4 cells: in sight
	sim.update_fog()
	assert_eq(sim.submit(Commands.move("player", [mine], Vector2i(25, 5))), "ok")
	var c: Dictionary = CommandAids.fight_back_command(sim, "player", _hit(foe, mine), {})
	assert_eq(c.get("command", ""), "attack")
	assert_eq(c.args.unit_ids, [mine])
	assert_eq(c.args.target_id, foe)
	assert_eq(sim.submit(c), "ok")
	assert_eq(sim.entity(mine).order_type, "attack")


func test_ac_115_only_a_plain_move_is_interrupted() -> void:
	var sim: Simulation = _sim()
	var foe: int = sim.spawn_unit("melee", "ai", Vector2i(10, 9))
	var idle: int = sim.spawn_unit("melee", "player", Vector2i(10, 7))
	var am: int = sim.spawn_unit("melee", "player", Vector2i(11, 7))
	var route: int = sim.spawn_unit("melee", "player", Vector2i(9, 7))
	var worker: int = sim.spawn_unit("worker", "player", Vector2i(12, 7))
	var away: int = sim.spawn_unit("melee", "player", Vector2i(8, 7))
	var tower: int = sim.place_building_unchecked("tower", "ai", Vector2i(14, 9), true)
	sim.update_fog()
	assert_eq(sim.submit(Commands.attack_move("player", [am], Vector2i(25, 5))), "ok")
	assert_eq(sim.submit(Commands.move("player", [route], Vector2i(25, 2))), "ok")
	assert_eq(sim.submit(Commands.move("player", [route], Vector2i(25, 9), true)), "ok")
	assert_eq(sim.submit(Commands.move("player", [worker, away], Vector2i(25, 5))), "ok")
	assert_eq(CommandAids.fight_back_command(sim, "player", _hit(foe, idle), {}), {}, "idle: auto-acquire handles it")
	assert_eq(CommandAids.fight_back_command(sim, "player", _hit(foe, am), {}), {}, "attack-move already fights")
	assert_eq(CommandAids.fight_back_command(sim, "player", _hit(foe, route), {}), {}, "a Shift-queued route is kept")
	assert_eq(CommandAids.fight_back_command(sim, "player", _hit(foe, worker), {}), {}, "workers cannot attack")
	assert_eq(CommandAids.fight_back_command(sim, "player", _hit(tower, away), {}), {}, "never turn on a tower")
	assert_eq(CommandAids.fight_back_command(sim, "player", _hit(foe, away), {away: true}), {}, "retreating")
	assert_eq(CommandAids.fight_back_command(sim, "ai", _hit(away, foe), {}), {}, "the AI is unchanged")


func test_ac_115_a_move_given_while_fighting_back_is_a_retreat() -> void:
	var sim: Simulation = _sim()
	var a: int = sim.spawn_unit("melee", "player", Vector2i(10, 5))
	var b: int = sim.spawn_unit("melee", "player", Vector2i(11, 5))
	var foe: int = sim.spawn_unit("melee", "ai", Vector2i(10, 7))
	sim.update_fog()
	var fought: Dictionary = {}
	var retreat: Dictionary = {}
	assert_eq(sim.submit(Commands.move("player", [a, b], Vector2i(25, 5))), "ok")
	var c: Dictionary = CommandAids.fight_back_command(sim, "player", _hit(foe, a), retreat)
	assert_eq(sim.submit(c), "ok")
	CommandAids.note_fight_back(c, fought)
	# The player orders both away: a was fighting back, so it is retreating;
	# b was not, so a hit on b still turns it.
	var away: Dictionary = Commands.move("player", [a, b], Vector2i(2, 5))
	CommandAids.note_retreat(away, fought, retreat)
	assert_eq(sim.submit(away), "ok")
	assert_eq(retreat, {a: true})
	assert_eq(CommandAids.fight_back_command(sim, "player", _hit(foe, a), retreat), {}, "a keeps retreating")
	assert_eq(CommandAids.fight_back_command(sim, "player", _hit(foe, b), retreat).get("command", ""), "attack")
	# Once a stops moving (arrived, or a new order), it fights back again.
	assert_eq(sim.submit(Commands.attack_move("player", [a], Vector2i(4, 5))), "ok")
	CommandAids.prune_fight_back(sim, fought, retreat)
	assert_eq(retreat, {})
