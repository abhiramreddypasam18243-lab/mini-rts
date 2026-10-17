## Builds the animated unit sprite sheets from the Liberated Pixel Cup
## (LPC) character parts (decision D-41). Each unit is a stack of layers
## (shadow, body, clothes, armour, team tabard, helmet, weapon...) drawn in
## the generator's z order; team parts come in blue and red. Output: one
## PNG per unit, team and animation in assets/lpc/, frames in rows
## up / left / down / right (hurt has one row).
##   godot --headless --script res://tools/make_units.gd -- <LPC spritesheets dir> [out_dir]
## The LPC parts are from
## https://github.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator
## and every artist is credited in assets/lpc/CREDITS.md and ASSETS.md.
extends SceneTree

## Animations written for each unit: name -> [source animation, frames, rows, frame size].
const ANIMS: Dictionary = {
	"worker": {"walk": ["walk", 9, 4, 64], "chop": ["slash", 6, 4, 128], "mine": ["slash", 6, 4, 128], "hammer": ["slash", 6, 4, 128], "hurt": ["hurt", 6, 1, 64]},
	"melee": {"walk": ["walk", 9, 4, 64], "slash": ["slash", 6, 4, 128], "hurt": ["hurt", 6, 1, 64]},
	"ranged": {"walk": ["walk", 9, 4, 64], "shoot": ["shoot", 13, 4, 64], "hurt": ["hurt", 6, 1, 64]},
}
const TEAMS: Dictionary = {"player": "blue", "ai": "red"}
const TEAM_TINT: Dictionary = {"player": Color("4f8fe0"), "ai": Color("d9473a")}

var _src: String
var _missing: PackedStringArray = PackedStringArray()


## Layers per unit. Each: z (draw order), file pattern ({a} = source
## animation, {team} = blue/red), size of its frames (64 or 128), the
## animations it applies to ("" = all), and an optional tint ("team").
func _layers(unit: String) -> Array[Dictionary]:
	var common: Array[Dictionary] = [
		{"z": 0, "f": "shadow/adult/{a}.png"},
		{"z": 10, "f": "body/bodies/male/{a}.png"},
		{"z": 100, "f": "head/heads/human/male/{a}.png"},
	]
	match unit:
		"worker":
			common.append_array([
				{"z": 15, "f": "feet/shoes/basic/male/{a}.png"},
				{"z": 20, "f": "legs/pants/male/{a}.png", "tint": Color("7a5a3a")},
				{"z": 35, "f": "torso/clothes/longsleeve/longsleeve/male/{a}.png", "tint": Color("e9dcc0")},
				{"z": 55, "f": "torso/jacket/tabard/male/{a}/{team}.png"},
				{"z": 120, "f": "hair/plain/adult/{a}.png"},
				{"z": 140, "f": "tools/axe/male/walk.png", "only": "walk"},
				{"z": 9, "f": "tools/axe/bg.png", "only": "chop", "size": 128},
				{"z": 150, "f": "tools/axe/fg.png", "only": "chop", "size": 128},
				{"z": 9, "f": "tools/pickaxe/bg.png", "only": "mine", "size": 128},
				{"z": 150, "f": "tools/pickaxe/fg.png", "only": "mine", "size": 128},
				{"z": 9, "f": "tools/hammer/bg.png", "only": "hammer", "size": 128},
				{"z": 150, "f": "tools/hammer/fg.png", "only": "hammer", "size": 128},
			])
		"melee":
			common.append_array([
				{"z": 3, "f": "shield/heater/revised/paint/bg/{a}.png", "tint": "team"},
				{"z": 9, "f": "weapon/sword/arming/universal/bg/{a}/steel.png"},
				{"z": 8, "f": "weapon/sword/arming/attack_slash/bg/steel.png", "only": "slash", "size": 128},
				{"z": 15, "f": "feet/armour/plate/male/{a}.png"},
				{"z": 20, "f": "legs/armour/plate/male/{a}.png"},
				{"z": 60, "f": "torso/armour/plate/male/{a}.png"},
				{"z": 61, "f": "arms/armour/plate/male/{a}.png"},
				{"z": 65, "f": "torso/jacket/tabard/male/{a}/{team}.png"},
				{"z": 111, "f": "shield/heater/revised/paint/fg/{a}.png", "tint": "team"},
				{"z": 130, "f": "hat/helmet/armet/adult/{a}.png"},
				{"z": 140, "f": "weapon/sword/arming/universal/fg/{a}/steel.png"},
				{"z": 150, "f": "weapon/sword/arming/attack_slash/fg/steel.png", "only": "slash", "size": 128},
			])
		"ranged":
			common.append_array([
				{"z": -1, "f": "weapon/ranged/bow/normal/universal/background/{a}/medium.png"},
				{"z": -1, "f": "weapon/ranged/bow/normal/walk/background/medium.png", "only": "walk"},
				{"z": 8, "f": "quiver/{a}/quiver.png"},
				{"z": 15, "f": "feet/boots/basic/male/{a}.png"},
				{"z": 20, "f": "legs/pants/male/{a}.png", "tint": Color("5b4632")},
				{"z": 60, "f": "torso/armour/leather/male/{a}.png"},
				{"z": 65, "f": "torso/jacket/tabard/male/{a}/{team}.png"},
				{"z": 130, "f": "hat/cloth/hood/adult/{a}.png", "tint": "team_dark"},
				{"z": 140, "f": "weapon/ranged/bow/normal/universal/foreground/{a}/medium.png"},
				{"z": 141, "f": "weapon/ranged/bow/normal/walk/foreground/medium.png", "only": "walk"},
				{"z": 150, "f": "weapon/ranged/bow/arrow/{a}/arrow.png"},
			])
	common.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.z < y.z)
	return common


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_src = args[0]
	var out: String = args[1] if args.size() > 1 else "res://assets/lpc"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out) if out.begins_with("res://") else out)
	for unit: String in ANIMS:
		for faction: String in TEAMS:
			for anim: String in ANIMS[unit]:
				var img: Image = _compose(unit, faction, anim, ANIMS[unit][anim])
				var path: String = out.path_join("%s_%s_%s.png" % [unit, TEAMS[faction], anim])
				img.save_png(path)
				print("saved ", path, " ", img.get_size())
	for m: String in _missing:
		print("skipped (no such file): ", m)
	quit(0)


func _compose(unit: String, faction: String, anim: String, spec: Array) -> Image:
	var src_anim: String = spec[0]
	var frames: int = spec[1]
	var rows: int = spec[2]
	var size: int = spec[3]
	var img: Image = Image.create(frames * size, rows * size, false, Image.FORMAT_RGBA8)
	for layer: Dictionary in _layers(unit):
		if layer.has("only") and layer.only != anim:
			continue
		var rel: String = String(layer.f).replace("{a}", src_anim).replace("{team}", TEAMS[faction])
		var path: String = _src.path_join(rel)
		if not FileAccess.file_exists(path):
			if not _missing.has(rel):
				_missing.append(rel)
			continue
		var part: Image = Image.load_from_file(path)
		part.convert(Image.FORMAT_RGBA8)
		if layer.has("tint"):
			_tint(part, layer.tint, faction)
		var lsize: int = layer.get("size", 64)
		var off: int = (size - lsize) / 2
		for r: int in rows:
			for c: int in frames:
				var from: Rect2i = Rect2i(c * lsize, r * lsize, lsize, lsize)
				if from.end.x > part.get_width() or from.end.y > part.get_height():
					continue
				img.blend_rect(part, from, Vector2i(c * size + off, r * size + off))
	return img


## Multiplies a part's colours by a tint, keeping its shading.
func _tint(part: Image, tint: Variant, faction: String) -> void:
	var col: Color
	if tint is Color:
		col = tint
	elif tint == "team":
		col = TEAM_TINT[faction]
	else:
		col = TEAM_TINT[faction].darkened(0.35)
	for y: int in part.get_height():
		for x: int in part.get_width():
			var p: Color = part.get_pixel(x, y)
			if p.a > 0.0:
				var l: float = clampf(p.get_luminance() * 1.35, 0.0, 1.0)
				part.set_pixel(x, y, Color(col.r * l, col.g * l, col.b * l, p.a))
