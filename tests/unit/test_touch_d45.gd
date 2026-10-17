## Phone and tablet controls (decision D-45): taps select or order, a drag
## pans the map, the toolbar replaces keys and the right mouse button.
extends GutTest

var main: Node
var game: Game


func before_each() -> void:
	TouchInput.force(true)
	main = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(main)
	main.start_match({"map": "generated", "seed": 42, "ai_policy": "balanced"})
	game = main.game


func after_each() -> void:
	TouchInput.force(null)


func _screen_of(world: Vector2) -> Vector2:
	return game.get_global_transform_with_canvas() * world


func _tap(world: Vector2) -> void:
	var s: Vector2 = _screen_of(world)
	game.touch_press(s)
	game.touch_release(s)


func _worker() -> int:
	return game.sim.unit_ids().filter(func(id: int) -> bool: return game.sim.entity(id).faction == "player")[0]


func test_d45_touch_mode_is_on() -> void:
	assert_true(game.touch)
	assert_true(game.hud._touch_bar.visible, "the touch toolbar shows")


func test_d45_tap_own_unit_selects_it() -> void:
	var w: int = _worker()
	_tap(game.draw_pos(game.sim.entity(w)))
	assert_eq(game.selection.selected, [w])


func test_d45_tap_ground_orders_the_selection() -> void:
	var w: int = _worker()
	game.select_only(w)
	var cell: Vector2i = game.sim.entity(w).unit_cell() + Vector2i(0, 3)
	_tap((Vector2(cell) + Vector2(0.5, 0.5)) * Consts.PIXELS_PER_CELL)
	assert_eq(game.sim.entity(w).order_type, "move")
	assert_eq(game.sim.entity(w).order_cell, cell)
	assert_eq(game.selection.selected, [w], "the selection is kept")


func test_d45_drag_pans_the_map_and_gives_no_order() -> void:
	var w: int = _worker()
	game.select_only(w)
	var before: Vector2 = game.camera.position
	var start: Vector2 = Vector2(640, 300)
	game.touch_press(start)
	# Drag the ground 100 screen pixels to the left: the camera moves right.
	game.touch_move(start + Vector2(-40, 0), Vector2(-40, 0))
	game.touch_move(start + Vector2(-100, 0), Vector2(-60, 0))
	game.touch_release(start + Vector2(-100, 0))
	assert_gt(game.camera.position.x, before.x, "the view moved")
	assert_eq(game.sim.entity(w).order_type, "idle", "a drag is not an order")


func test_d45_box_select_mode_selects_a_group() -> void:
	var sim: Simulation = game.sim
	var mine: Array = sim.unit_ids().filter(func(id: int) -> bool: return sim.entity(id).faction == "player")
	var lo: Vector2 = game.draw_pos(sim.entity(mine[0]))
	var hi: Vector2 = lo
	for id: int in mine:
		var p: Vector2 = game.draw_pos(sim.entity(id))
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	game.box_mode = true
	game.touch_press(_screen_of(lo - Vector2(20, 20)))
	game.touch_move(_screen_of(hi + Vector2(20, 20)), Vector2(1, 1))
	game.touch_release(_screen_of(hi + Vector2(20, 20)))
	assert_eq(game.selection.selected.size(), mine.size(), "all three workers")
	assert_false(game.box_mode, "box mode is used once")


func test_d45_placement_needs_two_taps_on_the_same_spot() -> void:
	var sim: Simulation = game.sim
	# The start (200 wood, 100 gold) pays for a barracks (120 wood, 60 gold).
	game.select_only(_worker())
	game.start_placing()
	assert_true(game.placing)
	# Seed 42: the HQ is at (3, 9); anchor (9, 4) is a valid, explored site.
	# A 2 x 2 barracks centred on the corner (10, 5) is anchored at (9, 4).
	var spot: Vector2 = Vector2(10, 5) * Consts.PIXELS_PER_CELL
	game.touch_press(_screen_of(spot))
	assert_true(game.placing, "the first tap only moves the preview")
	game.touch_press(_screen_of(spot))
	assert_false(game.placing, "the second tap on the same spot builds")
	var built: bool = false
	for id: int in sim.entities:
		if sim.entity(id).kind == "barracks":
			built = true
	assert_true(built)


func test_d45_cancel_clears_modes_then_selection() -> void:
	game.select_only(_worker())
	game.start_aiming()
	game.touch_cancel()
	assert_false(game.aiming)
	assert_eq(game.selection.selected.size(), 1, "first Cancel only stops aiming")
	game.touch_cancel()
	assert_eq(game.selection.selected.size(), 0)


func test_d45_queue_toggle_queues_tapped_orders() -> void:
	var w: int = _worker()
	game.select_only(w)
	var c: Vector2i = game.sim.entity(w).unit_cell()
	# Open ground above the workers (the HQ is below them).
	_tap((Vector2(c + Vector2i(0, -3)) + Vector2(0.5, 0.5)) * Consts.PIXELS_PER_CELL)
	game.touch_queue = true
	_tap((Vector2(c + Vector2i(3, -3)) + Vector2(0.5, 0.5)) * Consts.PIXELS_PER_CELL)
	assert_eq(game.sim.entity(w).orders.size(), 1, "the second tap was queued")
