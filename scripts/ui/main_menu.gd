## The main menu (SPEC 9; AC-74): starts a match on a generated map (with a
## seed) or the tutorial map, and shows the controls. The background is
## drawn in code: soft faction glows, a drifting grid and slowly circling
## unit tokens.
class_name MainMenu
extends Control

signal start_requested(settings: Dictionary)

var _t: float = 0.0
var _seed_edit: LineEdit
var _policy: OptionButton
const POLICIES: Array[Array] = [["balanced", "Balanced"], ["aggressive", "Aggressive"], ["economy_first", "Economy-first"]]
var _help: PanelContainer
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	_rng.randomize()  # presentation only: picks a suggested seed

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col: VBoxContainer = VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	center.add_child(col)

	var title: Label = UiTheme.label("MINI RTS", 78, "bold")
	title.add_theme_font_override("font", UiTheme.spaced("bold", 10))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var underline: CenterContainer = CenterContainer.new()
	var bar: ColorRect = ColorRect.new()
	bar.color = Palette.ACCENT
	bar.custom_minimum_size = Vector2(84, 3)
	underline.add_child(bar)
	col.add_child(underline)
	var tag: Label = UiTheme.label("GATHER  ·  BUILD  ·  CONQUER", 15, "semibold", Palette.MUTED)
	tag.add_theme_font_override("font", UiTheme.spaced("semibold", 4))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tag)
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0, 26)
	col.add_child(gap)

	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.box(Palette.PANEL, 16, Palette.PANEL_BORDER, 1, Vector2(26, 22), 26))
	col.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(380, 0)
	panel.add_child(box)

	var play: Button = _button("Play  ·  random map", true)
	play.pressed.connect(func() -> void: start_requested.emit(_settings("generated")))
	box.add_child(play)
	var tutorial: Button = _button("Play  ·  tutorial map", false)
	tutorial.pressed.connect(func() -> void: start_requested.emit(_settings("tutorial")))
	box.add_child(tutorial)

	var seed_row: HBoxContainer = HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	box.add_child(seed_row)
	var seed_label: Label = UiTheme.label("Map seed", 14, "semibold", Palette.MUTED)
	seed_label.custom_minimum_size = Vector2(66, 0)
	seed_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	seed_row.add_child(seed_label)
	_seed_edit = LineEdit.new()
	_seed_edit.text = str(_rng.randi_range(1, 99999))
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.max_length = 9
	seed_row.add_child(_seed_edit)
	var shuffle: Button = Button.new()
	shuffle.text = "Shuffle"
	shuffle.focus_mode = Control.FOCUS_NONE
	shuffle.pressed.connect(func() -> void: _seed_edit.text = str(_rng.randi_range(1, 99999)))
	seed_row.add_child(shuffle)

	var policy_row: HBoxContainer = HBoxContainer.new()
	policy_row.add_theme_constant_override("separation", 8)
	box.add_child(policy_row)
	var policy_label: Label = UiTheme.label("Opponent", 14, "semibold", Palette.MUTED)
	policy_label.custom_minimum_size = Vector2(66, 0)
	policy_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	policy_row.add_child(policy_label)
	_policy = OptionButton.new()
	_policy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_policy.focus_mode = Control.FOCUS_NONE
	for p: Array in POLICIES:
		_policy.add_item(p[1])
	policy_row.add_child(_policy)

	var help_button: Button = _button("How to play", false)
	box.add_child(help_button)
	_help = _build_help()
	_help.visible = false
	col.add_child(_help)
	help_button.pressed.connect(func() -> void: _help.visible = not _help.visible)

	var footer: Label = UiTheme.label("Godot 4.7.2  ·  deterministic 20 Hz simulation  ·  A*, fog of war, state-machine AI", 12, "regular", Palette.FAINT)
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	footer.offset_right = -20
	footer.offset_bottom = -14
	footer.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(footer)


func _button(text: String, primary: bool) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 48)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 17)
	if primary:
		b.add_theme_stylebox_override("normal", UiTheme.box(Color(Palette.ACCENT, 0.88), 10))
		b.add_theme_stylebox_override("hover", UiTheme.box(Palette.ACCENT.lightened(0.15), 10))
		b.add_theme_stylebox_override("pressed", UiTheme.box(Palette.ACCENT.darkened(0.1), 10))
		b.add_theme_color_override("font_color", Palette.BG)
		b.add_theme_color_override("font_hover_color", Palette.BG)
		b.add_theme_color_override("font_pressed_color", Palette.BG)
	return b


func _build_help() -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.box(Palette.PANEL, 14, Palette.PANEL_BORDER, 1, Vector2(22, 16), 18))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 5)
	p.add_child(grid)
	var rows: Array = [
		["Left click", "Select a unit or building"],
		["Left drag", "Box-select your units (up to 24)"],
		["Right click", "Move · gather (workers on wood/gold) · attack (soldiers)"],
		["B, then click", "Place a barracks (a worker must be selected)"],
		["Q / W / E", "Train worker / melee / ranged at the selected building"],
		["Esc", "Cancel placement or clear the selection"],
		["WASD, screen edges", "Pan the camera"],
	]
	for r: Array in rows:
		grid.add_child(UiTheme.label(r[0], 14, "semibold", Palette.ACCENT))
		grid.add_child(UiTheme.label(r[1], 14, "regular", Palette.TEXT))
	return p


func _settings(map: String) -> Dictionary:
	return {"map": map, "seed": _seed(), "ai_policy": POLICIES[_policy.selected][0]}


func _seed() -> int:
	return int(_seed_edit.text) if _seed_edit.text.is_valid_int() else 1


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var s: Vector2 = size
	draw_rect(Rect2(Vector2.ZERO, s), Palette.BG)
	# Soft glows in the faction colours.
	_glow(Vector2(s.x * 0.18, s.y * 0.85), s.y * 0.75, Palette.TEAM["player"])
	_glow(Vector2(s.x * 0.86, s.y * 0.12), s.y * 0.7, Palette.TEAM["ai"])
	# A slowly drifting grid.
	var step: float = 48.0
	var off: Vector2 = Vector2(fmod(_t * 6.0, step), fmod(_t * 3.0, step))
	var x: float = -step + off.x
	while x < s.x + step:
		draw_line(Vector2(x, 0), Vector2(x, s.y), Color(1, 1, 1, 0.028), 1.0)
		x += step
	var y: float = -step + off.y
	while y < s.y + step:
		draw_line(Vector2(0, y), Vector2(s.x, y), Color(1, 1, 1, 0.028), 1.0)
		y += step
	# Decorative pieces circling slowly.
	Art.node(self, Vector2(s.x * 0.12, s.y * 0.3), "wood", 1.0, _t, 0.35)
	Art.node(self, Vector2(s.x * 0.9, s.y * 0.72), "gold", 1.0, _t, 0.35)
	var kinds: Array[String] = ["worker", "melee", "ranged", "worker", "ranged", "melee"]
	for i: int in 12:
		var f: String = "player" if i % 2 == 0 else "ai"
		var base: Vector2 = Vector2(s.x * (0.08 + 0.84 * fmod(i * 0.37, 1.0)), s.y * (0.1 + 0.8 * fmod(i * 0.61, 1.0)))
		var p: Vector2 = base + Vector2(sin(_t * 0.25 + i), cos(_t * 0.2 + i * 1.7)) * 40.0
		Art.unit(self, p, kinds[i % kinds.size()], f, -1.0, 0.28)
	# Vignette.
	for k: int in 6:
		var a: float = 0.06 * (k + 1)
		var m: float = 40.0 * (6 - k)
		draw_rect(Rect2(Vector2.ZERO, Vector2(s.x, m * 0.6)), Color(0, 0, 0, a * 0.5))
		draw_rect(Rect2(Vector2(0, s.y - m * 0.6), Vector2(s.x, m * 0.6)), Color(0, 0, 0, a * 0.5))


func _glow(c: Vector2, r: float, col: Color) -> void:
	for k: int in 18:
		var f: float = 1.0 - float(k) / 18.0
		draw_circle(c, r * f, Color(col, 0.012), true, -1.0, true)
