## AC-08 to AC-11: map loading, coordinates and the symmetric generator.
extends GutTest

const N: int = 48


func _tutorial_raw() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/tutorial.json"))


func test_ac_08_tutorial_map_loads() -> void:
	var r: Dictionary = MapGrid.load_file("res://data/maps/tutorial.json")
	assert_eq(r.error, "")
	var m: MapGrid = r.map
	assert_eq(m.map_name, "tutorial")
	assert_eq(m.width, 12)
	assert_eq(m.height, 8)
	# The "##" blocks in rows 2 and 3 at columns 6 and 7: exactly 4 blocked cells.
	var blocked: Array[Vector2i] = []
	for y: int in m.height:
		for x: int in m.width:
			if not m.is_walkable(Vector2i(x, y)):
				blocked.append(Vector2i(x, y))
	assert_eq(blocked, [Vector2i(6, 2), Vector2i(7, 2), Vector2i(6, 3), Vector2i(7, 3)])
	assert_eq(m.nodes.size(), 2)
	assert_eq(m.nodes[0].type, "wood")
	assert_eq(m.nodes[0].cell, Vector2i(5, 1))
	assert_eq(m.nodes[0].amount, 500)
	assert_eq(m.nodes[1].type, "gold")
	assert_eq(m.nodes[1].cell, Vector2i(5, 6))
	assert_eq(m.nodes[1].amount, 300)
	assert_eq(m.starts["player"], Vector2i(1, 3))
	assert_eq(m.starts["ai"], Vector2i(8, 3))
	assert_eq(m.possible_starts, [Vector2i(1, 3), Vector2i(8, 3)])
	assert_false(m.is_walkable(Vector2i(-1, 0)), "out of bounds is not walkable")
	assert_false(m.is_walkable(Vector2i(12, 0)), "out of bounds is not walkable")


func test_ac_08_ragged_row_fails() -> void:
	var raw: Dictionary = _tutorial_raw()
	raw.tiles[4] = "..........."  # 11 characters instead of 12
	var r: Dictionary = MapGrid.from_dict(raw)
	assert_null(r.map)
	assert_true(r.error.contains("row 4") and r.error.contains("ragged"), r.error)


func test_ac_08_unknown_tile_character_fails() -> void:
	var raw: Dictionary = _tutorial_raw()
	raw.tiles[0] = "....x......."
	var r: Dictionary = MapGrid.from_dict(raw)
	assert_null(r.map)
	assert_true(r.error.contains("unknown tile") and r.error.contains("'x'") and r.error.contains("(4, 0)"), r.error)


func test_ac_08_wrong_row_count_fails() -> void:
	var raw: Dictionary = _tutorial_raw()
	(raw.tiles as Array).pop_back()
	var r: Dictionary = MapGrid.from_dict(raw)
	assert_null(r.map)
	assert_true(r.error.contains("rows"), r.error)


func test_ac_08_start_on_blocked_cell_fails() -> void:
	# An HQ anchored at (5, 1) covers (5..7, 1..3), which includes blocked (6, 2).
	var raw: Dictionary = _tutorial_raw()
	raw.starts[1].cell = [5, 1]
	raw.nodes[0].cell = [0, 0]  # keep the wood node out of the footprint
	var r: Dictionary = MapGrid.from_dict(raw)
	assert_null(r.map)
	assert_true(r.error.contains("start") and r.error.contains("ai") and r.error.contains("blocked"), r.error)


func test_ac_08_node_on_blocked_cell_fails() -> void:
	var raw: Dictionary = _tutorial_raw()
	raw.nodes[1].cell = [7, 3]
	var r: Dictionary = MapGrid.from_dict(raw)
	assert_null(r.map)
	assert_true(r.error.contains("node") and r.error.contains("blocked"), r.error)


func test_ac_08_node_outside_map_fails() -> void:
	var raw: Dictionary = _tutorial_raw()
	raw.nodes[0].cell = [12, 1]
	var r: Dictionary = MapGrid.from_dict(raw)
	assert_null(r.map)
	assert_true(r.error.contains("node") and r.error.contains("outside"), r.error)


func test_ac_09_cell_centre_round_trip() -> void:
	var centre: Vector2i = MapGrid.cell_center(Vector2i(3, 4))
	assert_eq(centre, Vector2i(3500, 4500))
	assert_eq(MapGrid.milli_to_cell(centre), Vector2i(3, 4))
	assert_eq(MapGrid.milli_to_pixel(centre), Vector2i(112, 144))
	# Any point inside the cell maps back to it; the next milli-cell does not.
	assert_eq(MapGrid.milli_to_cell(Vector2i(3000, 4999)), Vector2i(3, 4))
	assert_eq(MapGrid.milli_to_cell(Vector2i(4000, 4500)), Vector2i(4, 4))


# --- generator (AC-10, AC-11) ---------------------------------------------

## Independent BFS on the generated map: passable = walkable terrain that is not
## a resource node and not inside an HQ footprint. Returns distances, -1 if unreached.
func _bfs(m: MapGrid, sources: Array[Vector2i]) -> PackedInt32Array:
	var solid: PackedByteArray = PackedByteArray()
	solid.resize(m.width * m.height)
	for y: int in m.height:
		for x: int in m.width:
			solid[y * m.width + x] = 0 if m.is_walkable(Vector2i(x, y)) else 1
	for node: Dictionary in m.nodes:
		solid[node.cell.y * m.width + node.cell.x] = 1
	for f: String in m.starts:
		for c: Vector2i in _footprint(m.starts[f]):
			solid[c.y * m.width + c.x] = 1
	var dist: PackedInt32Array = PackedInt32Array()
	dist.resize(m.width * m.height)
	dist.fill(-1)
	var queue: Array[Vector2i] = []
	for s: Vector2i in sources:
		if solid[s.y * m.width + s.x] == 0 and dist[s.y * m.width + s.x] == -1:
			dist[s.y * m.width + s.x] = 0
			queue.append(s)
	var head: int = 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= m.width or n.y >= m.height:
				continue
			var i: int = n.y * m.width + n.x
			if solid[i] == 1 or dist[i] != -1:
				continue
			dist[i] = dist[c.y * m.width + c.x] + 1
			queue.append(n)
	return dist


func _footprint(anchor: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy: int in 3:
		for dx: int in 3:
			out.append(anchor + Vector2i(dx, dy))
	return out


## The cells 4-adjacent to a w x h rectangle (not diagonal, inside the map).
func _ring(m: MapGrid, anchor: Vector2i, w: int, h: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in range(anchor.y - 1, anchor.y + h + 1):
		for x: int in range(anchor.x - 1, anchor.x + w + 1):
			var inside: bool = x >= anchor.x and x < anchor.x + w and y >= anchor.y and y < anchor.y + h
			var corner: bool = (x < anchor.x or x >= anchor.x + w) and (y < anchor.y or y >= anchor.y + h)
			if not inside and not corner and x >= 0 and y >= 0 and x < m.width and y < m.height:
				out.append(Vector2i(x, y))
	return out


func _check_generated(p_seed: int) -> void:
	var r: Dictionary = MapGenerator.generate(p_seed)
	assert_eq(r.error, "", "seed %d generates" % p_seed)
	if r.error != "":
		return
	var m: MapGrid = r.map
	assert_eq(m.width, N)
	assert_eq(m.height, N)
	# Point symmetry of terrain: (x, y) <-> (47 - x, 47 - y).
	var sym: bool = true
	for y: int in N:
		for x: int in N:
			sym = sym and m.is_walkable(Vector2i(x, y)) == m.is_walkable(Vector2i(N - 1 - x, N - 1 - y))
	assert_true(sym, "seed %d terrain symmetric" % p_seed)
	# Nodes: each node has a mirror of the same type and amount.
	var keys: Dictionary = {}
	for node: Dictionary in m.nodes:
		keys["%s %d %d %d" % [node.type, node.cell.x, node.cell.y, node.amount]] = true
	for node: Dictionary in m.nodes:
		var mk: String = "%s %d %d %d" % [node.type, N - 1 - node.cell.x, N - 1 - node.cell.y, node.amount]
		assert_true(keys.has(mk), "seed %d node %s mirrored" % [p_seed, node.cell])
	# Starts: a 3 x 3 footprint mirrors to anchor (45 - x, 45 - y) (decision D-22).
	var p: Vector2i = m.starts["player"]
	assert_eq(m.starts["ai"], Vector2i(N - 3 - p.x, N - 3 - p.y), "seed %d starts mirrored" % p_seed)
	# HQs connected, and each side has >= 2 wood and >= 1 gold within 15 path steps.
	for f: String in ["player", "ai"]:
		var other: String = "ai" if f == "player" else "player"
		var dist: PackedInt32Array = _bfs(m, _ring(m, m.starts[f], 3, 3))
		var reaches: bool = false
		for c: Vector2i in _ring(m, m.starts[other], 3, 3):
			reaches = reaches or dist[c.y * N + c.x] >= 0
		assert_true(reaches, "seed %d: %s HQ reaches the other HQ" % [p_seed, f])
		var near: Dictionary = {"wood": 0, "gold": 0}
		for node: Dictionary in m.nodes:
			var best: int = -1
			for c: Vector2i in _ring(m, node.cell, 1, 1):
				var d: int = dist[c.y * N + c.x]
				if d >= 0 and (best == -1 or d < best):
					best = d
			if best >= 0 and best <= 15:
				near[node.type] += 1
		assert_true(near.wood >= 2 and near.gold >= 1, "seed %d: %s has %s near its HQ" % [p_seed, f, near])


func test_ac_10_generated_maps_symmetric_connected_and_resourced() -> void:
	var count: int = TestCounts.pick(40, 1000)
	for s: int in count:
		_check_generated(s)


func test_ac_10_impossible_settings_fail_with_code() -> void:
	# A 6 x 6 map cannot hold two 3 x 3 HQs with clear space around them.
	var r: Dictionary = MapGenerator.generate(1, 6)
	assert_null(r.map)
	assert_eq(r.error, "map_generation_failed")


func test_ac_11_same_seed_same_map() -> void:
	for s: int in [0, 5, 12345]:
		var a: MapGrid = MapGenerator.generate(s).map
		var b: MapGrid = MapGenerator.generate(s).map
		assert_eq(a.fingerprint(), b.fingerprint(), "seed %d" % s)


func test_ac_11_hundred_seeds_at_least_95_distinct() -> void:
	var seen: Dictionary = {}
	for s: int in 100:
		seen[MapGenerator.generate(s).map.fingerprint()] = true
	assert_gte(seen.size(), 95)
