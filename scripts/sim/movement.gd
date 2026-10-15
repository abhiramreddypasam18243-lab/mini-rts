## Moves a unit along its path (SPEC 4; AC-25).
## A unit walks from cell centre to cell centre, `speed` milli-cells per tick.
## Leftover distance carries over at a corner, so a unit covers exactly
## speed x ticks along the path: 15 cells at 150 per tick take 100 ticks.
## Between two centres a unit is on the straight segment joining two adjacent
## walkable cells, so it is never inside a blocked cell.
class_name Movement
extends RefCounted


## Advances the unit by one tick. Returns true when it has reached the end.
static func advance(unit: Entity, speed: int) -> bool:
	var budget: int = speed
	while budget > 0 and unit.path_i < unit.path.size():
		var target: Vector2i = MapGrid.cell_center(unit.path[unit.path_i])
		var dx: int = target.x - unit.pos.x
		var dy: int = target.y - unit.pos.y
		var dist: int = absi(dx) + absi(dy)
		if dist <= budget:
			unit.pos = target
			budget -= dist
			unit.path_i += 1
		elif dx != 0:
			# Move along x first; a unit is only ever off-centre along one axis.
			var step: int = mini(budget, absi(dx))
			unit.pos.x += step * signi(dx)
			budget -= step
		else:
			unit.pos.y += budget * signi(dy)
			budget = 0
	return unit.path_i >= unit.path.size()


## Index of the first waypoint to walk to on a fresh path. path[0] is the
## unit's own cell; if the unit already stands between path[0] and path[1]
## (it was interrupted mid-step), it heads straight for path[1].
static func start_index(unit: Entity) -> int:
	if unit.path.size() < 2:
		return 0
	var a: Vector2i = MapGrid.cell_center(unit.path[0])
	var b: Vector2i = MapGrid.cell_center(unit.path[1])
	var p: Vector2i = unit.pos
	var on_x: bool = a.y == b.y and p.y == a.y and mini(a.x, b.x) <= p.x and p.x <= maxi(a.x, b.x)
	var on_y: bool = a.x == b.x and p.x == a.x and mini(a.y, b.y) <= p.y and p.y <= maxi(a.y, b.y)
	return 1 if (on_x or on_y) and p != a else 0


## True if any cell the unit has still to enter is now solid.
static func path_blocked(unit: Entity, solid: PackedByteArray, width: int) -> bool:
	for i: int in range(unit.path_i, unit.path.size()):
		var c: Vector2i = unit.path[i]
		if solid[c.y * width + c.x] == 1:
			return true
	return false
