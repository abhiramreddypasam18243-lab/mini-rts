## Unit sprites (presentation layer, decision D-50): pre-rendered 3D
## characters from Kay Lousberg's CC0 KayKit Adventurers pack (Barbarian
## worker, Knight, hooded Rogue with a crossbow), rendered by
## tools/render_3d.gd in 8 directions with their own soft shadows, like the
## units of Age of Empires II. Each sheet is one animation: rows are the 8
## directions (row k faces k * 45 degrees clockwise from facing the camera:
## S, SE, E, NE, N, NW, W, SW), columns the frames. The callers still speak
## the frame counts of the earlier 2D sheets (D-41); `draw` maps them.
class_name UnitSprites
extends RefCounted

const DIR: String = "res://assets/units3d/"
const TEAM: Dictionary = {"player": "blue", "ai": "red"}
## Frame counts the callers use (the earlier sheets): walk frame 0 is
## standing, 1 to 8 the cycle; a shot's useful frames are 4 to 12.
const SPEC: Dictionary = {
	"walk": [9], "chop": [6], "mine": [6], "hammer": [6], "slash": [6], "shoot": [13], "hurt": [6],
}
const DIRS: int = 8
const DOWN: int = 0
const RIGHT: int = 2
const UP: int = 4
const LEFT: int = 6
## The game's default scale (kept from D-42: units are drawn at this scale
## in the world; 1.0 draws them 1.6 times larger, as the menu does).
const SCALE: float = 1.0 / 1.6
## World pixels per 3D unit (a 3D character is about 1.6 units tall, so
## about 28 world pixels; D-56 made units about 30 % larger so they read
## clearly at the default zoom).
const WORLD_PER_UNIT: float = 17.5

static var _tex: Dictionary = {}
static var _meta: Dictionary = {}


static func meta() -> Dictionary:
	if _meta.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "units.json"))
		_meta = d if d is Dictionary else {"_frame": {"size": 96, "ppu": 28.2, "origin": [48, 64.5], "dirs": 8}}
	return _meta


static func tex(kind: String, faction: String, anim: String) -> Texture2D:
	var key: String = "%s_%s_%s" % [kind, TEAM[faction], anim]
	if not _tex.has(key):
		_tex[key] = load(DIR + key + ".png")
	return _tex[key]


## Loads every sheet now (at match start), so the first sword swing or bow
## shot of a battle does not stall while its texture loads.
static func preload_all() -> void:
	for kind: String in ["worker", "melee", "ranged", "cavalry"]:
		for faction: String in TEAM:
			for anim: String in ["idle", "walk", "hurt", _attack(kind)]:
				tex(kind, faction, anim)


## The attack (or work) sheet of a unit kind.
static func _attack(kind: String) -> String:
	return {"worker": "chop", "melee": "slash", "ranged": "shoot", "cavalry": "slash"}[kind]


## True when this unit kind has this animation.
static func has(kind: String, anim: String) -> bool:
	match anim:
		"walk", "hurt":
			return true
		"chop", "mine", "hammer":
			return kind == "worker"
		"slash":
			return kind == "melee" or kind == "cavalry"
		"shoot":
			return kind == "ranged"
	return false


## The direction (0 to 7) facing along `v` (screen), or `fallback` if v is ~0.
static func dir_of(v: Vector2, fallback: int) -> int:
	if v.length_squared() < 0.0001:
		return fallback
	return posmod(int(round(atan2(v.x, v.y) / (PI / 4.0))), DIRS)


## Maps a caller's animation and frame to a sheet and a frame of it.
static func _resolve(kind: String, anim: String, frame: int) -> Array:
	match anim:
		"walk":
			if frame <= 0:
				return ["idle", 0]
			return ["walk", (frame - 1) % 8]
		"chop", "mine", "hammer":
			return ["chop", clampi(frame * 8 / 6, 0, 7)]
		"slash":
			return ["slash", clampi(frame * 8 / 6, 0, 7)]
		"shoot":
			return ["shoot", clampi((frame - 4) * 8 / 9, 0, 7)]
		"hurt":
			return ["hurt", clampi(frame * 8 / 6, 0, 7)]
	return ["idle", 0]


## Draws one frame with the character's feet at `feet`.
static func draw(ci: CanvasItem, feet: Vector2, kind: String, faction: String, anim: String, dir: int,
		frame: int, scale: float = SCALE, modulate: Color = Color.WHITE) -> void:
	var r: Array = _resolve(kind, anim, frame)
	var f: Dictionary = meta()._frame
	var size: float = f.size
	var k: float = WORLD_PER_UNIT / float(f.ppu) * (scale / SCALE)
	var origin: Vector2 = Vector2(f.origin[0], f.origin[1])
	var dst: Rect2 = Rect2(feet - origin * k, Vector2(size, size) * k)
	var row: int = posmod(dir, DIRS)
	ci.draw_texture_rect_region(tex(kind, faction, r[0]), dst, Rect2(r[1] * size, row * size, size, size), modulate)


## The standing character facing the viewer, its body about `height` tall,
## centred on `centre` (HUD icons and portraits).
static func icon(ci: CanvasItem, centre: Vector2, kind: String, faction: String, height: float, alpha: float = 1.0) -> void:
	# A character is about 1.6 units tall.
	var scale: float = height / (1.6 * WORLD_PER_UNIT) * SCALE
	draw(ci, centre + Vector2(0, height * 0.5), kind, faction, "walk", DOWN, 0, scale, Color(1, 1, 1, alpha))
