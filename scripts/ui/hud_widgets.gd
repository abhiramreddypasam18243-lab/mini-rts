## Small custom-drawn HUD controls (presentation layer).
class_name HudWidgets
extends RefCounted


## Draws a resource cost as small icons and numbers; red when unaffordable.
static func draw_cost(ci: CanvasItem, pos: Vector2, cost: Dictionary, have: Dictionary, size: int = 13) -> void:
	var font: Font = UiTheme.font("semibold")
	var x: float = pos.x
	for r: String in ["wood", "gold"]:
		if cost[r] <= 0:
			continue
		ci.draw_circle(Vector2(x + 4, pos.y - 4), 4.0, Palette.resource(r), true, -1.0, true)
		var col: Color = Palette.MUTED if have.get(r, 0) >= cost[r] else Palette.BAD
		ci.draw_string(font, Vector2(x + 11, pos.y), str(cost[r]), HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		x += 14 + font.get_string_size(str(cost[r]), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 8


## A command button: symbol, title, hotkey badge and cost, all drawn on top
## of the themed button background. The disabled reason is its tooltip.
class CommandButton extends Button:
	var title: String = ""
	var hotkey: String = ""
	var kind: String = ""
	var faction: String = "player"
	var cost: Dictionary = {"wood": 0, "gold": 0}
	var have: Dictionary = {}

	func _init() -> void:
		custom_minimum_size = Vector2(204, 58)
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func set_state(enabled: bool, reason: String, p_have: Dictionary) -> void:
		if disabled == enabled or tooltip_text != reason or have != p_have:
			disabled = not enabled
			tooltip_text = reason
			have = p_have.duplicate()
			queue_redraw()

	func _draw() -> void:
		var a: float = 0.45 if disabled else 1.0
		var c: Vector2 = Vector2(24, size.y / 2.0)
		if kind == "barracks":
			draw_circle(c, 14.0, Color(Palette.TEAM_DARK[faction], a), true, -1.0, true)
			Art.glyph(self, "barracks", c, 1.0, Color(Palette.TEAM_LIGHT[faction], a))
		else:
			Art.unit(self, c, kind, faction, 12.0, a)
		var font: Font = UiTheme.font("semibold")
		draw_string(font, Vector2(46, 25), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(Palette.TEXT, a))
		HudWidgets.draw_cost(self, Vector2(46, 45), cost, have, 13)
		if hotkey != "":
			var badge: Rect2 = Rect2(size.x - 26, 7, 19, 19)
			draw_style_box(UiTheme.box(Color(1, 1, 1, 0.08 * a), 5, Color(1, 1, 1, 0.18 * a), 1, Vector2.ZERO), badge)
			var hw: float = font.get_string_size(hotkey, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(font, Vector2(badge.get_center().x - hw / 2.0, badge.end.y - 5), hotkey, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(Palette.MUTED, a))


## One production queue slot: the unit being made and its progress.
## Clicking it cancels that item (refunded once).
class QueueSlot extends Button:
	var kind: String = ""
	var faction: String = "player"
	var progress: float = 0.0
	var active: bool = false

	func _init() -> void:
		custom_minimum_size = Vector2(40, 40)
		focus_mode = Control.FOCUS_NONE

	func _draw() -> void:
		if kind == "":
			draw_style_box(UiTheme.box(Color(1, 1, 1, 0.02), 7, Color(1, 1, 1, 0.06), 1, Vector2.ZERO), Rect2(Vector2.ZERO, size))
			return
		Art.unit(self, size / 2.0 - Vector2(0, 2), kind, faction, 10.0)
		if active:
			Art.bar(self, Rect2(5, size.y - 6, size.x - 10, 3), progress, Palette.ACCENT)


## A large portrait of the inspected entity.
class Portrait extends Control:
	var kind: String = ""
	var faction: String = "player"
	var ghost: bool = false
	var t: float = 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(76, 76)

	func _draw() -> void:
		draw_style_box(UiTheme.box(Color(0, 0, 0, 0.28), 12, Color(1, 1, 1, 0.07), 1, Vector2.ZERO), Rect2(Vector2.ZERO, size))
		var c: Vector2 = size / 2.0
		match kind:
			"":
				return
			"wood", "gold":
				draw_set_transform(c, 0.0, Vector2(2.0, 2.0))
				Art.node(self, Vector2.ZERO, kind, 1.0, t)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"hq", "barracks":
				Art.building(self, Rect2(c - Vector2(30, 30), Vector2(60, 60)), kind, faction, t, true, 1.0, ghost)
			_:
				Art.unit(self, c, kind, faction, 22.0)


## A health bar with its numbers.
class HealthBar extends Control:
	var hp: int = 0
	var max_hp: int = 1

	func _init() -> void:
		custom_minimum_size = Vector2(180, 16)

	func _draw() -> void:
		var ratio: float = float(hp) / maxf(max_hp, 1)
		Art.bar(self, Rect2(0, 5, size.x, 6), ratio, Palette.health(ratio))


## A small resource or population icon.
class Icon extends Control:
	var kind: String = "wood"

	func _init(p_kind: String = "wood") -> void:
		kind = p_kind
		custom_minimum_size = Vector2(24, 24)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		Art.icon(self, size / 2.0, kind, 1.0)


## One unit in a multi-selection: click to select just that unit.
class UnitTile extends Button:
	var kind: String = ""
	var faction: String = "player"
	var hp_ratio: float = 1.0

	func _init() -> void:
		custom_minimum_size = Vector2(38, 38)
		focus_mode = Control.FOCUS_NONE

	func _draw() -> void:
		Art.unit(self, size / 2.0 - Vector2(0, 2), kind, faction, 10.0)
		Art.bar(self, Rect2(6, size.y - 6, size.x - 12, 3), hp_ratio, Palette.health(hp_ratio))
