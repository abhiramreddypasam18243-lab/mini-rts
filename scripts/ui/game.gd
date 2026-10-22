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
## Mouse-wheel zoom range (D-56).
const ZOOM_MIN: float = 1.0
const ZOOM_MAX: float = 2.4

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
## What is being placed (D-51): "barracks", "farm", "tower" or "stable".
var placing_kind: String = "barracks"
## True after F: the next left click is an attack-move destination (D-44).
var aiming: bool = false
## Touch mode (phones and tablets, D-45): drag pans, tap selects or orders.
var touch: bool = false
## Touch toolbar toggles: the next drag draws a selection box; orders queue.
var box_mode: bool = false
var touch_queue: bool = false
var _touch_moved: bool = false
## Where a touch drag box ends (world), and where the placement ghost is.
var drag_to: Vector2 = Vector2.ZERO
var _touch_at: Vector2 = Vector2.ZERO
var dragging: bool = false
var drag_from: Vector2 = Vector2.ZERO
var hud: Hud
var camera: Camera2D
## The opponent: the enemy AI, driven through its firewall (build step 8).
var opponent: AIController
## The current camera zoom (D-56: the mouse wheel changes it).
var zoom: float = ZOOM
## Peace time of this game (D-56): the AI attacks from this tick on.
var peace_ticks: int = 0
## The auto-economy supervisor (D-55) while it is switched on, else null.
var helper: AIController = null
## Control groups (D-54): 1..9 -> unit ids; rally points: building id -> cell.
var groups: Dictionary = {}
var rally: Dictionary = {}
var _group_time: Dictionary = {}
var _last_alert: float = -100.0
var _alert_at: Vector2 = Vector2.ZERO
var _last_idle: int = 0
## Fights grouped into battles (D-57): summaries and the battle camera.
var battles: BattleTracker = BattleTracker.new()
## The battle camera (K): drifts to the hottest fight when the player has
## not moved the camera for a while.
var battle_cam: bool = true
## Slow motion (D-57): the game runs at `_slow` speed until `_slow_until`.
var _slow: float = 1.0
var _slow_until: float = -1.0
## Knock-back of a unit just hit: id -> direction it was pushed (D-57).
var hit_dir: Dictionary = {}
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
	var name: String = str(p_settings.get("map", "generated"))
	if name == "tutorial":
		return MapGrid.load_file("res://data/maps/tutorial.json").map
	# "generated" is the classic style; "river" and "highlands" are D-53.
	var style: String = name if name in MapGenerator.STYLES else "classic"
	return MapGenerator.generate(int(p_settings.get("seed", 1)), Consts.DEFAULT_MAP_SIZE, style).map


func _ready() -> void:
	touch = TouchInput.enabled()
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
			opponent = AIController.new("ai", AIConfig.for_game(str(settings.get("ai_policy", "balanced"))))
			peace_ticks = opponent.ai.config.peace_ticks
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
	camera.zoom = Vector2(zoom, zoom)
	var hq: Entity = sim.entity(sim.hq_of(faction))
	camera.position = (Vector2(hq.cell) + Vector2(hq.size) / 2.0) * C
	_clamp_camera()
	# The colour grade copies the whole screen every frame; phones skip it (D-46).
	if not touch:
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
		# Slow motion when an HQ falls (D-57) eases back to full speed.
		if time > _slow_until:
			_slow = minf(_slow + delta * 1.5, 1.0)
		advance_ticks(clock.advance(delta * (DEMO_SPEED if demo else 1.0) * _slow))
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
	effects.update(delta * _slow)
	Benchmark.mark("fxupd", t0)
	_battle_frame(delta)
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
		if helper != null and not demo:
			helper.before_step(sim)
		sim.step()
		_consume(sim.take_events())
		if peace_ticks > 0 and sim.tick == peace_ticks and not demo:
			messages.add("Peace time is over: the enemy may attack now", time, "bad")
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
				if ev.type == "completed" and ev.get("faction", "") == faction and not demo:
					_builders_to_work(sim.entity(int(ev.entity_id)))
			"trained":
				if ev.faction == faction:
					_trained += 1
					# Units walk to (or gather at) their building's rally point (D-54);
					# without one, a new worker starts gathering by itself (D-56).
					if rally.has(int(ev.building_id)):
						issue(CommandAids.rally_command(sim, faction, int(ev.entity_id), rally[int(ev.building_id)]), true)
					else:
						var g: Dictionary = CommandAids.auto_gather(sim, faction, int(ev.entity_id))
						if not g.is_empty():
							issue(g, true)
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
				if t != null and not demo and not spectate:
					var where: Vector2 = draw_pos(t) if t.is_unit() else (Vector2(t.cell) + Vector2(t.size) / 2.0) * C
					if CommandAids.should_alert(sim, faction, ev, view_rect().has_point(where), time, _last_alert):
						_last_alert = time
						_alert_at = where
						messages.add("Under attack! (Space to look)", time, "bad")
						Sound.play("error", -6.0, 0.0)
						if hud != null and hud.minimap != null:
							hud.minimap.ping(where)
				if a == null or t == null or not (_seen(a) or _seen(t)):
					continue
				var tp: Vector2 = draw_pos(t) + _world._off.get(t.id, Vector2.ZERO) + Vector2(0, -6) if t.is_unit() 					else (Vector2(t.cell) + Vector2(t.size) / 2.0) * C
				var ap: Vector2 = draw_pos(a) + _world._off.get(a.id, Vector2.ZERO)
				_action_pos = tp if time - _action_time > 2.0 else _action_pos.lerp(tp, 0.2)
				_action_time = time
				if hud != null and hud.minimap != null:
					hud.minimap.ping(tp)
				attack_info[a.id] = {"t": time, "dir": (tp - ap).normalized()}
				battles.add_hit(tp, time)
				if ev.get("charge", false):
					# A cavalry charge (D-57): a burst of dust, a jolt, a label.
					effects.dust(tp + Vector2(0, 8), 6, 14.0, 16.0)
					effects.float_text(tp + Vector2(0, -34), "Charge!", Color("ffd36b"), 15)
					if view_rect().has_point(tp):
						shake(0.22)
				if a.kind == "ranged" or a.kind == "tower":
					# The arrow leaves the bow at the shot's release frame (a
					# tower shoots from its lookout); the target flashes when it lands.
					var bow: Vector2 = ap + Vector2(0, -14) + (tp - ap).normalized() * 8.0
					if a.kind == "tower":
						bow = ap + Vector2(0, -C * 1.9)
					effects.arrow(bow, tp + Vector2(0, -8), a.faction, t.id, int(ev.damage), 0.17)
					effects.later(0.17, func() -> void: Sound.play_at("bow", bow, camera.position, -7.0))
				else:
					# The sparks and the flash come when the swing connects.
					var tid: int = t.id
					var push: Vector2 = (tp - ap).normalized()
					effects.later(0.2, func() -> void:
						_hit_time[tid] = time
						hit_dir[tid] = push
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
						battles.add_death(center, ev.faction, time)
						# A small jolt for a kill on screen (D-57).
						if view_rect().has_point(center):
							shake(0.12)
						Sound.play_at("death", center, camera.position, -3.0)
					else:
						effects.building_died(Rect2(Vector2(ev.cell) * C, Vector2(ev.size) * C))
						# An HQ falling plays in slow motion, the camera on it (D-57).
						if ev.kind == "hq":
							_slow = 0.3
							_slow_until = time + 1.6
							look_at_world(center)
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
			# A healthy, finished HQ has a gently smoking chimney (D-48).
			if e.kind == "hq" and e.complete and ratio >= 0.65 and r.randf() < delta * 1.4:
				effects.smoke(rect.get_center() + Vector2(10, -rect.size.y * 0.55), 0.45, 0.0)
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
			# Charging cavalry kicks up a dust trail (D-57).
			if e.kind == "cavalry" and e.charge >= Consts.CHARGE_DIST and _prev_pos.has(id) 					and _prev_pos[id] != e.pos and r.randf() < delta * 14.0:
				effects.dust(p + Vector2(r.randf_range(-6, 6), 2), 1, 4.0, 9.0)
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
## `quiet` (automatic orders such as rally points) skips the feedback.
func issue(cmd: Dictionary, quiet: bool = false) -> String:
	if demo:
		return "demo"
	var r: String = sim.submit(cmd)
	if quiet:
		return r
	if r != "ok":
		messages.add(HudModel.MESSAGES.get(r, r), time, "warn")
		Sound.play("error", -10.0, 0.0)
	elif cmd.command == "train" or cmd.command == "build" or cmd.command == "research":
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


## Research an upgrade at the selected barracks (D-51).
func research(upgrade: String) -> void:
	var b: Entity = selection.building(sim)
	if b != null and b.faction == faction and b.kind == "barracks":
		issue(Commands.research(faction, b.id, upgrade))


func start_placing(kind: String = "barracks") -> void:
	if demo:
		return
	placing_kind = kind
	if selection.of_kind(sim, func(e: Entity) -> bool: return e.kind == "worker").is_empty():
		messages.add("Select a worker first", time, "warn")
		return
	placing = true
	if touch:
		# The preview starts in the middle of the screen; tap to move it,
		# tap it again to build there.
		_touch_at = camera.position


## Touch toolbar "Cancel": ends placing, aiming or box mode, else clears the
## selection (the Esc key of touch mode).
func touch_cancel() -> void:
	if placing or aiming or box_mode:
		placing = false
		aiming = false
		box_mode = false
		_touch_at = Vector2.ZERO
	else:
		selection.clear()


func select_only(id: int) -> void:
	selection.selected = [id]
	selection.inspected = id


## Top-left cell of the barracks footprint, centred on the mouse (or, in
## touch mode, on the last spot touched).
func placement_anchor() -> Vector2i:
	var size: Vector2 = Vector2(sim.stats[placing_kind].footprint)
	var at: Vector2 = _touch_at if touch else get_global_mouse_position()
	var m: Vector2 = at / C - size / 2.0 + Vector2(0.5, 0.5)
	return Vector2i(floori(m.x), floori(m.y))


## Where the drag box ends: the mouse, or the finger in touch mode.
func drag_end() -> Vector2:
	return drag_to if touch else get_global_mouse_position()


## Touch placement (D-45): the first tap shows the barracks there; tapping
## the same spot again places it (another spot moves the preview).
func _place_at(world: Vector2) -> void:
	var before: Vector2i = placement_anchor()
	var first: bool = _touch_at == Vector2.ZERO
	_touch_at = world
	if not first and placement_anchor() == before:
		_try_place()


func _try_place() -> void:
	var anchor: Vector2i = placement_anchor()
	var workers: Array[int] = selection.of_kind(sim, func(e: Entity) -> bool: return e.kind == "worker")
	if workers.is_empty():
		placing = false
		_touch_at = Vector2.ZERO
		return
	# The selected worker nearest to the site builds it.
	var target: Vector2i = MapGrid.cell_center(anchor)
	workers.sort_custom(func(a: int, b: int) -> bool:
		var da: Vector2i = sim.entity(a).pos - target
		var db: Vector2i = sim.entity(b).pos - target
		return da.length_squared() < db.length_squared() or (da.length_squared() == db.length_squared() and a < b))
	if issue(Commands.build(faction, workers[0], placing_kind, anchor)) == "ok":
		placing = false
		_touch_at = Vector2.ZERO
		_add_fx({"type": "marker", "a": (Vector2(anchor) + Vector2.ONE) * C, "color": Palette.ACCENT, "life": 0.7, "order": "build"})
		effects.dust((Vector2(anchor) + Vector2.ONE) * C, 8, 22.0, 18.0)


# --- input ------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if sim == null or sim.match_result != "":
		return
	if event is InputEventScreenTouch and not touch:
		# A real touch: switch to touch controls (a touchscreen laptop).
		TouchInput.saw_touch()
		touch = true
		hud.set_touch(true)
	if touch:
		_touch_input(event)
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
				# Double-click a unit: every unit of that kind in view (D-56).
				if mb.double_click:
					var id: int = Selection.pick(sim, faction, _to_milli(mouse))
					var e: Entity = sim.entity(id)
					if e != null and e.is_unit() and e.faction == faction:
						var same: Array[int] = CommandAids.same_kind_in(sim, faction, e.kind, view_rect())
						selection.selected = same.slice(0, Consts.MAX_SELECTION)
						selection.inspected = id
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
		elif (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN) and mb.pressed:
			set_zoom(zoom * (1.1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1))
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
				start_placing("barracks")
			KEY_N:
				start_placing("farm")
			KEY_T:
				start_placing("tower")
			KEY_V:
				start_placing("stable")
			KEY_C:
				train("cavalry")
			KEY_R:
				research("forging")
			KEY_Y:
				research("armour")
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
			KEY_G:
				toggle_helper()
			KEY_K:
				battle_cam = not battle_cam
				messages.add("Battle camera on: the view drifts to big fights while you leave it alone" if battle_cam else "Battle camera off", time, "good")
			KEY_A:
				if (event as InputEventKey).ctrl_pressed:
					var all: Array[int] = CommandAids.all_soldiers(sim, faction)
					selection.selected = all.slice(0, Consts.MAX_SELECTION)
					selection.inspected = selection.selected[0] if not selection.selected.is_empty() else 0
			KEY_PERIOD:
				select_idle_worker()
			KEY_SPACE:
				if _last_alert > -100.0:
					look_at_world(_alert_at)
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				_group_key((event as InputEventKey).keycode - KEY_0, (event as InputEventKey).ctrl_pressed)
			KEY_ESCAPE:
				if placing or aiming:
					placing = false
					aiming = false
				else:
					selection.clear()


## Battles (D-57): reports finished ones, and the battle camera drifts to
## the hottest fight after 5 s without camera input (not while selecting,
## placing or aiming).
func _battle_frame(delta: float) -> void:
	for s: Dictionary in battles.update(time):
		if not demo:
			var won: bool = int(s.ai_lost) > int(s.player_lost)
			messages.add(BattleTracker.summary_text(s), time, "good" if won else "bad")
	if not battle_cam or demo or touch or _pressed or placing or aiming or time - _last_manual_pan < 5.0:
		return
	var hot: Variant = battles.hottest(time)
	if hot != null and (camera.position as Vector2).distance_to(hot) > 64.0:
		camera.position = camera.position.lerp(hot, clampf(delta * 0.9, 0.0, 1.0))
		_clamp_camera()


## The builders of a building that just finished go back to work (D-56):
## a farm's builders farm it, others gather from the nearest known node.
func _builders_to_work(b: Entity) -> void:
	if b == null:
		return
	for id: int in sim.entities:
		var w: Entity = sim.entities[id]
		if w.kind == "worker" and w.faction == faction and w.order_type == "idle" and b.chebyshev_to(w.unit_cell()) == 1:
			var g: Dictionary = CommandAids.auto_gather(sim, faction, id, b.id)
			if not g.is_empty():
				issue(g, true)


## Ctrl+n stores the selected units as group n; n selects the group, and a
## second press within 0.4 s centres the camera on it (D-54).
func _group_key(n: int, store: bool) -> void:
	if store:
		CommandAids.assign(groups, n, selection.units(sim))
		messages.add("Group %d: %d units" % [n, selection.units(sim).size()], time, "good")
		return
	var ids: Array[int] = CommandAids.recall(groups, n, sim, faction)
	if ids.is_empty():
		return
	selection.selected = ids
	selection.inspected = ids[0]
	if time - float(_group_time.get(n, -10.0)) < 0.4:
		look_at_world(draw_pos(sim.entity(ids[0])))
	_group_time[n] = time


## "." selects the next idle worker and centres the camera on it (D-54).
func select_idle_worker() -> void:
	var id: int = CommandAids.next_idle(sim, faction, _last_idle)
	if id == 0:
		messages.add("No idle workers", time, "warn")
		return
	_last_idle = id
	select_only(id)
	look_at_world(draw_pos(sim.entity(id)))


## G switches the auto-economy supervisor on or off (D-55).
func toggle_helper() -> void:
	if demo or spectate:
		return
	helper = null if helper != null else AIController.economy_helper(faction)
	messages.add("Auto economy on: idle workers gather, the HQ trains workers, farms are built" if helper != null else "Auto economy off", time, "good")
	if hud != null:
		hud.refresh_helper()


## Mouse-wheel zoom (D-56), kept within ZOOM_MIN..ZOOM_MAX.
func set_zoom(z: float) -> void:
	zoom = clampf(z, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(zoom, zoom)
	_clamp_camera()


## The terrain layer (the minimap draws its forests, rocks and roads).
func terrain() -> TerrainLayer:
	return _terrain


## The part of the world the camera shows (world pixels).
func view_rect() -> Rect2:
	var size: Vector2 = get_viewport_rect().size / zoom
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


## True while Shift is held, or the touch Queue toggle is on: orders are
## queued instead of replacing (D-44, D-45).
func queueing() -> bool:
	return Input.is_key_pressed(KEY_SHIFT) or touch_queue


# --- touch controls (D-45) -----------------------------------------------------

## Touch arrives as emulated mouse events (Godot's default), so HUD buttons
## work as they are; touches on the map end up here. Positions are screen
## (viewport) positions.
func _touch_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			touch_press(mb.position)
		else:
			touch_release(mb.position)
		return
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null and _pressed:
		touch_move(mm.position, mm.relative)


## Screen position -> world position.
func screen_to_world(p: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * p


func touch_press(screen: Vector2) -> void:
	var world: Vector2 = screen_to_world(screen)
	if placing:
		_place_at(world)
		return
	if aiming:
		attack_move_to(world)
		return
	_pressed = true
	_touch_moved = false
	dragging = false
	_press_screen = screen
	drag_from = world


func touch_move(screen: Vector2, relative: Vector2) -> void:
	if not _pressed:
		return
	if not _touch_moved and screen.distance_to(_press_screen) <= DRAG_THRESHOLD * 2.0:
		return
	_touch_moved = true
	if box_mode:
		dragging = true
		drag_to = screen_to_world(screen)
	else:
		# Drag the map: the ground follows the finger.
		camera.position -= relative / zoom
		_clamp_camera()
		_last_manual_pan = time


func touch_release(screen: Vector2) -> void:
	if not _pressed:
		return
	_pressed = false
	var world: Vector2 = screen_to_world(screen)
	if box_mode and _touch_moved:
		selection.box(sim, faction, _to_milli(drag_from), _to_milli(world))
		box_mode = false
	elif not _touch_moved:
		tap(world)
	dragging = false


## A tap: your own unit or building is selected; anything else (ground, a
## resource, an enemy) is an order for the selected units, the same as a
## right click; with nothing selected it shows what was tapped.
func tap(world: Vector2) -> void:
	var p: Vector2i = _to_milli(world)
	var id: int = Selection.pick(sim, faction, p)
	var e: Entity = sim.entity(id)
	if (e != null and e.faction == faction) or selected_units().is_empty():
		selection.click(sim, faction, p)
	else:
		_right_click(world)


## Toolbar: every own soldier (up to the selection limit).
func select_army() -> void:
	var ids: Array[int] = []
	for id: int in sim.unit_ids():
		var e: Entity = sim.entity(id)
		if e.faction == faction and e.is_soldier() and ids.size() < Consts.MAX_SELECTION:
			ids.append(id)
	if ids.is_empty():
		messages.add("No soldiers yet", time, "warn")
		return
	selection.selected = ids
	selection.inspected = ids[0]


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
	# With one of the player's training buildings selected, a right click
	# sets its rally point (D-54).
	var b: Entity = selection.building(sim)
	if b != null and b.faction == faction and not (Simulation.TRAINS.get(b.kind, []) as Array).is_empty():
		var cell: Vector2i = MapGrid.milli_to_cell(_to_milli(mouse))
		if sim.map.in_bounds(cell):
			rally[b.id] = cell
			_add_fx({"type": "marker", "a": mouse, "color": Palette.ACCENT, "life": 0.7, "order": "move"})
			Sound.play("order", -9.0, 0.05)
		return
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
	if Input.is_key_pressed(KEY_A) and not Input.is_key_pressed(KEY_CTRL):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		dir.x += 1
	if Input.is_key_pressed(KEY_S):
		dir.y += 1
	if Input.is_key_pressed(KEY_W) and not building_selected:
		dir.y -= 1
	var vp: Viewport = get_viewport()
	var mouse: Vector2 = vp.get_mouse_position()
	# No edge panning in touch mode: the finger's last spot would pan forever.
	var over_hud: bool = touch or (hud != null and hud.minimap_rect().has_point(mouse))
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
	var view: Vector2 = get_viewport_rect().size / zoom
	var map_px: Vector2 = Vector2(sim.map.width, sim.map.height) * C
	var top: float = TOP_PAD / zoom
	var padded: Vector2 = map_px + Vector2(0, top + BOTTOM_PAD / zoom)
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
