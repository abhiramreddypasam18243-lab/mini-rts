## The minimap (presentation layer; build step 11, decision D-43). A small
## picture of the whole map in the HUD's corner: terrain (grass, forest,
## rock, roads), the player's fog of war, resource nodes, buildings (enemy
## ones remembered as ghosts), the player's units and the enemy units they
## can see now, red pings where fighting is seen, and the camera's view as a
## frame. It shows only what the main view may show (all of it in the demo).
## Left click or drag moves the camera there; right click gives the selected
## units the same context order as a right click on that spot of the map.
class_name Minimap
extends Control

## The largest side of the map picture, in pixels.
const SIDE: float = 176.0
const GRASS: Color = Color("5b9a3f")
const FOREST: Color = Color("2f5f2b")
const ROCK: Color = Color("8e8b7f")
const ROAD: Color = Color("b8925c")
const UNEXPLORED: Color = Color(0.04, 0.05, 0.08, 0.82)
const EXPLORED: Color = Color(0.04, 0.05, 0.08, 0.5)

var game: Game
var _terrain_tex: ImageTexture
var _fog_img: Image
var _fog_tex: ImageTexture
var _fog_key: Vector2i = Vector2i(-1, -1)
var _dragging: bool = false
## Fights seen recently: world position and time.
var _pings: Array[Dictionary] = []


func setup(p_game: Game) -> void:
	game = p_game
	custom_minimum_size = picture_size()
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_build_terrain()


## The picture's size in pixels (the map's shape, longest side SIDE).
func picture_size() -> Vector2:
	var m: MapGrid = game.sim.map
	var k: float = SIDE / maxf(m.width, m.height)
	return Vector2(m.width, m.height) * k


## Pixels per map cell on the minimap.
func scale_px() -> float:
	return SIDE / maxf(game.sim.map.width, game.sim.map.height)


## World position (pixels) -> minimap position, and back.
func to_minimap(world: Vector2) -> Vector2:
	return world / Consts.PIXELS_PER_CELL * scale_px()


func to_world(local: Vector2) -> Vector2:
	var p: Vector2 = local.clamp(Vector2.ZERO, picture_size())
	return p / scale_px() * Consts.PIXELS_PER_CELL


func _build_terrain() -> void:
	var m: MapGrid = game.sim.map
	var t: TerrainLayer = game.terrain()
	var img: Image = Image.create(m.width, m.height, false, Image.FORMAT_RGBA8)
	for y: int in m.height:
		for x: int in m.width:
			var c: Vector2i = Vector2i(x, y)
			var col: Color = GRASS
			if not m.is_walkable(c):
				col = FOREST if t != null and t.is_forest(c) else ROCK
			elif t != null and t.is_worn(c):
				col = ROAD
			# A faint checker so the grass is not one flat colour.
			if (x + y) % 2 == 0:
				col = col.darkened(0.04)
			img.set_pixel(x, y, col)
	_terrain_tex = ImageTexture.create_from_image(img)
	_fog_img = Image.create(m.width, m.height, false, Image.FORMAT_RGBA8)
	_fog_tex = ImageTexture.create_from_image(_fog_img)


## Recolours the fog picture when the simulation's fog may have changed.
func _update_fog() -> void:
	var key: Vector2i = Vector2i(game.sim.fog_tick, game.sim.next_id)
	if key == _fog_key:
		return
	_fog_key = key
	var m: MapGrid = game.sim.map
	var g: PackedByteArray = game.sim.fog.grid(game.faction)
	for i: int in g.size():
		var col: Color = Color(0, 0, 0, 0)
		if not game.spectate:
			if g[i] == Fog.UNEXPLORED:
				col = UNEXPLORED
			elif g[i] == Fog.EXPLORED:
				col = EXPLORED
		_fog_img.set_pixel(i % m.width, i / m.width, col)
	_fog_tex.update(_fog_img)


## Remembers a fight the player can see, to ping it on the minimap.
func ping(world: Vector2) -> void:
	for p: Dictionary in _pings:
		if (p.at as Vector2).distance_to(world) < 64.0 and game.time - float(p.t) < 1.0:
			return
	_pings.append({"at": world, "t": game.time})


## Everything to mark on the minimap, as the main view would show it:
## [{kind: "node" | "building" | "ghost" | "unit", cell, size, faction, type}].
func markers() -> Array[Dictionary]:
	var sim: Simulation = game.sim
	var f: String = game.faction
	var out: Array[Dictionary] = []
	var mem: Dictionary = sim.fog.memory[f]
	if game.spectate:
		for id: int in sim.entities:
			var n: Entity = sim.entities[id]
			if n.is_node():
				out.append({"kind": "node", "cell": n.cell, "size": n.size, "faction": "", "type": n.kind})
	else:
		for id: int in mem:
			var g: Dictionary = mem[id]
			if g.faction == "":
				out.append({"kind": "node", "cell": g.cell, "size": Vector2i(1, 1), "faction": "", "type": g.kind})
			elif g.faction != f and not (sim.fog.any_visible(f, g.cell, g.size) and sim.entities.has(id)):
				out.append({"kind": "ghost", "cell": g.cell, "size": g.size, "faction": g.faction, "type": g.kind})
	for id: int in sim.entities:
		var e: Entity = sim.entities[id]
		var seen: bool = e.faction == f or game.spectate
		if e.is_building() and (seen or sim.fog.any_visible(f, e.cell, e.size)):
			out.append({"kind": "building", "cell": e.cell, "size": e.size, "faction": e.faction, "type": e.kind})
		elif e.is_unit() and (seen or sim.fog.is_visible(f, e.unit_cell())):
			out.append({"kind": "unit", "cell": e.unit_cell(), "size": Vector2i(1, 1), "faction": e.faction, "type": e.kind})
	return out


## Redrawn 10 times a second: the simulation changes 20 times a second, and
## a minimap needs no more.
const REDRAW: float = 0.1
var _since_draw: float = 0.0


func _process(delta: float) -> void:
	_since_draw += delta
	if game != null and (_since_draw >= REDRAW or _dragging):
		_since_draw = 0.0
		queue_redraw()


func _draw() -> void:
	if game == null:
		return
	_update_fog()
	var size_px: Vector2 = picture_size()
	var k: float = scale_px()
	draw_texture_rect(_terrain_tex, Rect2(Vector2.ZERO, size_px), false)
	var unit_px: float = maxf(k * 1.3, 3.0)
	for mk: Dictionary in markers():
		var r: Rect2 = Rect2(Vector2(mk.cell) * k, Vector2(mk.size) * k)
		match mk.kind:
			"node":
				draw_rect(r.grow(0.3), Palette.resource(mk.type))
			"building", "ghost":
				var col: Color = Palette.TEAM[mk.faction]
				if mk.kind == "ghost":
					col = col.darkened(0.35)
				draw_rect(r.grow(0.5), Color(0.05, 0.03, 0.02))
				draw_rect(r, col)
			"unit":
				var c: Vector2 = (Vector2(mk.cell) + Vector2(0.5, 0.5)) * k
				draw_rect(Rect2(c - Vector2(unit_px, unit_px) / 2.0, Vector2(unit_px, unit_px)), Palette.TEAM_LIGHT[mk.faction])
	draw_texture_rect(_fog_tex, Rect2(Vector2.ZERO, size_px), false)
	# Fights seen in the last 1.5 seconds: an expanding red ring.
	var keep: Array[Dictionary] = []
	for p: Dictionary in _pings:
		var age: float = game.time - float(p.t)
		if age > 1.5:
			continue
		keep.append(p)
		var a: float = 1.0 - age / 1.5
		draw_arc(to_minimap(p.at), 3.0 + 9.0 * (age / 1.5), 0.0, TAU, 20, Color(1.0, 0.3, 0.2, a), 1.5, true)
	_pings = keep
	# The camera's view.
	var view: Rect2 = game.view_rect()
	var vr: Rect2 = Rect2(to_minimap(view.position), view.size / Consts.PIXELS_PER_CELL * k).intersection(Rect2(Vector2.ZERO, size_px))
	draw_rect(vr, Color(1, 1, 1, 0.9), false, 1.5)


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_dragging = true
		game.look_at_world(to_world(mb.position))
		accept_event()
	elif mb != null and not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_dragging = false
		accept_event()
	elif mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		game.order_at(to_world(mb.position))
		accept_event()
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null and _dragging:
		game.look_at_world(to_world(mm.position))
		accept_event()
