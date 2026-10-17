## Drawn above the fog (presentation layer): order markers, the drag box,
## and the barracks placement ghost, green when valid and red when not,
## with the reason under it (SPEC 9; AC-75).
class_name OverlayLayer
extends Node2D

const C: float = Consts.PIXELS_PER_CELL

var game: Game


func _draw() -> void:
	if game == null or game.sim == null:
		return
	for fx: Dictionary in game.fx:
		if fx.type != "marker":
			continue
		var k: float = clampf((game.time - fx.t0) / fx.life, 0.0, 1.0)
		var p: Vector2 = fx.a
		draw_set_transform(p, 0.0, Vector2(1.0, 0.6))
		draw_arc(Vector2.ZERO, 16.0 * (1.0 - k) + 4.0, 0.0, TAU, 32, Color(fx.color, 1.0 - k), 2.5, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_circle(p, 2.5, Color(fx.color, 1.0 - k), true, -1.0, true)

	if game.dragging:
		var r: Rect2 = Rect2(game.drag_from, Vector2.ZERO).expand(get_global_mouse_position())
		draw_rect(r, Color(Palette.ACCENT, 0.10))
		draw_rect(r, Color(Palette.ACCENT, 0.85), false, 1.5, true)

	if game.placing:
		var anchor: Vector2i = game.placement_anchor()
		var size: Vector2i = game.sim.stats["barracks"].footprint
		var code: String = game.sim.placement_check(game.faction, "barracks", anchor)
		var ok: bool = code == "ok"
		var col: Color = Palette.GOOD if ok else Palette.BAD
		var r: Rect2 = Rect2(Vector2(anchor) * C, Vector2(size) * C)
		var s: StyleBoxFlat = StyleBoxFlat.new()
		s.bg_color = Color(col, 0.22 + 0.06 * sin(game.time * 6.0))
		s.border_color = Color(col, 0.95)
		s.set_border_width_all(2)
		s.set_corner_radius_all(9)
		s.anti_aliasing = true
		draw_style_box(s, r.grow(-2.0))
		draw_texture_rect(Art.tex("barracks"), r.grow(4.0), false, Color(col.lightened(0.4), 0.75))
		var text: String = "Build barracks" if ok else HudModel.reason_text(code, HudModel.cost_of(game.sim, "barracks"))
		var font: Font = UiTheme.font("semibold")
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var tp: Vector2 = Vector2(r.get_center().x - w / 2.0, r.end.y + 18)
		draw_string_outline(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 5, Color(0, 0, 0, 0.8))
		draw_string(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(col.lightened(0.2), 1.0))
