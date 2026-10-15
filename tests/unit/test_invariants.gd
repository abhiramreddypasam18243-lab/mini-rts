## AC-06: the invariant checker under random valid and invalid commands.
extends GutTest

const COMMANDS: Array[String] = ["move", "harvest", "build", "attack", "train", "cancel_train"]


## A random command: real or fake ids, own or enemy units, cells inside or
## outside the map, negative indexes. Built from a seeded test generator.
func _random_command(rng: SimRng, sim: Simulation) -> Dictionary:
	var ids: Array = sim.entities.keys()
	var f: String = Consts.FACTIONS[rng.range_int(2)]
	var pick: Callable = func() -> int:
		return 9999 if rng.range_int(10) == 0 else ids[rng.range_int(ids.size())]
	var some: Array = []
	for i: int in rng.between(0, 4):
		some.append(pick.call())
	var cell: Vector2i = Vector2i(rng.between(-2, sim.map.width + 1), rng.between(-2, sim.map.height + 1))
	match COMMANDS[rng.range_int(COMMANDS.size())]:
		"move":
			return Commands.move(f, some, cell)
		"harvest":
			return Commands.harvest(f, some, pick.call())
		"build":
			return Commands.build(f, pick.call(), "barracks", cell)
		"attack":
			return Commands.attack(f, some, pick.call())
		"train":
			return Commands.train(f, pick.call(), ["worker", "melee", "ranged", "hq"][rng.range_int(4)])
		_:
			return Commands.cancel_train(f, pick.call(), rng.between(-2, 6))


func test_ac_06_invariants_hold_under_random_commands() -> void:
	var sims: int = TestCounts.pick(6, 1000)
	var ticks: int = TestCounts.pick(1000, 2000)
	var rng: SimRng = SimRng.new(6)
	var failures: int = 0
	for s: int in sims:
		var m: MapGrid = MapGenerator.generate(1000 + s).map
		var sim: Simulation = Simulation.new(m, s, {})
		for t: int in ticks:
			if rng.range_int(8) == 0:
				sim.submit(_random_command(rng, sim))
			sim.step()
			var problems: PackedStringArray = Invariants.check(sim)
			if not problems.is_empty():
				failures += 1
				assert_eq(problems, PackedStringArray(), "sim %d tick %d" % [s, sim.tick])
				break
	assert_eq(failures, 0, "%d simulations x %d ticks" % [sims, ticks])


func test_ac_06_checker_detects_planted_violations() -> void:
	var sim: Simulation = TestMaps.sim(TestMaps.open(20, 12, [Vector2i(9, 9)]))
	var u: int = sim.spawn_unit("worker", "player", Vector2i(5, 5))
	assert_eq(Invariants.check(sim), PackedStringArray(), "a fresh simulation is clean")
	sim.entity(u).pos = MapGrid.cell_center(Vector2i(9, 9))
	assert_true(Array(Invariants.check(sim)).any(func(p: String) -> bool: return p.contains("blocked")), "unit on blocked terrain")
	sim.entity(u).pos = MapGrid.cell_center(Vector2i(1, 1))
	assert_true(Array(Invariants.check(sim)).any(func(p: String) -> bool: return p.contains("inside")), "unit inside a building")
	sim.entity(u).pos = MapGrid.cell_center(Vector2i(5, 5))
	sim.entity(u).order_type = "attack"
	sim.entity(u).order_target = 4242
	assert_true(Array(Invariants.check(sim)).any(func(p: String) -> bool: return p.contains("4242")), "order to a dead entity")
	sim.entity(u).set_idle()
	sim.resources["player"]["wood"] = -1
	assert_true(Array(Invariants.check(sim)).any(func(p: String) -> bool: return p.contains("wood")), "negative resource")
	sim.resources["player"]["wood"] = 0
	sim.place_building_unchecked("barracks", "ai", Vector2i(6, 6), true)
	sim.place_building_unchecked("barracks", "ai", Vector2i(7, 7), true)
	assert_true(Array(Invariants.check(sim)).any(func(p: String) -> bool: return p.contains("overlap")), "overlapping buildings")
