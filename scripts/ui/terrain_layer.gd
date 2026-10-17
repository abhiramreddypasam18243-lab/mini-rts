## Draws the static terrain once; Godot caches the drawing, so it costs
## nothing per frame (presentation layer).
## Ground cells get a small deterministic tone variation and specks; blocked
## cells become rounded rocks that merge with their neighbours.
class_name TerrainLayer
extends Node2D

const C: float = Consts.PIXELS_PER_CELL

var map: MapGrid


func setup(p_map: MapGrid) -> void:
	map = p_map
	queue_redraw()


## A stable pseudo-random value in [0, 1) for a cell (drawing only).
static func noise(x: int, y: int, salt: int = 0) -> float:
	return float(SimRng.mix32(x * 73856093 ^ y * 19349663 ^ salt * 83492791) & 0xFFFF) / 65536.0


func _draw() -> void:
	if map == null:
		return
	var size: Vector2 = Vector2(map.width, map.height) * C
	# Soft frame around the board.
	draw_rect(Rect2(Vector2(-10, -10), size + Vector2(20, 20)), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(Vector2(-4, -4), size + Vector2(8, 8)), Palette.MAP_EDGE)
	for y: int in map.height:
		for x: int in map.width:
			var r: Rect2 = Rect2(Vector2(x, y) * C, Vector2(C, C))
			var n: float = noise(x, y)
			var base: Color = Palette.GROUND if (x + y) % 2 == 0 else Palette.GROUND_ALT
			draw_rect(r, base.lightened(n * 0.025))
			if map.is_walkable(Vector2i(x, y)):
				for k: int in 2:
					var p: Vector2 = r.position + Vector2(noise(x, y, 11 + k), noise(x, y, 23 + k)) * C
					draw_circle(p, 1.2, Palette.GROUND_SPECK)
	# Faint grid lines.
	for x: int in range(1, map.width):
		draw_line(Vector2(x * C, 0), Vector2(x * C, size.y), Palette.GRID, 1.0)
	for y: int in range(1, map.height):
		draw_line(Vector2(0, y * C), Vector2(size.x, y * C), Palette.GRID, 1.0)
	_draw_rocks()


## Rocks: rounded blocks that merge with blocked neighbours, drawn in four
## passes (shadow, dark rim, body, lit top edge and pebbles).
func _draw_rocks() -> void:
	var inset: float = 2.5
	var rim: StyleBoxFlat = _rounded(Palette.ROCK_DARK)
	var body: StyleBoxFlat = _rounded(Palette.ROCK)
	var shade: StyleBoxFlat = _rounded(Color(0, 0, 0, 0.32))
	for pass_i: int in 4:
		for y: int in map.height:
			for x: int in map.width:
				if map.is_walkable(Vector2i(x, y)):
					continue
				var r: Rect2 = Rect2(Vector2(x, y) * C, Vector2(C, C)).grow(-inset)
				var right: bool = x + 1 < map.width and not map.is_walkable(Vector2i(x + 1, y))
				var down: bool = y + 1 < map.height and not map.is_walkable(Vector2i(x, y + 1))
				match pass_i:
					0:
						draw_style_box(shade, Rect2(r.position + Vector2(1, 5), r.size))
						if right:
							draw_rect(Rect2(r.end.x - 4, r.position.y + 7, inset * 2 + 8, r.size.y - 6), Color(0, 0, 0, 0.32))
						if down:
							draw_rect(Rect2(r.position.x + 5, r.end.y, r.size.x - 8, inset * 2 + 4), Color(0, 0, 0, 0.32))
					1:
						draw_style_box(rim, r)
						if right:
							draw_rect(Rect2(r.end.x - 4, r.position.y, inset * 2 + 8, r.size.y), Palette.ROCK_DARK)
						if down:
							draw_rect(Rect2(r.position.x, r.end.y - 4, r.size.x, inset * 2 + 8), Palette.ROCK_DARK)
					2:
						var b: Rect2 = r.grow_individual(-1.5, -1.5, -1.5, -3.0)
						draw_style_box(body, b)
						if right:
							draw_rect(Rect2(b.end.x - 4, b.position.y, inset * 2 + 8, b.size.y), Palette.ROCK)
						if down:
							draw_rect(Rect2(b.position.x, b.end.y - 4, b.size.x, inset * 2 + 9.5), Palette.ROCK)
					3:
						if y == 0 or map.is_walkable(Vector2i(x, y - 1)):
							draw_line(r.position + Vector2(5, 2.5), Vector2(r.end.x - 5, r.position.y + 2.5), Palette.ROCK_LIGHT, 2.0, true)
						if noise(x, y, 5) > 0.5:
							var p: Vector2 = r.position + Vector2(noise(x, y, 7), noise(x, y, 9)) * (r.size - Vector2(12, 12)) + Vector2(6, 7)
							draw_circle(p, 2.4, Palette.ROCK_LIGHT.darkened(0.3), true, -1.0, true)
							draw_circle(p + Vector2(4, 3), 1.5, Palette.ROCK_LIGHT.darkened(0.4), true, -1.0, true)


func _rounded(col: Color) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(7)
	s.anti_aliasing = true
	return s
