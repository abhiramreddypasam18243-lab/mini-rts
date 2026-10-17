## Animated unit sprites (presentation layer, decision D-41): sheets built
## by tools/make_units.gd from Liberated Pixel Cup parts (credits in
## assets/lpc/CREDITS.md). Each sheet holds one animation in four rows
## (up, left, down, right; "hurt" has one row). Frames are 64 px, or
## 128 px for wide weapon swings, with the character centred.
class_name UnitSprites
extends RefCounted

const DIR: String = "res://assets/lpc/"
const TEAM: Dictionary = {"player": "blue", "ai": "red"}
## Animation -> [frames, rows, frame size].
const SPEC: Dictionary = {
	"walk": [9, 4, 64], "chop": [6, 4, 128], "mine": [6, 4, 128], "hammer": [6, 4, 128],
	"slash": [6, 4, 128], "shoot": [13, 4, 64], "hurt": [6, 1, 64],
}
const UP: int = 0
const LEFT: int = 1
const DOWN: int = 2
const RIGHT: int = 3
## Drawn so one sprite pixel is one screen pixel at the game's zoom
## (Game.ZOOM, 1.6; crisp pixel art): a character is about 50 screen pixels
## tall, slightly less than one cell, so soldiers in neighbouring cells do
## not overlap.
const SCALE: float = 1.0 / 1.6
## Where the feet are in a 64-px frame.
const FEET: Vector2 = Vector2(32, 59)

static var _tex: Dictionary = {}


static func tex(kind: String, faction: String, anim: String) -> Texture2D:
	var key: String = "%s_%s_%s" % [kind, TEAM[faction], anim]
	if not _tex.has(key):
		_tex[key] = load(DIR + key + ".png")
	return _tex[key]


## Loads every sheet now (at match start), so the first sword swing or bow
## shot of a battle does not stall while its texture loads.
static func preload_all() -> void:
	for kind: String in ["worker", "melee", "ranged"]:
		for faction: String in TEAM:
			for anim: String in SPEC:
				if has(kind, anim):
					tex(kind, faction, anim)


## True when this unit kind has this animation.
static func has(kind: String, anim: String) -> bool:
	match anim:
		"walk", "hurt":
			return true
		"chop", "mine", "hammer":
			return kind == "worker"
		"slash":
			return kind == "melee"
		"shoot":
			return kind == "ranged"
	return false


## The sheet row facing along `v` (dominant axis), or `fallback` if v is ~0.
static func dir_of(v: Vector2, fallback: int) -> int:
	if v.length_squared() < 0.0001:
		return fallback
	if absf(v.x) > absf(v.y):
		return RIGHT if v.x > 0.0 else LEFT
	return DOWN if v.y > 0.0 else UP


## Draws one frame with the character's feet at `feet`.
static func draw(ci: CanvasItem, feet: Vector2, kind: String, faction: String, anim: String, dir: int,
		frame: int, scale: float = SCALE, modulate: Color = Color.WHITE) -> void:
	var s: Array = SPEC[anim]
	var size: int = s[2]
	var row: int = dir if s[1] == 4 else 0
	var f: int = clampi(frame, 0, s[0] - 1)
	var anchor: Vector2 = FEET + Vector2(size - 64, size - 64) / 2.0
	var dst: Rect2 = Rect2(feet - anchor * scale, Vector2(size, size) * scale)
	ci.draw_texture_rect_region(tex(kind, faction, anim), dst, Rect2(f * size, row * size, size, size), modulate)


## The standing character facing down, its body about `height` tall,
## centred on `centre` (HUD icons and portraits).
static func icon(ci: CanvasItem, centre: Vector2, kind: String, faction: String, height: float, alpha: float = 1.0) -> void:
	# The figure spans roughly y 12 to 60 of its 64-px frame.
	var scale: float = height / 48.0
	draw(ci, centre + Vector2(0, 24.0 * scale), kind, faction, "walk", DOWN, 0, scale, Color(1, 1, 1, alpha))
