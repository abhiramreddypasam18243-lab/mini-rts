## A* on a 4-directional grid (SPEC 4, 5.2; AC-12 to AC-18; decision D-03).
##
## f(n) = g(n) + h(n): g = steps from the start, h = Manhattan distance to the
## goal. Each step costs 1 and moves up, right, down or left, so Manhattan
## distance never overestimates (admissible) and changes by at most 1 per step
## (consistent). With a consistent heuristic the first time a cell is taken
## from the open set its g is final, so the path returned is a shortest one.
##
## Determinism (AC-17): neighbours are always tried in the order up, right,
## down, left, and the open set is ordered by (f, then h, then insertion
## order). Equal inputs therefore give the identical path every time.
##
## Failure (AC-14): a blocked or out-of-bounds start or goal returns no path
## at once; otherwise the search ends when the open set is empty, having
## expanded only cells reachable from the start. No partial path is returned.
class_name Pathfinder
extends RefCounted

## Open-set keys pack (f, h, seq) into one int so one comparison orders them:
## f in bits 42+, h in bits 26..41, seq (insertion counter) in bits 0..25.
const F_SHIFT: int = 42
const H_SHIFT: int = 26
const MAX_CELLS: int = 1 << 20
const DX: Array[int] = [0, 1, 0, -1]
const DY: Array[int] = [-1, 0, 1, 0]


static func heuristic(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## solid[y * w + x] == 1 means the cell cannot be entered.
## Returns {"path": Array[Vector2i] (empty = no path), "expanded": int}.
static func find_path(w: int, h: int, solid: PackedByteArray, start: Vector2i, goal: Vector2i) -> Dictionary:
	assert(w * h < MAX_CELLS, "grid too large for the packed open-set keys")
	var path: Array[Vector2i] = []
	if not _open_cell(w, h, solid, start) or not _open_cell(w, h, solid, goal):
		return {"path": path, "expanded": 0}
	var n: int = w * h
	var si: int = start.y * w + start.x
	var gi: int = goal.y * w + goal.x
	var g: PackedInt32Array = PackedInt32Array()
	g.resize(n)
	g.fill(-1)
	var came: PackedInt32Array = PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var closed: PackedByteArray = PackedByteArray()
	closed.resize(n)

	# Binary min-heap kept in two parallel arrays (keys, cell indexes).
	# Written inline: packed arrays are copied when passed to a function.
	var keys: PackedInt64Array = PackedInt64Array()
	var cells: PackedInt32Array = PackedInt32Array()
	var h0: int = heuristic(start, goal)
	keys.append((h0 << F_SHIFT) | (h0 << H_SHIFT))
	cells.append(si)
	g[si] = 0
	var seq: int = 0
	var expanded: int = 0

	while keys.size() > 0:
		# Pop the smallest key.
		var ci: int = cells[0]
		var last: int = keys.size() - 1
		var lk: int = keys[last]
		var lc: int = cells[last]
		keys.resize(last)
		cells.resize(last)
		if last > 0:
			var i: int = 0
			while true:
				var l: int = 2 * i + 1
				if l >= last:
					break
				var m: int = l
				if l + 1 < last and keys[l + 1] < keys[l]:
					m = l + 1
				if keys[m] >= lk:
					break
				keys[i] = keys[m]
				cells[i] = cells[m]
				i = m
			keys[i] = lk
			cells[i] = lc

		if closed[ci] == 1:
			continue  # an outdated entry: this cell was already expanded
		closed[ci] = 1
		expanded += 1
		if ci == gi:
			var c: int = gi
			while c != -1:
				path.append(Vector2i(c % w, c / w))
				c = came[c]
			path.reverse()
			return {"path": path, "expanded": expanded}

		var cx: int = ci % w
		var cy: int = ci / w
		var ng: int = g[ci] + 1
		for k: int in 4:
			var nx: int = cx + DX[k]
			var ny: int = cy + DY[k]
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var ni: int = ny * w + nx
			if solid[ni] == 1 or closed[ni] == 1:
				continue
			if g[ni] != -1 and g[ni] <= ng:
				continue
			g[ni] = ng
			came[ni] = ci
			var hn: int = absi(nx - goal.x) + absi(ny - goal.y)
			seq += 1
			var key: int = ((ng + hn) << F_SHIFT) | (hn << H_SHIFT) | seq
			# Push and sift up.
			var j: int = keys.size()
			keys.append(key)
			cells.append(ni)
			while j > 0:
				var p: int = (j - 1) / 2
				if keys[p] <= key:
					break
				keys[j] = keys[p]
				cells[j] = cells[p]
				j = p
			keys[j] = key
			cells[j] = ni
	return {"path": path, "expanded": expanded}


static func _open_cell(w: int, h: int, solid: PackedByteArray, c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h and solid[c.y * w + c.x] == 0
