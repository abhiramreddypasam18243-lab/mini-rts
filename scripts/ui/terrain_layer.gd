## Draws the static terrain once; Godot caches the drawing, so it costs
## nothing per frame (presentation layer). Walkable ground is grass tiles
## with a few scattered details; blocked cells are rock outcrops or dense
## forest (chosen per cell by a stable hash), from Kenney's CC0 Medieval RTS
## pack (decision D-38).
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
	# A wooden frame around the board.
	draw_rect(Rect2(Vector2(-14, -14), size + Vector2(28, 28)), Palette.MAP_EDGE_DARK)
	draw_rect(Rect2(Vector2(-9, -9), size + Vector2(18, 18)), Palette.MAP_EDGE)
	draw_rect(Rect2(Vector2(-3, -3), size + Vector2(6, 6)), Palette.MAP_EDGE_DARK)
	var grass_a: Texture2D = Art.tex("grass_a")
	var grass_b: Texture2D = Art.tex("grass_b")
	for y: int in map.height:
		for x: int in map.width:
			var r: Rect2 = Rect2(Vector2(x, y) * C, Vector2(C, C))
			draw_texture_rect(grass_a if noise(x, y) < 0.6 else grass_b, r, false)
	# Scattered details on open ground.
	for y: int in map.height:
		for x: int in map.width:
			if not map.is_walkable(Vector2i(x, y)):
				continue
			if noise(x, y, 5) > 0.035:
				continue
			var name: String = ["pebble", "bush", "stump"][int(noise(x, y, 6) * 3.0) % 3]
			var p: Vector2 = (Vector2(x, y) + Vector2(noise(x, y, 7) * 0.5 + 0.25, noise(x, y, 8) * 0.5 + 0.25)) * C
			draw_texture_rect(Art.tex(name), Rect2(p - Vector2(10, 10), Vector2(20, 20)), false, Color(1, 1, 1, 0.9))
	_draw_blocked()


## Blocked cells: neighbouring cells are mostly the same kind (forest or
## rock), picked by a hash of their 3 x 3 block, so they read as woods and
## outcrops rather than a checkerboard. Forests are individual tree sprites
## standing on the grass, rows drawn top to bottom so lower trees overlap.
func _draw_blocked() -> void:
	for y: int in map.height:
		for x: int in map.width:
			if map.is_walkable(Vector2i(x, y)):
				continue
			var r: Rect2 = Rect2(Vector2(x, y) * C, Vector2(C, C))
			if noise(x / 3, y / 3, 41) < 0.5:
				for k: int in 3:
					var name: String = ["tree_pine", "tree_tall", "tree_pine_small"][int(noise(x, y, 10 + k) * 3.0) % 3]
					var sz: float = C * (1.05 + noise(x, y, 20 + k) * 0.35)
					var foot: Vector2 = r.position + Vector2(0.2 + 0.6 * noise(x, y, 30 + k), 0.45 + 0.45 * float(k) / 2.0) * C
					draw_texture_rect(Art.tex(name), Rect2(foot - Vector2(sz * 0.5, sz * 0.82), Vector2(sz, sz)), false)
			else:
				var name2: String = ["rock_cluster", "rock_pair", "rock_big"][int(noise(x, y, 3) * 3.0) % 3]
				var s2: float = C * 1.6
				draw_texture_rect(Art.tex(name2), Rect2(r.get_center() - Vector2(s2, s2) * 0.5 - Vector2(0, 3), Vector2(s2, s2)), false)
