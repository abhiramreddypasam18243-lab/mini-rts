## Unit spacing (decision D-42, replacing the "units share cells" part of
## D-04). Units may still pass through each other while walking (no traffic
## jams or deadlocks), but they do not end up standing on the same cell:
##   1. Formation: a group sent to one cell is given distinct cells: the unit
##      nearest the goal stands on it, and the others fill the free cells in
##      rings around it, inner rings first, each taking the free cell of the
##      ring nearest to itself.
##   2. Melee slots: a melee soldier attacking a unit walks to a free cell
##      next to the target (nearest to itself), not onto the target's cell.
##   3. Step aside: every INTERVAL ticks, units standing still on a cell
##      that another unit (lower id) also stands on step to a free cell next
##      to it; an attacking unit only steps where its target stays in range.
## Workers that are gathering or building are left alone, so the economy's
## timings are unchanged. Everything is integer and in id order.
class_name Spacing
extends RefCounted

const RINGS: int = 4
const INTERVAL: int = 5
## Step-aside order: the four straight neighbours, then the diagonals.
const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1),
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1),
]


## The cell each unit holds: the end of its path if it is walking, else the
## cell it stands on. Units in `except` are left out. Cell -> lowest unit id.
static func held_cells(sim: Simulation, except: Dictionary = {}) -> Dictionary:
	var held: Dictionary = {}
	for id: int in sim.entities:
		var e: Entity = sim.entities[id]
		if not e.is_unit() or except.has(id):
			continue
		var c: Vector2i = e.path[e.path.size() - 1] if e.path_i < e.path.size() else e.unit_cell()
		if not held.has(c):
			held[c] = id
	return held


static func is_free(sim: Simulation, c: Vector2i, held: Dictionary) -> bool:
	return sim.map.in_bounds(c) and not sim.is_solid(c) and not held.has(c)


## The cells at Chebyshev distance `r` from `centre`, in row-major order.
static func ring(centre: Vector2i, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			if maxi(absi(dx), absi(dy)) == r:
				out.append(centre + Vector2i(dx, dy))
	return out


## Rule 1: one destination per unit for a group move to `goal`. Units
## without a free slot within RINGS rings keep the goal itself.
static func formation(sim: Simulation, units: Array[Entity], goal: Vector2i) -> Dictionary:
	var out: Dictionary = {}
	if not sim.map.in_bounds(goal) or sim.is_solid(goal):
		# A blocked or outside goal stays as it is, so the move reports
		# no_path exactly as before (AC-28).
		for e: Entity in units:
			out[e.id] = goal
		return out
	var group: Dictionary = {}
	for e: Entity in units:
		group[e.id] = true
	var held: Dictionary = held_cells(sim, group)
	# Free cells ring by ring (ring 0 is the goal), until there are enough.
	var rings: Array = []
	var total: int = 0
	for r: int in RINGS + 1:
		var free: Array[Vector2i] = []
		for c: Vector2i in ring(goal, r):
			if is_free(sim, c, held):
				free.append(c)
		rings.append(free)
		total += free.size()
		if total >= units.size():
			break
	# The unit nearest the goal goes first; each unit takes, in the innermost
	# ring with a cell left, the cell nearest to itself (ties: ring order).
	var order: Array[Entity] = units.duplicate()
	order.sort_custom(func(x: Entity, y: Entity) -> bool:
		var dx: int = _dist_sq(x.unit_cell(), goal)
		var dy: int = _dist_sq(y.unit_cell(), goal)
		return dx < dy or (dx == dy and x.id < y.id))
	for e: Entity in order:
		var picked: bool = false
		for free: Array in rings:
			if free.is_empty():
				continue
			var best: int = 0
			for i: int in range(1, free.size()):
				if _dist_sq(e.unit_cell(), free[i]) < _dist_sq(e.unit_cell(), free[best]):
					best = i
			out[e.id] = free[best]
			free.remove_at(best)
			picked = true
			break
		if not picked:
			out[e.id] = goal
	return out


## Rule 2: the free cell next to the unit target `t` nearest to `e`, or the
## target's own cell if every neighbour is taken.
static func melee_slot(sim: Simulation, e: Entity, t: Entity) -> Vector2i:
	var tc: Vector2i = t.unit_cell()
	var held: Dictionary = held_cells(sim, {e.id: true})
	var best: Vector2i = tc
	var best_d: int = -1
	for n: Vector2i in NEIGHBOURS:
		var c: Vector2i = tc + n
		if not is_free(sim, c, held):
			continue
		var d: int = _dist_sq(e.unit_cell(), c)
		if best_d < 0 or d < best_d:
			best = c
			best_d = d
	return best


## Rule 3: units standing still on a shared cell step aside (every
## INTERVAL ticks, called by Simulation.step()).
static func step_aside(sim: Simulation) -> void:
	var held: Dictionary = held_cells(sim)
	var standing: Dictionary = {}
	for id: int in sim.entities:
		var e: Entity = sim.entities[id]
		if not e.is_unit() or e.path_i < e.path.size():
			continue
		if not (e.order_type == "idle" or e.order_type == "attack"):
			continue
		var c: Vector2i = e.unit_cell()
		if e.pos != MapGrid.cell_center(c):
			continue  # stopped between two cells: leave it
		if not standing.has(c):
			standing[c] = id
			continue
		# Another unit already stands here: find a free neighbour.
		var t: Entity = sim.entity(e.order_target) if e.order_type == "attack" else null
		for n: Vector2i in NEIGHBOURS:
			var to: Vector2i = c + n
			if not is_free(sim, to, held):
				continue
			if t != null and not sim.in_range_at(e, t, MapGrid.cell_center(to)):
				continue
			var r: Dictionary = Pathfinder.find_path(sim.map.width, sim.map.height, sim.solid, c, to)
			if (r.path as Array).is_empty():
				continue
			e.path = r.path
			e.path_i = Movement.start_index(e)
			if e.order_type == "idle":
				e.order_type = "move"
				e.order_cell = to
			else:
				e.stepping = true
			held[to] = id
			break


static func _dist_sq(a: Vector2i, b: Vector2i) -> int:
	var d: Vector2i = a - b
	return d.x * d.x + d.y * d.y
