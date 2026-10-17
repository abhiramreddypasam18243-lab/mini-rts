## The root of the app (presentation layer): shows the main menu, starts a
## match, and on restart replaces the match with a brand-new one built from
## the same settings, so nothing from the old match remains (AC-53, AC-74).
extends Node

var menu: MainMenu
var game: Game
## The menu lives in its own CanvasLayer so it is laid out against the screen.
var _menu_layer: CanvasLayer
var _settings: Dictionary = {}


func _ready() -> void:
	show_menu()


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


func start_match(settings: Dictionary) -> void:
	_settings = settings.duplicate()
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


func restart() -> void:
	start_match(_settings)


func back_to_menu() -> void:
	show_menu()


func _free_game() -> void:
	if game != null:
		remove_child(game)
		game.queue_free()
		game = null
