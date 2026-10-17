## The minimap (build step 11, decision D-43): it shows only what the main
## view may show, maps clicks to the right place, and orders units.
extends GutTest

var main: Node
var game: Game


func before_each() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(main)
	main.start_match({"map": "generated", "seed": 42, "ai_policy": "balanced"})
	game = main.game


func test_minimap_mapping_round_trips() -> void:
	var mm: Minimap = game.hud.minimap
	# 48 x 48 cells drawn 176 px wide: 176 / 48 px per cell.
	assert_almost_eq(mm.scale_px(), 176.0 / 48.0, 0.0001)
	var world: Vector2 = Vector2(10.5, 20.5) * Consts.PIXELS_PER_CELL
	assert_almost_eq(mm.to_world(mm.to_minimap(world)).x, world.x, 0.01)
	assert_almost_eq(mm.to_world(mm.to_minimap(world)).y, world.y, 0.01)
	assert_eq(mm.picture_size(), Vector2(176, 176))


func test_minimap_shows_only_what_the_player_may_see() -> void:
	var sim: Simulation = game.sim
	var mm: Minimap = game.hud.minimap
	var own: int = sim.unit_ids().filter(func(id: int) -> bool: return sim.entity(id).faction == "player")[0]
	var hidden_enemy: int = sim.unit_ids().filter(func(id: int) -> bool: return sim.entity(id).faction == "ai")[0]
	assert_false(sim.fog.is_visible("player", sim.entity(hidden_enemy).unit_cell()), "the AI's workers start in fog")
	var units: Array = mm.markers().filter(func(m: Dictionary) -> bool: return m.kind == "unit")
	var cells: Array = units.map(func(m: Dictionary) -> Vector2i: return m.cell)
	assert_true(cells.has(sim.entity(own).unit_cell()), "own unit shown")
	for m: Dictionary in units:
		assert_eq(m.faction, "player", "no enemy unit leaks through the fog")
	var enemy_hq: int = sim.hq_of("ai")
	var buildings: Array = mm.markers().filter(func(m: Dictionary) -> bool: return m.kind == "building" and m.faction == "ai")
	assert_eq(buildings.size(), 0, "the unseen enemy HQ is not shown (id %d)" % enemy_hq)


func test_minimap_left_click_moves_the_camera() -> void:
	var mm: Minimap = game.hud.minimap
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = mm.picture_size() / 2.0
	mm._gui_input(click)
	# The map's centre (24, 24 cells); the camera may be clamped only by the
	# HUD padding, never further than half a screen from it.
	var centre: Vector2 = Vector2(24, 24) * Consts.PIXELS_PER_CELL
	assert_lt(game.camera.position.distance_to(centre), 200.0)


func test_minimap_right_click_orders_the_selection() -> void:
	var sim: Simulation = game.sim
	var mm: Minimap = game.hud.minimap
	var worker: int = sim.unit_ids().filter(func(id: int) -> bool: return sim.entity(id).faction == "player")[0]
	game.select_only(worker)
	var target_cell: Vector2i = sim.entity(worker).unit_cell() + Vector2i(3, 0)
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	click.position = mm.to_minimap((Vector2(target_cell) + Vector2(0.5, 0.5)) * Consts.PIXELS_PER_CELL)
	mm._gui_input(click)
	assert_eq(sim.entity(worker).order_type, "move")
	assert_eq(sim.entity(worker).order_cell, target_cell)
