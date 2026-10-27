## The title screen (SPEC 9; AC-74): starts a match on a generated map (with
## a seed) or the tutorial map, chooses the opponent, plays the demo and shows
## the controls. Behind it, a slowly drifting battlefield drawn with the
## game's own sprites: two castles, forests, rocks, gold and two armies.
class_name MainMenu
extends Control

signal start_requested(settings: Dictionary)

const POLICIES: Array[Array] = [["balanced", "Balanced"], ["aggressive", "Aggressive"], ["economy_first", "Economy-first"]]
## Generated map styles (D-53) and AI difficulties (D-52).
const MAP_STYLES: Array[Array] = [["generated", "Classic"], ["river", "River crossing"], ["highlands", "Highlands"]]
const DIFFICULTIES: Array[Array] = [["easy", "Easy"], ["normal", "Normal"], ["hard", "Hard"]]
## The backdrop is a field this big; the view drifts across it.
const FIELD: Vector2 = Vector2(2200, 1100)
const TILE: float = 56.0

var _t: float = 0.0
var _seed_edit: LineEdit
var _policy: OptionButton
var _map_style: OptionButton
var _difficulty: OptionButton
var _help: PanelContainer
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _scene: Array[Dictionary] = []
## The backdrop's battle effects (drawing only).
var _fx: Effects = Effects.new()
var _fx_holder: Node2D
var _cam: Vector2 = Vector2.ZERO
var _next_clash: float = 0.0
var _units: Array[Dictionary] = []
var _credits: Control
## Online play (D-60): the panel, its status line, the code box, and the
## connection while hosting or joining.
var _online: Control
var _online_status: Label
var _online_code: Label
var _join_edit: LineEdit
var _online_buttons: Array[Button] = []
var _net: NetClient = null
## A bright band that sweeps across the gold title now and then.
const SHINE_SHADER: String = """
shader_type canvas_item;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float x = FRAGCOORD.x + FRAGCOORD.y * 0.6;
	float band = exp(-pow((x - mod(TIME * 260.0, 2600.0) + 400.0) / 34.0, 2.0));
	float bright = smoothstep(0.45, 0.75, dot(c.rgb, vec3(0.3, 0.59, 0.11)));
	c.rgb += vec3(1.0, 0.95, 0.8) * band * bright * 0.75;
	COLOR = c;
}
"""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	_rng.randomize()  # presentation only: picks a suggested seed
	_build_scene()

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col: VBoxContainer = VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	center.add_child(col)

	# Phones (D-45): a smaller title and tighter spacing fit short screens.
	var compact: bool = TouchInput.enabled()
	var title: Label = UiTheme.label("MINI RTS", 60 if compact else 92, "title", Palette.ACCENT)
	title.add_theme_font_override("font", UiTheme.spaced("title", 8))
	title.add_theme_constant_override("outline_size", 16)
	title.add_theme_color_override("font_outline_color", Color(0.22, 0.12, 0.05))
	title.add_theme_constant_override("shadow_offset_y", 6)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var shine: Shader = Shader.new()
	shine.code = SHINE_SHADER
	var shine_mat: ShaderMaterial = ShaderMaterial.new()
	shine_mat.shader = shine
	title.material = shine_mat
	col.add_child(title)
	var tag: Label = UiTheme.label("GATHER  ·  BUILD  ·  CONQUER", 15 if compact else 20, "title", Palette.TEXT)
	tag.add_theme_font_override("font", UiTheme.spaced("title", 4))
	tag.add_theme_constant_override("outline_size", 8)
	tag.add_theme_color_override("font_outline_color", Color(0.15, 0.09, 0.04, 0.9))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tag)
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0, 8 if compact else 22)
	col.add_child(gap)

	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(Vector2(26, 22)))
	col.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(400, 0)
	panel.add_child(box)

	var play: Button = _button("Play", "gold")
	play.pressed.connect(func() -> void: start_requested.emit(_settings(MAP_STYLES[_map_style.selected][0])))
	box.add_child(play)
	var tutorial: Button = _button("Play  ·  tutorial map", "beige")
	tutorial.pressed.connect(func() -> void: start_requested.emit(_settings("tutorial")))
	box.add_child(tutorial)

	var seed_row: HBoxContainer = HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	box.add_child(seed_row)
	seed_row.add_child(_row_label("Map seed"))
	_seed_edit = LineEdit.new()
	_seed_edit.text = str(_rng.randi_range(1, 99999))
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.max_length = 9
	_seed_edit.add_theme_font_size_override("font_size", 17)
	seed_row.add_child(_seed_edit)
	var shuffle: Button = Button.new()
	shuffle.text = "Shuffle"
	shuffle.focus_mode = Control.FOCUS_NONE
	shuffle.custom_minimum_size = Vector2(96, 0)
	shuffle.pressed.connect(func() -> void: _seed_edit.text = str(_rng.randi_range(1, 99999)))
	seed_row.add_child(shuffle)

	_map_style = _option_row(box, "Map", MAP_STYLES, 0)
	var policy_row: HBoxContainer = HBoxContainer.new()
	policy_row.add_theme_constant_override("separation", 8)
	box.add_child(policy_row)
	policy_row.add_child(_row_label("Opponent"))
	_policy = OptionButton.new()
	_policy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_policy.focus_mode = Control.FOCUS_NONE
	_policy.add_theme_font_size_override("font_size", 17)
	for p: Array in POLICIES:
		_policy.add_item(p[1])
	policy_row.add_child(_policy)
	# New players start on Easy (D-56).
	_difficulty = _option_row(box, "Difficulty", DIFFICULTIES, 0)

	var online: Button = _button("Play online  ·  vs a friend", "gold")
	online.pressed.connect(func() -> void: _online.visible = true)
	box.add_child(online)
	var demo: Button = _button("Watch demo", "beige")
	demo.pressed.connect(func() -> void: start_requested.emit({"mode": "demo"}))
	box.add_child(demo)
	var info_row: HBoxContainer = HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 10)
	box.add_child(info_row)
	var help_button: Button = _button("How to play", "brown")
	help_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_row.add_child(help_button)
	var credits_button: Button = _button("Credits", "brown")
	credits_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_row.add_child(credits_button)
	_help = _build_help()
	_help.visible = false
	col.add_child(_help)
	help_button.pressed.connect(func() -> void: _help.visible = not _help.visible)
	credits_button.pressed.connect(show_credits)

	var footer: Label = UiTheme.label("Godot 4.7.2  ·  art by Kenney, Kay Lousberg and ambientCG (CC0)  ·  see Credits", 14, "semibold", Palette.TEXT)
	footer.add_theme_constant_override("outline_size", 6)
	footer.add_theme_color_override("font_outline_color", Color(0.12, 0.07, 0.03, 0.9))
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	footer.offset_right = -20
	footer.offset_bottom = -14
	footer.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(footer)
	_credits = _build_credits()
	_credits.visible = false
	add_child(_credits)
	_online = _build_online()
	_online.visible = false
	add_child(_online)


func _row_label(text: String) -> Label:
	var l: Label = UiTheme.label(text, 17, "bold", Palette.TEXT)
	l.custom_minimum_size = Vector2(82, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _button(text: String, colour: String) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44 if TouchInput.enabled() else 50)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UiTheme.style_button(b, colour, 19)
	return b


func _build_help() -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.frame("panel_beigeLight", 18, Vector2(22, 16)))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 4)
	p.add_child(grid)
	var rows: Array = []
	if TouchInput.enabled():
		rows = [
			["Tap a unit", "Select it (Box select or All soldiers for groups)"],
			["Tap ground / tree / gold / enemy", "Move · gather · attack with the selection"],
			["Drag", "Move the map (or the minimap)"],
			["Attack-move, then tap", "Walk there, fighting on the way"],
			["Queue: on", "Orders line up instead of replacing"],
			["Cancel", "Stop placing or aiming, or clear the selection"],
		]
		for r: Array in rows:
			grid.add_child(UiTheme.label(r[0], 16, "bold", Palette.INK))
			grid.add_child(UiTheme.label(r[1], 16, "regular", Palette.INK))
		return p
	rows = [
		["Left click", "Select a unit or building"],
		["Left drag", "Box-select your units (up to 24)"],
		["Right click", "Move · gather (workers on wood/gold) · attack (soldiers)"],
		["B, then click", "Place a barracks (a worker must be selected)"],
		["Q / W / E", "Train worker / knight / archer at the selected building"],
		["Esc", "Cancel placement or clear the selection"],
		["WASD, screen edges", "Pan the camera"],
		["M", "Sound and music on / off"],
	]
	for r: Array in rows:
		grid.add_child(UiTheme.label(r[0], 16, "bold", Palette.INK))
		grid.add_child(UiTheme.label(r[1], 16, "regular", Palette.INK))
	return p


## Opens the credits.
func show_credits() -> void:
	_credits.visible = true


func is_credits_showing() -> bool:
	return _credits.visible


func _build_credits() -> Control:
	var layer: ColorRect = ColorRect.new()
	layer.color = Color(0.05, 0.03, 0.01, 0.75)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(Vector2(26, 22)))
	center.add_child(panel)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var title: Label = UiTheme.label("Credits", 40, "title", Palette.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var page: PanelContainer = PanelContainer.new()
	page.add_theme_stylebox_override("panel", UiTheme.parchment(Vector2(18, 14)))
	col.add_child(page)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var text: RichTextLabel = RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_override("normal_font", UiTheme.font("regular"))
	text.add_theme_font_override("bold_font", UiTheme.font("bold"))
	text.add_theme_font_size_override("normal_font_size", 16)
	text.add_theme_font_size_override("bold_font_size", 17)
	text.add_theme_color_override("default_color", Palette.INK)
	text.text = credits_text()
	scroll.add_child(text)
	var close: Button = _button("Close", "gold")
	close.pressed.connect(func() -> void: layer.visible = false)
	col.add_child(close)
	return layer


## Online play (D-60): host a match and get a code, or join with a code.
## The host's map and seed (from the menu) are used for both players.
func _build_online() -> Control:
	var layer: ColorRect = ColorRect.new()
	layer.color = Color(0.05, 0.03, 0.01, 0.75)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(Vector2(26, 22)))
	center.add_child(panel)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(460, 0)
	panel.add_child(col)
	var title: Label = UiTheme.label("Play online", 40, "title", Palette.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var intro: Label = UiTheme.label("Play against a friend on another computer. One of you hosts and reads out the code; the other joins with it. The host plays Blue, the guest Red, on the host's map.", 16, "regular", Palette.TEXT)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(460, 0)
	col.add_child(intro)
	var host: Button = _button("Host a match", "gold")
	host.pressed.connect(_host)
	col.add_child(host)
	_online_code = UiTheme.label("", 64, "title", Palette.ACCENT)
	_online_code.add_theme_font_override("font", UiTheme.spaced("title", 12))
	_online_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_online_code.visible = false
	col.add_child(_online_code)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	_join_edit = LineEdit.new()
	_join_edit.placeholder_text = "Code, e.g. K7QM"
	_join_edit.max_length = 4
	_join_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_edit.add_theme_font_size_override("font_size", 22)
	_join_edit.text_submitted.connect(func(_t: String) -> void: _join())
	row.add_child(_join_edit)
	var join: Button = _button("Join", "beige")
	join.custom_minimum_size = Vector2(120, 0)
	join.pressed.connect(_join)
	row.add_child(join)
	_online_buttons = [host, join]
	_online_status = UiTheme.label("", 16, "semibold", Palette.TEXT)
	_online_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_online_status.custom_minimum_size = Vector2(460, 0)
	col.add_child(_online_status)
	var back: Button = _button("Back", "brown")
	back.pressed.connect(func() -> void:
		_drop_net()
		_online_status.text = ""
		_online_code.visible = false
		layer.visible = false)
	col.add_child(back)
	return layer


func _new_net() -> NetClient:
	_drop_net()
	_net = NetClient.new()
	add_child(_net)
	_net.started.connect(_online_started)
	_net.failed.connect(_online_failed)
	_net.open()
	for b: Button in _online_buttons:
		b.disabled = true
	_online_status.add_theme_color_override("font_color", Palette.TEXT)
	_online_status.text = "Connecting to the game server… (a sleeping server can take up to a minute to wake)"
	return _net


func _drop_net() -> void:
	if _net != null:
		_net.leave()
		_net.queue_free()
		_net = null
	for b: Button in _online_buttons:
		b.disabled = false


func _host() -> void:
	var n: NetClient = _new_net()
	n.hosted.connect(func(code: String) -> void:
		_online_code.text = code
		_online_code.visible = true
		_online_status.text = "Tell the other player this code. The match starts when they join.")
	n.host({"map": MAP_STYLES[_map_style.selected][0], "seed": _seed()})


func _join() -> void:
	var code: String = _join_edit.text.strip_edges().to_upper()
	if code.length() != 4:
		_online_status.add_theme_color_override("font_color", Palette.BAD)
		_online_status.text = "Type the 4-letter code the host sees."
		return
	_online_code.visible = false
	_new_net().join(code)


func _online_started(you: String, setup: Dictionary) -> void:
	var n: NetClient = _net
	_net = null  # handed over to the match
	n.started.disconnect(_online_started)
	n.failed.disconnect(_online_failed)
	start_requested.emit({"mode": "online", "net": n, "you": you,
		"map": str(setup.get("map", "generated")), "seed": int(setup.get("seed", 1))})


func _online_failed(text: String) -> void:
	_drop_net()
	_online_code.visible = false
	_online_status.add_theme_color_override("font_color", Palette.BAD)
	_online_status.text = text


## The credits, as BBCode.
static func credits_text() -> String:
	var t: String = "[b]Units[/b]\n"
	t += "KayKit Character Pack: Adventurers by Kay Lousberg (kaylousberg.com). CC0. "
	t += "Cavalry horse: Farm Animals pack by Quaternius (quaternius.com). CC0. "
	t += "Rendered in 8 directions with Godot's 3D engine (tools/render_3d.gd).\n\n"
	t += "[b]Buildings, trees and rocks[/b]\nKenney (kenney.nl): Castle Kit, Fantasy Town Kit, Nature Kit (3D, rendered as sprites). CC0.\n\n"
	t += "[b]Ground[/b]\nambientCG (ambientcg.com): Grass007, Ground037, Ground054. CC0.\n\n"
	t += "[b]Scenery, interface and effects[/b]\n"
	t += "Kenney (kenney.nl): Medieval RTS, UI Pack: RPG Expansion, Particle Pack. CC0.\n\n"
	t += "[b]Sound and music[/b]\n"
	t += "Sound effects: Kenney (kenney.nl): Impact Sounds, RPG Audio, Interface Sounds. CC0. "
	t += "Music: \"Town Theme RPG\" and \"Battle Theme A\" by cynicmusic (opengameart.org). CC0.\n\n"
	t += "[b]Fonts[/b]\nCinzel by Natanael Gama; Alegreya Sans by Huerta Tipográfica. SIL Open Font License 1.1.\n\n"
	t += "[b]Engine[/b]\nGodot Engine 4.7.2 (MIT licence), godotengine.org.\n\n"
	t += "Every asset file, its source and licence: ASSETS.md in the project repository."
	return t


func _settings(map: String) -> Dictionary:
	var level: String = DIFFICULTIES[_difficulty.selected][0]
	var policy: String = POLICIES[_policy.selected][0] + ("" if level == "normal" else ":" + level)
	return {"map": map, "seed": _seed(), "ai_policy": policy}


## A labelled drop-down row in the menu panel.
func _option_row(box: VBoxContainer, label: String, items: Array[Array], selected: int) -> OptionButton:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	row.add_child(_row_label(label))
	var o: OptionButton = OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.focus_mode = Control.FOCUS_NONE
	o.add_theme_font_size_override("font_size", 17)
	for it: Array in items:
		o.add_item(it[1])
	o.selected = selected
	row.add_child(o)
	return o


func _seed() -> int:
	return int(_seed_edit.text) if _seed_edit.text.is_valid_int() else 1


# --- the drifting battlefield backdrop -------------------------------------------

## Places castles, barracks, forests, rocks and gold on the field, two
## armies that march in and clash in the middle, and the effect layers.
func _build_scene() -> void:
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = 7  # the same backdrop every time
	_scene.append({"kind": "castle", "pos": Vector2(330, 520), "size": 230.0, "faction": "player"})
	_scene.append({"kind": "castle", "pos": Vector2(1870, 470), "size": 230.0, "faction": "ai"})
	_scene.append({"kind": "barracks", "pos": Vector2(560, 760), "size": 150.0, "faction": "player"})
	_scene.append({"kind": "barracks", "pos": Vector2(1640, 260), "size": 150.0, "faction": "ai"})
	for i: int in 90:
		var p: Vector2 = Vector2(r.randf_range(0, FIELD.x), r.randf_range(0, FIELD.y))
		if absf(p.y - 520.0) < 170.0 and absf(p.x - 1100.0) < 760.0:
			continue  # keep the middle open for the armies
		var k: String = ["tree_a", "tree_c", "rock_a", "rock_d", "gold_ore", "tree_f", "tree_g"][r.randi_range(0, 6)]
		_scene.append({"kind": k, "pos": p, "size": r.randf_range(60.0, 110.0)})
	for i: int in 16:
		var f: String = "player" if i < 8 else "ai"
		var side: float = -1.0 if f == "player" else 1.0
		var kind: String = "ranged" if i % 8 >= 5 else "melee"
		var row: int = i % 8
		var y: float = 400.0 + (row % 5) * 52.0 + r.randf_range(-10, 10) + (26.0 if kind == "ranged" else 0.0)
		var front: float = 1100.0 + side * (60.0 + (90.0 if kind == "ranged" else 0.0) + r.randf_range(0, 30))
		var u: Dictionary = {"kind": "unit", "unit": kind, "faction": f, "home": Vector2(1100.0 + side * r.randf_range(520, 700), y),
			"front": Vector2(front, y), "delay": r.randf_range(0.0, 2.5), "pos": Vector2(0, y), "hit": -10.0, "atk": -10.0,
			"dir": Vector2.ZERO, "phase": r.randf() * TAU}
		u.pos = u.home
		_units.append(u)
		_scene.append(u)
	# Effect layers (above the field, below the panel): particles, glows,
	# drifting cloud shadows, then the vignette.
	_fx_holder = Node2D.new()
	add_child(_fx_holder)
	for additive: bool in [false, true]:
		var n: MenuFx = MenuFx.new()
		n.menu = self
		n.additive = additive
		if additive:
			var m: CanvasItemMaterial = CanvasItemMaterial.new()
			m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			n.material = m
		_fx_holder.add_child(n)
	var clouds: ColorRect = ColorRect.new()
	clouds.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clouds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh: Shader = Shader.new()
	sh.code = TerrainLayer.CLOUD_SHADER
	var cm: ShaderMaterial = ShaderMaterial.new()
	cm.shader = sh
	cm.set_shader_parameter("size", Vector2(1800, 1000))
	clouds.material = cm
	add_child(clouds)
	var vig: Vignette = Vignette.new()
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vig)


func _process(delta: float) -> void:
	_t += delta
	var s: Vector2 = size
	_cam = Vector2((FIELD.x - s.x) * 0.5 + sin(_t * 0.05) * (FIELD.x - s.x) * 0.45, (FIELD.y - s.y) * 0.5 + cos(_t * 0.04) * 60.0)
	_fx_holder.position = -_cam
	for u: Dictionary in _units:
		var k: float = clampf((_t - u.delay) / 7.0, 0.0, 1.0)
		u.pos = u.home.lerp(u.front, smoothstep(0.0, 1.0, k))
	_clash()
	_ambient(delta)
	_fx.update(delta)
	for n: Node in _fx_holder.get_children():
		(n as Node2D).queue_redraw()
	queue_redraw()


## Once the armies meet, soldiers trade blows: sword swings and arrows.
func _clash() -> void:
	if _t < 7.5 or _t < _next_clash:
		return
	_next_clash = _t + _rng.randf_range(0.18, 0.45)
	var u: Dictionary = _units[_rng.randi_range(0, _units.size() - 1)]
	var foes: Array[Dictionary] = []
	for v: Dictionary in _units:
		if v.faction != u.faction:
			foes.append(v)
	foes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.pos.distance_squared_to(u.pos) < b.pos.distance_squared_to(u.pos))
	var target: Dictionary = foes[_rng.randi_range(0, mini(2, foes.size() - 1))]
	var to: Vector2 = target.pos + Vector2(0, -10)
	u.atk = _t
	u.dir = (to - u.pos).normalized()
	if u.unit == "ranged":
		_fx.arrow(u.pos + Vector2(0, -18) + u.dir * 10.0, to, u.faction, 0, 8, 0.17)
		target.hit = _t + 0.45
	else:
		var from: Vector2 = u.pos
		_fx.later(0.2, func() -> void: _fx.hit(to, from))
		target.hit = _t + 0.2


## Leaves drifting on the wind and golden motes floating up.
func _ambient(delta: float) -> void:
	var s: Vector2 = size
	if _rng.randf() < delta * 6.0:
		var p: Vector2 = _cam + Vector2(_rng.randf_range(-100, s.x * 0.6), _rng.randf_range(-60, s.y))
		var leaf: Color = [Color("8fcf5a"), Color("d7c24a"), Color("e09a3a"), Color("6fae45")][_rng.randi_range(0, 3)]
		_fx.emit("", p, Vector2(_rng.randf_range(45, 80), _rng.randf_range(10, 30)), 7.0, 7.0, 6.0, leaf, false, 3.0, 0.0, _rng.randf_range(-3, 3), 0.1)
	if _rng.randf() < delta * 5.0:
		var q: Vector2 = _cam + Vector2(_rng.randf_range(0, s.x), _rng.randf_range(s.y * 0.3, s.y))
		_fx.emit("light_01", q, Vector2(_rng.randf_range(-8, 8), _rng.randf_range(-22, -10)), 4.0, 10.0, 4.0, Color(1.0, 0.85, 0.45, 0.6), true, 0.0, 0.0, 0.0, 0.3)


func _draw() -> void:
	var s: Vector2 = size
	var cam: Vector2 = _cam
	# Grass.
	var grass_a: Texture2D = Art.tex("grass_a")
	var grass_b: Texture2D = Art.tex("grass_b")
	var x0: int = int(floor(cam.x / TILE))
	var y0: int = int(floor(cam.y / TILE))
	for y: int in range(y0, y0 + int(s.y / TILE) + 2):
		for x: int in range(x0, x0 + int(s.x / TILE) + 2):
			draw_texture_rect(grass_a if TerrainLayer.noise(x, y) < 0.6 else grass_b, Rect2(Vector2(x, y) * TILE - cam, Vector2(TILE, TILE)), false, Color(0.9, 0.94, 0.86))
	# Scenery and armies, lower ones drawn last.
	_scene.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.pos.y < b.pos.y)
	for o: Dictionary in _scene:
		var p: Vector2 = o.pos - cam
		if p.x < -260 or p.x > s.x + 260 or p.y < -260 or p.y > s.y + 260:
			continue
		match o.kind:
			"castle", "barracks":
				# Pre-rendered 3D buildings (D-49); `size` is the drawn width of
				# the footprint (3 cells for the castle, 2 for the barracks).
				var units: float = 3.0 if o.kind == "castle" else 2.0
				var name: String = "%s_%s" % ["hq" if o.kind == "castle" else "barracks", Art.TEAM_ART[o.faction]]
				Art.draw_rendered(self, name, p, Color.WHITE, -INF, o.size / units)
			"unit":
				var flash: float = clampf(1.0 - (_t - o.hit) / 0.15, 0.0, 1.0) if _t >= o.hit else 0.0
				var a: Dictionary = _pose(o)
				Art.unit(self, p, o.unit, o.faction, a.anim, a.dir, a.frame, 1.0, flash, 1.0)
			_:
				var sz2: float = o.size
				if o.kind.begins_with("tree") or o.kind.begins_with("rock"):
					var sway: float = sin(_t * 1.6 + o.pos.x * 0.045) * 0.04 if o.kind.begins_with("tree") else 0.0
					draw_set_transform_matrix(Transform2D(Vector2(1, 0), Vector2(sway, 1), p))
					Art.draw_rendered(self, o.kind, Vector2.ZERO, Color(1.08, 1.08, 1.08), -INF, sz2 * 0.55)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				else:
					draw_texture_rect(Art.tex(o.kind), Rect2(p - Vector2(sz2, sz2) * 0.5, Vector2(sz2, sz2)), false)
					draw_texture_rect(Art.tex(o.kind), Rect2(p - Vector2(sz2, sz2) * 0.5, Vector2(sz2, sz2)), false)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The animation frame for a backdrop soldier: walking in, then standing
## ready, a sword swing or a bow shot when it attacks.
func _pose(u: Dictionary) -> Dictionary:
	var facing: int = UnitSprites.RIGHT if u.faction == "player" else UnitSprites.LEFT
	var since: float = _t - u.atk
	if u.unit == "melee" and since < 0.42:
		return {"anim": "slash", "dir": UnitSprites.dir_of(u.dir, facing), "frame": int(since / 0.42 * 6.0)}
	if u.unit == "ranged" and since < 0.42:
		return {"anim": "shoot", "dir": UnitSprites.dir_of(u.dir, facing), "frame": 4 + int(since / 0.42 * 9.0)}
	if _t > u.delay and _t < u.delay + 7.0:
		return {"anim": "walk", "dir": facing, "frame": 1 + int(_t * 9.0 + u.phase) % 8}
	if u.unit == "ranged" and _t > 7.5:
		return {"anim": "shoot", "dir": facing, "frame": 4}
	return {"anim": "walk", "dir": facing, "frame": 0}


## Draws the backdrop's particles, offset with the drifting view.
class MenuFx extends Node2D:
	var menu: MainMenu
	var additive: bool = false

	func _draw() -> void:
		menu._fx.draw_particles(self, additive)


## Warm darkening so the title and panel stand out, and a smooth vignette:
## each edge is a quad whose colour fades from dark to clear (no banding).
class Vignette extends Control:
	func _draw() -> void:
		var s: Vector2 = size
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.1, 0.06, 0.02, 0.22))
		var dark: Color = Color(0.06, 0.035, 0.01, 0.75)
		var clear: Color = Color(0.06, 0.035, 0.01, 0.0)
		var m: float = minf(s.x, s.y) * 0.32
		_quad(Vector2.ZERO, Vector2(s.x, 0), Vector2(s.x, m), Vector2(0, m), dark, clear)
		_quad(Vector2(0, s.y), Vector2(s.x, s.y), Vector2(s.x, s.y - m), Vector2(0, s.y - m), dark, clear)
		_quad(Vector2.ZERO, Vector2(0, s.y), Vector2(m, s.y), Vector2(m, 0), dark, clear)
		_quad(Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(s.x - m, s.y), Vector2(s.x - m, 0), dark, clear)

	func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, dark: Color, clear: Color) -> void:
		draw_polygon(PackedVector2Array([a, b, c, d]), PackedColorArray([dark, dark, clear, clear]))


func _exit_tree() -> void:
	# A connection still hosting or joining closes with the menu (D-60).
	if _net != null:
		_net.leave()
