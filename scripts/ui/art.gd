## The game's art (presentation layer): sprites from Kenney's CC0 "Medieval
## RTS" pack (decision D-38), plus team rings, shadows, banners, bars and
## effects drawn in code. Each function draws onto the CanvasItem it is
## given, from inside that item's _draw(), so the map, the HUD and the menu
## share one look.
class_name Art
extends RefCounted

const DIR: String = "res://assets/kenney/medieval_rts/"
## Sprite names per unit kind and faction.
const UNIT_SPRITES: Dictionary = {
	"worker": {"player": "unit_worker_blue", "ai": "unit_worker_red"},
	"melee": {"player": "unit_melee_blue", "ai": "unit_melee_red"},
	"ranged": {"player": "unit_ranged_blue", "ai": "unit_ranged_red"},
}
## A unit sprite is drawn this big (world pixels; one cell is 32). The figure
## fills about 40 % of the 128 px canvas, its feet at 69 % of the height.
const UNIT_SIZE: float = 62.0
const FEET: float = 88.0 / 128.0

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
		_tex[name] = load(DIR + name + ".png")
	return _tex[name]


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
	return 9.0 if kind == "worker" else 11.0


## A unit standing at `pos` (its feet): a team-coloured ring on the ground,
## a soft shadow, then the sprite. `flash` tints it red when hit. `pose`
## animates it (all optional): flip (face left), lift (hop height, px),
## tilt (radians, about the feet), sx / sy (squash and stretch), ring (bool).
static func unit(ci: CanvasItem, pos: Vector2, kind: String, faction: String, scale: float = 1.0,
		alpha: float = 1.0, flash: float = 0.0, pose: Dictionary = {}) -> void:
	var r: float = unit_radius(kind) * scale
	var lift: float = pose.get("lift", 0.0)
	var shadow_k: float = 1.0 - clampf(lift / 14.0, 0.0, 0.35)
	# Shadow and team ring are stamped from small cached textures: far
	# cheaper than tessellating anti-aliased circles for every unit.
	ci.draw_set_transform(pos + Vector2(0, 3 * scale), 0.0, Vector2(shadow_k, 0.45 * shadow_k))
	var sr: float = r + 3.0
	ci.draw_texture_rect(disc(), Rect2(-sr, -sr, sr * 2.0, sr * 2.0), false, Color(0, 0, 0, 0.36 * alpha))
	if pose.get("ring", true):
		var rr: float = r + 1.5 * scale
		ci.draw_texture_rect(ring(), Rect2(-rr, -rr, rr * 2.0, rr * 2.0), false, Color(Palette.TEAM[faction], 0.95 * alpha))
	var size: float = UNIT_SIZE * scale
	var flip: float = -1.0 if pose.get("flip", false) else 1.0
	# The sprite is drawn about the feet so tilt and squash pivot there.
	ci.draw_set_transform(pos + Vector2(0, 4 * scale - lift), pose.get("tilt", 0.0),
		Vector2(flip * pose.get("sx", 1.0), pose.get("sy", 1.0)))
	var rect: Rect2 = Rect2(-size / 2.0, -size * FEET, size, size)
	var tint: Color = Color(1, 1 - 0.55 * flash, 1 - 0.55 * flash, alpha)
	ci.draw_texture_rect(tex(UNIT_SPRITES[kind][faction]), rect, false, tint)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Just the sprite, centred in a box (HUD icons and portraits).
static func unit_icon(ci: CanvasItem, centre: Vector2, kind: String, faction: String, height: float, alpha: float = 1.0) -> void:
	var size: float = height / 0.42
	var rect: Rect2 = Rect2(centre.x - size / 2.0, centre.y - size * 0.49, size, size)
	ci.draw_texture_rect(tex(UNIT_SPRITES[kind][faction]), rect, false, Color(1, 1, 1, alpha))


## A building on its footprint `rect`: a dirt plot with a team-coloured edge,
## the sprite standing on it, and a team banner. While under construction it
## is faded with scaffold stripes and a progress bar; a ghost is greyed out.
static func building(ci: CanvasItem, rect: Rect2, kind: String, faction: String, t: float,
		complete: bool = true, progress: float = 1.0, ghost: bool = false, flash: float = 0.0) -> void:
	var team: Color = Palette.TEAM[faction]
	var plot: Rect2 = rect.grow(-2.0)
	# A soft shadow and a team-coloured outline on the grass.
	ci.draw_style_box(_box("plot_shadow", Color(0, 0, 0, 0.18), 10), Rect2(plot.position + Vector2(0, 3), plot.size))
	ci.draw_style_box(_box("plot_edge_%s_%s" % [faction, ghost], Color(team, 0.12 if not ghost else 0.05), 8,
		Color(team, 0.85 if not ghost else 0.35), 3), plot)
	var a: float = 1.0
	var tint: Color = Color(1, 1, 1)
	if ghost:
		tint = Color(0.62, 0.62, 0.66)
		a = 0.6
	elif not complete:
		a = 0.55
	if flash > 0.0:
		tint = Color(1, 1 - 0.5 * flash, 1 - 0.5 * flash)
	var s: Texture2D = tex("castle" if kind == "hq" else "barracks")
	var sprite: Rect2
	if kind == "hq":
		# The castle fills the top 76 / 128 of its canvas: scale it to the
		# footprint's width and stand it on the plot.
		# Its visible part is centred on the footprint.
		var w: float = rect.size.x * 128.0 / 120.0 * 1.08
		var visible_h: float = w * 76.0 / 128.0
		sprite = Rect2(rect.get_center().x - w / 2.0, rect.get_center().y - visible_h / 2.0 - 2.0, w, w)
	else:
		var w2: float = rect.size.x * 128.0 / 112.0 * 1.04
		sprite = Rect2(rect.get_center().x - w2 / 2.0, rect.end.y - w2 * 124.0 / 128.0 + 1.0, w2, w2)
	ci.draw_texture_rect(s, sprite, false, Color(tint, a))
	if not complete:
		hatch(ci, plot.grow(-3.0), Color(0.36, 0.24, 0.14, 0.45), 8.0)
		bar(ci, Rect2(plot.position.x + 6, plot.end.y - 8, plot.size.x - 12, 5), progress, Palette.ACCENT)
	if not ghost:
		banner(ci, Vector2(rect.end.x - 6, rect.position.y + 4), team, t)


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
	ci.draw_rect(r.grow(1.0), Color(0.12, 0.08, 0.05, 0.85))
	if ratio > 0.0:
		ci.draw_rect(Rect2(r.position, Vector2(maxf(r.size.x * clampf(ratio, 0.0, 1.0), 2.0), r.size.y)), col)
		ci.draw_rect(Rect2(r.position + Vector2(1, 0.5), Vector2(maxf(r.size.x * ratio - 2.0, 0.0), maxf(r.size.y * 0.35, 1.0))), Color(1, 1, 1, 0.25))


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
			var sz: float = cell * 1.25 * sp.z
			var foot: Vector2 = c + Vector2(sp.x, sp.y)
			# Sway in the wind: shear the tree about its foot.
			var sway: float = sin(t * 1.6 + foot.x * 0.045 + foot.y * 0.031) * 0.05
			ci.draw_set_transform_matrix(Transform2D(Vector2(1, 0), Vector2(sway, 1), foot))
			ci.draw_texture_rect(tex("tree_pine"), Rect2(Vector2(-sz * 0.5, -sz * 0.84), Vector2(sz, sz)), false, Color(1, 1, 1, alpha))
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
