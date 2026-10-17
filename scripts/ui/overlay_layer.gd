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
		if fx.type == "marker":
			_marker(fx)

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


## An order marker: ripples on the ground, plus three chevrons dropping in
## (move, harvest, build) or crossed blades snapping shut (attack), each
## outlined in dark so it reads on grass and dirt.
func _marker(fx: Dictionary) -> void:
	var k: float = clampf((game.time - fx.t0) / fx.life, 0.0, 1.0)
	var p: Vector2 = fx.a
	var col: Color = Color(fx.color).lightened(0.3)
	var fade: float = 1.0 - k * k
	draw_set_transform(p, 0.0, Vector2(1.0, 0.5))
	for i: int in 2:
		var kk: float = clampf(k * 1.5 - i * 0.3, 0.0, 1.0)
		if kk > 0.0 and kk < 1.0:
			var r: float = 8.0 + 24.0 * ease(kk, 0.4)
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 36, Color(0, 0, 0, (1.0 - kk) * 0.45), 5.0, true)
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 36, Color(col, 1.0 - kk), 3.0, true)
	draw_circle(Vector2.ZERO, 6.0 * fade + 1.0, Color(col, fade * 0.6), true, -1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if fx.get("order", "move") == "attack":
		var s: float = 13.0 * (1.0 - 0.35 * ease(minf(k * 3.0, 1.0), 0.3))
		for d: Vector2 in [Vector2(1, 1), Vector2(1, -1)]:
			draw_line(p - d * s - Vector2(0, 14), p + d * s - Vector2(0, 14), Color(0, 0, 0, 0.6 * fade), 7.0, true)
			draw_line(p - d * s - Vector2(0, 14), p + d * s - Vector2(0, 14), Color(col, fade), 4.0, true)
	else:
		for i: int in 3:
			var a: float = i * TAU / 3.0 + PI / 2.0
			var drop: float = 22.0 * (1.0 - ease(minf(k * 2.5, 1.0), 0.3))
			var c: Vector2 = p + Vector2(cos(a) * 15.0, sin(a) * 7.5) * (1.0 + drop / 22.0) - Vector2(0, 6.0 + drop)
			var dir: Vector2 = (p - c).normalized()
			var side: Vector2 = dir.orthogonal() * 6.5
			var pts: PackedVector2Array = PackedVector2Array([c + dir * 8.0, c - dir * 3.0 + side, c - dir * 3.0 - side])
			draw_colored_polygon(pts, Color(col, fade))
			pts.append(pts[0])
			draw_polyline(pts, Color(0, 0, 0, 0.55 * fade), 1.5, true)
