## AC-36 to AC-38: building placement and construction.
extends GutTest

const BARRACKS_WOOD: int = 120
const BARRACKS_GOLD: int = 60


## 16 x 12 map with a wall at (8, 8) and a wood node at (9, 3).
## Player HQ covers (0..2, 0..2); the AI HQ covers (13..15, 9..11).
func _setup(config: Dictionary = {}) -> Array:
	var m: MapGrid = TestMaps.open(16, 12, [Vector2i(8, 8)], [{"type": "wood", "cell": Vector2i(9, 3), "amount": 500}])
	var cfg: Dictionary = {"start_workers": 0}
	cfg.merge(config, true)
	var sim: Simulation = Simulation.new(m, 1, cfg)
	var worker: int = sim.spawn_unit("worker", "player", Vector2i(4, 8))
	return [sim, worker]


func _assert_rejected(sim: Simulation, worker: int, cell: Vector2i, code: String, why: String) -> void:
	var before_res: Dictionary = sim.resources.player.duplicate()
	var before_count: int = sim.entities.size()
	var before_hash: int = sim.state_hash()
	assert_eq(sim.submit(Commands.build("player", worker, "barracks", cell)), code, why)
	assert_eq(sim.resources.player, before_res, why + ": stockpile unchanged")
	assert_eq(sim.entities.size(), before_count, why + ": nothing placed")
	assert_eq(sim.state_hash(), before_hash, why + ": state unchanged")


func test_ac_36_out_of_bounds() -> void:
	var s: Array = _setup()
	# A 2 x 2 footprint at (15, 5) covers x = 15..16; x = 16 is outside.
	_assert_rejected(s[0], s[1], Vector2i(15, 5), "invalid_placement", "out of bounds")
	_assert_rejected(s[0], s[1], Vector2i(-1, 5), "invalid_placement", "negative cell")


func test_ac_36_blocked_terrain() -> void:
	var s: Array = _setup()
	# (7, 7) covers (7..8, 7..8), which includes the wall (8, 8).
	_assert_rejected(s[0], s[1], Vector2i(7, 7), "invalid_placement", "blocked terrain")


func test_ac_36_overlapping_a_building() -> void:
	var s: Array = _setup()
	# (2, 2) covers (2..3, 2..3); (2, 2) is part of the player HQ.
	_assert_rejected(s[0], s[1], Vector2i(2, 2), "invalid_placement", "overlaps the HQ")


func test_ac_36_overlapping_a_resource_node() -> void:
	var s: Array = _setup()
	_assert_rejected(s[0], s[1], Vector2i(8, 2), "invalid_placement", "overlaps the node at (9, 3)")


func test_ac_36_overlapping_a_unit() -> void:
	var s: Array = _setup()
	var sim: Simulation = s[0]
	sim.spawn_unit("melee", "player", Vector2i(11, 6))
	_assert_rejected(sim, s[1], Vector2i(10, 5), "invalid_placement", "a unit stands at (11, 6)")
	_assert_rejected(sim, s[1], Vector2i(4, 7), "invalid_placement", "the builder itself stands at (4, 8)")


func test_ac_36_unexplored_cell() -> void:
	var s: Array = _setup()
	var sim: Simulation = s[0]
	sim.fog.set_explored("player", Vector2i(12, 4), false)
	_assert_rejected(sim, s[1], Vector2i(11, 3), "not_explored", "(12, 4) is unexplored")


func test_ac_36_insufficient_resources() -> void:
	var s: Array = _setup({"start_wood": 100})
	_assert_rejected(s[0], s[1], Vector2i(6, 5), "insufficient_resources", "100 wood < 120")


func test_ac_36_not_a_worker_or_not_a_building_type() -> void:
	var s: Array = _setup()
	var sim: Simulation = s[0]
	var soldier: int = sim.spawn_unit("melee", "player", Vector2i(5, 9))
	_assert_rejected(sim, soldier, Vector2i(6, 5), "invalid_target", "only workers build")
	assert_eq(sim.submit(Commands.build("player", s[1], "hq", Vector2i(6, 5))), "invalid_target", "an HQ cannot be built")


func test_ac_37_valid_placement_pays_once_and_blocks_at_once() -> void:
	var s: Array = _setup()
	var sim: Simulation = s[0]
	assert_eq(sim.submit(Commands.build("player", s[1], "barracks", Vector2i(6, 5))), "ok")
	assert_eq(sim.resources.player, {"wood": 200 - BARRACKS_WOOD, "gold": 100 - BARRACKS_GOLD, "food": 100})
	assert_eq(sim.bank.spent.player, {"wood": BARRACKS_WOOD, "gold": BARRACKS_GOLD, "food": 0}, "deducted exactly once")
	for c: Vector2i in [Vector2i(6, 5), Vector2i(7, 5), Vector2i(6, 6), Vector2i(7, 6)]:
		assert_true(sim.is_solid(c), "%s blocks movement from the placement tick" % c)
	# A straight path along row 5 from (4, 5) to (10, 5) must now go round.
	var path: Array[Vector2i] = Pathfinder.find_path(16, 12, sim.solid, Vector2i(4, 5), Vector2i(10, 5)).path
	assert_eq(path.size() - 1, 8, "6 steps straight are blocked; the detour is 8")
	for _t: int in 300:
		sim.step()
	assert_eq(sim.resources.player, {"wood": 200 - BARRACKS_WOOD, "gold": 100 - BARRACKS_GOLD, "food": 100}, "no second charge")


func test_ac_38_completes_after_exactly_300_ticks() -> void:
	var s: Array = _setup()
	var sim: Simulation = s[0]
	# The worker at (4, 8) already touches a barracks at (5, 6) (covers 5..6, 6..7).
	assert_eq(sim.submit(Commands.build("player", s[1], "barracks", Vector2i(5, 6))), "ok")
	var b: int = sim.occupant_at(Vector2i(5, 6))
	assert_false(sim.entity(b).complete)
	assert_eq(sim.submit(Commands.train("player", b, "melee")), "not_ready")
	for _t: int in 299:
		sim.step()
	assert_false(sim.entity(b).complete, "not complete after 299 ticks")
	assert_eq(sim.entity(b).progress, 299)
	assert_eq(sim.submit(Commands.train("player", b, "melee")), "not_ready")
	sim.step()
	assert_true(sim.entity(b).complete, "complete after exactly 300 ticks")
	assert_eq(sim.entity(s[1]).order_type, "idle", "the builder is released")
	assert_eq(sim.submit(Commands.train("player", b, "melee")), "ok", "soldiers can now be trained")


func test_ac_38_progress_pauses_and_resumes() -> void:
	var s: Array = _setup()
	var sim: Simulation = s[0]
	var w: int = s[1]
	sim.submit(Commands.build("player", w, "barracks", Vector2i(5, 6)))
	var b: int = sim.occupant_at(Vector2i(5, 6))
	for _t: int in 100:
		sim.step()
	assert_eq(sim.entity(b).progress, 100)
	sim.submit(Commands.move("player", [w], Vector2i(11, 9)))
	for _t: int in 80:
		sim.step()
	assert_eq(sim.entity(b).progress, 100, "holds while no worker is adjacent")
	assert_eq(sim.submit(Commands.build("player", w, "barracks", Vector2i(5, 6))), "ok", "resume: no new charge")
	assert_eq(sim.resources.player, {"wood": 80, "gold": 40, "food": 100})
	var seen: Array[int] = []
	for _t: int in 400:
		sim.step()
		var p: int = sim.entity(b).progress
		if seen.is_empty() or seen[seen.size() - 1] != p:
			seen.append(p)
		if sim.entity(b).complete:
			break
	assert_eq(seen[0], 100, "resumes from the same value")
	assert_true(sim.entity(b).complete)
	assert_eq(sim.entity(b).progress, 300)
