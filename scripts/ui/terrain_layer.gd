## Draws the static terrain once; Godot caches the drawing, so it costs
## nothing per frame (presentation layer). Walkable ground is grass tiles
## with a painted colour wash, worn dirt roads between the two bases and to
## their nearest wood and gold, dirt clearings around each HQ, flowers and
## grass tufts. Blocked cells are rock outcrops or forest (chosen by a stable
## hash), and a forest border surrounds the map. Trees live on a child layer
## whose shader sways them in the wind; `make_clouds()` gives a layer of
## drifting cloud shadows. Kenney CC0 sprites (decisions D-38, D-39).
class_name TerrainLayer
extends Node2D

const C: float = Consts.PIXELS_PER_CELL
## Forest drawn this many cells beyond each map edge.
const BORDER: int = 4
const SWAY_SHADER: String = """
shader_type canvas_item;
void vertex() {
	float top = 1.0 - UV.y;
	VERTEX.x += sin(TIME * 1.6 + VERTEX.x * 0.045 + VERTEX.y * 0.031) * 1.9 * top * top;
}
"""
const CLOUD_SHADER: String = """
shader_type canvas_item;
uniform vec2 size = vec2(1536.0, 1536.0);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
void fragment() {
	vec2 p = UV * size / 300.0 + vec2(TIME * 0.03, TIME * 0.011);
	float c = smoothstep(0.5, 0.74, fbm(p));
	vec4 sun = vec4(1.0, 0.93, 0.7, 0.05);
	vec4 shade = vec4(0.04, 0.07, 0.12, 0.17);
	COLOR = mix(sun, shade, c);
}
"""
const FLOWERS: Array[Color] = [Color("fff6e0"), Color("ffd84a"), Color("ff9fc4"), Color("c7a6ff"), Color("8fd3ff")]

var map: MapGrid
var _trees: Node2D
## The ground (grass, roads, flowers, rocks) is drawn once into this
## viewport and then shown as one texture, so it costs one quad per frame.
var _bake: SubViewport
var _board: Rect2
## Trees are split into chunks of this many cells, so Godot skips the ones
## off screen.
const CHUNK: int = 8
## Cells covered by roads or clearings (no flowers or details there).
var _worn: Dictionary = {}
var _roads: Array[Dictionary] = []
## Kept as a member: a texture freed after _draw() would leave the cached
## drawing pointing at nothing (it renders white).
var _wash_tex: ImageTexture


func setup(p_map: MapGrid) -> void:
	map = p_map
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_plan_roads()
	_board = Rect2(Vector2(-BORDER, -BORDER) * C, (Vector2(map.width, map.height) + Vector2(BORDER, BORDER) * 2.0) * C)
	_bake_ground()
	if _trees != null:
		_trees.queue_free()
	_trees = Node2D.new()
	var sh: Shader = Shader.new()
	sh.code = SWAY_SHADER
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = sh
	_trees.material = mat
	add_child(_trees)
	for cy: int in range(-BORDER, map.height + BORDER, CHUNK):
		for cx: int in range(-BORDER, map.width + BORDER, CHUNK):
			var chunk: TreeDraw = TreeDraw.new()
			chunk.terrain = self
			chunk.cells = Rect2i(cx, cy, CHUNK, CHUNK)
			chunk.use_parent_material = true
			_trees.add_child(chunk)
	queue_redraw()


## Renders the ground once, at the game's zoom (capped at 4096 px), into a
## viewport that keeps the picture.
func _bake_ground() -> void:
	if _bake != null:
		_bake.queue_free()
	# Phones (D-46): half the memory, at the cost of slightly softer grass.
	var k: float = minf(1.0 if TouchInput.enabled() else Game.ZOOM, 4096.0 / maxf(_board.size.x, _board.size.y))
	_bake = SubViewport.new()
	_bake.size = Vector2i(ceili(_board.size.x * k), ceili(_board.size.y * k))
	_bake.transparent_bg = false
	_bake.disable_3d = true
	_bake.render_target_update_mode = SubViewport.UPDATE_ONCE
	var base: BaseDraw = BaseDraw.new()
	base.terrain = self
	base.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_bake.add_child(base)
	add_child(_bake)
	# The transform can be set only once the viewport is in the tree.
	_bake.canvas_transform = Transform2D(0.0, Vector2(k, k), 0.0, -_board.position * k)
	_free_after_bake.call_deferred(base)


## Once the ground has been drawn into the viewport, its thousands of drawing
## commands (roads, flowers) are not needed any more: free them (D-46).
func _free_after_bake(base: Node) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if is_instance_valid(base):
		base.queue_free()


func _draw() -> void:
	if _bake != null:
		draw_texture_rect(_bake.get_texture(), _board, false)


## A layer of drifting cloud shadows over the whole board (add it above the units).
func make_clouds() -> Node2D:
	var n: CloudDraw = CloudDraw.new()
	n.rect = Rect2(Vector2(-BORDER, -BORDER) * C, (Vector2(map.width, map.height) + Vector2(BORDER, BORDER) * 2.0) * C)
	var sh: Shader = Shader.new()
	sh.code = CLOUD_SHADER
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("size", n.rect.size)
	n.material = mat
	return n


## A stable pseudo-random value in [0, 1) for a cell (drawing only).
static func noise(x: int, y: int, salt: int = 0) -> float:
	return float(SimRng.mix32(x * 73856093 ^ y * 19349663 ^ salt * 83492791) & 0xFFFF) / 65536.0


func _walk(c: Vector2i) -> bool:
	return map.in_bounds(c) and map.is_walkable(c)


func _draw_base(ci: CanvasItem) -> void:
	if map == null:
		return
	var grass_a: Texture2D = Art.tex("grass_a")
	var grass_b: Texture2D = Art.tex("grass_b")
	for y: int in range(-BORDER, map.height + BORDER):
		for x: int in range(-BORDER, map.width + BORDER):
			ci.draw_texture_rect(grass_a if noise(x, y) < 0.6 else grass_b, Rect2(Vector2(x, y) * C, Vector2(C, C)), false, Color(0.9, 0.94, 0.86))
	_draw_wash(ci)
	_draw_worn_ground(ci)
	_draw_details(ci)
	_draw_rocks(ci)


## Soft patches of dry, sunlit and lush grass, so the field is not one green.
func _draw_wash(ci: CanvasItem) -> void:
	var w: int = (map.width + BORDER * 2) / 2 + 1
	var h: int = (map.height + BORDER * 2) / 2 + 1
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y: int in h:
		for x: int in w:
			var n: float = (noise(x / 3, y / 3, 70) * 0.6 + noise(x, y, 71) * 0.4)
			var col: Color = Color(0, 0, 0, 0)
			if n > 0.62:
				col = Color(0.92, 0.86, 0.45, (n - 0.62) * 0.9)
			elif n < 0.34:
				col = Color(0.02, 0.24, 0.12, (0.34 - n) * 0.9)
			img.set_pixel(x, y, col)
	_wash_tex = ImageTexture.create_from_image(img)
	ci.draw_texture_rect(_wash_tex, Rect2(Vector2(-BORDER, -BORDER) * C, Vector2(w, h) * C * 2.0), false)


# --- roads and clearings -------------------------------------------------------

## Breadth-first search over walkable terrain from `from`; returns a parent map.
func _bfs(from: Vector2i) -> Dictionary:
	var parent: Dictionary = {from: from}
	var queue: Array[Vector2i] = [from]
	var i: int = 0
	while i < queue.size():
		var c: Vector2i = queue[i]
		i += 1
		for d: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var n: Vector2i = c + d
			if not parent.has(n) and _walk(n):
				parent[n] = c
				queue.append(n)
	return parent


func _path(parent: Dictionary, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not parent.has(to):
		return out
	var c: Vector2i = to
	while parent[c] != c:
		out.append(c)
		c = parent[c]
	out.append(c)
	out.reverse()
	return out


func _plan_roads() -> void:
	_roads.clear()
	_worn.clear()
	var hqs: Array[Vector2i] = []
	for f: String in ["player", "ai"]:
		if map.starts.has(f):
			hqs.append(map.starts[f] + Vector2i(1, 1))
	for i: int in hqs.size():
		var parent: Dictionary = _bfs(hqs[i])
		if i == 0 and hqs.size() > 1:
			_add_road(_path(parent, hqs[1]), 11.0)
		for kind: String in ["gold", "wood"]:
			var best: Array[Vector2i] = []
			for n: Dictionary in map.nodes:
				if n.type != kind:
					continue
				var p: Array[Vector2i] = _path(parent, n.cell)
				if not p.is_empty() and (best.is_empty() or p.size() < best.size()):
					best = p
			if best.size() > 4:
				best.resize(best.size() - 1)
				_add_road(best, 7.0)
	for i: int in hqs.size():
		for dy: int in range(-3, 4):
			for dx: int in range(-3, 4):
				_worn[hqs[i] + Vector2i(dx, dy)] = true


## Smooths a cell path into a curve (Chaikin) and records it as a road.
func _add_road(cells: Array[Vector2i], width: float) -> void:
	if cells.size() < 2:
		return
	var pts: PackedVector2Array = PackedVector2Array()
	for c: Vector2i in cells:
		pts.append((Vector2(c) + Vector2(0.5, 0.5)) * C)
		_worn[c] = true
	for it: int in 3:
		var sm: PackedVector2Array = PackedVector2Array([pts[0]])
		for k: int in pts.size() - 1:
			sm.append(pts[k].lerp(pts[k + 1], 0.25))
			sm.append(pts[k].lerp(pts[k + 1], 0.75))
		sm.append(pts[pts.size() - 1])
		pts = sm
	_roads.append({"pts": pts, "w": width})


func _stamp_along(ci: CanvasItem, pts: PackedVector2Array, radius: float, col: Color, salt: int) -> void:
	var acc: float = 0.0
	for k: int in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var seg: float = a.distance_to(b)
		while acc < seg:
			var p: Vector2 = a.lerp(b, acc / seg)
			var wob: float = 0.82 + 0.36 * noise(int(p.x / 6.0), int(p.y / 6.0), salt)
			ci.draw_circle(p, radius * wob, col, true, -1.0, true)
			acc += 3.0
		acc -= seg


func _draw_worn_ground(ci: CanvasItem) -> void:
	var edge: Color = Color(0.36, 0.25, 0.13, 0.32)
	var body: Color = Color(0.71, 0.56, 0.35, 0.92)
	var light: Color = Color(0.82, 0.69, 0.47, 0.55)
	# Clearings around each HQ: overlapping dirt blobs.
	var centres: Array[Vector2] = []
	for f: String in ["player", "ai"]:
		if map.starts.has(f):
			centres.append((Vector2(map.starts[f]) + Vector2(1.5, 1.5)) * C)
	for pass_i: int in 3:
		for c: Vector2 in centres:
			for k: int in 26:
				var ang: float = k * TAU / 26.0
				var rr: float = C * (2.3 + 0.7 * noise(k, int(c.x), 90))
				var p: Vector2 = c + Vector2.from_angle(ang) * rr * 0.55
				var rad: float = rr * 0.62
				match pass_i:
					0:
						ci.draw_circle(p, rad + 4.0, edge, true, -1.0, true)
					1:
						ci.draw_circle(p, rad, body, true, -1.0, true)
					2:
						ci.draw_circle(c + (p - c) * 0.6, rad * 0.45, light, true, -1.0, true)
		for r: Dictionary in _roads:
			match pass_i:
				0:
					_stamp_along(ci, r.pts, r.w + 4.0, edge, 91)
				1:
					_stamp_along(ci, r.pts, r.w, body, 92)
				2:
					_stamp_along(ci, r.pts, r.w * 0.42, light, 93)
	# A few pebbles on the dirt.
	for c: Vector2i in _worn:
		if _walk(c) and noise(c.x, c.y, 94) < 0.18:
			var p2: Vector2 = (Vector2(c) + Vector2(noise(c.x, c.y, 95), noise(c.x, c.y, 96))) * C
			ci.draw_circle(p2, 1.6, Color(0.45, 0.36, 0.25, 0.8), true, -1.0, true)
			ci.draw_circle(p2 + Vector2(-0.4, -0.4), 0.8, Color(0.9, 0.82, 0.66, 0.8), true, -1.0, true)


# --- details on the grass ----------------------------------------------------------

func _draw_details(ci: CanvasItem) -> void:
	for y: int in range(-BORDER, map.height + BORDER):
		for x: int in range(-BORDER, map.width + BORDER):
			var c: Vector2i = Vector2i(x, y)
			if (map.in_bounds(c) and not map.is_walkable(c)) or _worn.has(c):
				continue
			var base: Vector2 = Vector2(x, y) * C
			# Grass tufts.
			if noise(x, y, 60) < 0.32:
				var p: Vector2 = base + Vector2(noise(x, y, 61), noise(x, y, 62)) * C
				var col: Color = Color(0.05, 0.36, 0.14, 0.55)
				for b: int in 3:
					var bx: float = p.x + (b - 1) * 2.5
					ci.draw_line(Vector2(bx, p.y), Vector2(bx + (b - 1) * 1.8, p.y - 5.0 - b % 2 * 2.0), col, 1.4, true)
			# Flower clusters.
			if noise(x / 3, y / 3, 50) < 0.1 and noise(x, y, 51) < 0.45:
				var fc: Color = FLOWERS[int(noise(x / 2, y / 2, 52) * FLOWERS.size()) % FLOWERS.size()]
				for k: int in 2 + int(noise(x, y, 53) * 2.0):
					var fp: Vector2 = base + Vector2(noise(x, y, 54 + k), noise(x, y, 64 + k)) * C
					ci.draw_line(fp, fp + Vector2(0, 4), Color(0.1, 0.4, 0.15, 0.7), 1.0, true)
					for pi: int in 5:
						ci.draw_circle(fp + Vector2.from_angle(pi * TAU / 5.0) * 1.7, 1.35, fc, true, -1.0, true)
					ci.draw_circle(fp, 1.0, Color("ffc23a") if fc != Color("ffd84a") else Color("ff8a3a"), true, -1.0, true)
			# Small sprites: pebbles, bushes, stumps.
			if map.in_bounds(c) and noise(x, y, 5) < 0.03:
				var name: String = ["pebble", "bush", "stump"][int(noise(x, y, 6) * 3.0) % 3]
				var sp: Vector2 = (Vector2(x, y) + Vector2(noise(x, y, 7) * 0.5 + 0.25, noise(x, y, 8) * 0.5 + 0.25)) * C
				ci.draw_texture_rect(Art.tex(name), Rect2(sp - Vector2(10, 10), Vector2(20, 20)), false, Color(1, 1, 1, 0.92))


## Blocked cells in rock groups get rocks with a soft shadow; forest cells get
## tree shadows here (the trees themselves sway on the child layer).
func _draw_rocks(ci: CanvasItem) -> void:
	for y: int in range(-BORDER, map.height + BORDER):
		for x: int in range(-BORDER, map.width + BORDER):
			var c: Vector2i = Vector2i(x, y)
			if not is_forest(c) and not is_rock(c):
				continue
			var r: Rect2 = Rect2(Vector2(x, y) * C, Vector2(C, C))
			if is_forest(c):
				for t: Dictionary in trees_in(c):
					ci.draw_set_transform(t.foot + Vector2(3, 1), 0.0, Vector2(1.0, 0.42))
					ci.draw_circle(Vector2.ZERO, t.size * 0.3, Color(0.0, 0.08, 0.02, 0.22), true, -1.0, true)
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				ci.draw_set_transform(r.get_center() + Vector2(2, 9), 0.0, Vector2(1.0, 0.45))
				ci.draw_circle(Vector2.ZERO, C * 0.6, Color(0, 0.05, 0, 0.25), true, -1.0, true)
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				var name: String = ["rock_cluster", "rock_pair", "rock_big"][int(noise(x, y, 3) * 3.0) % 3]
				var s: float = C * 1.6
				ci.draw_texture_rect(Art.tex(name), Rect2(r.get_center() - Vector2(s, s) * 0.5 - Vector2(0, 3), Vector2(s, s)), false)


## True on roads and base clearings (the minimap draws them as dirt).
func is_worn(c: Vector2i) -> bool:
	return _worn.has(c)


## Forest: a blocked cell in a forest group, or any cell of the outer border.
func is_forest(c: Vector2i) -> bool:
	if not map.in_bounds(c):
		return true
	return not map.is_walkable(c) and noise(c.x / 3, c.y / 3, 41) < 0.5


func is_rock(c: Vector2i) -> bool:
	return map.in_bounds(c) and not map.is_walkable(c) and noise(c.x / 3, c.y / 3, 41) >= 0.5


## The trees standing in a forest cell: up to three, stable per cell.
func trees_in(c: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var r: Vector2 = Vector2(c) * C
	var n: int = 3 if map.in_bounds(c) else 2 + int(noise(c.x, c.y, 9) < 0.5)
	for k: int in n:
		var name: String = ["tree_pine", "tree_tall", "tree_pine_small"][int(noise(c.x, c.y, 10 + k) * 3.0) % 3]
		var size: float = C * (1.05 + noise(c.x, c.y, 20 + k) * 0.4)
		var foot: Vector2 = r + Vector2(0.2 + 0.6 * noise(c.x, c.y, 30 + k), 0.45 + 0.45 * float(k) / 2.0) * C
		out.append({"name": name, "size": size, "foot": foot})
	return out


## Draws the ground into the bake viewport.
class BaseDraw extends Node2D:
	var terrain: TerrainLayer

	func _draw() -> void:
		terrain._draw_base(self)


## Draws the trees of one chunk (row by row, so lower trees overlap the ones
## behind; chunks are drawn in row order too).
class TreeDraw extends Node2D:
	var terrain: TerrainLayer
	var cells: Rect2i

	func _draw() -> void:
		var m: MapGrid = terrain.map
		if m == null:
			return
		for y: int in range(cells.position.y, mini(cells.end.y, m.height + TerrainLayer.BORDER)):
			for x: int in range(cells.position.x, mini(cells.end.x, m.width + TerrainLayer.BORDER)):
				var c: Vector2i = Vector2i(x, y)
				if not terrain.is_forest(c):
					continue
				for t: Dictionary in terrain.trees_in(c):
					var s: float = t.size
					var shade: float = 0.86 + 0.14 * TerrainLayer.noise(x, y, 33)
					draw_texture_rect(Art.tex(t.name), Rect2(t.foot - Vector2(s * 0.5, s * 0.82), Vector2(s, s)), false, Color(shade, shade, shade))


## One rectangle whose shader draws moving cloud shadows.
class CloudDraw extends Node2D:
	var rect: Rect2
	var _white: ImageTexture

	func _draw() -> void:
		if _white == null:
			var img: Image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
			img.fill(Color.WHITE)
			_white = ImageTexture.create_from_image(img)
		draw_texture_rect(_white, rect, false)
