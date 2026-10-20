## AC-104 (player conveniences, decision D-54) and AC-105 (the auto-economy
## supervisor, D-55).
extends GutTest


func _sim() -> Simulation:
	return Simulation.new(TestMaps.open(30, 12), 1, {"start_workers": 0})


# --- AC-104 ---------------------------------------------------------------------

func test_ac_104_control_groups_keep_only_living_own_units() -> void:
	var sim: Simulation = _sim()
	var a: int = sim.spawn_unit("melee", "player", Vector2i(5, 5))
	var b: int = sim.spawn_unit("ranged", "player", Vector2i(6, 5))
	var groups: Dictionary = {}
	CommandAids.assign(groups, 1, [a, b])
	assert_eq(CommandAids.recall(groups, 1, sim, "player"), [a, b])
	sim.destroy_entity(a)
	assert_eq(CommandAids.recall(groups, 1, sim, "player"), [b], "the dead unit leaves the group")
	assert_eq(CommandAids.recall(groups, 2, sim, "player"), [], "an empty group")


func test_ac_104_idle_workers_cycle_in_id_order() -> void:
	var sim: Simulation = _sim()
	var w1: int = sim.spawn_unit("worker", "player", Vector2i(5, 5))
	var busy: int = sim.spawn_unit("worker", "player", Vector2i(6, 5))
	var w3: int = sim.spawn_unit("worker", "player", Vector2i(7, 5))
	sim.spawn_unit("worker", "ai", Vector2i(8, 5))
	sim.submit(Commands.move("player", [busy], Vector2i(10, 8)))
	assert_eq(CommandAids.idle_workers(sim, "player"), [w1, w3])
	assert_eq(CommandAids.next_idle(sim, "player", 0), w1)
	assert_eq(CommandAids.next_idle(sim, "player", w1), w3)
	assert_eq(CommandAids.next_idle(sim, "player", w3), w1, "wraps round")


func test_ac_104_rally_point_moves_or_gathers() -> void:
	var m: MapGrid = TestMaps.open(30, 12, [], [{"type": "wood", "cell": Vector2i(9, 3), "amount": 500}])
	var sim: Simulation = Simulation.new(m, 1, {"start_workers": 0})
	var w: int = sim.spawn_unit("worker", "player", Vector2i(5, 5))
	var s: int = sim.spawn_unit("melee", "player", Vector2i(6, 5))
	var on_wood: Dictionary = CommandAids.rally_command(sim, "player", w, Vector2i(9, 3))
	assert_eq(on_wood.command, "harvest", "a worker rallied to wood gathers it")
	assert_eq(CommandAids.rally_command(sim, "player", s, Vector2i(9, 3)).command, "move", "a soldier just walks")
	assert_eq(CommandAids.rally_command(sim, "player", w, Vector2i(12, 6)).command, "move", "open ground")
	var enemy_farm: int = sim.place_building_unchecked("farm", "ai", Vector2i(15, 6), true)
	assert_eq(CommandAids.rally_command(sim, "player", w, Vector2i(15, 6)).command, "move", "not the enemy's farm")
	assert_eq(sim.submit(on_wood), "ok")
	assert_true(sim.entity(enemy_farm) != null)


func test_ac_104_attack_alert_is_throttled_and_only_off_screen() -> void:
	var sim: Simulation = _sim()
	var mine: int = sim.spawn_unit("worker", "player", Vector2i(5, 5))
	var theirs: int = sim.spawn_unit("worker", "ai", Vector2i(6, 5))
	var ev: Dictionary = {"type": "attack", "target": mine}
	assert_true(CommandAids.should_alert(sim, "player", ev, false, 10.0, -100.0))
	assert_false(CommandAids.should_alert(sim, "player", ev, true, 10.0, -100.0), "on screen: no alert")
	assert_false(CommandAids.should_alert(sim, "player", ev, false, 10.0, 5.0), "5 s after the last one")
	assert_true(CommandAids.should_alert(sim, "player", ev, false, 13.0, 5.0), "8 s after")
	assert_false(CommandAids.should_alert(sim, "player", {"type": "attack", "target": theirs}, false, 10.0, -100.0), "not ours")


# --- AC-105 ---------------------------------------------------------------------

func test_ac_105_helper_runs_the_economy_and_never_touches_soldiers() -> void:
	for s: int in TestCounts.pick(2, 10):
		var sim: Simulation = Simulation.new(MapGenerator.generate(7300 + s).map, s, {"start_food": 0})
		var helper: AIController = AIController.economy_helper("player")
		var soldiers: Dictionary = {}
		var c: Vector2i = sim.map.starts.player + Vector2i(4, 4)
		for cell: Vector2i in [c, c + Vector2i(1, 0)]:
			if not sim.is_solid(cell):
				soldiers[sim.spawn_unit("melee", "player", cell)] = true
		for t: int in 3000:
			for cmd: Dictionary in helper.before_step(sim):
				assert_true(cmd.command in ["harvest", "train", "build"], "seed %d: %s" % [s, cmd.command])
				if cmd.command == "train":
					assert_eq(cmd.args.unit_type, "worker")
				if cmd.command == "build":
					assert_eq(cmd.args.building_type, "farm")
				for id: int in EnemyAI.unit_ids_of(cmd):
					assert_false(soldiers.has(id), "seed %d: a soldier was commanded" % s)
			sim.step()
		assert_eq(helper.violations, 0, "seed %d: firewall" % s)
		var workers: int = 0
		var farms: int = 0
		for id: int in sim.entities:
			var e: Entity = sim.entities[id]
			workers += 1 if e.kind == "worker" and e.faction == "player" else 0
			farms += 1 if e.kind == "farm" and e.faction == "player" else 0
		gut.p("AC-105 measured: seed %d: %d workers, %d farms, %d wood + %d gold + %d food gathered" % [s, workers, farms,
			sim.bank.deposited.player.wood, sim.bank.deposited.player.gold, sim.bank.deposited.player.food])
		assert_gt(workers, Consts.START_WORKERS, "seed %d: trained workers" % s)
		assert_gt(farms + sim.bank.deposited.player.food, 0, "seed %d: started with no food, so it farmed" % s)
		assert_eq(Invariants.check(sim), PackedStringArray())


func test_ac_105_idle_workers_are_put_to_work_at_the_next_decision() -> void:
	var sim: Simulation = Simulation.new(MapGenerator.generate(7301).map, 7301, {})
	var helper: AIController = AIController.economy_helper("player")
	var cmds: Array[Dictionary] = helper.before_step(sim)
	var gathering: int = 0
	for cmd: Dictionary in cmds:
		if cmd.command == "harvest":
			gathering += (cmd.args.unit_ids as Array).size()
	assert_eq(gathering, Consts.START_WORKERS, "all 3 starting workers sent to gather at tick 0")
