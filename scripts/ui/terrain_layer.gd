## Draws the static terrain once; Godot caches the drawing, so it costs
## nothing per frame (presentation layer). Walkable ground is grass tiles
## with a painted colour wash, worn dirt roads between the two bases and to
## their nearest wood and gold, dirt clearings around each HQ, flowers and
## grass tufts. Blocked cells are forest, rock outcrops or ponds (chosen by a
## stable hash of 3 x 3 blocks; all equally impassable, so the rules do not
## change), and a forest border surrounds the map. Trees live on a child layer
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
## Ponds: a moving sparkle drawn over the water (D-48).
const WATER_SHADER: String = """
shader_type canvas_item;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
varying vec2 world;
void vertex() { world = VERTEX; }
void fragment() {
	vec2 p = world / 24.0;
	float a = noise(p + vec2(TIME * 0.35, TIME * 0.2));
	float b = noise(p * 1.7 - vec2(TIME * 0.25, -TIME * 0.3));
	float ripple = smoothstep(0.66, 0.78, a * 0.6 + b * 0.5) * (1.0 - smoothstep(0.78, 0.86, a * 0.6 + b * 0.5));
	float glint = smoothstep(0.86, 0.95, noise(p * 3.1 + vec2(TIME * 0.6, 0.0)));
	COLOR = vec4(vec3(0.85, 0.95, 1.0), COLOR.a * (ripple * 0.08 + glint * 0.22));
}
"""
## The ground (D-50): CC0 photo textures (ambientCG) blended per pixel when
## the ground is pre-drawn: fine grass, patches of thin grass and earth
## where a slow noise is high, bare earth on roads and base clearings
## (from a mask with noisy edges), then a gentle colour grade.
const GROUND_SHADER: String = """
shader_type canvas_item;
uniform sampler2D grass : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D patchy : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D dirt : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D worn : filter_linear;
uniform vec2 origin;
uniform vec2 size;
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
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
void fragment() {
	vec2 w = origin + UV * size;
	vec3 g = texture(grass, w / 160.0).rgb;
	vec3 g2 = texture(grass, w / 230.0 + vec2(0.37, 0.61)).rgb;
	g = mix(g, g2, 0.45);
	vec3 pt = texture(patchy, w / 210.0).rgb;
	vec3 d = texture(dirt, w / 150.0).rgb;
	float n = fbm(w / 300.0);
	vec3 col = mix(g, pt, smoothstep(0.56, 0.72, n) * 0.85);
	// Broad light and shade so the field is not flat.
	col *= 0.9 + 0.22 * fbm(w / 520.0 + vec2(7.1, 3.3));
	float m = texture(worn, UV).r;
	float edge = (fbm(w / 22.0) - 0.5) * 0.45;
	float dw = smoothstep(0.42, 0.58, m + edge);
	// A darker rim where the earth meets the grass.
	float rim = smoothstep(0.3, 0.45, m + edge) * (1.0 - dw);
	col = mix(col, col * 0.78, rim * 0.6);
	col = mix(col, d * vec3(1.02, 0.98, 0.92), dw);
	// Grade: a little less saturated, warmer, as in AoE II.
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, 1.0) * vec3(0.97, 1.03, 0.9);
	COLOR = vec4(col, 1.0);
}
"""
const FLOWERS: Array[Color] = [Color("fff6e0"), Color("ffd84a"), Color("ff9fc4"), Color("c7a6ff"), Color("8fd3ff")]

var map: MapGrid
var _trees: Node2D
var _water: Node2D
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
	if _water != null:
		_water.queue_free()
	_water = WaterDraw.new()
	_water.terrain = self
	var wsh: Shader = Shader.new()
	wsh.code = WATER_SHADER
	var wmat: ShaderMaterial = ShaderMaterial.new()
	wmat.shader = wsh
	_water.material = wmat
	add_child(_water)
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
	var ground: GroundDraw = GroundDraw.new()
	ground.rect = _board
	var gsh: Shader = Shader.new()
	gsh.code = GROUND_SHADER
	var gmat: ShaderMaterial = ShaderMaterial.new()
	gmat.shader = gsh
	gmat.set_shader_parameter("grass", load("res://assets/textures/grass.jpg"))
	gmat.set_shader_parameter("patchy", load("res://assets/textures/grass_patchy.jpg"))
	gmat.set_shader_parameter("dirt", load("res://assets/textures/dirt.jpg"))
	gmat.set_shader_parameter("worn", _worn_mask())
	gmat.set_shader_parameter("origin", _board.position)
	gmat.set_shader_parameter("size", _board.size)
	ground.material = gmat
	_bake.add_child(ground)
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
## Where the ground is bare earth: roads (stamped along their smooth curves)
## and base clearings, 4 pixels per cell over the whole board.
var _mask_tex: ImageTexture


func _worn_mask() -> ImageTexture:
	var k: float = 4.0 / C
	var w: int = int(_board.size.x * k)
	var h: int = int(_board.size.y * k)
	var img: Image = Image.create(w, h, false, Image.FORMAT_L8)
	var stamp: Callable = func(world: Vector2, radius: float) -> void:
		var c: Vector2 = (world - _board.position) * k
		var r: float = radius * k
		for y: int in range(maxi(0, int(c.y - r - 1)), mini(h, int(c.y + r + 2))):
			for x: int in range(maxi(0, int(c.x - r - 1)), mini(w, int(c.x + r + 2))):
				var dd: float = Vector2(x + 0.5, y + 0.5).distance_to(c)
				var v: float = clampf(1.0 - (dd - r) / 1.5, 0.0, 1.0)
				if v > img.get_pixel(x, y).r:
					img.set_pixel(x, y, Color(v, v, v))
	for r: Dictionary in _roads:
		var pts: PackedVector2Array = r.pts
		for i: int in range(0, pts.size(), 2):
			stamp.call(pts[i], r.w * 0.95)
	for f: String in ["player", "ai"]:
		if map.starts.has(f):
			var c2: Vector2 = (Vector2(map.starts[f]) + Vector2(1.5, 1.5)) * C
			for a: int in 16:
				var off: Vector2 = Vector2.from_angle(a * TAU / 16.0) * C * (1.1 + 0.4 * noise(a, int(c2.x), 90))
				stamp.call(c2 + off, C * 1.5)
			stamp.call(c2, C * 2.2)
	_mask_tex = ImageTexture.create_from_image(img)
	return _mask_tex


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
	# Grass and earth come from the ground shader (D-50).
	_draw_edges(ci)
	_draw_details(ci)
	_draw_water(ci)
	_draw_rocks(ci)


## Soft patches of dry, sunlit and lush grass, so the field is not one
## green: one value per 3 x 3 cells, smoothed by the linear filter into broad
## gradients, plus a finer layer for texture (D-48: stronger, larger).
func _draw_wash(ci: CanvasItem) -> void:
	var w: int = (map.width + BORDER * 2) / 3 + 2
	var h: int = (map.height + BORDER * 2) / 3 + 2
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y: int in h:
		for x: int in w:
			var n: float = noise(x / 2, y / 2, 70) * 0.55 + noise(x, y, 71) * 0.45
			var col: Color = Color(0, 0, 0, 0)
			if n > 0.58:
				col = Color(0.88, 0.8, 0.42, (n - 0.58) * 1.1)
			elif n < 0.4:
				col = Color(0.0, 0.18, 0.1, (0.4 - n) * 0.8)
			img.set_pixel(x, y, col)
	_wash_tex = ImageTexture.create_from_image(img)
	ci.draw_texture_rect(_wash_tex, Rect2(Vector2(-BORDER, -BORDER) * C, Vector2(w, h) * C * 3.0), false)


## Grass next to forest, rock or water is shaded (and forests get a dark
## undergrowth), so obstacles sit in the ground instead of on top of it.
func _draw_edges(ci: CanvasItem) -> void:
	for y: int in range(-BORDER, map.height + BORDER):
		for x: int in range(-BORDER, map.width + BORDER):
			var c: Vector2i = Vector2i(x, y)
			var centre: Vector2 = (Vector2(c) + Vector2(0.5, 0.5)) * C
			if is_forest(c):
				ci.draw_texture_rect(Art.disc(), Rect2(centre - Vector2(C, C) * 0.95, Vector2(C, C) * 1.9), false, Color(0.02, 0.16, 0.06, 0.55))
			elif is_rock(c):
				ci.draw_texture_rect(Art.disc(), Rect2(centre - Vector2(C, C) * 0.9, Vector2(C, C) * 1.8), false, Color(0.12, 0.14, 0.08, 0.28))


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
			if noise(x, y, 60) < 0.08:
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


## Ponds: each water cell is a rounded blob joined to its water neighbours
## by bars, so neighbouring cells merge into one body of water: a sandy
## shore, the water, then darker deep water where all four sides are water.
func _draw_water(ci: CanvasItem) -> void:
	# Natural water (D-50): a muddy bank, shallow green-blue, deep blue.
	# Kept inside the water cells, so units beside a pond are on dry land.
	water_shape(ci, 0.62, Color(0.42, 0.36, 0.24, 0.9), false)
	water_shape(ci, 0.55, Color("5d7f6f"), false)
	water_shape(ci, 0.48, Color("3d6878"), false)
	water_shape(ci, 0.34, Color("2c5064"), true)


## Draws the union of a disc of `r` cells per water cell and a bar of the
## same width to each water neighbour (`deep`: interior cells only).
func water_shape(ci: CanvasItem, r: float, col: Color, deep: bool) -> void:
	for y: int in map.height:
		for x: int in map.width:
			var c: Vector2i = Vector2i(x, y)
			if not is_water(c) or (deep and not _interior_water(c)):
				continue
			var centre: Vector2 = (Vector2(c) + Vector2(0.5, 0.5)) * C
			ci.draw_circle(centre, C * r, col, true, -1.0, true)
			# Where four water cells meet, fill the square between their centres.
			var quad: Array[Vector2i] = [c + Vector2i.RIGHT, c + Vector2i.DOWN, c + Vector2i.ONE]
			if quad.all(func(q: Vector2i) -> bool: return is_water(q) and (not deep or _interior_water(q))):
				ci.draw_rect(Rect2(centre, Vector2(C, C)), col)
			for d: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				var n: Vector2i = c + d
				if is_water(n) and (not deep or _interior_water(n)):
					var other: Vector2 = (Vector2(n) + Vector2(0.5, 0.5)) * C
					# Bars a little narrower than the discs: rounded corners
					# and a gently wavy shore.
					var half: Vector2 = Vector2(C * r, C * r) * 0.78
					ci.draw_rect(Rect2(centre - half, Vector2.ZERO).expand(other + half), col)


func _interior_water(c: Vector2i) -> bool:
	for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if not is_water(c + d):
			return false
	return true


## Blocked cells in rock groups get rocks with a soft shadow; forest cells get
## tree shadows here (the trees themselves sway on the child layer).
func _draw_rocks(ci: CanvasItem) -> void:
	for y: int in range(-BORDER, map.height + BORDER):
		for x: int in range(-BORDER, map.width + BORDER):
			var c: Vector2i = Vector2i(x, y)
			if not is_rock(c):
				continue
			var r: Rect2 = Rect2(Vector2(x, y) * C, Vector2(C, C))
			# Pre-rendered 3D rocks (D-49) with their own shadows, varied in
			# size, position and tone; pebbles scattered around.
			var name: String = ["rock_a", "rock_b", "rock_c", "rock_d"][int(noise(x, y, 3) * 4.0) % 4]
			var off: Vector2 = Vector2(noise(x, y, 12) - 0.5, noise(x, y, 13) - 0.5) * 8.0
			var tone: float = 0.9 + 0.14 * noise(x, y, 15)
			var sc: float = C * (0.8 + 0.3 * noise(x, y, 4))
			Art.draw_rendered(ci, name, r.get_center() + off + Vector2(0, 6), Color(tone, tone, tone), -INF, sc)
			for k: int in 2:
				if noise(x, y, 16 + k) < 0.5:
					var pp: Vector2 = r.get_center() + Vector2(noise(x, y, 18 + k) - 0.5, noise(x, y, 20 + k) - 0.5) * C * 1.6
					ci.draw_circle(pp, 1.8, Color(0.42, 0.4, 0.36, 0.85), true, -1.0, true)
					ci.draw_circle(pp - Vector2(0.5, 0.5), 0.9, Color(0.85, 0.83, 0.78, 0.8), true, -1.0, true)


## True on roads and base clearings (the minimap draws them as dirt).
func is_worn(c: Vector2i) -> bool:
	return _worn.has(c)


## What a blocked cell looks like, by a stable hash of its 3 x 3 block:
## forest (45 %), rock (35 %) or a pond (20 %). All are equally impassable.
func _kind(c: Vector2i) -> float:
	return noise(c.x / 3, c.y / 3, 41)


## Forest: a blocked cell in a forest group, or any cell of the outer border.
func is_forest(c: Vector2i) -> bool:
	if not map.in_bounds(c):
		return true
	return not map.is_walkable(c) and _kind(c) < 0.45


func is_rock(c: Vector2i) -> bool:
	return map.in_bounds(c) and not map.is_walkable(c) and _kind(c) >= 0.45 and _kind(c) < 0.8


func is_water(c: Vector2i) -> bool:
	return map.in_bounds(c) and not map.is_walkable(c) and _kind(c) >= 0.8


## The trees standing in a forest cell: up to three, stable per cell.
func trees_in(c: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var r: Vector2 = Vector2(c) * C
	# Pre-rendered 3D trees (D-49): mostly pines, some leafy trees.
	var n: int = 2
	for k: int in n:
		var pick: float = noise(c.x, c.y, 10 + k)
		var name: String = ["tree_a", "tree_b", "tree_c", "tree_d", "tree_e", "tree_a", "tree_d", "tree_f", "tree_g", "tree_h"][int(pick * 10.0) % 10]
		var size: float = C * (0.72 + noise(c.x, c.y, 20 + k) * 0.25)
		var foot: Vector2 = r + Vector2(0.2 + 0.6 * noise(c.x, c.y, 30 + k), 0.35 + 0.55 * float(k)) * C
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
					var shade: float = 1.05 + 0.15 * TerrainLayer.noise(x, y, 33)
					Art.draw_rendered(self, t.name, t.foot, Color(shade, shade, shade), -INF, t.size)


## The ponds' moving sparkle: one disc per water cell, coloured by the
## shader (D-48).
class WaterDraw extends Node2D:
	var terrain: TerrainLayer

	func _draw() -> void:
		var m: MapGrid = terrain.map
		if m == null:
			return
		terrain.water_shape(self, 0.47, Color.WHITE, false)


## One rectangle covering the board, coloured by the ground shader.
class GroundDraw extends Node2D:
	var rect: Rect2
	var _white: ImageTexture

	func _draw() -> void:
		if _white == null:
			var img: Image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
			img.fill(Color.WHITE)
			_white = ImageTexture.create_from_image(img)
		draw_texture_rect(_white, rect, false)


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
