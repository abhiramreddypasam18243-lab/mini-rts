## A full-screen colour grade over the game world, under the HUD
## (presentation layer, D-39): a little more saturation and contrast, warm
## highlights and cool shadows, and a soft vignette that draws the eye to
## the middle of the screen.
class_name PostFx
extends CanvasLayer

const SHADER: String = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float vignette = 0.3;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	// Calm the pure greens of the grass a little, keep other colours rich.
	float green = clamp((c.g - max(c.r, c.b)) * 2.5, 0.0, 1.0);
	c = mix(vec3(l), c, 1.08 - 0.22 * green);
	c = (c - 0.5) * 1.06 + 0.5;
	c *= mix(vec3(0.93, 0.97, 1.07), vec3(1.04, 1.0, 0.93), smoothstep(0.15, 0.85, l));
	vec2 uv = (SCREEN_UV - 0.5) * vec2(1.0, 0.82);
	c *= 1.0 - vignette * smoothstep(0.32, 0.78, length(uv));
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
"""


func _ready() -> void:
	layer = 5
	# Godot copies the screen once per frame for screen-reading shaders (the
	# fog already did); copy it again so markers, the drag box and the
	# placement ghost drawn after the fog are graded too, not painted over.
	var copy: BackBufferCopy = BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(copy)
	var rect: ColorRect = ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader: Shader = Shader.new()
	shader.code = SHADER
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	add_child(rect)
