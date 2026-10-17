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
const ZOOM: float = 1.6

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
## True after F: the next left click is an attack-move destination (D-44).
var aiming: bool = false
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
## The AC-77 frame-rate benchmark, when this match is one.
var bench: Benchmark
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
## Particles, arrows, rubble and floating numbers (drawing only, D-39, D-41).
var effects: Effects = Effects.new()
## Per unit: when it last attacked and towards where (for its lunge).
var attack_info: Dictionary = {}
## Screen shake strength, 0 to 1, decaying.
var _trauma: float = 0.0
var _fx_nodes: Array[FxDraw] = []
## A unit's last facing (a UnitSprites direction), kept by the world layer.
var facing: Dictionary = {}
## When each building last showed a damage number.
var _number_time: Dictionary = {}
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
		if settings.get("mode", "") == "bench":
			spectate = true
		else:
			opponent = AIController.new("ai", AIConfig.preset(str(settings.get("ai_policy", "balanced"))))
	UnitSprites.preload_all()
	_terrain = TerrainLayer.new()
	add_child(_terrain)
	_terrain.setup(sim.map)
	_world = WorldLayer.new()
	_world.game = self
	add_child(_world)
	for mode: String in ["normal", "add", "text"]:
		var n: FxDraw = FxDraw.new()
		n.game = self
		n.mode = mode
		if mode == "add":
			var m: CanvasItemMaterial = CanvasItemMaterial.new()
			m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			n.material = m
		add_child(n)
		_fx_nodes.append(n)
	add_child(_terrain.make_clouds())
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
	add_child(PostFx.new())
	hud = Hud.new()
	hud.game = self
	add_child(hud)
	_snapshot_positions()
	if spectate and not demo:
		bench = Benchmark.new()
		bench.setup(self)
		hud.toggle_fps()
		messages.add("Benchmark (AC-77): 80 units, 15 seconds. Results appear here.", time, "info")
	if demo:
		messages.add("Demo: a recorded match plays back. WASD pans; the camera follows the action.", time, "info")
	else:
		messages.add("Gather wood and gold, build a barracks, destroy the enemy HQ.", time, "info")


func _process(delta: float) -> void:
	time += delta
	var t_sim: int = Time.get_ticks_usec()
	if sim.match_result == "":
		advance_ticks(clock.advance(delta * (DEMO_SPEED if demo else 1.0)))
	t_sim = Time.get_ticks_usec() - t_sim
	_pan(delta)
	if demo:
		_follow_action(delta)
	hover_id = Selection.pick(sim, faction, _to_milli(get_global_mouse_position()))
	selection.prune(sim)
	var t0: int = Time.get_ticks_usec()
	_fog.refresh(delta)
	Benchmark.mark("fog", t0)
	fx = fx.filter(func(e: Dictionary) -> bool: return time - e.t0 < e.life)
	t0 = Time.get_ticks_usec()
	effects.update(delta)
	Benchmark.mark("fxupd", t0)
	for b: Dictionary in effects.landed:
		_hit_time[b.target] = time
		Sound.play_at("arrow_hit", b.b, camera.position, -6.0)
	# Battle music while fighting is on screen, calm music a while after.
	Sound.music("battle" if time - _action_time < 8.0 and sim.match_result == "" else "calm")
	t0 = Time.get_ticks_usec()
	_ambient_effects(delta)
	Benchmark.mark("ambient", t0)
	_shake(delta)
	if bench != null:
		bench.sim_us = t_sim
		bench.tick(delta)
		if bench.done and not bench.get_meta("reported", false):
			bench.set_meta("reported", true)
			messages.add(bench.text(), time, "good")
			if "--bench" in OS.get_cmdline_user_args() and "--quit" in OS.get_cmdline_user_args():
				get_tree().quit()
	if Engine.get_process_frames() % 300 == 0:
		_forget_dead()
	for n: FxDraw in _fx_nodes:
		n.queue_redraw()
	_world.queue_redraw()
	_overlay.queue_redraw()
	t0 = Time.get_ticks_usec()
	hud.refresh()
	Benchmark.mark("hud", t0)


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
		elif opponent != null:
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
						effects.float_text(draw_pos(w) + Vector2(0, -22), "+%d" % ev.amount, Palette.resource(ev.resource).lightened(0.25), 16, ev.resource)
						Sound.play_at("coins", draw_pos(w), camera.position, -14.0)
			"attack":
				var a: Entity = sim.entity(ev.attacker)
				var t: Entity = sim.entity(ev.target)
				if a == null or t == null or not (_seen(a) or _seen(t)):
					continue
				var tp: Vector2 = draw_pos(t) + _world._off.get(t.id, Vector2.ZERO) + Vector2(0, -6) if t.is_unit() 					else (Vector2(t.cell) + Vector2(t.size) / 2.0) * C
				var ap: Vector2 = draw_pos(a) + _world._off.get(a.id, Vector2.ZERO)
				_action_pos = tp if time - _action_time > 2.0 else _action_pos.lerp(tp, 0.2)
				_action_time = time
				if hud != null and hud.minimap != null:
					hud.minimap.ping(tp)
				attack_info[a.id] = {"t": time, "dir": (tp - ap).normalized()}
				if a.kind == "ranged":
					# The arrow leaves the bow at the shot's release frame; the
					# target flashes when it lands.
					var bow: Vector2 = ap + Vector2(0, -14) + (tp - ap).normalized() * 8.0
					effects.arrow(bow, tp + Vector2(0, -8), a.faction, t.id, int(ev.damage), 0.17)
					effects.later(0.17, func() -> void: Sound.play_at("bow", bow, camera.position, -7.0))
				else:
					# The sparks and the flash come when the swing connects.
					var tid: int = t.id
					effects.later(0.2, func() -> void:
						_hit_time[tid] = time
						effects.hit(tp + Vector2(0, -10), ap)
						Sound.play_at("sword", tp, camera.position, -4.0))
				# Buildings show damage numbers, at most one every 0.35 s each
				# (several attackers at once would otherwise pile them up).
				if t.is_building() and time - float(_number_time.get(t.id, -1.0)) > 0.35:
					_number_time[t.id] = time
					effects.float_text(tp + Vector2(0, -22) + Vector2(effects.rng.randf_range(-14, 14), 0), "-%d" % int(ev.damage), Color("ff6b5a"), 14)
			"destroyed":
				var center: Vector2 = Vector2(ev.pos) * C / 1000.0 if ev.kind in Entity.UNIT_KINDS \
					else (Vector2(ev.cell) + Vector2(ev.size) / 2.0) * C
				var cell: Vector2i = Vector2i(center / C)
				if ev.faction != "" and (ev.faction == faction or spectate or sim.fog.is_visible(faction, cell)):
					if ev.kind in Entity.UNIT_KINDS:
						effects.unit_died(center + Vector2(0, 8) + _world._off.get(ev.entity_id, Vector2.ZERO), ev.kind, ev.faction)
						Sound.play_at("death", center, camera.position, -3.0)
					else:
						effects.building_died(Rect2(Vector2(ev.cell) * C, Vector2(ev.size) * C))
						Sound.play_at("collapse", center, camera.position, 0.0)
						shake(0.75 if ev.kind == "hq" else 0.5)
				if ev.faction == faction and ev.kind in Entity.UNIT_KINDS:
					_lost += 1
					messages.add("%s lost" % HudModel.KIND_NAMES[ev.kind], time, "bad")
				elif ev.faction == faction:
					messages.add("%s destroyed" % HudModel.KIND_NAMES[ev.kind], time, "bad")


func _seen(e: Entity) -> bool:
	if e.faction == faction:
		return true
	return sim.fog.is_visible(faction, e.unit_cell()) if e.is_unit() else sim.fog.any_visible(faction, e.cell, e.size)


## Effects that run continuously while something is happening: smoke and
## fire on damaged buildings, dust and sparks at building sites, chips and
## glints at gathering workers, dust behind walking units. Rates are per
## second, so they do not depend on the frame rate.
func _ambient_effects(delta: float) -> void:
	var r: RandomNumberGenerator = effects.rng
	for id: int in sim.entities:
		var e: Entity = sim.entities[id]
		if e.faction == "" or not (e.faction == faction or spectate or _seen(e)):
			continue
		if e.is_building():
			var rect: Rect2 = Rect2(Vector2(e.cell) * C, Vector2(e.size) * C)
			var ratio: float = float(e.hp) / sim.stats[e.kind].health
			var roof: Vector2 = rect.get_center() + Vector2(r.randf_range(-0.3, 0.3) * rect.size.x, -rect.size.y * 0.3)
			if ratio < 0.65 and r.randf() < delta * (3.0 + 6.0 * (0.65 - ratio)):
				effects.smoke(roof, 0.9, 1.0 - ratio)
			if ratio < 0.35 and r.randf() < delta * 14.0:
				effects.fire(roof + Vector2(0, 10), 0.9)
			if not e.complete and _builder_near(e) and r.randf() < delta * 5.0:
				var hp: Vector2 = Vector2(r.randf_range(rect.position.x + 8, rect.end.x - 8), rect.end.y - r.randf_range(4, 18))
				effects.hammer(hp)
				Sound.play_at("hammer", hp, camera.position, -10.0)
		elif e.is_unit():
			var p: Vector2 = draw_pos(e) + Vector2(0, 8)
			if e.phase == "gathering" and e.harvest_type != "" and r.randf() < delta * 2.5:
				var node_p: Vector2 = (Vector2(e.harvest_cell) + Vector2(0.5, 0.5)) * C
				if e.harvest_type == "wood":
					effects.wood_chips(node_p.lerp(p, 0.35))
					if r.randf() < 0.4:
						Sound.play_at("chop", node_p, camera.position, -12.0)
				else:
					effects.gold_glint(node_p)
					if r.randf() < 0.4:
						Sound.play_at("mine", node_p, camera.position, -13.0)
			elif _prev_pos.has(id) and _prev_pos[id] != e.pos and r.randf() < delta * 3.0:
				effects.dust(p + Vector2(0, 2), 1, 3.0, 7.0)


func _builder_near(b: Entity) -> bool:
	for id: int in sim.entities:
		var w: Entity = sim.entities[id]
		if w.kind == "worker" and w.phase == "building" and w.order_target == b.id:
			return true
	return false


## Drops animation records of entities that no longer exist.
func _forget_dead() -> void:
	for d: Dictionary in [attack_info, facing, _hit_time, _world._walk, _world._last, _world._off]:
		for id: int in d.keys():
			if not sim.entities.has(id):
				d.erase(id)


## Shakes the camera; `amount` 0 to 1 (stacks, capped).
func shake(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)


func _shake(delta: float) -> void:
	_trauma = maxf(_trauma - delta * 1.8, 0.0)
	var k: float = _trauma * _trauma * 9.0
	camera.offset = Vector2(effects.rng.randf_range(-k, k), effects.rng.randf_range(-k, k))


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
		Sound.play("error", -10.0, 0.0)
	elif cmd.command == "train" or cmd.command == "build":
		Sound.play("confirm", -8.0, 0.0)
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
		_add_fx({"type": "marker", "a": (Vector2(anchor) + Vector2.ONE) * C, "color": Palette.ACCENT, "life": 0.7, "order": "build"})
		effects.dust((Vector2(anchor) + Vector2.ONE) * C, 8, 22.0, 18.0)


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
				if aiming:
					attack_move_to(mouse)
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
			if placing or aiming:
				placing = false
				aiming = false
				return
			_right_click(mouse)
	elif event is InputEventMouseMotion:
		if _pressed and not placing and (event as InputEventMouseMotion).position.distance_to(_press_screen) > DRAG_THRESHOLD:
			dragging = true
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_B:
				start_placing()
			KEY_F:
				start_aiming()
			KEY_Q:
				train("worker")
			KEY_W:
				train("melee")
			KEY_E:
				train("ranged")
			KEY_F3:
				hud.toggle_fps()
			KEY_ESCAPE:
				if placing or aiming:
					placing = false
					aiming = false
				else:
					selection.clear()


## The terrain layer (the minimap draws its forests, rocks and roads).
func terrain() -> TerrainLayer:
	return _terrain


## The part of the world the camera shows (world pixels).
func view_rect() -> Rect2:
	var size: Vector2 = get_viewport_rect().size / ZOOM
	return Rect2(camera.position - size / 2.0, size)


## Centres the camera on a world position (minimap click), within the map.
func look_at_world(world: Vector2) -> void:
	camera.position = world
	_clamp_camera()
	_last_manual_pan = time


## The context order of a right click at a world position (minimap).
func order_at(world: Vector2) -> void:
	if not demo:
		if aiming:
			attack_move_to(world)
		else:
			_right_click(world)


## True while Shift is held: orders are queued instead of replacing (D-44).
func queueing() -> bool:
	return Input.is_key_pressed(KEY_SHIFT)


## The selected own units (soldiers and workers).
func selected_units() -> Array[int]:
	var out: Array[int] = []
	for id: int in selection.selected:
		var e: Entity = sim.entity(id)
		if e != null and e.is_unit() and e.faction == faction:
			out.append(id)
	return out


## F: arm attack-move; the next left click (on the map or the minimap) is
## the destination (D-44).
func start_aiming() -> void:
	if demo:
		return
	if selected_units().is_empty():
		messages.add("Select units first", time, "warn")
		return
	placing = false
	aiming = true


## Attack-move the selection to a world position (Shift: queued). Stays armed
## while Shift is held, so several waypoints can be clicked in a row.
func attack_move_to(world: Vector2) -> void:
	var ids: Array[int] = selected_units()
	aiming = queueing()
	if ids.is_empty():
		aiming = false
		return
	var cell: Vector2i = Vector2i(floori(world.x / C), floori(world.y / C))
	var r: String = issue(Commands.attack_move(faction, ids, cell, queueing()))
	if r == "ok":
		Sound.play("order", -9.0, 0.05)
		_add_fx({"type": "marker", "a": world, "color": Palette.BAD, "life": 0.7, "order": "attack"})


func _right_click(mouse: Vector2) -> void:
	var cmds: Array[Dictionary] = selection.context_commands(sim, faction, _to_milli(mouse))
	for cmd: Dictionary in cmds:
		# Shift queues move, gather and attack orders (D-44).
		if queueing() and cmd.command in Simulation.QUEUEABLE:
			cmd.args["queue"] = true
		var r: String = issue(cmd)
		if r == "ok":
			Sound.play("order", -9.0, 0.05)
		if r == "ok" or r == "no_path":
			var col: Color = {"move": Color(1.0, 0.95, 0.72), "harvest": Palette.GOLD, "attack": Palette.BAD}[cmd.command]
			_add_fx({"type": "marker", "a": mouse, "color": col, "life": 0.7, "order": cmd.command})


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
	var over_hud: bool = hud != null and hud.minimap_rect().has_point(mouse)
	if not _pressed and not over_hud and vp.get_visible_rect().has_point(mouse) and DisplayServer.window_is_focused():
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


## Draws one group of effects above the units: "normal" particles,
## "add" glowing particles (additive blending) or "text" floating numbers.
class FxDraw extends Node2D:
	var game: Game
	var mode: String = "normal"

	func _draw() -> void:
		if game == null:
			return
		var t0: int = Time.get_ticks_usec()
		_draw_mode()
		Benchmark.mark("fxdraw", t0)

	func _draw_mode() -> void:
		match mode:
			"normal":
				game.effects.draw_particles(self, false)
			"add":
				game.effects.draw_particles(self, true)
			"text":
				game.effects.draw_texts(self)
