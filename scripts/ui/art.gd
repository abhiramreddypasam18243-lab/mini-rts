## The game's art, drawn with shapes in code (no image files; ASSETS rule L1).
## Each function draws onto the CanvasItem it is given, from inside that
## item's _draw(), so the map, the HUD portraits and the menu share one look.
class_name Art
extends RefCounted

const INK: Color = Color(0.05, 0.08, 0.11, 0.9)

static var _boxes: Dictionary = {}


static func _box(key: String, bg: Color, radius: int, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> StyleBoxFlat:
	if not _boxes.has(key):
		var s: StyleBoxFlat = StyleBoxFlat.new()
		s.bg_color = bg
		s.set_corner_radius_all(radius)
		s.border_color = border
		s.set_border_width_all(bw)
		s.anti_aliasing = true
		_boxes[key] = s
	return _boxes[key]


static func unit_radius(kind: String) -> float:
	return 8.5 if kind == "worker" else 10.5


## A unit token: shadow, faction body with a soft highlight, and its symbol.
static func unit(ci: CanvasItem, pos: Vector2, kind: String, faction: String, r: float = -1.0,
		alpha: float = 1.0, flash: float = 0.0) -> void:
	if r < 0.0:
		r = unit_radius(kind)
	var body: Color = Palette.TEAM[faction]
	ci.draw_set_transform(pos + Vector2(0, r * 0.75), 0.0, Vector2(1.0, 0.42))
	ci.draw_circle(Vector2.ZERO, r * 1.05, Color(0, 0, 0, 0.4 * alpha), true, -1.0, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ci.draw_circle(pos, r + 1.6, Color(Palette.TEAM_DARK[faction], alpha), true, -1.0, true)
	ci.draw_circle(pos, r, Color(body, alpha), true, -1.0, true)
	ci.draw_circle(pos - Vector2(r * 0.28, r * 0.32), r * 0.5, Color(1, 1, 1, 0.16 * alpha), true, -1.0, true)
	glyph(ci, kind, pos, r / 10.5, Color(INK, INK.a * alpha))
	if flash > 0.0:
		ci.draw_circle(pos, r + 1.0, Color(1, 1, 1, 0.75 * flash), true, -1.0, true)


## The symbol inside a unit: pickaxe, sword or bow. `s` scales a 10.5 px token.
static func glyph(ci: CanvasItem, kind: String, c: Vector2, s: float, col: Color) -> void:
	var w: float = maxf(1.6 * s, 1.0)
	match kind:
		"worker":
			ci.draw_line(c + Vector2(-4.5, 5) * s, c + Vector2(3, -2.5) * s, col, w * 1.15, true)
			ci.draw_polyline([c + Vector2(-1.5, -6.5) * s, c + Vector2(3.5, -5.2) * s, c + Vector2(6.5, -1) * s], col, w * 1.3, true)
		"melee":
			ci.draw_line(c + Vector2(-5, 5) * s, c + Vector2(5.5, -5.5) * s, col, w * 1.25, true)
			ci.draw_line(c + Vector2(-5, -0.5) * s, c + Vector2(0.5, 5) * s, col, w * 1.2, true)
			ci.draw_circle(c + Vector2(-5.6, 5.6) * s, 1.5 * s, col, true, -1.0, true)
		"ranged":
			ci.draw_arc(c + Vector2(1.5, 0) * s, 6.5 * s, deg_to_rad(110), deg_to_rad(250), 12, col, w * 1.15, true)
			var top: Vector2 = c + (Vector2(1.5, 0) + Vector2.from_angle(deg_to_rad(110)) * 6.5) * s
			var bot: Vector2 = c + (Vector2(1.5, 0) + Vector2.from_angle(deg_to_rad(250)) * 6.5) * s
			ci.draw_line(top, bot, Color(col, col.a * 0.7), maxf(w * 0.6, 1.0), true)
			ci.draw_line(c + Vector2(-4.5, 0) * s, c + Vector2(6, 0) * s, col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(7.5, 0) * s, c + Vector2(4.5, -2.2) * s, c + Vector2(4.5, 2.2) * s]), col)
		"hq":
			ci.draw_line(c + Vector2(0, 7) * s, c + Vector2(0, -8) * s, col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8) * s, c + Vector2(8, -5) * s, c + Vector2(0, -2) * s]), col)
		"barracks":
			ci.draw_line(c + Vector2(-6, 6) * s, c + Vector2(6, -6) * s, col, w * 1.2, true)
			ci.draw_line(c + Vector2(6, 6) * s, c + Vector2(-6, -6) * s, col, w * 1.2, true)
			ci.draw_line(c + Vector2(-6, 1) * s, c + Vector2(-1, 6) * s, col, w, true)
			ci.draw_line(c + Vector2(6, 1) * s, c + Vector2(1, 6) * s, col, w, true)


## A building: shadow, rounded base, roof, emblem; scaffold stripes and a
## progress bar while under construction. `ghost` draws a faded memory.
static func building(ci: CanvasItem, rect: Rect2, kind: String, faction: String, t: float,
		complete: bool = true, progress: float = 1.0, ghost: bool = false, flash: float = 0.0) -> void:
	var a: float = 0.55 if ghost else 1.0
	var team: Color = Palette.TEAM[faction]
	var dark: Color = Palette.TEAM_DARK[faction]
	if ghost:
		team = team.lerp(Color("6b7686"), 0.6)
		dark = dark.lerp(Color("2b323d"), 0.6)
	var r: Rect2 = rect.grow(-3.0)
	ci.draw_style_box(_box("shadow", Color(0, 0, 0, 0.38), 9), Rect2(r.position + Vector2(0, 6), r.size))
	var base: StyleBoxFlat = _box("base_%s_%s" % [faction, ghost], Color(dark, a), 9, Color(team.darkened(0.15), a * 0.9), 2)
	ci.draw_style_box(base, r)
	var roof: Rect2 = r.grow(-6.0)
	var roof_col: Color = Color(team.darkened(0.35), a) if complete else Color(team.darkened(0.55), a * 0.6)
	ci.draw_style_box(_box("roof_%s_%s_%s" % [faction, ghost, complete], roof_col, 6), roof)
	ci.draw_rect(Rect2(roof.position + Vector2(4, 2), Vector2(roof.size.x - 8, 2)), Color(1, 1, 1, 0.07 * a))
	var c: Vector2 = r.get_center()
	if kind == "hq":
		for corner: Vector2 in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
			var p: Vector2 = corner + (c - corner).normalized() * 9.0
			ci.draw_circle(p, 6.5, Color(dark, a), true, -1.0, true)
			ci.draw_circle(p, 4.5, Color(team, a), true, -1.0, true)
		# Waving flag.
		var top: Vector2 = c + Vector2(-2, -22)
		ci.draw_line(c + Vector2(-2, 14), top, Color(Palette.TEXT, a), 2.0, true)
		var wave: float = 0.0 if ghost else sin(t * 4.0)
		ci.draw_colored_polygon(PackedVector2Array([top, top + Vector2(10, 3 + wave), top + Vector2(19, 2 + wave * 1.6),
			top + Vector2(10, 10 + wave), top + Vector2(0, 11)]), Color(team.lightened(0.15), a))
		ci.draw_circle(c + Vector2(-2, 14), 3.0, Color(Palette.TEXT, a * 0.8), true, -1.0, true)
	else:
		glyph(ci, kind, c, 1.35, Color(Palette.TEAM_LIGHT[faction] if not ghost else Color("aab3bf"), a * 0.9))
	if not complete:
		hatch(ci, r.grow(-2.0), Color(1, 1, 1, 0.07))
		bar(ci, Rect2(r.position.x + 6, r.end.y - 9, r.size.x - 12, 4), progress, Palette.ACCENT)
	if flash > 0.0:
		ci.draw_rect(r.grow(-2.0), Color(1, 1, 1, 0.35 * flash))


## Diagonal scaffold stripes clipped to a rectangle.
static func hatch(ci: CanvasItem, r: Rect2, col: Color, gap: float = 7.0) -> void:
	var o: float = -r.size.y
	while o < r.size.x:
		var x0: float = r.position.x + o
		var a: Vector2 = Vector2(x0, r.position.y)
		var b: Vector2 = Vector2(x0 + r.size.y, r.end.y)
		if a.x < r.position.x:
			a = Vector2(r.position.x, r.position.y + (r.position.x - a.x))
		if b.x > r.end.x:
			b = Vector2(r.end.x, r.end.y - (b.x - r.end.x))
		if a.x <= b.x:
			ci.draw_line(a, b, col, 2.0, true)
		o += gap


## A small rounded bar with a dark background.
static func bar(ci: CanvasItem, r: Rect2, ratio: float, col: Color) -> void:
	ci.draw_style_box(_box("bar_bg", Color(0, 0, 0, 0.55), 2), r.grow(1.0))
	if ratio > 0.0:
		var fill: StyleBoxFlat = _box("bar_" + col.to_html(), col, 2)
		ci.draw_style_box(fill, Rect2(r.position, Vector2(maxf(r.size.x * clampf(ratio, 0.0, 1.0), 2.0), r.size.y)))


## A resource node: a cluster of trees or a faceted gold nugget. `fullness`
## (0..1) shrinks it as it runs out.
static func node(ci: CanvasItem, c: Vector2, kind: String, fullness: float, t: float, alpha: float = 1.0) -> void:
	var s: float = 0.75 + 0.25 * clampf(fullness, 0.0, 1.0)
	ci.draw_set_transform(c + Vector2(0, 9 * s), 0.0, Vector2(1.0, 0.4))
	ci.draw_circle(Vector2.ZERO, 12.0 * s, Color(0, 0, 0, 0.35 * alpha), true, -1.0, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if kind == "wood":
		for p: Vector3 in [Vector3(-5.5, 2.5, 7.0), Vector3(5.5, 3.5, 6.5), Vector3(0, -4.5, 7.5)]:
			var q: Vector2 = c + Vector2(p.x, p.y) * s
			ci.draw_circle(q, p.z * s + 1.2, Color(Palette.WOOD_DARK, alpha), true, -1.0, true)
			ci.draw_circle(q, p.z * s, Color(Palette.WOOD, alpha), true, -1.0, true)
			ci.draw_circle(q - Vector2(1.8, 2.2) * s, p.z * s * 0.45, Color(Palette.WOOD_LIGHT, 0.45 * alpha), true, -1.0, true)
	else:
		var pts: PackedVector2Array = PackedVector2Array()
		for k: int in 6:
			var ang: float = TAU * k / 6.0 + 0.3
			pts.append(c + Vector2(cos(ang) * 10.5, sin(ang) * 8.5) * s)
		ci.draw_colored_polygon(pts, Color(Palette.GOLD_DARK, alpha))
		var inner: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in pts:
			inner.append(c + (p - c) * 0.72 - Vector2(0, 1.2))
		ci.draw_colored_polygon(inner, Color(Palette.GOLD, alpha))
		ci.draw_colored_polygon(PackedVector2Array([inner[3], inner[4], c - Vector2(0, 1.2)]), Color(Palette.GOLD_LIGHT, 0.7 * alpha))
		var tw: float = maxf(sin(t * 2.3 + c.x * 0.1), 0.0)
		if tw > 0.6:
			var sp: Vector2 = c + Vector2(4, -5) * s
			var k: float = (tw - 0.6) * 2.5
			ci.draw_line(sp - Vector2(3, 0) * k, sp + Vector2(3, 0) * k, Color(1, 1, 1, 0.8 * alpha), 1.2, true)
			ci.draw_line(sp - Vector2(0, 3) * k, sp + Vector2(0, 3) * k, Color(1, 1, 1, 0.8 * alpha), 1.2, true)


## Small HUD icons: "wood", "gold", "pop", "clock".
static func icon(ci: CanvasItem, c: Vector2, kind: String, s: float = 1.0) -> void:
	match kind:
		"wood", "gold":
			node(ci, c + Vector2(0, -1), kind, 1.0, 0.0)
		"pop":
			ci.draw_circle(c + Vector2(0, -4) * s, 3.6 * s, Palette.TEXT, true, -1.0, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-6.5, 7) * s, c + Vector2(-5, 1) * s,
				c + Vector2(5, 1) * s, c + Vector2(6.5, 7) * s]), Palette.TEXT)
		"clock":
			ci.draw_arc(c, 6.5 * s, 0, TAU, 24, Palette.MUTED, 1.6, true)
			ci.draw_line(c, c + Vector2(0, -4) * s, Palette.MUTED, 1.6, true)
			ci.draw_line(c, c + Vector2(3, 0) * s, Palette.MUTED, 1.6, true)
