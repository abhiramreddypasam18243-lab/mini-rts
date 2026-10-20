## AC-54 to AC-58: fog of war and the observation.
extends GutTest


## 30 x 30 open map with no starting workers. Player HQ (0..2, 0..2) and AI
## HQ (27..29, 27..29) see 8 cells, so nothing near (10..20, 10..20) is seen
## until a unit goes there.
func _sim() -> Simulation:
	return TestMaps.sim(TestMaps.open(30, 30))


func _ids(list: Array) -> Array:
	var out: Array = []
	for d: Dictionary in list:
		out.append(d.id)
	return out


func test_ac_54_vision_radius_6() -> void:
	var sim: Simulation = _sim()
	sim.spawn_unit("worker", "player", Vector2i(10, 10))
	sim.update_fog()
	# (10, 16): 0 + 36 = 36 <= 36.  (14, 14): 16 + 16 = 32 <= 36.
	assert_true(sim.fog.is_visible("player", Vector2i(10, 16)), "(10, 16) visible")
	assert_true(sim.fog.is_visible("player", Vector2i(14, 14)), "(14, 14) visible")
	# (10, 17): 49 > 36.  (16, 14): 36 + 16 = 52 > 36.
	assert_false(sim.fog.is_visible("player", Vector2i(10, 17)), "(10, 17) not visible")
	assert_false(sim.fog.is_visible("player", Vector2i(16, 14)), "(16, 14) not visible")
	assert_false(sim.fog.is_explored("player", Vector2i(16, 14)), "never seen: unexplored")


func test_ac_54_visibility_matches_brute_force() -> void:
	# Every cell: visible exactly when some player unit or building is within
	# its vision (squared cell distance to the nearest footprint cell).
	var sim: Simulation = _sim()
	for c: Vector2i in [Vector2i(10, 10), Vector2i(13, 21), Vector2i(25, 4)]:
		sim.spawn_unit("ranged", "player", c)
	sim.place_building_unchecked("barracks", "player", Vector2i(18, 15), true)
	sim.update_fog()
	for y: int in 30:
		for x: int in 30:
			var expected: bool = false
			for id: int in sim.entities:
				var e: Entity = sim.entities[id]
				if e.faction != "player":
					continue
				var v: int = sim.stats[e.kind].vision
				var lo: Vector2i = e.unit_cell() if e.is_unit() else e.cell
				var hi: Vector2i = e.unit_cell() if e.is_unit() else e.cell + e.size - Vector2i.ONE
				var dx: int = maxi(maxi(lo.x - x, x - hi.x), 0)
				var dy: int = maxi(maxi(lo.y - y, y - hi.y), 0)
				expected = expected or dx * dx + dy * dy <= v * v
			assert_eq(sim.fog.is_visible("player", Vector2i(x, y)), expected, "(%d, %d)" % [x, y])


func test_ac_55_seen_cells_become_explored_never_unexplored() -> void:
	var sim: Simulation = _sim()
	var u: int = sim.spawn_unit("worker", "player", Vector2i(10, 10))
	sim.update_fog()
	assert_true(sim.fog.is_visible("player", Vector2i(10, 16)))
	sim.submit(Commands.move("player", [u], Vector2i(22, 10)))
	for _i: int in 200:
		sim.step()
	assert_false(sim.fog.is_visible("player", Vector2i(10, 16)), "no longer visible")
	assert_true(sim.fog.is_explored("player", Vector2i(10, 16)), "explored, not unexplored")
	assert_eq(sim.fog.state_of("player", Vector2i(10, 16)), Fog.EXPLORED)


func test_ac_56_hidden_enemy_unit_not_in_observation() -> void:
	var sim: Simulation = _sim()
	var scout: int = sim.spawn_unit("worker", "player", Vector2i(10, 10))
	var enemy: int = sim.spawn_unit("worker", "ai", Vector2i(12, 10))
	sim.update_fog()
	assert_true(_ids(sim.observation("player").enemy_units).has(enemy), "seen while visible")
	sim.entity(scout).pos = MapGrid.cell_center(Vector2i(4, 24))
	sim.update_fog()
	assert_true(sim.fog.is_explored("player", Vector2i(12, 10)), "its cell is explored")
	assert_false(sim.fog.is_visible("player", Vector2i(12, 10)), "but not visible")
	assert_false(_ids(sim.observation("player").enemy_units).has(enemy), "hidden enemy not observed")


func test_ac_56_building_ghost_stays_until_seen_destroyed() -> void:
	var sim: Simulation = _sim()
	var scout: int = sim.spawn_unit("worker", "player", Vector2i(10, 10))
	var b: int = sim.place_building_unchecked("barracks", "ai", Vector2i(13, 10), true)
	sim.update_fog()
	assert_true(_ids(sim.observation("player").ghosts).has(b), "seen")
	# Walk away: the building is remembered.
	sim.entity(scout).pos = MapGrid.cell_center(Vector2i(4, 24))
	sim.update_fog()
	assert_true(_ids(sim.observation("player").ghosts).has(b), "remembered when out of sight")
	# Destroyed while nobody watches: still a ghost.
	sim.destroy_entity(b)
	sim.update_fog()
	assert_true(_ids(sim.observation("player").ghosts).has(b), "not known to be gone yet")
	# Come back and see the empty site: the ghost goes.
	sim.entity(scout).pos = MapGrid.cell_center(Vector2i(10, 10))
	sim.update_fog()
	assert_false(_ids(sim.observation("player").ghosts).has(b), "seen destroyed")


func test_ac_56_ghost_keeps_last_seen_health() -> void:
	var sim: Simulation = _sim()
	var scout: int = sim.spawn_unit("worker", "player", Vector2i(10, 10))
	var b: int = sim.place_building_unchecked("barracks", "ai", Vector2i(13, 10), true)
	sim.update_fog()
	sim.entity(scout).pos = MapGrid.cell_center(Vector2i(4, 24))
	sim.update_fog()
	sim.entity(b).hp = 50
	sim.update_fog()
	var ghost: Dictionary = sim.observation("player").ghosts[0]
	assert_eq(ghost.hp, 300, "last seen health, not the hidden truth")


func test_ac_57_attack_on_hidden_enemy_is_rejected() -> void:
	var sim: Simulation = _sim()
	var a: int = sim.spawn_unit("melee", "player", Vector2i(10, 10))
	var far: int = sim.spawn_unit("worker", "ai", Vector2i(22, 22))
	var near: int = sim.spawn_unit("worker", "ai", Vector2i(12, 10))
	sim.update_fog()
	var before: int = sim.state_hash()
	assert_eq(sim.submit(Commands.attack("player", [a], far)), "target_not_visible")
	assert_eq(sim.state_hash(), before, "nothing changed")
	assert_eq(sim.submit(Commands.attack("player", [a], near)), "ok")


func test_ac_57_hidden_building_cannot_be_attacked_even_as_a_ghost() -> void:
	var sim: Simulation = _sim()
	var a: int = sim.spawn_unit("melee", "player", Vector2i(10, 10))
	var b: int = sim.place_building_unchecked("barracks", "ai", Vector2i(13, 10), true)
	sim.update_fog()
	sim.entity(a).pos = MapGrid.cell_center(Vector2i(4, 24))
	sim.update_fog()
	assert_eq(sim.submit(Commands.attack("player", [a], b)), "target_not_visible")


func test_ac_58_recomputed_at_least_every_5_ticks() -> void:
	var sim: Simulation = _sim()
	var u: int = sim.spawn_unit("worker", "player", Vector2i(10, 10))
	sim.submit(Commands.move("player", [u], Vector2i(10, 24)))
	# 14 cells at 150 per tick: arrives on tick 94. Fog must never be more
	# than 5 ticks old.
	for _i: int in 105:
		sim.step()
		assert_lt(sim.tick - sim.fog_tick, 5, "tick %d: fog last recomputed at %d" % [sim.tick, sim.fog_tick])
	assert_eq(sim.entity(u).unit_cell(), Vector2i(10, 24))
	# Recomputed from the new position: (10, 29) is 5 away, (10, 17) is 7 away.
	assert_true(sim.fog.is_visible("player", Vector2i(10, 29)))
	assert_false(sim.fog.is_visible("player", Vector2i(10, 17)), "old view dropped")
	assert_true(sim.fog.is_explored("player", Vector2i(10, 17)))


func test_ac_58_update_for_80_units_within_2_ms() -> void:
	var m: MapGrid = MapGenerator.generate(58).map
	var sim: Simulation = Simulation.new(m, 58, {"start_workers": 0})
	var rng: SimRng = SimRng.new(58)
	var placed: int = 0
	while placed < 80:
		var c: Vector2i = Vector2i(rng.range_int(48), rng.range_int(48))
		if not sim.is_solid(c):
			sim.spawn_unit(["worker", "melee", "ranged"][placed % 3], Consts.FACTIONS[placed % 2], c)
			placed += 1
	var runs: int = 50
	var t0: int = Time.get_ticks_usec()
	for i: int in runs:
		sim.update_fog()
	var avg: int = (Time.get_ticks_usec() - t0) / runs
	gut.p("AC-58 measured: fog update for 80 units (both factions) takes %d us on average" % avg)
	assert_lte(avg, 2000, "initial target: at most 2 ms")


func test_observation_contains_only_allowed_information() -> void:
	var sim: Simulation = Simulation.new(MapGenerator.generate(7).map, 7, {})
	var obs: Observation = sim.observation("ai")
	assert_eq(obs.tick, 0)
	assert_eq(obs.faction, "ai")
	assert_eq(obs.resources, {"wood": 200, "gold": 100, "food": 100})
	assert_eq(obs.own_units.size(), 3, "three starting workers")
	assert_eq(obs.own_buildings.size(), 1, "the HQ")
	assert_eq(obs.enemy_units.size(), 0, "the player is far away")
	assert_eq(obs.ghosts.size(), 0)
	assert_eq(obs.possible_starts, sim.map.possible_starts)
	assert_eq(obs.width, 48)
	assert_eq(obs.terrain, sim.map.blocked)
	assert_true(obs.stats.has("barracks"))
	# The observation is a copy: changing it cannot change the simulation.
	obs.resources.wood = 99999
	obs.terrain[0] = 1 - obs.terrain[0]
	assert_eq(sim.resources.ai.wood, 200)
	for n: Dictionary in obs.nodes:
		assert_true(sim.fog.is_explored("ai", n.cell), "only nodes it has seen")
