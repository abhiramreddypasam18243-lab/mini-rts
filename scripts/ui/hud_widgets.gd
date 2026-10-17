## Small custom-drawn HUD controls (presentation layer), in the parchment
## and wood style of the Kenney RPG UI pack.
class_name HudWidgets
extends RefCounted


## Draws a resource cost as small icons and numbers; red when unaffordable.
static func draw_cost(ci: CanvasItem, pos: Vector2, cost: Dictionary, have: Dictionary, size: int = 15) -> void:
	var font: Font = UiTheme.font("bold")
	var x: float = pos.x
	for r: String in ["wood", "gold"]:
		if cost[r] <= 0:
			continue
		Art.icon(ci, Vector2(x + 8, pos.y - 5), r, 0.55)
		var col: Color = Palette.INK if have.get(r, 0) >= cost[r] else Palette.BAD
		ci.draw_string(font, Vector2(x + 18, pos.y), str(cost[r]), HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		x += 24 + font.get_string_size(str(cost[r]), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 8


## A command button: unit or building sprite, title, gold hotkey badge and
## cost, drawn on a parchment button. The disabled reason is its tooltip.
class CommandButton extends Button:
	var title: String = ""
	var hotkey: String = ""
	var kind: String = ""
	var faction: String = "player"
	var cost: Dictionary = {"wood": 0, "gold": 0}
	var have: Dictionary = {}

	func _init() -> void:
		custom_minimum_size = Vector2(212, 62)
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func set_state(enabled: bool, reason: String, p_have: Dictionary) -> void:
		if disabled == enabled or tooltip_text != reason or have != p_have:
			disabled = not enabled
			tooltip_text = reason
			have = p_have.duplicate()
			queue_redraw()

	func _draw() -> void:
		var a: float = 0.5 if disabled else 1.0
		var c: Vector2 = Vector2(30, size.y / 2.0)
		if kind == "barracks":
			draw_texture_rect(Art.tex("barracks"), Rect2(c - Vector2(22, 24), Vector2(44, 44)), false, Color(1, 1, 1, a))
		else:
			Art.unit_icon(self, c, kind, faction, 36.0, a)
		var font: Font = UiTheme.font("bold")
		draw_string(font, Vector2(58, 27), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(Palette.INK, a))
		HudWidgets.draw_cost(self, Vector2(58, 48), cost, have, 15)
		if hotkey != "":
			var b: Vector2 = Vector2(size.x - 17, 16)
			draw_circle(b, 11.0, Color(0.36, 0.24, 0.14, a), true, -1.0, true)
			draw_circle(b, 9.0, Color(Palette.ACCENT, a), true, -1.0, true)
			var hw: float = font.get_string_size(hotkey, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			draw_string(font, b + Vector2(-hw / 2.0, 5), hotkey, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(Palette.INK, a))


## One production queue slot: the unit being made and its progress.
## Clicking it cancels that item (refunded once).
class QueueSlot extends Button:
	var kind: String = ""
	var faction: String = "player"
	var progress: float = 0.0
	var active: bool = false

	func _init() -> void:
		custom_minimum_size = Vector2(46, 48)
		focus_mode = Control.FOCUS_NONE
		var empty: StyleBoxTexture = UiTheme.frame("buttonSquare_beige_pressed", 10, Vector2.ZERO, Color(1, 1, 1, 0.45))
		add_theme_stylebox_override("normal", empty)
		add_theme_stylebox_override("hover", empty)
		add_theme_stylebox_override("pressed", empty)
		add_theme_stylebox_override("disabled", empty)

	func _draw() -> void:
		if kind == "":
			return
		draw_texture_rect(UiTheme.tex("buttonSquare_beige"), Rect2(Vector2.ZERO, size), false)
		Art.unit_icon(self, size / 2.0 - Vector2(0, 3), kind, faction, 30.0)
		if active:
			Art.bar(self, Rect2(6, size.y - 9, size.x - 12, 4), progress, Palette.GOOD)


## A large portrait of the inspected entity on a parchment square.
class Portrait extends Control:
	var kind: String = ""
	var faction: String = "player"
	var ghost: bool = false
	var t: float = 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(86, 86)

	func _draw() -> void:
		draw_style_box(UiTheme.parchment(Vector2.ZERO), Rect2(Vector2.ZERO, size))
		var c: Vector2 = size / 2.0
		match kind:
			"":
				return
			"wood", "gold":
				Art.icon(self, c, kind, 1.7)
			"hq", "barracks":
				var tint: Color = Color(0.65, 0.65, 0.7) if ghost else Color.WHITE
				draw_texture_rect(Art.tex("castle" if kind == "hq" else "barracks"), Rect2(c - Vector2(38, 36), Vector2(76, 76)), false, tint)
				Art.banner(self, Vector2(size.x - 18, 10), Palette.TEAM[faction], t)
			_:
				Art.unit_icon(self, c, kind, faction, 62.0)


## A health bar from the UI pack.
class HealthBar extends Control:
	var hp: int = 0
	var max_hp: int = 1

	func _init() -> void:
		custom_minimum_size = Vector2(180, 18)

	func _draw() -> void:
		var ratio: float = float(hp) / maxf(max_hp, 1)
		var colour: String = "Green" if ratio > 0.6 else ("Yellow" if ratio > 0.3 else "Red")
		Art.ui_bar(self, Rect2(0, 2, size.x, 14), ratio, colour)


## A small resource or population icon.
class Icon extends Control:
	var kind: String = "wood"

	func _init(p_kind: String = "wood") -> void:
		kind = p_kind
		custom_minimum_size = Vector2(30, 30)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		Art.icon(self, size / 2.0, kind, 1.0)


## One unit in a multi-selection: click to select just that unit.
class UnitTile extends Button:
	var kind: String = ""
	var faction: String = "player"
	var hp_ratio: float = 1.0

	func _init() -> void:
		custom_minimum_size = Vector2(44, 46)
		focus_mode = Control.FOCUS_NONE
		var s: StyleBoxTexture = UiTheme.frame("buttonSquare_beige", 10, Vector2.ZERO)
		add_theme_stylebox_override("normal", s)
		add_theme_stylebox_override("hover", UiTheme.frame("buttonSquare_beige", 10, Vector2.ZERO, Color(1.0, 0.95, 0.8)))
		add_theme_stylebox_override("pressed", UiTheme.frame("buttonSquare_beige_pressed", 10, Vector2.ZERO))

	func _draw() -> void:
		Art.unit_icon(self, size / 2.0 - Vector2(0, 4), kind, faction, 28.0)
		Art.bar(self, Rect2(6, size.y - 9, size.x - 12, 4), hp_ratio, Palette.health(hp_ratio))
