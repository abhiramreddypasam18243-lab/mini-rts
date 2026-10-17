## The title screen (SPEC 9; AC-74): starts a match on a generated map (with
## a seed) or the tutorial map, chooses the opponent, plays the demo and shows
## the controls. Behind it, a slowly drifting battlefield drawn with the
## game's own sprites: two castles, forests, rocks, gold and two armies.
class_name MainMenu
extends Control

signal start_requested(settings: Dictionary)

const POLICIES: Array[Array] = [["balanced", "Balanced"], ["aggressive", "Aggressive"], ["economy_first", "Economy-first"]]
## The backdrop is a field this big; the view drifts across it.
const FIELD: Vector2 = Vector2(2200, 1100)
const TILE: float = 56.0

var _t: float = 0.0
var _seed_edit: LineEdit
var _policy: OptionButton
var _help: PanelContainer
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _scene: Array[Dictionary] = []


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

	var title: Label = UiTheme.label("MINI RTS", 92, "title", Palette.ACCENT)
	title.add_theme_font_override("font", UiTheme.spaced("title", 8))
	title.add_theme_constant_override("outline_size", 16)
	title.add_theme_color_override("font_outline_color", Color(0.22, 0.12, 0.05))
	title.add_theme_constant_override("shadow_offset_y", 6)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var tag: Label = UiTheme.label("GATHER  ·  BUILD  ·  CONQUER", 20, "title", Palette.TEXT)
	tag.add_theme_font_override("font", UiTheme.spaced("title", 4))
	tag.add_theme_constant_override("outline_size", 8)
	tag.add_theme_color_override("font_outline_color", Color(0.15, 0.09, 0.04, 0.9))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tag)
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0, 22)
	col.add_child(gap)

	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(Vector2(26, 22)))
	col.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(400, 0)
	panel.add_child(box)

	var play: Button = _button("Play  ·  random map", "gold")
	play.pressed.connect(func() -> void: start_requested.emit(_settings("generated")))
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

	var demo: Button = _button("Watch demo", "beige")
	demo.pressed.connect(func() -> void: start_requested.emit({"mode": "demo"}))
	box.add_child(demo)
	var help_button: Button = _button("How to play", "brown")
	box.add_child(help_button)
	_help = _build_help()
	_help.visible = false
	col.add_child(_help)
	help_button.pressed.connect(func() -> void: _help.visible = not _help.visible)

	var footer: Label = UiTheme.label("Godot 4.7.2  ·  art by Kenney (CC0)  ·  A* · fog of war · state-machine AI", 14, "semibold", Palette.TEXT)
	footer.add_theme_constant_override("outline_size", 6)
	footer.add_theme_color_override("font_outline_color", Color(0.12, 0.07, 0.03, 0.9))
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	footer.offset_right = -20
	footer.offset_bottom = -14
	footer.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(footer)


func _row_label(text: String) -> Label:
	var l: Label = UiTheme.label(text, 17, "bold", Palette.TEXT)
	l.custom_minimum_size = Vector2(82, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _button(text: String, colour: String) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 50)
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
	var rows: Array = [
		["Left click", "Select a unit or building"],
		["Left drag", "Box-select your units (up to 24)"],
		["Right click", "Move · gather (workers on wood/gold) · attack (soldiers)"],
		["B, then click", "Place a barracks (a worker must be selected)"],
		["Q / W / E", "Train worker / knight / mage at the selected building"],
		["Esc", "Cancel placement or clear the selection"],
		["WASD, screen edges", "Pan the camera"],
	]
	for r: Array in rows:
		grid.add_child(UiTheme.label(r[0], 16, "bold", Palette.INK))
		grid.add_child(UiTheme.label(r[1], 16, "regular", Palette.INK))
	return p


func _settings(map: String) -> Dictionary:
	return {"map": map, "seed": _seed(), "ai_policy": POLICIES[_policy.selected][0]}


func _seed() -> int:
	return int(_seed_edit.text) if _seed_edit.text.is_valid_int() else 1


# --- the drifting battlefield backdrop -------------------------------------------

## Places castles, a barracks, forests, rocks, gold and two armies on the field.
func _build_scene() -> void:
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = 7  # the same backdrop every time
	_scene.append({"kind": "castle", "pos": Vector2(330, 520), "size": 230.0, "faction": "player"})
	_scene.append({"kind": "castle", "pos": Vector2(1870, 470), "size": 230.0, "faction": "ai"})
	_scene.append({"kind": "barracks", "pos": Vector2(560, 760), "size": 150.0, "faction": "player"})
	_scene.append({"kind": "barracks", "pos": Vector2(1640, 260), "size": 150.0, "faction": "ai"})
	for i: int in 70:
		var p: Vector2 = Vector2(r.randf_range(0, FIELD.x), r.randf_range(0, FIELD.y))
		if absf(p.y - 520.0) < 140.0 and absf(p.x - 1100.0) < 700.0:
			continue  # keep the middle open for the armies
		var k: String = ["tree_pine", "tree_tall", "rock_cluster", "rock_big", "gold_ore", "tree_pine_small", "tree_pine"][r.randi_range(0, 6)]
		_scene.append({"kind": k, "pos": p, "size": r.randf_range(60.0, 110.0)})
	for i: int in 14:
		var f: String = "player" if i < 7 else "ai"
		var x: float = (850.0 if f == "player" else 1350.0) + r.randf_range(-90, 90)
		var y: float = 470.0 + r.randf_range(-90, 110)
		_scene.append({"kind": "unit", "unit": ["melee", "ranged", "melee", "worker"][i % 4], "faction": f, "pos": Vector2(x, y)})
	_scene.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.pos.y < b.pos.y)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var s: Vector2 = size
	var cam: Vector2 = Vector2((FIELD.x - s.x) * 0.5 + sin(_t * 0.05) * (FIELD.x - s.x) * 0.45, (FIELD.y - s.y) * 0.5 + cos(_t * 0.04) * 60.0)
	# Grass.
	var grass_a: Texture2D = Art.tex("grass_a")
	var grass_b: Texture2D = Art.tex("grass_b")
	var x0: int = int(floor(cam.x / TILE))
	var y0: int = int(floor(cam.y / TILE))
	for y: int in range(y0, y0 + int(s.y / TILE) + 2):
		for x: int in range(x0, x0 + int(s.x / TILE) + 2):
			draw_texture_rect(grass_a if TerrainLayer.noise(x, y) < 0.6 else grass_b, Rect2(Vector2(x, y) * TILE - cam, Vector2(TILE, TILE)), false)
	# Scenery and armies.
	for o: Dictionary in _scene:
		var p: Vector2 = o.pos - cam
		if p.x < -260 or p.x > s.x + 260 or p.y < -260 or p.y > s.y + 260:
			continue
		match o.kind:
			"castle", "barracks":
				var sz: float = o.size
				draw_texture_rect(Art.tex(o.kind), Rect2(p - Vector2(sz / 2.0, sz * 0.75), Vector2(sz, sz)), false)
				Art.banner(self, p + Vector2(sz * 0.32, -sz * 0.62), Palette.TEAM[o.faction], _t)
			"unit":
				var bob: float = sin(_t * 3.0 + p.x * 0.05) * 1.5
				Art.unit(self, p + Vector2(0, bob), o.unit, o.faction, 1.45)
			_:
				var sz2: float = o.size
				draw_texture_rect(Art.tex(o.kind), Rect2(p - Vector2(sz2, sz2) * 0.5, Vector2(sz2, sz2)), false)
	# Warm darkening so the title and panel stand out, and a smooth vignette:
	# each edge is a quad whose colour fades from dark to clear (no banding).
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.1, 0.06, 0.02, 0.25))
	var dark: Color = Color(0.06, 0.035, 0.01, 0.75)
	var clear: Color = Color(0.06, 0.035, 0.01, 0.0)
	var m: float = minf(s.x, s.y) * 0.32
	_fade(Vector2.ZERO, Vector2(s.x, 0), Vector2(s.x, m), Vector2(0, m), dark, clear)
	_fade(Vector2(0, s.y), Vector2(s.x, s.y), Vector2(s.x, s.y - m), Vector2(0, s.y - m), dark, clear)
	_fade(Vector2.ZERO, Vector2(0, s.y), Vector2(m, s.y), Vector2(m, 0), dark, clear)
	_fade(Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(s.x - m, s.y), Vector2(s.x - m, 0), dark, clear)


## A quad dark along its first edge (a-b), fading to clear along the second (c-d).
func _fade(a: Vector2, b: Vector2, c: Vector2, d: Vector2, dark: Color, clear: Color) -> void:
	draw_polygon(PackedVector2Array([a, b, c, d]), PackedColorArray([dark, dark, clear, clear]))
