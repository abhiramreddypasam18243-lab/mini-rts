## The game's art (presentation layer): buildings and scenery from Kenney's
## CC0 "Medieval RTS" pack (decision D-38), pre-rendered 3D units (D-50,
## UnitSprites), plus team rings, shadows, banners, bars and
## effects drawn in code. Each function draws onto the CanvasItem it is
## given, from inside that item's _draw(), so the map, the HUD and the menu
## share one look.
class_name Art
extends RefCounted

const DIR: String = "res://assets/kenney/medieval_rts/"

static var _tex: Dictionary = {}
static var _boxes: Dictionary = {}


## A soft white disc and a white ring (64 px), made once, for shadows and
## team rings.
static var _disc: ImageTexture
static var _ring: ImageTexture


static func disc() -> Texture2D:
	if _disc == null:
		_disc = _round_tex(func(d: float) -> float: return clampf((1.0 - d) * 6.0, 0.0, 1.0))
	return _disc


static func ring() -> Texture2D:
	if _ring == null:
		# A band 14 % of the radius wide, with soft edges.
		_ring = _round_tex(func(d: float) -> float: return clampf(1.0 - absf(d - 0.84) / 0.09, 0.0, 1.0) * 1.4)
	return _ring


static func _round_tex(alpha_at: Callable) -> ImageTexture:
	var n: int = 64
	var img: Image = Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y: int in n:
		for x: int in n:
			var d: float = Vector2(x + 0.5 - n / 2.0, y + 0.5 - n / 2.0).length() / (n / 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(alpha_at.call(d), 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		var r: String = RENDERED + name + ".png"
		_tex[name] = load(r) if ResourceLoader.exists(r) else load(DIR + name + ".png")
	return _tex[name]


# --- pre-rendered 3D sprites (decision D-49) -----------------------------------

const RENDERED: String = "res://assets/rendered/"
## World pixels per 3D unit: one unit is one map cell.
const UNIT_PX: float = 32.0
const TEAM_ART: Dictionary = {"player": "blue", "ai": "red"}
static var _anchors: Dictionary = {}


## A rendered sprite's anchor: pixels per unit and the pixel where its 3D
## origin (a building's footprint centre, a tree's foot) lies.
static func anchor(name: String) -> Dictionary:
	if _anchors.is_empty():
		for f: String in ["rendered.json", "props.json"]:
			var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(RENDERED + f))
			if d is Dictionary:
				_anchors.merge(d)
	return _anchors.get(name, {"ppu": 64.0, "origin": [64.0, 64.0]})


## Draws a rendered sprite with its origin at `at` (world), `scale` world
## pixels per unit; only the part below `clip_y` (world y) is drawn.
static func draw_rendered(ci: CanvasItem, name: String, at: Vector2, tint: Color = Color.WHITE,
		clip_y: float = -INF, scale: float = UNIT_PX) -> void:
	var a: Dictionary = anchor(name)
	var t: Texture2D = tex(name)
	var k: float = scale / float(a.ppu)
	var src: Rect2 = Rect2(Vector2.ZERO, t.get_size())
	var dst: Rect2 = Rect2(at - Vector2(a.origin[0], a.origin[1]) * k, t.get_size() * k)
	if clip_y > dst.position.y:
		if clip_y >= dst.end.y:
			return
		var cut: float = (clip_y - dst.position.y) / k
		src = Rect2(0, cut, src.size.x, src.size.y - cut)
		dst = Rect2(dst.position.x, clip_y, dst.size.x, dst.end.y - clip_y)
	ci.draw_texture_rect_region(t, dst, src, tint)


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
	return 10.0 if kind == "worker" else 12.0


## A unit, animated (decision D-41): a team-coloured ring on the ground,
## then the unit's sprite frame (which carries its own shadow). `flash` tints
## it red when hit; `alpha` fades it.
static func unit(ci: CanvasItem, feet: Vector2, kind: String, faction: String, anim: String, dir: int, frame: int,
		alpha: float = 1.0, flash: float = 0.0, scale: float = UnitSprites.SCALE, ring_on: bool = true) -> void:
	if ring_on:
		var rr: float = unit_radius(kind) * scale / UnitSprites.SCALE
		ci.draw_set_transform(feet + Vector2(0, 1), 0.0, Vector2(1.0, 0.45))
		ci.draw_texture_rect(ring(), Rect2(-rr, -rr, rr * 2.0, rr * 2.0), false, Color(Palette.TEAM[faction], 0.85 * alpha))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var tint: Color = Color(1, 1 - 0.6 * flash, 1 - 0.6 * flash, alpha)
	UnitSprites.draw(ci, feet, kind, faction, anim, dir, frame, scale, tint)


## The standing unit, centred in a box (HUD icons and portraits).
static func unit_icon(ci: CanvasItem, centre: Vector2, kind: String, faction: String, height: float, alpha: float = 1.0) -> void:
	UnitSprites.icon(ci, centre, kind, faction, height, alpha)


## A building on its footprint `rect` (D-48): a paved stone base with a
## team-coloured trim, then the building made of several Kenney pieces. The
## HQ is a keep with two corner towers behind a gated wall; the barracks has
## an armoury rack. Under construction it rises from the base as `progress`
## grows, inside wooden scaffolding; a ghost is greyed out.
static func building(ci: CanvasItem, rect: Rect2, kind: String, faction: String, t: float,
		complete: bool = true, progress: float = 1.0, ghost: bool = false, flash: float = 0.0) -> void:
	var team: Color = Palette.TEAM[faction]
	_plinth(ci, rect, team, ghost)
	var tint: Color = Color(1, 1, 1)
	if ghost:
		tint = Color(0.62, 0.62, 0.66, 0.6)
	elif flash > 0.0:
		tint = Color(1, 1 - 0.5 * flash, 1 - 0.5 * flash)
	# The part of the building already built: everything below clip_y.
	var top: float = rect.position.y - rect.size.y * (0.9 if kind == "hq" else 0.5)
	var clip_y: float = -INF
	if not complete and not ghost:
		var f: float = clampf(progress, 0.0, 1.0)
		clip_y = lerpf(rect.end.y, top, 0.15 + 0.85 * f)
		tint.a = 0.9
	# The pre-rendered 3D building (D-49), its footprint centre on the plot's
	# centre; its team flags and shadow are part of the picture.
	draw_rendered(ci, "%s_%s" % [kind, TEAM_ART[faction]], rect.get_center(), tint, clip_y)
	if not complete and not ghost:
		_scaffold(ci, rect, clip_y)
		bar(ci, Rect2(rect.position.x + 8, rect.end.y - 7, rect.size.x - 16, 5), progress, Palette.ACCENT)


## The pieces of a building, back to front: [sprite, target rect].
static func _parts(kind: String, r: Rect2) -> Array:
	var x: float = r.position.x
	var y: float = r.position.y
	var w: float = r.size.x
	if kind == "hq":
		return [
			["tower", Rect2(x - 4, y - 22, w * 0.34, w * 0.5)],
			["tower", Rect2(r.end.x - w * 0.34 + 4, y - 22, w * 0.34, w * 0.5)],
			["keep", Rect2(x + w * 0.15, y - 18, w * 0.7, w * 0.8)],
			["gate", Rect2(x - 2, y + w * 0.56, w + 4, w * 0.46)],
		]
	return [
		["barracks", Rect2(x - 2, y - w * 0.22, w + 4, w * 1.18)],
		["armoury", Rect2(r.end.x - w * 0.42, r.end.y - w * 0.3, w * 0.5, w * 0.36)],
	]


## A paved stone base slightly larger than the footprint, with a soft
## shadow, a few joints, and a team-coloured trim.
static func _plinth(ci: CanvasItem, rect: Rect2, team: Color, ghost: bool) -> void:
	var base: Rect2 = rect.grow(3.0)
	ci.draw_style_box(_box("plinth_shadow", Color(0, 0, 0, 0.22), 9), Rect2(base.position + Vector2(2, 4), base.size))
	ci.draw_style_box(_box("plinth_%s" % ghost, Color("9a8f7c") if not ghost else Color(0.6, 0.6, 0.6, 0.35), 8,
		Color("6b604f") if not ghost else Color(0.4, 0.4, 0.4, 0.35), 2), base)
	if not ghost:
		var joint: Color = Color(0.36, 0.32, 0.26, 0.35)
		var step: float = 12.0
		var yy: float = base.position.y + step
		var row: int = 0
		while yy < base.end.y - 3:
			ci.draw_line(Vector2(base.position.x + 3, yy), Vector2(base.end.x - 3, yy), joint, 1.0)
			var xx: float = base.position.x + (8.0 if row % 2 == 0 else 14.0)
			while xx < base.end.x - 3:
				ci.draw_line(Vector2(xx, yy - step + 1), Vector2(xx, yy - 1), joint, 1.0)
				xx += 14.0
			yy += step
			row += 1
	ci.draw_style_box(_box("plinth_trim_%s_%s" % [team.to_html(), ghost], Color(0, 0, 0, 0), 7,
		Color(team, 0.9 if not ghost else 0.35), 2), base.grow(-3.0))


## Wooden scaffolding around a building site, with a plank at the height
## reached so far.
static func _scaffold(ci: CanvasItem, rect: Rect2, clip_y: float) -> void:
	var wood: Color = Color("8a5a2b")
	var dark: Color = Color("5a3a1c")
	var top: float = minf(clip_y, rect.end.y) - 6.0
	for px: float in [rect.position.x + 3, rect.get_center().x, rect.end.x - 3]:
		ci.draw_line(Vector2(px, rect.end.y), Vector2(px, top), dark, 3.0)
		ci.draw_line(Vector2(px, rect.end.y), Vector2(px, top), wood, 1.6)
	ci.draw_line(Vector2(rect.position.x, top + 3), Vector2(rect.end.x, top + 3), dark, 4.0)
	ci.draw_line(Vector2(rect.position.x, top + 3), Vector2(rect.end.x, top + 3), Color("b98a4e"), 2.4)
	ci.draw_line(Vector2(rect.position.x + 3, rect.end.y - 2), Vector2(rect.get_center().x, top + 4), Color(wood, 0.8), 1.5)


static var _bounds: Dictionary = {}


## The part of a sprite that is not transparent (in its own pixels).
static func used_rect(name: String) -> Rect2:
	if not _bounds.has(name):
		var img: Image = tex(name).get_image()
		if img == null:
			_bounds[name] = Rect2(Vector2.ZERO, tex(name).get_size())
		else:
			if img.is_compressed():
				img.decompress()
			_bounds[name] = Rect2(img.get_used_rect())
	return _bounds[name]


## Draws a sprite so its visible part fills `target`; only the part below
## `clip_y` (world y) is drawn (a building rising during construction).
static func draw_fit(ci: CanvasItem, name: String, target: Rect2, tint: Color = Color.WHITE, clip_y: float = -INF) -> void:
	var src: Rect2 = used_rect(name)
	var dst: Rect2 = target
	if clip_y > dst.position.y:
		if clip_y >= dst.end.y:
			return
		var cut: float = (clip_y - dst.position.y) / dst.size.y
		src = Rect2(src.position.x, src.position.y + src.size.y * cut, src.size.x, src.size.y * (1.0 - cut))
		dst = Rect2(dst.position.x, clip_y, dst.size.x, dst.end.y - clip_y)
	ci.draw_texture_rect_region(tex(name), dst, src, tint)


## A small flag on a pole, waving.
static func banner(ci: CanvasItem, top: Vector2, colour: Color, t: float) -> void:
	var foot: Vector2 = top + Vector2(0, 22)
	ci.draw_line(foot, top, Color("4a3523"), 2.0, true)
	var wave: float = sin(t * 4.0 + top.x * 0.05)
	ci.draw_colored_polygon(PackedVector2Array([top + Vector2(1, 0), top + Vector2(13, 2 + wave),
		top + Vector2(11, 6 + wave * 0.5), top + Vector2(14, 10 + wave), top + Vector2(1, 9)]), colour)
	ci.draw_circle(top, 1.8, Palette.ACCENT, true, -1.0, true)


## Diagonal scaffold stripes clipped to a rectangle.
static func hatch(ci: CanvasItem, r: Rect2, col: Color, gap: float = 7.0) -> void:
	var o: float = -r.size.y
	while o < r.size.x:
		var x0: float = r.position.x + o
		var p: Vector2 = Vector2(x0, r.position.y)
		var q: Vector2 = Vector2(x0 + r.size.y, r.end.y)
		if p.x < r.position.x:
			p = Vector2(r.position.x, r.position.y + (r.position.x - p.x))
		if q.x > r.end.x:
			q = Vector2(r.end.x, r.end.y - (q.x - r.end.x))
		if p.x <= q.x:
			ci.draw_line(p, q, col, 2.5, true)
		o += gap


## A small bar with a dark rim (world health and progress bars).
static func bar(ci: CanvasItem, r: Rect2, ratio: float, col: Color) -> void:
	ci.draw_rect(r.grow(1.0), Color(0.12, 0.08, 0.05, 0.85 * col.a))
	if ratio > 0.0:
		ci.draw_rect(Rect2(r.position, Vector2(maxf(r.size.x * clampf(ratio, 0.0, 1.0), 2.0), r.size.y)), col)
		ci.draw_rect(Rect2(r.position + Vector2(1, 0.5), Vector2(maxf(r.size.x * ratio - 2.0, 0.0), maxf(r.size.y * 0.35, 1.0))), Color(1, 1, 1, 0.25 * col.a))


## A UI-pack bar (HUD): back, then the coloured fill, three slices each.
static func ui_bar(ci: CanvasItem, r: Rect2, ratio: float, colour: String) -> void:
	_three_slice(ci, "barBack_horizontal", r)
	if ratio > 0.0:
		var w: float = maxf(r.size.x * clampf(ratio, 0.0, 1.0), r.size.y)
		_three_slice(ci, "bar%s_horizontal" % colour, Rect2(r.position, Vector2(w, r.size.y)))


static func _three_slice(ci: CanvasItem, prefix: String, r: Rect2) -> void:
	var cap: float = r.size.y * 0.5
	ci.draw_texture_rect(UiTheme.tex(prefix + "Left"), Rect2(r.position, Vector2(cap, r.size.y)), false)
	var mid: String = prefix + ("Mid" if not prefix.begins_with("barBlue") else "Blue")
	ci.draw_texture_rect(UiTheme.tex(mid), Rect2(r.position + Vector2(cap, 0), Vector2(maxf(r.size.x - 2 * cap, 0), r.size.y)), false)
	ci.draw_texture_rect(UiTheme.tex(prefix + "Right"), Rect2(Vector2(r.end.x - cap, r.position.y), Vector2(cap, r.size.y)), false)


## A resource node in the cell whose centre is `c`: a pine grove that thins
## out as it is used, or a gold-flecked ore mound that shrinks.
static func node(ci: CanvasItem, c: Vector2, kind: String, fullness: float, t: float, alpha: float = 1.0) -> void:
	var cell: float = Consts.PIXELS_PER_CELL
	if kind == "wood":
		# A small grove: three pines when full, fewer as it is used.
		var trees: int = 3 if fullness > 0.6 else (2 if fullness > 0.25 else 1)
		var spots: Array[Vector3] = [Vector3(-7, 2, 1.0), Vector3(8, 4, 0.95), Vector3(0, 11, 1.1)]
		ci.draw_set_transform(c + Vector2(0, 12), 0.0, Vector2(1.0, 0.4))
		ci.draw_texture_rect(disc(), Rect2(-cell * 0.55, -cell * 0.55, cell * 1.1, cell * 1.1), false, Color(0, 0, 0, 0.2 * alpha))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for i: int in trees:
			var sp: Vector3 = spots[i]
			var foot: Vector2 = c + Vector2(sp.x, sp.y)
			# Sway in the wind: shear the tree about its foot.
			var sway: float = sin(t * 1.6 + foot.x * 0.045 + foot.y * 0.031) * 0.04
			ci.draw_set_transform_matrix(Transform2D(Vector2(1, 0), Vector2(sway, 1), foot))
			draw_rendered(ci, ["tree_a", "tree_d", "tree_b"][i], Vector2.ZERO, Color(1, 1, 1, alpha), -INF, UNIT_PX * 0.62 * sp.z)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		var size: float = cell * (1.6 if fullness > 0.4 else 1.25)
		ci.draw_texture_rect(tex("gold_ore" if fullness > 0.4 else "gold_ore_small"),
			Rect2(c - Vector2(size, size) * 0.5 - Vector2(0, 2), Vector2(size, size)), false, Color(1, 1, 1, alpha))
		var tw: float = maxf(sin(t * 2.3 + c.x * 0.1), 0.0)
		if tw > 0.6 and alpha > 0.5:
			var sp: Vector2 = c + Vector2(5, -7)
			var k: float = (tw - 0.6) * 2.5
			ci.draw_line(sp - Vector2(3.5, 0) * k, sp + Vector2(3.5, 0) * k, Color(1, 1, 0.9, 0.9), 1.4, true)
			ci.draw_line(sp - Vector2(0, 3.5) * k, sp + Vector2(0, 3.5) * k, Color(1, 1, 0.9, 0.9), 1.4, true)


## Small HUD icons: "wood", "gold", "pop", "clock".
static func icon(ci: CanvasItem, c: Vector2, kind: String, s: float = 1.0) -> void:
	match kind:
		"wood":
			var size: float = 40.0 * s
			ci.draw_texture_rect(tex("tree_pine"), Rect2(c - Vector2(size * 0.5, size * 0.56), Vector2(size, size)), false)
		"gold":
			var size: float = 40.0 * s
			ci.draw_texture_rect(tex("gold_ore"), Rect2(c - Vector2(size, size) * 0.5 - Vector2(0, 1), Vector2(size, size)), false)
		"pop":
			unit_icon(ci, c + Vector2(0, 1), "worker", "player", 22.0 * s)
		"clock":
			ci.draw_circle(c, 9.0 * s, Color("f3e3bd"), true, -1.0, true)
			ci.draw_arc(c, 9.0 * s, 0, TAU, 24, Color("5a3d24"), 2.0, true)
			ci.draw_line(c, c + Vector2(0, -5.5) * s, Color("3d2a19"), 1.8, true)
			ci.draw_line(c, c + Vector2(4, 0) * s, Color("3d2a19"), 1.8, true)
