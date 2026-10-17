## Soft fog of war (presentation layer). One texture pixel per map cell,
## stretched over the board with linear filtering, so the edges between
## seen and unseen ground blur smoothly instead of forming hard squares.
## Each cell's opacity eases towards its target, so revealed ground fades in,
## and a small blur shader rounds off the cell-by-cell staircase.
class_name FogLayer
extends Sprite2D

const UNEXPLORED_ALPHA: float = 0.94
const EXPLORED_ALPHA: float = 0.52
const EASE: float = 7.0
## A 5 x 5 Gaussian blur over the (already bilinear) fog texture.
const BLUR_SHADER: String = """
shader_type canvas_item;
uniform vec2 texel;
void fragment() {
	vec4 sum = vec4(0.0);
	float total = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			float w = exp(-float(x * x + y * y) / 3.0);
			sum += texture(TEXTURE, UV + vec2(float(x), float(y)) * texel * 0.45) * w;
			total += w;
		}
	}
	COLOR = sum / total;
}
"""

var sim: Simulation
var faction: String = "player"
var _img: Image
var _tex: ImageTexture
var _alpha: PackedFloat32Array
var _targets: PackedFloat32Array
## Fog targets are recomputed only when the simulation's fog may have changed:
## a full recompute (fog_tick) or a new unit revealing ground (next_id).
var _key: Vector2i = Vector2i(-1, -1)


func setup(p_sim: Simulation, p_faction: String) -> void:
	sim = p_sim
	faction = p_faction
	var w: int = sim.map.width
	var h: int = sim.map.height
	_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_alpha = PackedFloat32Array()
	_alpha.resize(w * h)
	centered = false
	scale = Vector2(Consts.PIXELS_PER_CELL, Consts.PIXELS_PER_CELL)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_update_targets()
	for y: int in h:
		for x: int in w:
			_alpha[y * w + x] = _targets[y * w + x]
			_img.set_pixel(x, y, Color(Palette.FOG, _alpha[y * w + x]))
	_tex = ImageTexture.create_from_image(_img)
	texture = _tex
	var shader: Shader = Shader.new()
	shader.code = BLUR_SHADER
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("texel", Vector2(1.0 / w, 1.0 / h))
	material = mat


func _update_targets() -> void:
	var key: Vector2i = Vector2i(sim.fog_tick, sim.next_id)
	if key == _key:
		return
	_key = key
	var g: PackedByteArray = sim.fog.grid(faction)
	_targets.resize(g.size())
	for i: int in g.size():
		_targets[i] = 0.0 if g[i] == Fog.VISIBLE else (EXPLORED_ALPHA if g[i] == Fog.EXPLORED else UNEXPLORED_ALPHA)


func refresh(delta: float) -> void:
	if sim == null:
		return
	_update_targets()
	var w: int = sim.map.width
	var k: float = clampf(delta * EASE, 0.0, 1.0)
	var changed: bool = false
	for y: int in sim.map.height:
		for x: int in w:
			var i: int = y * w + x
			var t: float = _targets[i]
			var a: float = _alpha[i]
			if absf(a - t) < 0.004:
				continue
			a = t if absf(a - t) < 0.01 else lerpf(a, t, k)
			_alpha[i] = a
			_img.set_pixel(x, y, Color(Palette.FOG, a))
			changed = true
	if changed:
		_tex.update(_img)
