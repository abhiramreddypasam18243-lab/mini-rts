## Renders the game's buildings, trees and rocks from Kenney's CC0 3D kits
## (Castle Kit, Fantasy Town Kit, Nature Kit; https://kenney.nl) into
## sprites for the 2D game (decision D-49): each prop is assembled in
## Godot's 3D engine, lit by a low sun with real shadows, and drawn by an
## orthographic camera at the game's 3/4 view; a transparent ground plane
## catches the shadow, so the sprite carries its own cast shadow.
##   godot --rendering-driver opengl3 --script res://tools/render_3d.gd -- <kits dir> [out dir] [survey name...]
## <kits dir> holds the kits' GLB folders as `castle/`, `town/`, `nature/`.
extends SceneTree

## Camera pitch (degrees below horizontal) and the sun's direction.
const PITCH: float = 52.0
## The sun shines from the left front: fronts lit, shadows to the right.
const SUN: Vector3 = Vector3(-54.0, -66.0, 0.0)
const PX_PER_UNIT: float = 64.0
const AMBIENT: float = 0.3
const SUN_ENERGY: float = 0.8
const SHADOW_ALPHA: float = 0.5

var _kits: String
var _cache: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_kits = args[0]
	var out: String = args[1] if args.size() > 1 else "res://assets/rendered"
	if args.size() > 2 and args[2] == "survey":
		await _survey(out, args.slice(3))
	elif args.size() > 2 and args[2] == "buildings":
		await _render_buildings(out)
	elif args.size() > 2 and args[2] == "props":
		await _render_props(out)
	elif args.size() > 2 and args[2] == "units":
		await _render_units(out, args.slice(3))
	elif args.size() > 2 and args[2] == "boxes":
		for name: String in args.slice(3):
			var m: Node3D = model(name)
			root.add_child(m)
			var b: AABB = aabb_of(m)
			print("%s pos %s size %s" % [name, b.position, b.size])
			m.queue_free()
	quit(0)


## Loads a model ("castle/tower-square-base" etc.) as a fresh Node3D.
func model(name: String) -> Node3D:
	var doc: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	var path: String = _kits.path_join(name + ".glb")
	var err: Error = doc.append_from_file(path, state)
	if err != OK:
		push_error("cannot load " + path)
		return Node3D.new()
	var scene: Node3D = doc.generate_scene(state) as Node3D
	# Models loaded from outside the project do not get their external
	# colour texture; give every material the kit's colour map.
	var kit: String = name.get_slice("/", 0)
	var cmap_path: String = _kits.path_join(kit).path_join("Textures/colormap.png")
	if FileAccess.file_exists(cmap_path):
		if not _cache.has(kit):
			_cache[kit] = ImageTexture.create_from_image(Image.load_from_file(cmap_path))
		for c: Node in scene.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = c
			for i: int in mi.mesh.get_surface_count():
				var mat: StandardMaterial3D = mi.mesh.surface_get_material(i) as StandardMaterial3D
				if mat != null and mat.albedo_texture == null:
					mat.albedo_texture = _cache[kit]
	return scene


## The bounding box of everything under `n` (in n's parent space).
func aabb_of(n: Node3D) -> AABB:
	var box: AABB = AABB()
	var first: bool = true
	for c: Node in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Renders `prop` (already built, standing on y = 0) to an image of
## `size_px`, with its cast shadow. The shadow is a planar projection: a
## copy of the prop flattened onto the ground along the sun's direction and
## drawn in black, then blurred and made half-transparent (exact for shadows
## on flat ground, and independent of the graphics driver's shadow maps).
func render(prop: Node3D, size_px: Vector2i, ortho_size: float, look_at: Vector3 = Vector3.ZERO) -> Image:
	var vp: SubViewport = SubViewport.new()
	vp.size = size_px
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.72, 0.78, 0.9)
	env.environment.ambient_light_energy = AMBIENT
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	vp.add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = SUN
	sun.light_energy = SUN_ENERGY
	sun.light_color = Color(1.0, 0.95, 0.85)
	vp.add_child(sun)
	# A fill light from the other side keeps the shaded faces readable.
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25.0, SUN.y + 150.0, 0.0)
	fill.light_energy = 0.22
	fill.light_color = Color(0.75, 0.82, 1.0)
	vp.add_child(fill)
	vp.add_child(prop)
	var shadow: Node3D = _flattened(prop, sun)
	vp.add_child(shadow)
	shadow.visible = false
	var cam: Camera3D = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = ortho_size
	cam.rotation_degrees = Vector3(-PITCH, 0, 0)
	cam.position = look_at + Vector3(0, sin(deg_to_rad(PITCH)), cos(deg_to_rad(PITCH))) * 30.0
	vp.add_child(cam)
	cam.current = true
	for i: int in 6:
		await process_frame
	var alone: Image = vp.get_texture().get_image()
	prop.visible = false
	shadow.visible = true
	for i: int in 4:
		await process_frame
	var mask: Image = vp.get_texture().get_image()
	vp.queue_free()
	return _with_shadow(alone, mask)


## A black copy of `prop` squashed onto the ground along the sun's rays.
func _flattened(prop: Node3D, sun: DirectionalLight3D) -> Node3D:
	var l: Vector3 = -(Basis.from_euler(sun.rotation_degrees * PI / 180.0).z)
	var holder: Node3D = Node3D.new()
	holder.transform = Transform3D(Basis(Vector3(1, 0, 0), Vector3(-l.x / l.y, 0.001, -l.z / l.y), Vector3(0, 0, 1)), Vector3(0, 0.002, 0))
	var copy: Node3D = prop.duplicate()
	holder.add_child(copy)
	var black: StandardMaterial3D = StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color.BLACK
	black.cull_mode = BaseMaterial3D.CULL_DISABLED
	for c: Node in copy.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).material_override = black
	return holder


## The prop over its soft shadow: the shadow mask is blurred, and drawn as
## translucent dark blue-black where the prop is not.
func _with_shadow(alone: Image, mask: Image) -> Image:
	alone.convert(Image.FORMAT_RGBA8)
	mask.convert(Image.FORMAT_RGBA8)
	var w: int = alone.get_width()
	var h: int = alone.get_height()
	var soft: PackedFloat32Array = _blur(mask, w, h, maxi(1, w / 90))
	var out: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y: int in h:
		for x: int in w:
			var p: Color = alone.get_pixel(x, y)
			var sh: Color = Color(0.03, 0.05, 0.08, soft[y * w + x] * SHADOW_ALPHA)
			var a: float = p.a + sh.a * (1.0 - p.a)
			if a <= 0.0:
				out.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var rgb: Color = (Color(p.r, p.g, p.b) * p.a + Color(sh.r, sh.g, sh.b) * sh.a * (1.0 - p.a)) / a
			out.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, a))
	return out


## A box blur (two passes) of the mask's alpha; values 0 to 1.
func _blur(mask: Image, w: int, h: int, r: int) -> PackedFloat32Array:
	var a: PackedFloat32Array = PackedFloat32Array()
	a.resize(w * h)
	for y: int in h:
		for x: int in w:
			a[y * w + x] = mask.get_pixel(x, y).a
	for pass_i: int in 2:
		var tmp: PackedFloat32Array = PackedFloat32Array()
		tmp.resize(w * h)
		for y: int in h:
			for x: int in w:
				var s: float = 0.0
				for k: int in range(-r, r + 1):
					s += a[y * w + clampi(x + k, 0, w - 1)]
				tmp[y * w + x] = s / (2 * r + 1)
		for y: int in h:
			for x: int in w:
				var s2: float = 0.0
				for k: int in range(-r, r + 1):
					s2 += tmp[clampi(y + k, 0, h - 1) * w + x]
				a[y * w + x] = s2 / (2 * r + 1)
	return a


## Survey: each model alone, with its size printed, in one contact sheet.
func _survey(out: String, names: PackedStringArray) -> void:
	var cols: int = 5
	var cell: int = 220
	var sheet: Image = Image.create(cols * cell, ((names.size() + cols - 1) / cols) * cell, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.36, 0.6, 0.3))
	for i: int in names.size():
		var m: Node3D = model(names[i])
		var holder: Node3D = Node3D.new()
		holder.add_child(m)
		var img: Image = await render(holder, Vector2i(cell, cell), 4.0, Vector3(0, 0.6, 0))
		var box: AABB = aabb_of(m) if m.is_inside_tree() else AABB()
		print("%s size %s" % [names[i], box.size])
		img.convert(Image.FORMAT_RGBA8)
		sheet.blend_rect(img, Rect2i(0, 0, cell, cell), Vector2i((i % cols) * cell, (i / cols) * cell))
	sheet.save_png(out.path_join("survey.png"))
	print("saved survey")


# --- the buildings ---------------------------------------------------------------

## Team colours for flags and banners (the units' blue and red).
const TEAM: Dictionary = {"blue": Color("3d8fd6"), "red": Color("d84a3a")}


## Places a model at a tile position, turned `turns` quarter turns about y.
func put(parent: Node3D, name: String, at: Vector3, turns: int = 0) -> Node3D:
	var m: Node3D = model(name)
	m.position = at
	m.rotation.y = turns * PI / 2.0
	parent.add_child(m)
	return m


## A plain coloured material (team flags and banners).
func flat(col: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	return m


func paint(n: Node3D, col: Color) -> void:
	for c: Node in n.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).material_override = flat(col)


## A square tower: base, `mids` middle storeys, a pointed roof.
func tower(parent: Node3D, at: Vector3, mids: int, windows: bool = true) -> void:
	put(parent, "castle/tower-square-base", at)
	for i: int in mids:
		put(parent, "castle/tower-square-mid-windows" if windows and i == mids - 1 else "castle/tower-square-mid", at + Vector3(0, 1.0 + i, 0))
	put(parent, "castle/tower-square-top-roof-high", at + Vector3(0, 1.0 + mids, 0))


## The HQ, 3 x 3 tiles centred on the origin: four corner towers joined by
## walls, a gate at the front (towards the camera), a tall keep in the
## middle with the team's banner.
func build_hq(team: String) -> Node3D:
	var root3: Node3D = Node3D.new()
	for c: Vector2i in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		tower(root3, Vector3(c.x, 0, c.y), 1)
	put(root3, "castle/wall", Vector3(0, 0, -1), 0)
	put(root3, "castle/wall", Vector3(-1, 0, 0), 1)
	put(root3, "castle/wall", Vector3(1, 0, 0), 1)
	put(root3, "castle/wall", Vector3(0, 0, 1), 0)
	put(root3, "castle/metal-gate", Vector3(0, 0, 1.36), 1)
	# The keep, a storey taller than the corner towers, flies the team flag.
	tower(root3, Vector3(0, 0, -0.15), 3)
	var flag: Node3D = put(root3, "castle/flag", Vector3(0.0, 5.25, -0.15), 0)
	paint(flag, TEAM[team])
	for c: Vector2i in [Vector2i(-1, -1), Vector2i(1, -1)]:
		var f: Node3D = put(root3, "castle/flag-pennant", Vector3(c.x, 3.25, c.y), 0)
		f.scale = Vector3(0.8, 0.8, 0.8)
		paint(f, TEAM[team])
	return root3


## The barracks, 2 x 2 tiles: a timber hall with a gabled roof, a door at
## the front, a chimney and the team's banners.
func build_barracks(team: String) -> Node3D:
	var root3: Node3D = Node3D.new()
	for tx: float in [-0.5, 0.5]:
		for tz: float in [-0.5, 0.5]:
			var at: Vector3 = Vector3(tx, 0, tz)
			put(root3, "town/planks", at)
			# Walls on the outer edges of the 2 x 2 block.
			if tx > 0:
				put(root3, "town/wall-wood", at, 0)
			else:
				put(root3, "town/wall-wood", at, 2)
			if tz > 0:
				put(root3, "town/wall-wood-door" if tx < 0 else "town/wall-wood", at, 3)
			else:
				put(root3, "town/wall-wood", at, 1)
			put(root3, "town/roof-gable", at + Vector3(0, 1.0, 0), 0)
	put(root3, "town/chimney", Vector3(0.4, 1.2, -0.5))
	for tx2: float in [-0.5, 0.5]:
		var b: Node3D = put(root3, "town/banner-red", Vector3(tx2 + 0.05, 0.05, 1.0), 3)
		paint(b, TEAM[team])
	put(root3, "castle/siege-ballista", Vector3(1.35, 0, 0.75), 1).scale = Vector3(0.6, 0.6, 0.6)
	return root3


## Turns the castle kit's blue roofs red (for the red team's HQ).
func _blue_to_red(img: Image) -> void:
	for y: int in img.get_height():
		for x: int in img.get_width():
			var c: Color = img.get_pixel(x, y)
			if c.a > 0.5 and c.s > 0.25 and c.h > 0.55 and c.h < 0.72:
				img.set_pixel(x, y, Color.from_hsv(0.0 + (c.h - 0.63) * 0.3, c.s * 0.95, c.v * 0.95, c.a))


## Renders every building for both teams into `out`, plus rendered.json:
## per sprite, its pixels per unit and the pixel where the footprint's
## centre (the origin) lands.
func _render_buildings(out: String) -> void:
	DirAccess.make_dir_recursive_absolute(out)
	var meta: Dictionary = {}
	var specs: Array = [
		["hq", Vector2i(6, 7), Vector3(0.9, 2.2, 0.4)],
		["barracks", Vector2i(4, 4), Vector3(0.6, 0.9, 0.3)],
	]
	for spec: Array in specs:
		for team: String in TEAM:
			var prop: Node3D = build_hq(team) if spec[0] == "hq" else build_barracks(team)
			var units: Vector2i = spec[1]
			var look: Vector3 = spec[2]
			var img: Image = await render(prop, units * int(PX_PER_UNIT), float(units.y), look)
			if spec[0] == "hq" and team == "red":
				_blue_to_red(img)
			var name: String = "%s_%s" % [spec[0], team]
			img.save_png(out.path_join(name + ".png"))
			# Where the origin lands: the camera looks at `look`; a point's
			# screen offset is its x, and its height along the camera's up.
			var p: float = deg_to_rad(PITCH)
			var up: Vector3 = Vector3(0, cos(p), -sin(p))
			var origin_px: Vector2 = Vector2(units) * PX_PER_UNIT / 2.0 + Vector2(-look.x, (look - Vector3.ZERO).dot(up)) * PX_PER_UNIT
			meta[name] = {"ppu": PX_PER_UNIT, "origin": [origin_px.x, origin_px.y], "depth": sin(p)}
			print("saved ", name)
	var f: FileAccess = FileAccess.open(out.path_join("rendered.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "  "))
	f.close()


## Trees and rocks for the map (one sprite each, with its shadow).
const PROPS: Dictionary = {
	"tree_a": "nature/tree_pineRoundA", "tree_b": "nature/tree_pineRoundC", "tree_c": "nature/tree_pineTallA_detailed",
	"tree_d": "nature/tree_pineRoundE", "tree_e": "nature/tree_pineTallC_detailed", "tree_f": "nature/tree_default",
	"tree_g": "nature/tree_oak", "tree_h": "nature/tree_fat",
	"rock_a": "nature/stone_tallA", "rock_b": "nature/stone_tallC", "rock_c": "nature/stone_tallE", "rock_d": "nature/stone_tallB",
}


func _render_props(out: String) -> void:
	DirAccess.make_dir_recursive_absolute(out)
	var meta: Dictionary = {}
	var p: float = deg_to_rad(PITCH)
	var up: Vector3 = Vector3(0, cos(p), -sin(p))
	for name: String in PROPS:
		var holder: Node3D = Node3D.new()
		var m: Node3D = model(PROPS[name])
		holder.add_child(m)
		var tree: bool = name.begins_with("tree")
		# Rocks are scaled up to fill about one cell.
		m.scale = Vector3(1.3, 1.3, 1.3) if tree else Vector3(1.15, 1.0, 1.15)
		var units: Vector2 = Vector2(2.25, 2.75) if tree else Vector2(2.0, 2.0)
		var look: Vector3 = Vector3(0.45, 0.95 if tree else 0.5, 0.0)
		var img: Image = await render(holder, Vector2i(units * PX_PER_UNIT), units.y, look)
		img.save_png(out.path_join(name + ".png"))
		var origin_px: Vector2 = units * PX_PER_UNIT / 2.0 + Vector2(-look.x, look.dot(up)) * PX_PER_UNIT
		meta[name] = {"ppu": PX_PER_UNIT, "origin": [origin_px.x, origin_px.y]}
		print("saved ", name)
	var f: FileAccess = FileAccess.open(out.path_join("props.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "  "))
	f.close()


# --- units (decision D-50) -------------------------------------------------------

## Unit kinds: the KayKit character, the meshes kept (weapons, shields), the
## meshes painted in the team colour, and the animations to render:
## sheet name -> [KayKit animation, frames].
const UNITS: Dictionary = {
	"worker": {"model": "kay/Barbarian", "keep": ["1H_Axe"], "team": ["Barbarian_Cape"],
		"anims": {"idle": ["Idle", 1], "walk": ["Walking_A", 8], "chop": ["1H_Melee_Attack_Chop", 8], "hurt": ["Death_A", 8]}},
	"melee": {"model": "kay/Knight", "keep": ["1H_Sword", "Badge_Shield"], "team": ["Knight_Cape", "Badge_Shield"],
		"anims": {"idle": ["Idle", 1], "walk": ["Walking_A", 8], "slash": ["1H_Melee_Attack_Slice_Diagonal", 8], "hurt": ["Death_A", 8]}},
	"ranged": {"model": "kay/Rogue_Hooded", "keep": ["2H_Crossbow"], "team": ["Rogue_Cape"],
		"anims": {"idle": ["2H_Ranged_Aiming", 1], "walk": ["Walking_A", 8], "shoot": ["2H_Ranged_Shoot", 8], "hurt": ["Death_A", 8]}},
}
## Weapon and accessory meshes (everything else is the body).
const GEAR: Array[String] = ["1H_Sword_Offhand", "Badge_Shield", "Rectangle_Shield", "Round_Shield", "Spike_Shield", "1H_Sword",
	"2H_Sword", "1H_Axe_Offhand", "Barbarian_Round_Shield", "1H_Axe", "2H_Axe", "Mug", "Knife_Offhand", "1H_Crossbow",
	"2H_Crossbow", "Knife", "Throwable"]
const UNIT_FRAME: int = 96
const UNIT_ORTHO: float = 3.4
const DIRS: int = 8


## Renders every unit sheet: rows are the 8 directions (row k faces
## k * 45 degrees clockwise from facing the camera: S, SE, E, NE, N, NW, W,
## SW), columns the frames. Writes units.json with the sheets' layout.
func _render_units(out: String, only: PackedStringArray) -> void:
	DirAccess.make_dir_recursive_absolute(out)
	var meta: Dictionary = {}
	var p: float = deg_to_rad(PITCH)
	var up: Vector3 = Vector3(0, cos(p), -sin(p))
	var look: Vector3 = Vector3(0, 0.95, 0)
	var ppu: float = UNIT_FRAME / UNIT_ORTHO
	var origin_px: Vector2 = Vector2(UNIT_FRAME, UNIT_FRAME) / 2.0 + Vector2(0, look.dot(up)) * ppu
	meta["_frame"] = {"size": UNIT_FRAME, "ppu": ppu, "origin": [origin_px.x, origin_px.y], "dirs": DIRS}
	for kind: String in UNITS:
		if not only.is_empty() and not only.has(kind):
			continue
		for team: String in TEAM:
			var spec: Dictionary = UNITS[kind]
			var studio: Dictionary = await _studio(spec, team, look)
			for anim: String in spec.anims:
				var a: Array = spec.anims[anim]
				var frames: int = a[1]
				var sheet: Image = Image.create(UNIT_FRAME * frames, UNIT_FRAME * DIRS, false, Image.FORMAT_RGBA8)
				var player: AnimationPlayer = studio.player
				var length: float = player.get_animation(a[0]).length
				for d: int in DIRS:
					studio.body.rotation.y = d * TAU / DIRS
					for f: int in frames:
						# Loops sample evenly; one-shot animations end on their last pose.
						var t: float = length * float(f) / float(frames if anim == "walk" else maxi(frames - 1, 1))
						if frames == 1:
							t = 0.0
						var img: Image = await _shoot(studio, a[0], t)
						sheet.blend_rect(img, Rect2i(0, 0, UNIT_FRAME, UNIT_FRAME), Vector2i(f * UNIT_FRAME, d * UNIT_FRAME))
				var name: String = "%s_%s_%s" % [kind, team, anim]
				sheet.save_png(out.path_join(name + ".png"))
				meta[name] = {"frames": frames}
				print("saved ", name)
			studio.vp.queue_free()
	var path: String = out.path_join("units.json")
	if FileAccess.file_exists(path):
		var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if old is Dictionary:
			(old as Dictionary).merge(meta, true)
			meta = old
	var fo: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	fo.store_string(JSON.stringify(meta, "  "))
	fo.close()


## One lit scene for a unit: viewport, lights, camera and the character.
func _studio(spec: Dictionary, team: String, look: Vector3) -> Dictionary:
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(UNIT_FRAME, UNIT_FRAME)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.72, 0.78, 0.9)
	env.environment.ambient_light_energy = AMBIENT + 0.1
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	vp.add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = SUN
	sun.light_energy = SUN_ENERGY
	sun.light_color = Color(1.0, 0.95, 0.85)
	vp.add_child(sun)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25.0, SUN.y + 150.0, 0.0)
	fill.light_energy = 0.3
	fill.light_color = Color(0.75, 0.82, 1.0)
	vp.add_child(fill)
	var holder: Node3D = Node3D.new()
	vp.add_child(holder)
	var body: Node3D = model(spec.model)
	holder.add_child(body)
	for c: Node in body.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		if GEAR.has(String(mi.name)) and not (spec.keep as Array).has(String(mi.name)):
			mi.visible = false
		elif (spec.team as Array).has(String(mi.name)):
			var m: StandardMaterial3D = StandardMaterial3D.new()
			m.albedo_color = TEAM[team]
			m.roughness = 0.85
			mi.material_override = m
	var cam: Camera3D = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = UNIT_ORTHO
	cam.rotation_degrees = Vector3(-PITCH, 0, 0)
	cam.position = look + Vector3(0, sin(deg_to_rad(PITCH)), cos(deg_to_rad(PITCH))) * 30.0
	vp.add_child(cam)
	cam.current = true
	var player: AnimationPlayer = body.find_children("*", "AnimationPlayer", true, false)[0]
	for i: int in 3:
		await process_frame
	return {"vp": vp, "holder": holder, "body": body, "player": player, "sun": sun}


## One frame: the posed character, then its flattened black shadow.
func _shoot(studio: Dictionary, anim: String, t: float) -> Image:
	var player: AnimationPlayer = studio.player
	var holder: Node3D = studio.holder
	player.play(anim)
	player.seek(t, true)
	player.pause()
	holder.transform = Transform3D.IDENTITY
	_set_black(holder, false)
	for i: int in 3:
		await process_frame
	var alone: Image = (studio.vp as SubViewport).get_texture().get_image()
	var l: Vector3 = -(Basis.from_euler((studio.sun as DirectionalLight3D).rotation_degrees * PI / 180.0).z)
	holder.transform = Transform3D(Basis(Vector3(1, 0, 0), Vector3(-l.x / l.y, 0.001, -l.z / l.y), Vector3(0, 0, 1)), Vector3(0, 0.002, 0))
	_set_black(holder, true)
	for i: int in 3:
		await process_frame
	var mask: Image = (studio.vp as SubViewport).get_texture().get_image()
	holder.transform = Transform3D.IDENTITY
	_set_black(holder, false)
	return _with_shadow(alone, mask)


var _black: StandardMaterial3D
var _saved: Dictionary = {}


func _set_black(n: Node3D, on: bool) -> void:
	if _black == null:
		_black = StandardMaterial3D.new()
		_black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_black.albedo_color = Color.BLACK
		_black.cull_mode = BaseMaterial3D.CULL_DISABLED
	for c: Node in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		if on:
			_saved[mi.get_instance_id()] = mi.material_override
			mi.material_override = _black
		elif _saved.has(mi.get_instance_id()):
			mi.material_override = _saved[mi.get_instance_id()]
