## AC-12 to AC-18: the A* pathfinder.
extends GutTest


func _grid(w: int, h: int, blocked: Array[Vector2i]) -> PackedByteArray:
	var g: PackedByteArray = PackedByteArray()
	g.resize(w * h)
	for c: Vector2i in blocked:
		g[c.y * w + c.x] = 1
	return g


## Breadth-first distances from `from` (independent of the pathfinder).
func _bfs(w: int, h: int, solid: PackedByteArray, from: Vector2i) -> PackedInt32Array:
	var dist: PackedInt32Array = PackedInt32Array()
	dist.resize(w * h)
	dist.fill(-1)
	if solid[from.y * w + from.x] == 1:
		return dist
	dist[from.y * w + from.x] = 0
	var queue: Array[Vector2i] = [from]
	var head: int = 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var n: Vector2i = c + d
			if n.x >= 0 and n.y >= 0 and n.x < w and n.y < h and solid[n.y * w + n.x] == 0 and dist[n.y * w + n.x] == -1:
				dist[n.y * w + n.x] = dist[c.y * w + c.x] + 1
				queue.append(n)
	return dist


func _assert_legal(w: int, h: int, solid: PackedByteArray, path: Array[Vector2i], start: Vector2i, goal: Vector2i) -> void:
	assert_eq(path[0], start, "path starts at the start")
	assert_eq(path[path.size() - 1], goal, "path ends at the goal")
	for i: int in path.size():
		var c: Vector2i = path[i]
		assert_true(c.x >= 0 and c.y >= 0 and c.x < w and c.y < h and solid[c.y * w + c.x] == 0, "cell %s walkable" % c)
		if i > 0:
			assert_eq(absi(c.x - path[i - 1].x) + absi(c.y - path[i - 1].y), 1, "step %d is to a 4-neighbour" % i)


func test_ac_12_empty_grid_corner_to_corner() -> void:
	# Manhattan distance |9-0| + |9-0| = 18 steps, so 19 cells.
	var g: PackedByteArray = _grid(10, 10, [])
	var path: Array[Vector2i] = Pathfinder.find_path(10, 10, g, Vector2i(0, 0), Vector2i(9, 9)).path
	assert_eq(path.size(), 19)
	_assert_legal(10, 10, g, path, Vector2i(0, 0), Vector2i(9, 9))


func test_ac_13_wall_with_gap() -> void:
	# Wall at x = 5 for y = 0..8; the only gap is (5, 9).
	# Shortest route: down 9 to y = 9, right 9 to x = 9, up 9 to y = 0 = 27 steps.
	var wall: Array[Vector2i] = []
	for y: int in 9:
		wall.append(Vector2i(5, y))
	var g: PackedByteArray = _grid(10, 10, wall)
	var path: Array[Vector2i] = Pathfinder.find_path(10, 10, g, Vector2i(0, 0), Vector2i(9, 0)).path
	assert_eq(path.size() - 1, 27)
	_assert_legal(10, 10, g, path, Vector2i(0, 0), Vector2i(9, 0))
	assert_true(path.has(Vector2i(5, 9)), "goes through the gap")


func test_ac_14_enclosed_goal_returns_no_path() -> void:
	# Goal (5, 5) inside a ring of walls; 100 - 8 walls - 1 goal = 91 cells reachable.
	var ring: Array[Vector2i] = []
	for y: int in range(4, 7):
		for x: int in range(4, 7):
			if Vector2i(x, y) != Vector2i(5, 5):
				ring.append(Vector2i(x, y))
	var g: PackedByteArray = _grid(10, 10, ring)
	var r: Dictionary = Pathfinder.find_path(10, 10, g, Vector2i(0, 0), Vector2i(5, 5))
	assert_eq(r.path.size(), 0, "no partial path")
	var reachable: int = 0
	for d: int in _bfs(10, 10, g, Vector2i(0, 0)):
		if d >= 0:
			reachable += 1
	assert_eq(reachable, 91)
	assert_lte(r.expanded, reachable, "explores no more than the reachable cells")


func test_ac_14_blocked_goal_returns_no_path() -> void:
	var g: PackedByteArray = _grid(10, 10, [Vector2i(7, 7)])
	var r: Dictionary = Pathfinder.find_path(10, 10, g, Vector2i(0, 0), Vector2i(7, 7))
	assert_eq(r.path.size(), 0)
	assert_eq(r.expanded, 0)


func test_ac_14_blocked_start_returns_no_path() -> void:
	var g: PackedByteArray = _grid(10, 10, [Vector2i(0, 0)])
	var r: Dictionary = Pathfinder.find_path(10, 10, g, Vector2i(0, 0), Vector2i(7, 7))
	assert_eq(r.path.size(), 0)
	assert_eq(r.expanded, 0)


func test_ac_14_out_of_bounds_goal_returns_no_path() -> void:
	var g: PackedByteArray = _grid(10, 10, [])
	assert_eq(Pathfinder.find_path(10, 10, g, Vector2i(0, 0), Vector2i(10, 3)).path.size(), 0)


func test_ac_14_start_equals_goal() -> void:
	var g: PackedByteArray = _grid(10, 10, [])
	var path: Array[Vector2i] = Pathfinder.find_path(10, 10, g, Vector2i(4, 4), Vector2i(4, 4)).path
	assert_eq(path, [Vector2i(4, 4)], "one cell, length 0")


func test_ac_15_astar_length_equals_bfs_on_random_grids() -> void:
	var rng: SimRng = SimRng.new(15)
	var n: int = TestCounts.pick(200, 1000)
	for t: int in n:
		var w: int = rng.between(2, 20)
		var h: int = rng.between(2, 20)
		var density: int = rng.between(0, 45)
		var blocked: Array[Vector2i] = []
		for y: int in h:
			for x: int in w:
				if rng.range_int(100) < density:
					blocked.append(Vector2i(x, y))
		var g: PackedByteArray = _grid(w, h, blocked)
		var s: Vector2i = Vector2i(rng.range_int(w), rng.range_int(h))
		var e: Vector2i = Vector2i(rng.range_int(w), rng.range_int(h))
		var expected: int = _bfs(w, h, g, s)[e.y * w + e.x]
		var path: Array[Vector2i] = Pathfinder.find_path(w, h, g, s, e).path
		if expected < 0:
			assert_eq(path.size(), 0, "grid %d: both report no path" % t)
		else:
			assert_eq(path.size() - 1, expected, "grid %d: A* length equals BFS length" % t)
			_assert_legal(w, h, g, path, s, e)


func test_ac_16_manhattan_is_admissible_and_consistent() -> void:
	var rng: SimRng = SimRng.new(16)
	for t: int in TestCounts.pick(30, 300):
		var w: int = rng.between(3, 16)
		var h: int = rng.between(3, 16)
		var blocked: Array[Vector2i] = []
		for y: int in h:
			for x: int in w:
				if rng.range_int(100) < 30:
					blocked.append(Vector2i(x, y))
		var g: PackedByteArray = _grid(w, h, blocked)
		var goal: Vector2i = Vector2i(rng.range_int(w), rng.range_int(h))
		var true_dist: PackedInt32Array = _bfs(w, h, g, goal)
		for y: int in h:
			for x: int in w:
				var a: Vector2i = Vector2i(x, y)
				var ha: int = Pathfinder.heuristic(a, goal)
				if true_dist[y * w + x] >= 0:
					assert_lte(ha, true_dist[y * w + x], "admissible at %s" % a)
				for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
					var b: Vector2i = a + d
					if b.x < w and b.y < h:
						var hb: int = Pathfinder.heuristic(b, goal)
						assert_true(ha <= 1 + hb and hb <= 1 + ha, "consistent between %s and %s" % [a, b])


func test_ac_17_identical_inputs_identical_path() -> void:
	# An open grid has many equally short paths, so tie-breaking decides.
	var g: PackedByteArray = _grid(15, 15, [Vector2i(7, 7), Vector2i(3, 9)])
	var first: Array[Vector2i] = Pathfinder.find_path(15, 15, g, Vector2i(1, 2), Vector2i(13, 12)).path
	for i: int in 20:
		var again: Array[Vector2i] = Pathfinder.find_path(15, 15, g.duplicate(), Vector2i(1, 2), Vector2i(13, 12)).path
		assert_eq(again, first)


## A serpentine 48 x 48 maze: walls on odd columns 1..45, each with one gap,
## alternating bottom (x = 1, 5, ...) and top (x = 3, 7, ...), so the path
## snakes through almost every cell. This is the worst case for a 48 x 48 map.
func _serpentine() -> PackedByteArray:
	var blocked: Array[Vector2i] = []
	for x: int in range(1, 47, 2):
		var gap: int = 47 if (x / 2) % 2 == 0 else 0
		for y: int in 48:
			if y != gap:
				blocked.append(Vector2i(x, y))
	return _grid(48, 48, blocked)


func test_ac_18_worst_case_48_by_48_within_budget() -> void:
	var g: PackedByteArray = _serpentine()
	var goal: Vector2i = Vector2i(47, 0)
	var r: Dictionary = Pathfinder.find_path(48, 48, g, Vector2i(0, 0), goal)
	# Open columns 0, 2, ..., 44 are walked end to end (23 x 47 = 1081 steps),
	# joined by 23 gaps of 2 steps (46), reaching (46, 47) after 1127 steps;
	# then 47 up and 1 right to (47, 0): 1127 + 48 = 1175.
	assert_eq(r.path.size() - 1, 1175)
	var runs: int = 20
	var t0: int = Time.get_ticks_usec()
	for i: int in runs:
		Pathfinder.find_path(48, 48, g, Vector2i(0, 0), goal)
	var avg_usec: int = (Time.get_ticks_usec() - t0) / runs
	gut.p("AC-18 measured: worst-case 48x48 path takes %d us on average" % avg_usec)
	assert_lte(avg_usec, 5000, "initial target: at most 5 ms")
