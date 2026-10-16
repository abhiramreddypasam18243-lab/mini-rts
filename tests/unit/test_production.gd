## AC-39 to AC-42: production queues, spawning and cancellation.
extends GutTest


func _count(sim: Simulation, kind: String, faction: String) -> int:
	var n: int = 0
	for id: int in sim.entities:
		var e: Entity = sim.entities[id]
		if e.kind == kind and e.faction == faction:
			n += 1
	return n


func _rich(m: MapGrid) -> Simulation:
	return Simulation.new(m, 1, {"start_workers": 0, "start_wood": 5000, "start_gold": 5000})


func test_ac_39_melee_appears_at_tick_200_second_at_400() -> void:
	var sim: Simulation = _rich(TestMaps.open(16, 12))
	var b: int = sim.place_building_unchecked("barracks", "player", Vector2i(6, 5), true)
	assert_eq(sim.submit(Commands.train("player", b, "melee")), "ok")
	assert_eq(sim.submit(Commands.train("player", b, "melee")), "ok")
	for _t: int in 199:
		sim.step()
	assert_eq(_count(sim, "melee", "player"), 0, "absent at tick 199")
	sim.step()
	assert_eq(sim.tick, 200)
	assert_eq(_count(sim, "melee", "player"), 1, "present at tick 200")
	for _t: int in 199:
		sim.step()
	assert_eq(_count(sim, "melee", "player"), 1, "second absent at tick 399")
	sim.step()
	assert_eq(_count(sim, "melee", "player"), 2, "second present at tick 400")
	assert_eq(sim.entity(b).queue.size(), 0)


func test_ac_39_spawns_in_first_free_ring_cell() -> void:
	var sim: Simulation = _rich(TestMaps.open(16, 12))
	var b: int = sim.place_building_unchecked("barracks", "player", Vector2i(6, 5), true)
	sim.submit(Commands.train("player", b, "ranged"))
	for _t: int in 240:
		sim.step()
	var u: int = sim.unit_ids()[0]
	# Ring 1 around (6..7, 5..6) starts at (5, 4), the first cell in row-major order.
	assert_eq(sim.entity(u).unit_cell(), Vector2i(5, 4))
	assert_eq(sim.entity(u).order_type, "idle")


func test_ac_40_soldier_at_hq_is_invalid() -> void:
	var sim: Simulation = _rich(TestMaps.open(16, 12))
	assert_eq(sim.submit(Commands.train("player", sim.hq_of("player"), "melee")), "invalid_unit_for_building")
	var b: int = sim.place_building_unchecked("barracks", "player", Vector2i(6, 5), true)
	assert_eq(sim.submit(Commands.train("player", b, "worker")), "invalid_unit_for_building")


func test_ac_40_sixth_queue_item_is_full() -> void:
	var sim: Simulation = _rich(TestMaps.open(16, 12))
	var hq: int = sim.hq_of("player")
	for i: int in 5:
		assert_eq(sim.submit(Commands.train("player", hq, "worker")), "ok", "item %d" % (i + 1))
	var wood: int = sim.resources.player.wood
	assert_eq(sim.submit(Commands.train("player", hq, "worker")), "queue_full")
	assert_eq(sim.resources.player.wood, wood, "nothing charged")


func test_ac_40_41st_unit_hits_population_cap() -> void:
	var sim: Simulation = _rich(TestMaps.open(30, 20))
	var hq: int = sim.hq_of("player")
	# 39 units alive + 1 queued = 40 = the cap.
	for i: int in 39:
		sim.spawn_unit("worker", "player", Vector2i(5 + i % 20, 6 + i / 20))
	assert_eq(sim.submit(Commands.train("player", hq, "worker")), "ok", "the 40th unit")
	var wood: int = sim.resources.player.wood
	assert_eq(sim.submit(Commands.train("player", hq, "worker")), "population_cap", "the 41st unit")
	assert_eq(sim.resources.player.wood, wood, "nothing charged")


## A barracks at (5..6, 5..6) with every spawn-ring cell (rings 1 to 3, i.e.
## x and y in 2..9) walled off, except three cells holding resource nodes:
## (4, 4) in ring 1, and (6, 3) and (3, 4) in ring 2.
func _boxed_in() -> Array:
	var walls: Array[Vector2i] = []
	var keep: Array[Vector2i] = [Vector2i(4, 4), Vector2i(6, 3), Vector2i(3, 4), Vector2i(2, 2)]
	for y: int in range(2, 10):
		for x: int in range(2, 10):
			var c: Vector2i = Vector2i(x, y)
			var in_footprint: bool = x >= 5 and x <= 6 and y >= 5 and y <= 6
			if not in_footprint and not keep.has(c):
				walls.append(c)
	var nodes: Array[Dictionary] = []
	for c: Vector2i in keep.slice(0, 3):
		nodes.append({"type": "gold", "cell": c, "amount": 300})
	var sim: Simulation = _rich(TestMaps.open(14, 14, walls, nodes))
	var b: int = sim.place_building_unchecked("barracks", "player", Vector2i(5, 5), true)
	sim.submit(Commands.train("player", b, "melee"))
	var events: Array[Dictionary] = []
	for _t: int in 260:
		sim.step()
		events.append_array(sim.take_events())
	return [sim, b, events]


func test_ac_41_blocked_spawn_waits_with_one_message() -> void:
	var s: Array = _boxed_in()
	var sim: Simulation = s[0]
	assert_eq(_count(sim, "melee", "player"), 0, "no free cell: nothing spawned")
	assert_eq(sim.entity(s[1]).queue.size(), 1, "the finished unit waits at the front")
	assert_eq(sim.entity(s[1]).queue[0].status, "spawn_blocked")
	var n: int = 0
	for e: Dictionary in s[2]:
		if e.type == "message" and e.code == "spawn_blocked":
			n += 1
	assert_eq(n, 1, "one message, not one per tick")


func test_ac_41_spawns_first_tick_a_cell_frees_row_major_within_ring() -> void:
	var s: Array = _boxed_in()
	var sim: Simulation = s[0]
	# Free two ring-2 cells in the same tick: (6, 3) comes first in row-major order.
	sim.destroy_entity(sim.node_at(Vector2i(3, 4)))
	sim.destroy_entity(sim.node_at(Vector2i(6, 3)))
	sim.step()
	assert_eq(_count(sim, "melee", "player"), 1, "spawns on the first tick a cell is free")
	assert_eq(sim.entity(sim.unit_ids()[0]).unit_cell(), Vector2i(6, 3))


func test_ac_41_inner_ring_comes_before_outer_ring() -> void:
	var s: Array = _boxed_in()
	var sim: Simulation = s[0]
	# (6, 3) is in an earlier row, but (4, 4) is in ring 1, which is scanned first.
	sim.destroy_entity(sim.node_at(Vector2i(6, 3)))
	sim.destroy_entity(sim.node_at(Vector2i(4, 4)))
	sim.step()
	assert_eq(sim.entity(sim.unit_ids()[0]).unit_cell(), Vector2i(4, 4))


func test_ac_42_destroyed_building_loses_queue_without_refund() -> void:
	var sim: Simulation = Simulation.new(TestMaps.open(16, 12), 1, {"start_workers": 0})
	var b: int = sim.place_building_unchecked("barracks", "player", Vector2i(6, 5), true)
	sim.submit(Commands.train("player", b, "melee"))
	sim.submit(Commands.train("player", b, "melee"))
	var after_paying: Dictionary = sim.resources.player.duplicate()
	assert_eq(after_paying, {"wood": 200 - 120, "gold": 100 - 40})
	assert_eq(sim.population("player"), 2)
	sim.destroy_entity(b)
	assert_eq(sim.resources.player, after_paying, "no refund")
	assert_eq(sim.population("player"), 0, "queued units are gone")
	for c: Vector2i in [Vector2i(6, 5), Vector2i(7, 5), Vector2i(6, 6), Vector2i(7, 6)]:
		assert_false(sim.is_solid(c), "%s walkable again" % c)
	for _t: int in 400:
		sim.step()
	assert_eq(_count(sim, "melee", "player"), 0, "nothing ever spawns")
	assert_eq(Invariants.check(sim), PackedStringArray())
