## Fog of war on screen (presentation layer). One texture pixel per map
## cell holds two eased amounts: red = "not visible now" (explored ground is
## shown dimmed and desaturated, like a memory) and green = "never seen"
## (covered by drifting dark clouds with wispy edges). A shader reads the
## picture underneath (the screen texture), so the fog recolours the ground
## instead of just darkening it. The layer covers the forest border too,
## which takes the fog of the nearest map edge.
class_name FogLayer
extends Node2D

const EASE: float = 7.0
const SHADER: String = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 map_cells = vec2(48.0, 48.0);
uniform float border = 4.0;
uniform float time_offset = 0.0;

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
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.02; a *= 0.5; }
	return v;
}
void fragment() {
	vec2 cell = UV * (map_cells + 2.0 * border) - border;
	vec2 texel = 1.0 / map_cells;
	vec2 muv = clamp(cell / map_cells, texel * 0.5, 1.0 - texel * 0.5);
	// Four bilinear taps half a cell apart: a cheap blur that rounds off the
	// cell-by-cell staircase.
	vec2 o = texel * 0.5;
	vec4 f = 0.25 * (texture(TEXTURE, muv + vec2(-o.x, -o.y)) + texture(TEXTURE, muv + vec2(o.x, -o.y))
		+ texture(TEXTURE, muv + vec2(-o.x, o.y)) + texture(TEXTURE, muv + vec2(o.x, o.y)));
	if (f.r < 0.004 && f.g < 0.004) {
		discard;  // visible now: leave the picture untouched
	}
	vec3 scr = texture(screen_tex, SCREEN_UV).rgb;
	float lum = dot(scr, vec3(0.299, 0.587, 0.114));
	vec3 memory = mix(scr, vec3(lum), 0.7) * vec3(0.5, 0.54, 0.64);
	vec3 col = mix(scr, memory, smoothstep(0.0, 1.0, f.r));
	if (f.g > 0.004) {
		float t = TIME + time_offset;
		float n = fbm(cell * 0.32 + vec2(t * 0.06, t * 0.025));
		float n2 = noise(cell * 1.1 - vec2(t * 0.09, -t * 0.05));
		// Wispy cloud edge: noise eats into the cloud where it thins out.
		float c = smoothstep(0.15, 0.85, f.g * (0.7 + 0.6 * n));
		vec3 cloud = mix(vec3(0.06, 0.07, 0.1), vec3(0.21, 0.23, 0.3), clamp(n * (0.6 + 0.8 * n2), 0.0, 1.0));
		col = mix(col, cloud, c);
	}
	COLOR = vec4(col, 1.0);
}
"""

var sim: Simulation
var faction: String = "player"
var _img: Image
var _tex: ImageTexture
var _dim: PackedFloat32Array
var _cloud: PackedFloat32Array
var _t_dim: PackedFloat32Array
var _t_cloud: PackedFloat32Array
## Fog targets are recomputed only when the simulation's fog may have changed:
## a full recompute (fog_tick) or a new unit revealing ground (next_id).
var _key: Vector2i = Vector2i(-1, -1)
var _board: Rect2


func setup(p_sim: Simulation, p_faction: String) -> void:
	sim = p_sim
	faction = p_faction
	var w: int = sim.map.width
	var h: int = sim.map.height
	var b: float = TerrainLayer.BORDER
	_board = Rect2(Vector2(-b, -b) * Consts.PIXELS_PER_CELL, (Vector2(w, h) + Vector2(b, b) * 2.0) * Consts.PIXELS_PER_CELL)
	_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_dim.resize(w * h)
	_cloud.resize(w * h)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_update_targets()
	for i: int in w * h:
		_dim[i] = _t_dim[i]
		_cloud[i] = _t_cloud[i]
		_img.set_pixel(i % w, i / w, Color(_dim[i], _cloud[i], 0.0, 1.0))
	_tex = ImageTexture.create_from_image(_img)
	var shader: Shader = Shader.new()
	shader.code = SHADER
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("map_cells", Vector2(w, h))
	mat.set_shader_parameter("border", b)
	material = mat
	queue_redraw()


func _draw() -> void:
	if _tex != null:
		draw_texture_rect(_tex, _board, false)


func _update_targets() -> void:
	var key: Vector2i = Vector2i(sim.fog_tick, sim.next_id)
	if key == _key:
		return
	_key = key
	var g: PackedByteArray = sim.fog.grid(faction)
	_t_dim.resize(g.size())
	_t_cloud.resize(g.size())
	for i: int in g.size():
		_t_dim[i] = 0.0 if g[i] == Fog.VISIBLE else 1.0
		_t_cloud[i] = 1.0 if g[i] == Fog.UNEXPLORED else 0.0


func refresh(delta: float) -> void:
	if sim == null:
		return
	_update_targets()
	var w: int = sim.map.width
	var k: float = clampf(delta * EASE, 0.0, 1.0)
	var changed: bool = false
	for i: int in _dim.size():
		var d: float = _dim[i]
		var c: float = _cloud[i]
		if absf(d - _t_dim[i]) < 0.004 and absf(c - _t_cloud[i]) < 0.004:
			continue
		d = _t_dim[i] if absf(d - _t_dim[i]) < 0.01 else lerpf(d, _t_dim[i], k)
		c = _t_cloud[i] if absf(c - _t_cloud[i]) < 0.01 else lerpf(c, _t_cloud[i], k * 0.6)
		_dim[i] = d
		_cloud[i] = c
		_img.set_pixel(i % w, i / w, Color(d, c, 0.0, 1.0))
		changed = true
	if changed:
		_tex.update(_img)
