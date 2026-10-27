## The root of the app (presentation layer): shows the main menu, starts a
## match, and on restart replaces the match with a brand-new one built from
## the same settings, so nothing from the old match remains (AC-53, AC-74).
extends Node

var menu: MainMenu
var game: Game
## The menu lives in its own CanvasLayer so it is laid out against the screen.
var _menu_layer: CanvasLayer
var _settings: Dictionary = {}
## A dark sheet that fades out after each screen change (drawing only).
var _fade: ColorRect
var _rotate: Control


func _ready() -> void:
	# Kenney CC0 cursors: a gold sword, and a gauntlet over buttons.
	Input.set_custom_mouse_cursor(UiTheme.tex("cursorSword_gold"), Input.CURSOR_ARROW, Vector2(2, 2))
	Input.set_custom_mouse_cursor(UiTheme.tex("cursorGauntlet_bronze"), Input.CURSOR_POINTING_HAND, Vector2(6, 2))
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.06, 0.04, 0.02)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	add_child(Sound.new())
	# Phones and tablets (D-45): a larger interface, and a notice in portrait.
	TouchInput.apply_layout(get_tree())
	_rotate = _build_rotate_notice()
	layer.add_child(_rotate)
	get_viewport().size_changed.connect(_check_orientation)
	_check_orientation()
	if Benchmark.requested():
		start_match({"map": "generated", "seed": 42, "mode": "bench"})
	else:
		show_menu()


## "Turn your phone sideways", shown over everything in portrait on touch
## screens: the game and its HUD are laid out for landscape.
func _build_rotate_notice() -> Control:
	var sheet: ColorRect = ColorRect.new()
	sheet.color = Color(0.1, 0.07, 0.04, 0.96)
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet.add_child(center)
	var l: Label = UiTheme.label("Turn your phone sideways\nto play Mini RTS", 40, "title", Palette.ACCENT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(l)
	sheet.visible = false
	return sheet


func _check_orientation() -> void:
	var s: Vector2 = get_viewport().get_visible_rect().size
	_rotate.visible = TouchInput.enabled() and s.y > s.x


## Fades in from dark, so screen changes are not hard cuts.
func _fade_in() -> void:
	_fade.modulate.a = 1.0
	var tw: Tween = _fade.create_tween()
	tw.tween_property(_fade, "modulate:a", 0.0, 0.55).set_trans(Tween.TRANS_SINE)


func is_menu_showing() -> bool:
	return menu != null


func show_menu() -> void:
	_free_game()
	if menu == null:
		_menu_layer = CanvasLayer.new()
		add_child(_menu_layer)
		menu = MainMenu.new()
		menu.start_requested.connect(start_match)
		_menu_layer.add_child(menu)
		_fade_in()


func start_match(settings: Dictionary) -> void:
	_settings = settings.duplicate()
	# An online match's connection (D-60) outlives the menu that opened it.
	if settings.get("net") is NetClient:
		(settings.net as NetClient).reparent(self)
	if menu != null:
		remove_child(_menu_layer)
		_menu_layer.queue_free()
		_menu_layer = null
		menu = null
	_free_game()
	game = Game.new()
	game.setup(_settings)
	game.restart_requested.connect(restart)
	game.menu_requested.connect(back_to_menu)
	add_child(game)
	_fade_in()


func restart() -> void:
	start_match(_settings)


func back_to_menu() -> void:
	show_menu()


func _free_game() -> void:
	if game != null:
		remove_child(game)
		game.queue_free()
		game = null
