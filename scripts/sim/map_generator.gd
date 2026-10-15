## Generates point-symmetric maps from a seed (AC-10, AC-11, decision D-08).
##
## Symmetry: cell (x, y) mirrors to (size-1-x, size-1-y). A w x h footprint
## anchored at (x, y) mirrors to anchor (size-w-x, size-h-y) (decision D-22),
## so the 3 x 3 HQs sit at (x, y) and (size-3-x, size-3-y).
##
## Each attempt: pick the player HQ, keep a 2-cell clear zone round both HQs,
## scatter mirrored rectangular rocks, then place mirrored resource nodes
## (2 wood + 1 gold near each HQ, plus extras). An attempt is accepted only if
##   - the two HQs are connected by a walkable path, and
##   - each HQ has >= 2 wood and >= 1 gold node within 15 path steps
##     (path length from a cell 4-adjacent to the HQ footprint to a cell
##     4-adjacent to the node; decision D-25).
## After 50 failed attempts the result is "map_generation_failed".
class_name MapGenerator
extends RefCounted

const MAX_TRIES: int = 50
const HQ: int = 3
const CLEAR: int = 2
const NEAR_STEPS: int = 15
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


static func generate(p_seed: int, size: int = Consts.DEFAULT_MAP_SIZE) -> Dictionary:
	var rng: SimRng = SimRng.new(p_seed)
	for attempt: int in MAX_TRIES:
		var m: MapGrid = _attempt(rng, size)
		if m != null and _acceptable(m):
			m.map_name = "generated-%d" % p_seed
			return {"map": m, "error": ""}
	return {"map": null, "error": "map_generation_failed"}


static func mirror(cell: Vector2i, size: int) -> Vector2i:
	return Vector2i(size - 1 - cell.x, size - 1 - cell.y)


static func _attempt(rng: SimRng, size: int) -> MapGrid:
	var hi: int = mini(9, size / 2 - HQ - CLEAR)
	if hi < CLEAR:
		return null
	var m: MapGrid = MapGrid.new(size, size)
	var p: Vector2i = Vector2i(rng.between(CLEAR, hi), rng.between(CLEAR, hi))
	var a: Vector2i = Vector2i(size - HQ - p.x, size - HQ - p.y)
	m.starts = {"player": p, "ai": a}
	m.possible_starts = [p, a]

	# Cells kept free of rocks and nodes: each HQ footprint plus a 2-cell margin.
	var reserved: PackedByteArray = PackedByteArray()
	reserved.resize(size * size)
	for anchor: Vector2i in [p, a]:
		for y: int in range(anchor.y - CLEAR, anchor.y + HQ + CLEAR):
			for x: int in range(anchor.x - CLEAR, anchor.x + HQ + CLEAR):
				if m.in_bounds(Vector2i(x, y)):
					reserved[y * size + x] = 1

	# Rocks: mirrored rectangles.
	var rocks: int = rng.between(10, 18)
	for i: int in rocks:
		var c: Vector2i = Vector2i(rng.range_int(size), rng.range_int(size))
		var w: int = rng.between(1, 5)
		var h: int = rng.between(1, 5)
		for y: int in range(c.y, c.y + h):
			for x: int in range(c.x, c.x + w):
				var cell: Vector2i = Vector2i(x, y)
				if m.in_bounds(cell) and reserved[y * size + x] == 0:
					m.set_blocked(cell, true)
					m.set_blocked(mirror(cell, size), true)

	# Resource nodes: guaranteed ones near the player HQ (mirrored to the AI), then extras.
	var occupied: Dictionary = {}
	var hq_centre: Vector2i = p + Vector2i(1, 1)
	for type: String in ["wood", "wood", "gold"]:
		for t: int in 30:
			var c: Vector2i = hq_centre + Vector2i(rng.between(-9, 9), rng.between(-9, 9))
			var manhattan: int = absi(c.x - hq_centre.x) + absi(c.y - hq_centre.y)
			if manhattan >= 5 and manhattan <= 10 and _place_pair(m, reserved, occupied, type, c):
				break
	var extra_wood: int = rng.between(2, 4)
	var extra_gold: int = rng.between(1, 3)
	for k: int in extra_wood + extra_gold:
		var type: String = "wood" if k < extra_wood else "gold"
		for t: int in 30:
			if _place_pair(m, reserved, occupied, type, Vector2i(rng.range_int(size), rng.range_int(size))):
				break
	return m


## Places a node and its mirror if both cells are free; returns true on success.
static func _place_pair(m: MapGrid, reserved: PackedByteArray, occupied: Dictionary, type: String, c: Vector2i) -> bool:
	var mc: Vector2i = mirror(c, m.width)
	if c == mc or not m.is_walkable(c) or not m.is_walkable(mc):
		return false
	if reserved[c.y * m.width + c.x] == 1 or reserved[mc.y * m.width + mc.x] == 1:
		return false
	if occupied.has(c) or occupied.has(mc):
		return false
	var amount: int = Consts.WOOD_NODE_AMOUNT if type == "wood" else Consts.GOLD_NODE_AMOUNT
	m.nodes.append({"type": type, "cell": c, "amount": amount})
	m.nodes.append({"type": type, "cell": mc, "amount": amount})
	occupied[c] = true
	occupied[mc] = true
	return true


static func _acceptable(m: MapGrid) -> bool:
	var solid: PackedByteArray = m.blocked.duplicate()
	for node: Dictionary in m.nodes:
		solid[node.cell.y * m.width + node.cell.x] = 1
	for f: String in m.starts:
		for c: Vector2i in footprint(m.starts[f], HQ, HQ):
			solid[c.y * m.width + c.x] = 1
	for f: String in m.starts:
		var other: String = "ai" if f == "player" else "player"
		var dist: PackedInt32Array = bfs(m.width, m.height, solid, ring(m, m.starts[f], HQ, HQ))
		var connected: bool = false
		for c: Vector2i in ring(m, m.starts[other], HQ, HQ):
			if dist[c.y * m.width + c.x] >= 0:
				connected = true
				break
		if not connected:
			return false
		var wood: int = 0
		var gold: int = 0
		for node: Dictionary in m.nodes:
			var best: int = -1
			for c: Vector2i in ring(m, node.cell, 1, 1):
				var d: int = dist[c.y * m.width + c.x]
				if d >= 0 and (best < 0 or d < best):
					best = d
			if best >= 0 and best <= NEAR_STEPS:
				if node.type == "wood":
					wood += 1
				else:
					gold += 1
		if wood < 2 or gold < 1:
			return false
	return true


static func footprint(anchor: Vector2i, w: int, h: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy: int in h:
		for dx: int in w:
			out.append(anchor + Vector2i(dx, dy))
	return out


## Cells 4-adjacent to the w x h rectangle at anchor, inside the map.
static func ring(m: MapGrid, anchor: Vector2i, w: int, h: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in footprint(anchor, w, h):
		for d: Vector2i in DIRS:
			var n: Vector2i = c + d
			var inside: bool = n.x >= anchor.x and n.x < anchor.x + w and n.y >= anchor.y and n.y < anchor.y + h
			if not inside and m.in_bounds(n) and not out.has(n):
				out.append(n)
	return out


## Breadth-first distances over cells where solid == 0; -1 means unreachable.
static func bfs(w: int, h: int, solid: PackedByteArray, sources: Array[Vector2i]) -> PackedInt32Array:
	var dist: PackedInt32Array = PackedInt32Array()
	dist.resize(w * h)
	dist.fill(-1)
	var queue: Array[Vector2i] = []
	for s: Vector2i in sources:
		var i: int = s.y * w + s.x
		if solid[i] == 0 and dist[i] == -1:
			dist[i] = 0
			queue.append(s)
	var head: int = 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var dc: int = dist[c.y * w + c.x]
		for d: Vector2i in DIRS:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
				continue
			var i: int = n.y * w + n.x
			if solid[i] == 0 and dist[i] == -1:
				dist[i] = dc + 1
				queue.append(n)
	return dist
