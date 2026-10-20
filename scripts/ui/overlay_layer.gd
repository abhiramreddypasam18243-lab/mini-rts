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
	_waypoints()
	for fx: Dictionary in game.fx:
		if fx.type == "marker":
			_marker(fx)
	if game.aiming:
		_aim_cursor()

	if game.dragging:
		var r: Rect2 = Rect2(game.drag_from, Vector2.ZERO).expand(game.drag_end())
		draw_rect(r, Color(Palette.ACCENT, 0.10))
		draw_rect(r, Color(Palette.ACCENT, 0.85), false, 1.5, true)

	if game.placing:
		var anchor: Vector2i = game.placement_anchor()
		var kind: String = game.placing_kind
		var size: Vector2i = game.sim.stats[kind].footprint
		var code: String = game.sim.placement_check(game.faction, kind, anchor)
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
		Art.draw_rendered(self, "%s_%s" % [kind, Art.TEAM_ART[game.faction]], r.get_center(), Color(col.lightened(0.5), 0.7))
		var text: String = "Build " + HudModel.KIND_NAMES[kind].to_lower() if ok else HudModel.reason_text(code, HudModel.cost_of(game.sim, kind))
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


## The route of each selected unit (D-44): its current destination, then
## its queued orders, as dashed lines with a dot at every waypoint (white:
## move, red: attack-move or attack, gold: gather).
func _waypoints() -> void:
	var colours: Dictionary = {"move": Color(1, 0.96, 0.8), "attack_move": Color(1.0, 0.45, 0.35),
		"attack": Color(1.0, 0.3, 0.25), "harvest": Palette.GOLD}
	for id: int in game.selected_units():
		var e: Entity = game.sim.entity(id)
		var points: Array[Array] = []
		if e.order_type == "move" or e.order_type == "attack_move":
			points.append([_cell_centre(e.order_cell), e.order_type])
		elif e.am_cell != Simulation.NO_CELL:
			points.append([_cell_centre(e.am_cell), "attack_move"])
		for o: Dictionary in e.orders:
			if o.has("cell"):
				points.append([_cell_centre(o.cell), o.command])
			else:
				var t: Entity = game.sim.entity(o.target)
				if t != null:
					points.append([_entity_centre(t), o.command])
		if points.is_empty():
			continue
		var from: Vector2 = game.draw_pos(e)
		for p: Array in points:
			var col: Color = colours.get(p[1], Color.WHITE)
			_dashed(from, p[0], Color(col, 0.75))
			draw_circle(p[0], 4.0, Color(0, 0, 0, 0.5), true, -1.0, true)
			draw_circle(p[0], 3.0, col, true, -1.0, true)
			from = p[0]


func _dashed(a: Vector2, b: Vector2, col: Color) -> void:
	var length: float = a.distance_to(b)
	if length < 1.0:
		return
	var d: Vector2 = (b - a) / length
	var t: float = fmod(game.time * 20.0, 10.0)
	while t < length:
		draw_line(a + d * t, a + d * minf(t + 6.0, length), col, 1.6, true)
		t += 10.0


func _cell_centre(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * C


func _entity_centre(t: Entity) -> Vector2:
	return game.draw_pos(t) if t.is_unit() else (Vector2(t.cell) + Vector2(t.size) / 2.0) * C


## While aiming an attack-move: crossed swords at the mouse and a hint.
func _aim_cursor() -> void:
	var m: Vector2 = get_global_mouse_position()
	var col: Color = Color(1.0, 0.4, 0.3)
	draw_set_transform(m + Vector2(0, 4), 0.0, Vector2(1.0, 0.5))
	draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 32, Color(col, 0.8), 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for d: Vector2 in [Vector2(1, 1), Vector2(1, -1)]:
		draw_line(m - d * 8.0 - Vector2(0, 8), m + d * 8.0 - Vector2(0, 8), Color(0, 0, 0, 0.6), 4.0, true)
		draw_line(m - d * 8.0 - Vector2(0, 8), m + d * 8.0 - Vector2(0, 8), col, 2.2, true)
	var text: String = "Attack-move: click a destination  (Shift: more waypoints · right-click or Esc: cancel)"
	var font: Font = UiTheme.font("semibold")
	var tp: Vector2 = m + Vector2(18, 28)
	draw_string_outline(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.8))
	draw_string(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.9, 0.85))
