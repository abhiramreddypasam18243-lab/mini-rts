## Renders the app icon from the game's own art (the Kenney CC0 unit sprites
## listed in ASSETS.md) and saves it in the sizes the web app and the
## desktop build need. Needs a display (not --headless):
##   godot --rendering-driver opengl3 --script res://tools/make_icon.gd -- assets/icons
extends SceneTree

const SIZE: int = 512


class IconArt extends Node2D:
	func _draw() -> void:
		var s: float = 512.0
		var bg: StyleBoxFlat = StyleBoxFlat.new()
		bg.bg_color = Color("3a2716")
		bg.set_corner_radius_all(112)
		bg.border_color = Color("f2b632")
		bg.set_border_width_all(10)
		bg.anti_aliasing = true
		draw_style_box(bg, Rect2(16, 16, s - 32, s - 32))
		# A soft blue glow, a red mage behind, the blue knight in front.
		for k: int in 14:
			draw_circle(Vector2(s * 0.42, s * 0.6), 210.0 * (1.0 - k / 14.0), Color(0.24, 0.56, 0.84, 0.03), true, -1.0, true)
		Art.unit_icon(self, Vector2(s * 0.68, s * 0.36), "ranged", "ai", 150.0)
		Art.unit_icon(self, Vector2(s * 0.42, s * 0.6), "melee", "player", 260.0)


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "assets/icons"
	_render.call_deferred(out_dir)


func _render(out_dir: String) -> void:
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	vp.add_child(IconArt.new())
	for i: int in 4:
		await process_frame
	var img: Image = vp.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out_dir)
	for px: int in [512, 180, 144]:
		var copy: Image = img.duplicate()
		copy.resize(px, px, Image.INTERPOLATE_LANCZOS)
		copy.save_png(out_dir.path_join("icon_%d.png" % px))
		print("saved ", out_dir.path_join("icon_%d.png" % px))
	quit(0)
