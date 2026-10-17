## One match on screen (presentation layer). It owns the Simulation, runs it
## at 20 ticks per second from real time, turns mouse and keys into commands
## (SPEC 9), and lets the layers and the HUD draw what the player may see.
## It never changes simulation state except through sim.submit().
##
## Controls: left click select · left drag box-select · right click context
## order · B then click place a barracks · Q / W / E train at the selected
## building · Esc cancel or clear · WASD or screen edges pan. W trains a melee
## soldier when a building is selected and pans otherwise (decision D-32).
class_name Game
extends Node2D

signal restart_requested
signal menu_requested

const C: float = Consts.PIXELS_PER_CELL
const DRAG_THRESHOLD: float = 6.0
## Extra room so the map's edges can be scrolled out from under the HUD bars.
const TOP_PAD: float = 70.0
const BOTTOM_PAD: float = 190.0
## The world is drawn zoomed in so the sprites read well (screen pixels per world pixel).
const ZOOM: float = 1.35

var settings: Dictionary = {}
var faction: String = "player"
var sim: Simulation
var clock: TickClock = TickClock.new()
var selection: Selection = Selection.new()
var messages: MessageLog = MessageLog.new()
## Real seconds since the match started (animations only).
var time: float = 0.0
var fx: Array[Dictionary] = []
var hover_id: int = 0
var placing: bool = false
var dragging: bool = false
var drag_from: Vector2 = Vector2.ZERO
var hud: Hud
var camera: Camera2D
## The opponent: the enemy AI, driven through its firewall (build step 8).
var opponent: AIController
## Demo mode (AC-93): a recorded replay plays back; the player only watches.
const DEMO_PATH: String = "res://data/replays/demo.replay.jsonl"
const DEMO_SPEED: float = 2.0
var demo: bool = false
## Draw every unit and building, ignoring fog (demo only; drawing only).
var spectate: bool = false
var demo_policies: Dictionary = {}
var _demo_cmds: Array = []
var _demo_next: int = 0
var _last_manual_pan: float = -100.0
## Where and when the last attack happened (the demo camera follows it).
var _action_pos: Vector2 = Vector2.ZERO
var _action_time: float = -100.0

var _terrain: TerrainLayer
var _world: WorldLayer
var _fog: FogLayer
var _overlay: OverlayLayer
var _prev_pos: Dictionary = {}
var _hit_time: Dictionary = {}
var _pressed: bool = false
var _press_screen: Vector2 = Vector2.ZERO
var _trained: int = 0
var _lost: int = 0
var _result_shown: bool = false


func setup(p_settings: Dictionary) -> void:
	settings = p_settings


static func load_map(p_settings: Dictionary) -> MapGrid:
	if p_settings.get("map", "generated") == "tutorial":
		return MapGrid.load_file("res://data/maps/tutorial.json").map
	return MapGenerator.generate(int(p_settings.get("seed", 1))).map


func _ready() -> void:
	if settings.get("mode", "") == "demo":
		var r: Dictionary = Replay.parse(FileAccess.get_file_as_string(DEMO_PATH))
		demo = true
		spectate = true
		demo_policies = r.header.ai_configs
		_demo_cmds = r.commands
		sim = Simulation.new(Replay.map_for(str(r.header.map)), int(r.header.seed), {"max_ticks": int(r.header.max_ticks)})
	else:
		sim = Simulation.new(load_map(settings), int(settings.get("seed", 1)), {})
		opponent = AIController.new("ai", AIConfig.preset(str(settings.get("ai_policy", "balanced"))))
	_terrain = TerrainLayer.new()
	add_child(_terrain)
	_terrain.setup(sim.map)
	_world = WorldLayer.new()
	_world.game = self
	add_child(_world)
	_fog = FogLayer.new()
	add_child(_fog)
	_fog.setup(sim, faction)
	_fog.visible = not spectate
	_overlay = OverlayLayer.new()
	_overlay.game = self
	add_child(_overlay)
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	camera.zoom = Vector2(ZOOM, ZOOM)
	var hq: Entity = sim.entity(sim.hq_of(faction))
	camera.position = (Vector2(hq.cell) + Vector2(hq.size) / 2.0) * C
	_clamp_camera()
	hud = Hud.new()
	hud.game = self
	add_child(hud)
	_snapshot_positions()
	if demo:
		messages.add("Demo: a recorded match plays back. WASD pans; the camera follows the action.", time, "info")
	else:
		messages.add("Gather wood and gold, build a barracks, destroy the enemy HQ.", time, "info")


func _process(delta: float) -> void:
	time += delta
	if sim.match_result == "":
		advance_ticks(clock.advance(delta * (DEMO_SPEED if demo else 1.0)))
	_pan(delta)
	if demo:
		_follow_action(delta)
	hover_id = Selection.pick(sim, faction, _to_milli(get_global_mouse_position()))
	selection.prune(sim)
	_fog.refresh(delta)
	fx = fx.filter(func(e: Dictionary) -> bool: return time - e.t0 < e.life)
	_world.queue_redraw()
	_overlay.queue_redraw()
	hud.refresh()


## Runs `n` simulation ticks and turns their events into messages and effects.
func advance_ticks(n: int) -> void:
	for i: int in n:
		if sim.match_result != "":
			break
		_snapshot_positions()
		if demo:
			while _demo_next < _demo_cmds.size() and int(_demo_cmds[_demo_next].tick) == sim.tick:
				Replay.apply(sim, _demo_cmds[_demo_next])
				_demo_next += 1
		else:
			opponent.before_step(sim)
		sim.step()
		_consume(sim.take_events())
	if sim.match_result != "" and not _result_shown:
		_result_shown = true
		placing = false
		hud.show_result(sim.match_result, {"tick": sim.tick, "wood": sim.bank.deposited[faction].wood,
			"gold": sim.bank.deposited[faction].gold, "trained": _trained, "lost": _lost})


func _snapshot_positions() -> void:
	_prev_pos.clear()
	for id: int in sim.entities:
		var e: Entity = sim.entities[id]
		if e.is_unit():
			_prev_pos[id] = e.pos


## A unit's drawing position, smoothed between the last two ticks.
func draw_pos(e: Entity) -> Vector2:
	var now: Vector2 = Vector2(e.pos) * C / 1000.0
	if not _prev_pos.has(e.id):
		return now
	var before: Vector2 = Vector2(_prev_pos[e.id]) * C / 1000.0
	return before.lerp(now, clock.fraction())


## 1 just after an entity is hit, fading to 0.
func flash(id: int) -> float:
	if not _hit_time.has(id):
		return 0.0
	return clampf(1.0 - (time - _hit_time[id]) / 0.14, 0.0, 1.0)


func _consume(events: Array[Dictionary]) -> void:
	for ev: Dictionary in events:
		match ev.type:
			"message", "completed":
				if ev.get("faction", "") == faction:
					messages.add(HudModel.message_text(ev), time, "good" if ev.type == "completed" else "warn")
			"trained":
				if ev.faction == faction:
					_trained += 1
					var u: Entity = sim.entity(ev.entity_id)
					messages.add("%s ready" % HudModel.KIND_NAMES[u.kind] if u != null else "Unit ready", time, "good")
			"deposit":
				if ev.faction == faction:
					var w: Entity = sim.entity(ev.entity_id)
					if w != null:
						_add_fx({"type": "float", "a": draw_pos(w) + Vector2(0, -12), "text": "+%d" % ev.amount,
							"color": Palette.resource(ev.resource), "life": 0.9})
			"attack":
				var a: Entity = sim.entity(ev.attacker)
				var t: Entity = sim.entity(ev.target)
				if a == null or t == null or not (_seen(a) or _seen(t)):
					continue
				_hit_time[t.id] = time
				var tp: Vector2 = draw_pos(t) if t.is_unit() else (Vector2(t.cell) + Vector2(t.size) / 2.0) * C
				_action_pos = tp if time - _action_time > 2.0 else _action_pos.lerp(tp, 0.2)
				_action_time = time
				if a.kind == "ranged":
					_add_fx({"type": "tracer", "a": draw_pos(a), "b": tp, "faction": a.faction, "life": 0.22})
				else:
					_add_fx({"type": "slash", "b": tp, "life": 0.18})
			"destroyed":
				var center: Vector2 = Vector2(ev.pos) * C / 1000.0 if ev.kind in Entity.UNIT_KINDS \
					else (Vector2(ev.cell) + Vector2(ev.size) / 2.0) * C
				var cell: Vector2i = Vector2i(center / C)
				if ev.faction == faction or sim.fog.is_visible(faction, cell):
					if ev.faction != "":
						_add_fx({"type": "puff", "a": center, "color": Palette.TEAM[ev.faction], "life": 0.55})
				if ev.faction == faction and ev.kind in Entity.UNIT_KINDS:
					_lost += 1
					messages.add("%s lost" % HudModel.KIND_NAMES[ev.kind], time, "bad")
				elif ev.faction == faction:
					messages.add("%s destroyed" % HudModel.KIND_NAMES[ev.kind], time, "bad")


func _seen(e: Entity) -> bool:
	if e.faction == faction:
		return true
	return sim.fog.is_visible(faction, e.unit_cell()) if e.is_unit() else sim.fog.any_visible(faction, e.cell, e.size)


func _add_fx(e: Dictionary) -> void:
	e.t0 = time
	fx.append(e)


# --- commands from the player -------------------------------------------------

## Submits a command; a rejection is shown as a message. In the demo the
## player only watches: nothing is submitted, so the replay stays exact.
func issue(cmd: Dictionary) -> String:
	if demo:
		return "demo"
	var r: String = sim.submit(cmd)
	if r != "ok":
		messages.add(HudModel.MESSAGES.get(r, r), time, "warn")
	return r


func train(kind: String) -> void:
	var b: Entity = selection.building(sim)
	if b != null and b.faction == faction and kind in Simulation.TRAINS[b.kind]:
		issue(Commands.train(faction, b.id, kind))


func cancel_train(index: int) -> void:
	var b: Entity = selection.building(sim)
	if b != null and index < b.queue.size():
		issue(Commands.cancel_train(faction, b.id, index))


func start_placing() -> void:
	if demo:
		return
	if selection.of_kind(sim, func(e: Entity) -> bool: return e.kind == "worker").is_empty():
		messages.add("Select a worker first", time, "warn")
		return
	placing = true


func select_only(id: int) -> void:
	selection.selected = [id]
	selection.inspected = id


## Top-left cell of the barracks footprint, centred on the mouse.
func placement_anchor() -> Vector2i:
	var size: Vector2 = Vector2(sim.stats["barracks"].footprint)
	var m: Vector2 = get_global_mouse_position() / C - size / 2.0 + Vector2(0.5, 0.5)
	return Vector2i(floori(m.x), floori(m.y))


func _try_place() -> void:
	var anchor: Vector2i = placement_anchor()
	var workers: Array[int] = selection.of_kind(sim, func(e: Entity) -> bool: return e.kind == "worker")
	if workers.is_empty():
		placing = false
		return
	# The selected worker nearest to the site builds it.
	var target: Vector2i = MapGrid.cell_center(anchor)
	workers.sort_custom(func(a: int, b: int) -> bool:
		var da: Vector2i = sim.entity(a).pos - target
		var db: Vector2i = sim.entity(b).pos - target
		return da.length_squared() < db.length_squared() or (da.length_squared() == db.length_squared() and a < b))
	if issue(Commands.build(faction, workers[0], "barracks", anchor)) == "ok":
		placing = false
		_add_fx({"type": "marker", "a": (Vector2(anchor) + Vector2.ONE) * C, "color": Palette.ACCENT, "life": 0.5})


# --- input ------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if sim == null or sim.match_result != "":
		return
	var mouse: Vector2 = get_global_mouse_position()
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if placing:
					_try_place()
					return
				_pressed = true
				dragging = false
				_press_screen = mb.position
				drag_from = mouse
			elif _pressed:
				_pressed = false
				if dragging:
					selection.box(sim, faction, _to_milli(drag_from), _to_milli(mouse))
				else:
					selection.click(sim, faction, _to_milli(mouse))
				dragging = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if placing:
				placing = false
				return
			_right_click(mouse)
	elif event is InputEventMouseMotion:
		if _pressed and not placing and (event as InputEventMouseMotion).position.distance_to(_press_screen) > DRAG_THRESHOLD:
			dragging = true
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_B:
				start_placing()
			KEY_Q:
				train("worker")
			KEY_W:
				train("melee")
			KEY_E:
				train("ranged")
			KEY_F3:
				hud.toggle_fps()
			KEY_ESCAPE:
				if placing:
					placing = false
				else:
					selection.clear()


func _right_click(mouse: Vector2) -> void:
	var cmds: Array[Dictionary] = selection.context_commands(sim, faction, _to_milli(mouse))
	for cmd: Dictionary in cmds:
		var r: String = issue(cmd)
		if r == "ok" or r == "no_path":
			var col: Color = {"move": Palette.GOOD, "harvest": Palette.GOLD, "attack": Palette.BAD}[cmd.command]
			_add_fx({"type": "marker", "a": mouse, "color": col, "life": 0.45})


func _to_milli(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x * 1000.0 / C), floori(p.y * 1000.0 / C))


# --- camera -----------------------------------------------------------------------

func _pan(delta: float) -> void:
	var dir: Vector2 = Vector2.ZERO
	var building_selected: bool = selection.building(sim) != null
	if Input.is_key_pressed(KEY_A):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		dir.x += 1
	if Input.is_key_pressed(KEY_S):
		dir.y += 1
	if Input.is_key_pressed(KEY_W) and not building_selected:
		dir.y -= 1
	var vp: Viewport = get_viewport()
	var mouse: Vector2 = vp.get_mouse_position()
	if not _pressed and vp.get_visible_rect().has_point(mouse) and DisplayServer.window_is_focused():
		dir += CameraMath.edge_direction(mouse, vp.get_visible_rect().size)
	if dir != Vector2.ZERO:
		camera.position += dir.normalized() * CameraMath.SPEED * delta
		_clamp_camera()
		_last_manual_pan = time


## Demo camera, unless the viewer panned in the last 3 seconds: glides to
## where fighting happened in the last 2 seconds, else to the main blue
## army (median position, so one scout far away does not pull the camera
## into empty ground), else to the blue base.
func _follow_action(delta: float) -> void:
	if time - _last_manual_pan < 3.0:
		return
	var xs: Array[float] = []
	var ys: Array[float] = []
	for id: int in sim.entities:
		var e: Entity = sim.entities[id]
		if e.faction == faction and e.is_soldier():
			var p: Vector2 = draw_pos(e)
			xs.append(p.x)
			ys.append(p.y)
	var target: Vector2
	if time - _action_time < 2.0:
		target = _action_pos
	elif not xs.is_empty():
		xs.sort()
		ys.sort()
		target = Vector2(xs[xs.size() / 2], ys[ys.size() / 2])
	else:
		var hq: Entity = sim.entity(sim.hq_of(faction))
		if hq == null:
			return
		target = (Vector2(hq.cell) + Vector2(hq.size) / 2.0) * C
	camera.position = camera.position.lerp(target, clampf(delta * 1.5, 0.0, 1.0))
	_clamp_camera()


func _clamp_camera() -> void:
	# The view and the HUD paddings in world units (the camera is zoomed in).
	var view: Vector2 = get_viewport_rect().size / ZOOM
	var map_px: Vector2 = Vector2(sim.map.width, sim.map.height) * C
	var top: float = TOP_PAD / ZOOM
	var padded: Vector2 = map_px + Vector2(0, top + BOTTOM_PAD / ZOOM)
	camera.position = CameraMath.clamp_center(camera.position + Vector2(0, top), view, padded) - Vector2(0, top)
