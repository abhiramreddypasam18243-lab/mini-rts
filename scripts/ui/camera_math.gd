## Camera rules (SPEC 9; AC-76): pan with keys or screen edges, never leave
## the map. Pure functions so they can be tested headless.
class_name CameraMath
extends RefCounted

## Mouse within this many pixels of a screen edge pans the camera.
const EDGE: float = 14.0
const SPEED: float = 900.0


## Clamps the camera centre so the view stays on the map. A map smaller than
## the view (in one direction) is centred in that direction.
static func clamp_center(c: Vector2, view: Vector2, map_size: Vector2) -> Vector2:
	var out: Vector2 = c
	for axis: int in 2:
		if map_size[axis] <= view[axis]:
			out[axis] = map_size[axis] / 2.0
		else:
			out[axis] = clampf(c[axis], view[axis] / 2.0, map_size[axis] - view[axis] / 2.0)
	return out


## -1, 0 or 1 per axis when the mouse is at a screen edge.
static func edge_direction(mouse: Vector2, view: Vector2) -> Vector2:
	var d: Vector2 = Vector2.ZERO
	if mouse.x <= EDGE:
		d.x = -1
	elif mouse.x >= view.x - EDGE:
		d.x = 1
	if mouse.y <= EDGE:
		d.y = -1
	elif mouse.y >= view.y - EDGE:
		d.y = 1
	return d
