## The in-game HUD (SPEC 9; AC-73, AC-74). Presentation layer: it reads the
## simulation through HudModel and sends commands through the Game.
##   top bar:      wood, gold, food, population, match clock; Restart and Menu
##   bottom panel: details card of the selection, command buttons with
##                 costs and disabled reasons, the production queue
##   left:         status messages that fade after 3 seconds
##   overlay:      victory / defeat / draw / time's up, with Restart
class_name Hud
extends CanvasLayer

var game: Game
var root: Control
var _wood: Label
var _gold: Label
var _food: Label
var _idle: Button
var _helper: Button
var _pop: Label
var _clock: Label
var _card: VBoxContainer
var _actions: GridContainer
var _actions_box: VBoxContainer
var _queue: HBoxContainer
var _hint: Label
var _messages: VBoxContainer
var _overlay: Control
var _overlay_title: Label
var _overlay_sub: Label
var _overlay_stats: Label

# Card widgets, rebuilt only when the selection changes.
var _key: String = ""
var _portrait: HudWidgets.Portrait
var _name: Label
var _sub: Label
var _hp: HudWidgets.HealthBar
var _hp_text: Label
var _status: Label
var _buttons: Dictionary = {}
var _tiles: Array[HudWidgets.UnitTile] = []
var _slots: Array[HudWidgets.QueueSlot] = []
var _last_res: Dictionary = {}
## Frames-per-second readout, toggled with F3 (for measuring AC-77).
var _fps: Label


var _overlay_panel: PanelContainer
var minimap: Minimap
var _minimap_frame: PanelContainer
var _bottom: PanelContainer
## The touch toolbar (D-45) and its toggle buttons.
var _touch_bar: VBoxContainer
var _box_button: Button
var _queue_button: Button

func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.get_theme()
	add_child(root)
	_build_top_bar()
	_build_bottom_panel()
	_build_minimap()
	_build_messages()
	_build_touch_bar()
	set_touch(game.touch)
	_build_overlay()
	_fps = UiTheme.label("", 13, "semibold", Palette.MUTED)
	_fps.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_fps.offset_left = 16
	_fps.offset_top = 18
	_fps.visible = false
	root.add_child(_fps)
	if game.demo:
		var banner: Label = UiTheme.label("DEMO REPLAY  ·  %s (blue) vs %s (red)  ·  %d× speed" % [
			_policy_name("player"), _policy_name("ai"), int(Game.DEMO_SPEED)], 14, "semibold", Palette.WARN)
		banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		banner.offset_top = 66
		banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
		banner.add_theme_constant_override("outline_size", 6)
		banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		root.add_child(banner)


func _policy_name(slot: String) -> String:
	var names: Dictionary = {"balanced": "Balanced", "aggressive": "Aggressive", "economy_first": "Economy-first"}
	return names.get(game.demo_policies.get(slot, ""), "AI")


# --- building the layout ------------------------------------------------------

## Slides a control in from `dy` pixels away (and fades it in) after `delay`.
func _slide_in(c: Control, dy: float, delay: float) -> void:
	c.modulate.a = 0.0
	c.offset_top += dy
	c.offset_bottom += dy
	var tw: Tween = c.create_tween().set_parallel(true)
	tw.tween_property(c, "offset_top", c.offset_top - dy, 0.5).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "offset_bottom", c.offset_bottom - dy, 0.5).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, 0.35).set_delay(delay)


func _build_top_bar() -> void:
	var bar: PanelContainer = PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiTheme.panel_box(Vector2(22, 10)))
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	bar.offset_top = 12
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(bar)
	_slide_in(bar, -90.0, 0.15)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	_wood = _stat(row, "wood")
	_divider(row)
	_gold = _stat(row, "gold")
	_divider(row)
	_food = _stat(row, "food")
	_divider(row)
	_pop = _stat(row, "pop")
	_divider(row)
	_clock = _stat(row, "clock")

	var right: HBoxContainer = HBoxContainer.new()
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.offset_top = 14
	right.offset_right = -16
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.add_theme_constant_override("separation", 8)
	root.add_child(right)
	_slide_in(right, -90.0, 0.25)
	var sound: Button = _small_button("Sound: on" if not Sound.is_muted() else "Sound: off", func() -> void: pass)
	sound.custom_minimum_size = Vector2(118, 40)
	sound.pressed.connect(func() -> void:
		Sound.toggle_mute()
		sound.text = "Sound: off" if Sound.is_muted() else "Sound: on")
	right.add_child(sound)
	if not game.demo:
		# The auto-economy supervisor (D-55) and the idle-worker finder
		# (D-54), on a second row under the top-right buttons.
		var row2: HBoxContainer = HBoxContainer.new()
		row2.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		row2.offset_top = 62
		row2.offset_right = -16
		row2.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		row2.add_theme_constant_override("separation", 8)
		root.add_child(row2)
		_slide_in(row2, -90.0, 0.3)
		_idle = _small_button("Idle: 0", func() -> void: game.select_idle_worker())
		_idle.tooltip_text = "Select the next idle worker (.)"
		row2.add_child(_idle)
		_helper = _small_button("Auto economy: off", func() -> void: game.toggle_helper())
		_helper.custom_minimum_size = Vector2(176, 40)
		_helper.tooltip_text = "G: a helper runs your economy (gathering, workers, farms); you command the army"
		row2.add_child(_helper)
	right.add_child(_small_button("Restart", func() -> void: game.restart_requested.emit()))
	right.add_child(_small_button("Menu", func() -> void: game.menu_requested.emit()))


func _stat(row: HBoxContainer, kind: String) -> Label:
	row.add_child(HudWidgets.Icon.new(kind))
	var l: Label = UiTheme.label("0", 21, "bold")
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0.2, 0.12, 0.06, 0.8))
	l.custom_minimum_size = Vector2(54, 0)
	row.add_child(l)
	return l


func _divider(row: HBoxContainer) -> void:
	var d: ColorRect = ColorRect.new()
	d.color = Color(0.2, 0.12, 0.06, 0.5)
	d.custom_minimum_size = Vector2(1, 22)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(d)


func _small_button(text: String, action: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	UiTheme.style_button(b, "beige", 15)
	b.custom_minimum_size = Vector2(96, 40)
	b.pressed.connect(action)
	return b


func _build_bottom_panel() -> void:
	var panel: PanelContainer = PanelContainer.new()
	_bottom = panel
	_slide_in.call_deferred(panel, 220.0, 0.2)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.custom_minimum_size = Vector2(840, 138)
	panel.offset_bottom = -14
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(panel)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)
	var card_frame: PanelContainer = PanelContainer.new()
	card_frame.add_theme_stylebox_override("panel", UiTheme.parchment(Vector2(14, 10)))
	card_frame.custom_minimum_size = Vector2(280, 0)
	row.add_child(card_frame)
	_card = VBoxContainer.new()
	card_frame.add_child(_card)
	# A carved divider between the details and the commands (D-48).
	var sep: ColorRect = ColorRect.new()
	sep.color = Color(0.22, 0.13, 0.06, 0.55)
	sep.custom_minimum_size = Vector2(2, 0)
	row.add_child(sep)
	_actions_box = VBoxContainer.new()
	_actions_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actions_box.add_theme_constant_override("separation", 6)
	row.add_child(_actions_box)
	var heading: Label = UiTheme.label("COMMANDS", 12, "title", Color(Palette.MUTED, 0.8))
	heading.add_theme_font_override("font", UiTheme.spaced("title", 3))
	heading.visible = not game.demo
	_actions_box.add_child(heading)
	_actions = GridContainer.new()
	_actions.columns = 3
	_actions.add_theme_constant_override("h_separation", 8)
	_actions.add_theme_constant_override("v_separation", 6)
	_actions_box.add_child(_actions)
	_queue = HBoxContainer.new()
	_queue.add_theme_constant_override("separation", 6)
	_actions_box.add_child(_queue)
	# The hint sits at the bottom of the panel as a tip line.
	var fill: Control = Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_actions_box.add_child(fill)
	_hint = UiTheme.label("", 14, "regular", Color(Palette.MUTED, 0.85))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_actions_box.add_child(_hint)


## The minimap in a wooden frame, bottom right (build step 11, D-43).
func _build_minimap() -> void:
	_minimap_frame = PanelContainer.new()
	_minimap_frame.add_theme_stylebox_override("panel", UiTheme.panel_box(Vector2(8, 8)))
	_minimap_frame.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_minimap_frame.offset_right = -12
	_minimap_frame.offset_bottom = -14
	_minimap_frame.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_minimap_frame.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(_minimap_frame)
	minimap = Minimap.new()
	_minimap_frame.add_child(minimap)
	minimap.setup(game)
	_slide_in.call_deferred(_minimap_frame, 220.0, 0.3)


## The minimap's area on screen (mouse over it does not edge-pan).
func minimap_rect() -> Rect2:
	return _minimap_frame.get_global_rect() if _minimap_frame != null else Rect2()


## Buttons that replace the keyboard and the right mouse button on phones
## and tablets (D-45), down the right side above the minimap.
func _build_touch_bar() -> void:
	_touch_bar = VBoxContainer.new()
	_touch_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_touch_bar.offset_top = 66
	_touch_bar.offset_right = -12
	_touch_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_touch_bar.add_theme_constant_override("separation", 6)
	root.add_child(_touch_bar)
	_box_button = _touch_button("Box select", func() -> void:
		game.box_mode = not game.box_mode
		game.aiming = false)
	_touch_button("All soldiers", func() -> void: game.select_army())
	_touch_button("Attack-move", func() -> void: game.start_aiming())
	_queue_button = _touch_button("Queue: off", func() -> void: game.touch_queue = not game.touch_queue)
	_touch_button("Cancel", func() -> void: game.touch_cancel())


func _touch_button(text: String, action: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	UiTheme.style_button(b, "beige", 17)
	b.custom_minimum_size = Vector2(150, 50)
	b.pressed.connect(action)
	_touch_bar.add_child(b)
	return b


## Switches the HUD between mouse and touch layouts: the toolbar shows, and
## the bottom panel sits at the left so it never covers the minimap on
## narrow screens.
func set_touch(on: bool) -> void:
	if _touch_bar == null:
		return
	_touch_bar.visible = on and not game.demo
	if on:
		_bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_KEEP_SIZE)
		_bottom.offset_left = 10
		_bottom.offset_bottom = -14
		_bottom.grow_horizontal = Control.GROW_DIRECTION_END
		_bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _update_touch_bar() -> void:
	if _touch_bar == null or not _touch_bar.visible:
		return
	var tint: Color = Color(1.0, 0.82, 0.38)
	_box_button.self_modulate = tint if game.box_mode else Color.WHITE
	_queue_button.text = "Queue: on" if game.touch_queue else "Queue: off"
	_queue_button.self_modulate = tint if game.touch_queue else Color.WHITE


func _build_messages() -> void:
	_messages = VBoxContainer.new()
	_messages.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_messages.custom_minimum_size = Vector2(420, 150)
	_messages.offset_left = 20
	_messages.offset_bottom = -184
	_messages.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_messages.alignment = BoxContainer.ALIGNMENT_END
	_messages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_messages.add_theme_constant_override("separation", 4)
	root.add_child(_messages)


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	root.add_child(_overlay)
	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.05, 0.62)
	_overlay.add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	_overlay_panel = panel
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(Vector2(48, 36)))
	center.add_child(panel)
	var col: VBoxContainer = VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(420, 0)
	panel.add_child(col)
	_overlay_title = UiTheme.label("Victory", 60, "title")
	_overlay_title.add_theme_constant_override("outline_size", 10)
	_overlay_title.add_theme_color_override("font_outline_color", Color(0.18, 0.1, 0.05))
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_overlay_title)
	_overlay_sub = UiTheme.label("", 19, "semibold", Palette.MUTED)
	_overlay_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_overlay_sub)
	_overlay_stats = UiTheme.label("", 17, "bold", Palette.TEXT)
	_overlay_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_overlay_stats)
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	col.add_child(gap)
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	col.add_child(buttons)
	var again: Button = Button.new()
	again.text = "Play again"
	again.custom_minimum_size = Vector2(160, 46)
	UiTheme.style_button(again, "gold", 19)
	again.pressed.connect(func() -> void: game.restart_requested.emit())
	buttons.add_child(again)
	var menu: Button = Button.new()
	menu.text = "Main menu"
	menu.custom_minimum_size = Vector2(160, 46)
	menu.pressed.connect(func() -> void: game.menu_requested.emit())
	buttons.add_child(menu)


# --- per-frame refresh ----------------------------------------------------------

func refresh() -> void:
	var sim: Simulation = game.sim
	var f: String = game.faction
	var res: Dictionary = HudModel.resources(sim, f)
	_set_counter(_wood, res.wood, _last_res.get("wood", res.wood))
	_set_counter(_gold, res.gold, _last_res.get("gold", res.gold))
	_set_counter(_food, res.food, _last_res.get("food", res.food))
	_last_res = res
	_pop.text = HudModel.population(sim, f)
	if _idle != null:
		_idle.text = "Idle: %d" % CommandAids.idle_workers(sim, f).size()
	_clock.text = HudModel.clock_text(sim.tick)
	_refresh_card(sim, f)
	_refresh_messages()
	if game.touch and not game.demo:
		_update_touch_bar()
		_hint.text = _touch_hint(game.selection.building(sim), game.selection.units(sim))
	if _fps.visible:
		if game.bench != null:
			_fps.text = "%d FPS · %d units · %s" % [Engine.get_frames_per_second(), sim.unit_ids().size(), game.bench.text()]
		else:
			_fps.text = "%d FPS · %d units · enemy AI: %s" % [Engine.get_frames_per_second(), sim.unit_ids().size(), ("replay" if game.opponent == null else game.opponent.ai.state)]


func refresh_helper() -> void:
	if _helper != null:
		_helper.text = "Auto economy: on" if game.helper != null else "Auto economy: off"
		UiTheme.style_button(_helper, "gold" if game.helper != null else "beige", 15)


func toggle_fps() -> void:
	_fps.visible = not _fps.visible


## Counters flash green when they rise and red when they fall.
func _set_counter(l: Label, value: int, before: int) -> void:
	l.text = str(value)
	if value != before:
		var col: Color = Palette.GOOD if value > before else Palette.BAD
		l.add_theme_color_override("font_color", col)
		var tw: Tween = l.create_tween()
		tw.tween_method(func(c: Color) -> void: l.add_theme_color_override("font_color", c), col, Palette.TEXT, 0.6)


func _selection_key(sim: Simulation) -> String:
	var s: Selection = game.selection
	var parts: PackedStringArray = [str(s.selected), str(s.inspected), str(game.placing)]
	var b: Entity = s.building(sim)
	if b != null:
		parts.append("%s %s %d" % [b.kind, b.complete, b.queue.size()])
	return "|".join(parts)


func _clear(node: Node) -> void:
	for c: Node in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _refresh_card(sim: Simulation, f: String) -> void:
	var key: String = _selection_key(sim)
	if key != _key:
		_key = key
		_rebuild_card(sim, f)
	_update_card(sim, f)


func _rebuild_card(sim: Simulation, f: String) -> void:
	_clear(_card)
	_clear(_actions)
	_clear(_queue)
	_buttons.clear()
	_tiles.clear()
	_slots.clear()
	_portrait = null
	var sel: Selection = game.selection
	var units: Array[int] = sel.units(sim)
	if units.size() > 1:
		var title: Label = UiTheme.label("%d units selected" % units.size(), 19, "bold", Palette.INK)
		_card.add_child(title)
		var grid: GridContainer = GridContainer.new()
		grid.columns = 8
		grid.add_theme_constant_override("h_separation", 3)
		grid.add_theme_constant_override("v_separation", 3)
		_card.add_child(grid)
		for id: int in units:
			var tile: HudWidgets.UnitTile = HudWidgets.UnitTile.new()
			var e: Entity = sim.entity(id)
			tile.kind = e.kind
			tile.faction = e.faction
			tile.tooltip_text = HudModel.KIND_NAMES[e.kind]
			tile.pressed.connect(func() -> void: game.select_only(id))
			grid.add_child(tile)
			_tiles.append(tile)
	elif sel.inspected != 0 and not HudModel.details(sim, f, sel.inspected).is_empty():
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		_card.add_child(row)
		_portrait = HudWidgets.Portrait.new()
		row.add_child(_portrait)
		var info: VBoxContainer = VBoxContainer.new()
		info.add_theme_constant_override("separation", 2)
		row.add_child(info)
		_name = UiTheme.label("", 22, "bold", Palette.INK)
		info.add_child(_name)
		_sub = UiTheme.label("", 15, "semibold", Palette.INK_MUTED)
		info.add_child(_sub)
		var hp_row: HBoxContainer = HBoxContainer.new()
		hp_row.add_theme_constant_override("separation", 8)
		info.add_child(hp_row)
		_hp = HudWidgets.HealthBar.new()
		_hp.custom_minimum_size = Vector2(150, 16)
		hp_row.add_child(_hp)
		_hp_text = UiTheme.label("", 15, "bold", Palette.INK_MUTED)
		hp_row.add_child(_hp_text)
		_status = UiTheme.label("", 16, "semibold", Palette.INK)
		info.add_child(_status)
	else:
		_card.add_child(UiTheme.label("Nothing selected", 20, "bold", Palette.INK))
		var tip: Label = UiTheme.label("Tap a unit or building, or use Box select for a group." if game.touch else "Click a unit or building, or drag a box around your units.", 15, "regular", Palette.INK_MUTED)
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tip.custom_minimum_size = Vector2(320, 0)
		_card.add_child(tip)

	# Actions for the selection (none in the demo: the player only watches).
	var b: Entity = sel.building(sim)
	if game.demo:
		_hint.text = "Watching a recorded match. Click a unit or building to see its details; WASD pans."
	elif b != null and b.faction == f:
		for kind: String in Simulation.TRAINS[b.kind]:
			var hotkey: String = {"worker": "Q", "melee": "W", "ranged": "E", "cavalry": "C"}[kind]
			_add_button(kind, "Train " + HudModel.KIND_NAMES[kind].to_lower().replace(" soldier", ""), hotkey,
				func() -> void: game.train(kind))
		if b.kind == "barracks":
			for up: String in ["forging", "armour"]:
				if not game.sim.has_upgrade(f, up):
					_add_button(up, HudModel.KIND_NAMES[up], "R" if up == "forging" else "Y", func() -> void: game.research(up))
		for i: int in Consts.QUEUE_CAPACITY:
			var slot: HudWidgets.QueueSlot = HudWidgets.QueueSlot.new()
			slot.faction = f
			slot.pressed.connect(func() -> void: game.cancel_train(i))
			_queue.add_child(slot)
			_slots.append(slot)
		_hint.text = "Click a queued item to cancel it (full refund). Right-click the map to set a rally point." if b.complete else "It works once construction finishes."
		if b.kind == "farm":
			_hint.text = "Right-click the farm with workers selected to gather food (%d left)." % b.amount if b.complete else "Workers can farm here once it is built."
		elif b.kind == "tower":
			_hint.text = "The tower shoots the nearest enemy unit within 6 cells."
	elif not sel.of_kind(sim, func(e: Entity) -> bool: return e.kind == "worker").is_empty():
		for k: Array in [["barracks", "B"], ["farm", "N"], ["tower", "T"], ["stable", "V"]]:
			var kind: String = k[0]
			_add_button(kind, "Build " + kind, k[1], func() -> void: game.start_placing(kind))
		_add_button("attack_move", "Attack-move", "F", func() -> void: game.start_aiming())
		_hint.text = "Right-click: move · gather wood, gold or your farm's food. Shift: queue orders." \
			if not game.placing else "Click to place the %s · right-click or Esc to cancel." % HudModel.KIND_NAMES[game.placing_kind].to_lower()
	elif not units.is_empty():
		_add_button("attack_move", "Attack-move", "F", func() -> void: game.start_aiming())
		_hint.text = "Right-click: move, or attack a visible enemy. F, then click: attack-move (fight on the way). Hold Shift to queue orders."
	else:
		_hint.text = "Drag to box-select · right-click to command · WASD or screen edges to pan · Esc clears."
	if game.touch and not game.demo:
		_hint.text = _touch_hint(b, units)


## The hint line in touch mode (taps instead of clicks and keys).
func _touch_hint(b: Entity, units: Array) -> String:
	if game.placing:
		return "Tap to move the barracks preview, tap it again to build. Cancel to stop."
	if game.aiming:
		return "Tap where the soldiers should attack-move to."
	if b != null:
		return "Tap a queued unit to cancel it (full refund)." if b.complete else "Soldiers can be trained once construction finishes."
	if not units.is_empty():
		return "Tap the ground to move · a tree or gold to gather · an enemy to attack. Drag to move the map."
	return "Tap a unit to select it · drag to move the map · Box select for groups."


func _add_button(kind: String, title: String, hotkey: String, action: Callable) -> void:
	var b: HudWidgets.CommandButton = HudWidgets.CommandButton.new()
	b.kind = kind
	b.title = title
	b.hotkey = hotkey
	b.faction = game.faction
	b.cost = HudModel.cost_of(game.sim, kind) if game.sim.stats.has(kind) or Consts.UPGRADES.has(kind) else {"wood": 0, "gold": 0}
	b.pressed.connect(action)
	_actions.add_child(b)
	_buttons[kind] = b


func _update_card(sim: Simulation, f: String) -> void:
	var sel: Selection = game.selection
	var res: Dictionary = HudModel.resources(sim, f)
	if _portrait != null:
		var d: Dictionary = HudModel.details(sim, f, sel.inspected)
		if not d.is_empty():
			_portrait.kind = d.kind
			_portrait.faction = d.faction
			_portrait.ghost = d.ghost
			_portrait.t = game.time
			_portrait.queue_redraw()
			_name.text = d.name
			var owner: String = {"player": "Your", "ai": "Enemy", "": "Resource"}[d.faction]
			_sub.text = owner + (" · last seen" if d.ghost else "")
			_sub.add_theme_color_override("font_color", Palette.TEAM[d.faction] if d.faction != "" else Palette.resource(d.kind))
			var is_node: bool = d.faction == ""
			_hp.visible = not is_node
			_hp_text.visible = not is_node
			_hp.hp = d.hp
			_hp.max_hp = d.max_hp
			_hp.queue_redraw()
			_hp_text.text = "%d / %d" % [d.hp, d.max_hp]
			_status.text = d.status
	for i: int in _tiles.size():
		var id: int = sel.units(sim)[i] if i < sel.units(sim).size() else 0
		var e: Entity = sim.entity(id)
		if e != null:
			_tiles[i].hp_ratio = float(e.hp) / sim.stats[e.kind].health
			_tiles[i].queue_redraw()
	var b: Entity = sel.building(sim)
	for kind: String in _buttons:
		var state: Dictionary
		if kind in Simulation.BUILDABLE:
			state = HudModel.build_button(sim, f, sel.of_kind(sim, func(e: Entity) -> bool: return e.kind == "worker"), kind)
		elif Consts.UPGRADES.has(kind) and b != null:
			state = HudModel.research_button(sim, b.id, kind)
		elif b != null:
			state = HudModel.train_button(sim, b.id, kind)
		else:
			continue
		(_buttons[kind] as HudWidgets.CommandButton).set_state(state.enabled, state.reason, res)
	if b != null:
		for i: int in _slots.size():
			var slot: HudWidgets.QueueSlot = _slots[i]
			if i < b.queue.size():
				var item: Dictionary = b.queue[i]
				slot.kind = item.type
				slot.active = i == 0
				var total: int = Consts.UPGRADES[item.type].time if Consts.UPGRADES.has(item.type) else sim.stats[item.type].build_time
				slot.progress = 1.0 - float(item.remaining) / total
				slot.tooltip_text = "%s · click to cancel (refund %s)" % [HudModel.KIND_NAMES[item.type], HudModel.cost_text(item.cost)]
				if item.status == "spawn_blocked":
					slot.tooltip_text = "Waiting: spawn area blocked"
			else:
				slot.kind = ""
				slot.tooltip_text = ""
			slot.queue_redraw()


func _refresh_messages() -> void:
	var entries: Array[Dictionary] = game.messages.entries(game.time)
	while _messages.get_child_count() < entries.size():
		var l: Label = UiTheme.label("", 16, "bold")
		l.add_theme_constant_override("outline_size", 4)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		# A soft dark backing so messages read over any ground (D-48).
		var back: StyleBoxFlat = UiTheme.box(Color(0.12, 0.07, 0.03, 0.62), 6, Color(0.55, 0.38, 0.2, 0.5), 1, Vector2(10, 3))
		l.add_theme_stylebox_override("normal", back)
		l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_messages.add_child(l)
	while _messages.get_child_count() > entries.size():
		var c: Node = _messages.get_child(0)
		_messages.remove_child(c)
		c.queue_free()
	for i: int in entries.size():
		var l: Label = _messages.get_child(i)
		var m: Dictionary = entries[i]
		l.text = m.text
		var col: Color = {"warn": Palette.WARN, "good": Palette.GOOD, "bad": Palette.BAD}.get(m.kind, Palette.TEXT)
		l.add_theme_color_override("font_color", col)
		l.modulate.a = m.alpha


# --- end of match ---------------------------------------------------------------

func show_result(result: String, stats: Dictionary) -> void:
	var titles: Dictionary = {
		"victory_player": ["Victory", Palette.GOOD, "The enemy headquarters has fallen."],
		"victory_ai": ["Defeat", Palette.BAD, "Your headquarters was destroyed."],
		"draw": ["Draw", Palette.WARN, "Both headquarters fell in the same moment."],
		"timeout": ["Time's up", Palette.WARN, "The match reached its time limit."],
	}
	if game.demo:
		titles["victory_player"] = ["Blue wins", Palette.TEAM["player"], "%s beat %s in this recorded match." % [_policy_name("player"), _policy_name("ai")]]
		titles["victory_ai"] = ["Red wins", Palette.TEAM["ai"], "%s beat %s in this recorded match." % [_policy_name("ai"), _policy_name("player")]]
	var t: Array = titles.get(result, ["Match over", Palette.TEXT, ""])
	_overlay_title.text = t[0]
	_overlay_title.add_theme_color_override("font_color", t[1])
	_overlay_sub.text = t[2]
	_overlay_stats.text = "Time %s   ·   Wood %d   ·   Gold %d   ·   Units trained %d   ·   Units lost %d" % [
		HudModel.clock_text(stats.tick), stats.wood, stats.gold, stats.trained, stats.lost]
	_overlay.visible = true
	_overlay.modulate.a = 0.0
	var tw: Tween = _overlay.create_tween()
	tw.tween_property(_overlay, "modulate:a", 1.0, 0.35)
	# The dialog pops in, and its title settles from a little larger.
	_overlay_panel.pivot_offset = _overlay_panel.size / 2.0
	_overlay_panel.scale = Vector2(0.82, 0.82)
	var pop: Tween = _overlay_panel.create_tween()
	pop.tween_property(_overlay_panel, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_overlay_title.pivot_offset = _overlay_title.size / 2.0
	_overlay_title.scale = Vector2(1.35, 1.35)
	var ttl: Tween = _overlay_title.create_tween()
	ttl.tween_interval(0.12)
	ttl.tween_property(_overlay_title, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func is_overlay_showing() -> bool:
	return _overlay.visible


func overlay_title() -> String:
	return _overlay_title.text
