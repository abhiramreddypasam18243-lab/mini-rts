## AC-21 to AC-23, AC-73, AC-74, AC-76: the presentation layer's logic,
## tested headless. (Drawing itself is checked by eye and screenshots.)
extends GutTest

const P: String = "player"


## 20 x 12 map, wood node at (10, 3). Player HQ (0..2, 0..2), AI HQ (17..19, 9..11).
func _setup() -> Dictionary:
	var m: MapGrid = TestMaps.open(20, 12, [], [{"type": "wood", "cell": Vector2i(10, 3), "amount": 500}])
	var sim: Simulation = TestMaps.sim(m)
	var d: Dictionary = {"sim": sim}
	d.worker = sim.spawn_unit("worker", P, Vector2i(5, 5))
	d.melee = sim.spawn_unit("melee", P, Vector2i(6, 5))
	d.enemy = sim.spawn_unit("melee", "ai", Vector2i(9, 5))
	d.hidden_enemy = sim.spawn_unit("worker", "ai", Vector2i(16, 2))
	d.node = sim.node_at(Vector2i(10, 3))
	sim.update_fog()
	return d


func _at(cell: Vector2i) -> Vector2i:
	return MapGrid.cell_center(cell)


# --- AC-21: clicking ---------------------------------------------------------

func test_ac_21_click_friendly_unit_selects_it() -> void:
	var d: Dictionary = _setup()
	var s: Selection = Selection.new()
	s.click(d.sim, P, _at(Vector2i(5, 5)) + Vector2i(150, -100))
	assert_eq(s.selected, [d.worker])
	assert_eq(s.inspected, d.worker, "its details are shown")


func test_ac_21_click_enemy_shows_details_but_does_not_select() -> void:
	var d: Dictionary = _setup()
	var s: Selection = Selection.new()
	s.click(d.sim, P, _at(Vector2i(5, 5)))
	s.click(d.sim, P, _at(Vector2i(9, 5)))
	assert_eq(s.selected, [], "an enemy is never selected for commands")
	assert_eq(s.inspected, d.enemy)


func test_ac_21_click_hidden_enemy_shows_nothing() -> void:
	var d: Dictionary = _setup()
	var s: Selection = Selection.new()
	s.click(d.sim, P, _at(Vector2i(16, 2)))
	assert_eq(s.inspected, 0, "an enemy in fog cannot be clicked")


func test_ac_21_click_empty_ground_clears() -> void:
	var d: Dictionary = _setup()
	var s: Selection = Selection.new()
	s.click(d.sim, P, _at(Vector2i(5, 5)))
	s.click(d.sim, P, _at(Vector2i(12, 8)))
	assert_eq(s.selected, [])
	assert_eq(s.inspected, 0)


func test_ac_21_click_own_building_selects_it() -> void:
	var d: Dictionary = _setup()
	var s: Selection = Selection.new()
	s.click(d.sim, P, _at(Vector2i(1, 1)))
	assert_eq(s.selected, [d.sim.hq_of(P)])


# --- AC-22: box select -------------------------------------------------------

func test_ac_22_box_selects_only_friendly_units_inside() -> void:
	var d: Dictionary = _setup()
	var s: Selection = Selection.new()
	# The box (4..9, 4..6) holds the worker, the melee and the enemy melee.
	s.box(d.sim, P, _at(Vector2i(4, 4)), _at(Vector2i(9, 6)))
	assert_eq(s.selected, [d.worker, d.melee])


func test_ac_22_box_selects_at_most_24() -> void:
	var sim: Simulation = TestMaps.sim(TestMaps.open(40, 20))
	var ids: Array = []
	for i: int in 30:
		ids.append(sim.spawn_unit("worker", P, Vector2i(5 + i % 10, 5 + i / 10)))
	var s: Selection = Selection.new()
	s.box(sim, P, Vector2i(0, 0), Vector2i(40000, 20000))
	assert_eq(s.selected.size(), Consts.MAX_SELECTION)
	assert_eq(s.selected, ids.slice(0, 24), "the first 24 by id")


func test_ac_22_dead_unit_leaves_the_selection() -> void:
	var d: Dictionary = _setup()
	var s: Selection = Selection.new()
	s.box(d.sim, P, _at(Vector2i(4, 4)), _at(Vector2i(7, 6)))
	d.sim.destroy_entity(d.melee)
	s.prune(d.sim)
	assert_eq(s.selected, [d.worker])


# --- AC-23: context orders ---------------------------------------------------

func test_ac_23_right_click_empty_cell_moves() -> void:
	var d: Dictionary = _setup()
	var s: Selection = Selection.new()
	s.box(d.sim, P, _at(Vector2i(4, 4)), _at(Vector2i(7, 6)))
	var cmds: Array[Dictionary] = s.context_commands(d.sim, P, _at(Vector2i(12, 8)))
	assert_eq(cmds, [Commands.move(P, [d.worker, d.melee], Vector2i(12, 8))])


func test_ac_23_right_click_node_with_workers_harvests() -> void:
	var d: Dictionary = _setup()
	var s: Selection = Selection.new()
	s.box(d.sim, P, _at(Vector2i(4, 4)), _at(Vector2i(7, 6)))
	var cmds: Array[Dictionary] = s.context_commands(d.sim, P, _at(Vector2i(10, 3)))
	assert_eq(cmds, [Commands.harvest(P, [d.worker], d.node)], "only the workers harvest")


func test_ac_23_right_click_visible_enemy_attacks() -> void:
	var d: Dictionary = _setup()
	var s: Selection = Selection.new()
	s.box(d.sim, P, _at(Vector2i(4, 4)), _at(Vector2i(7, 6)))
	var cmds: Array[Dictionary] = s.context_commands(d.sim, P, _at(Vector2i(9, 5)))
	assert_eq(cmds, [Commands.attack(P, [d.melee], d.enemy)], "only the soldiers attack")


func test_ac_23_other_combinations_do_nothing() -> void:
	var d: Dictionary = _setup()
	var s: Selection = Selection.new()
	s.click(d.sim, P, _at(Vector2i(6, 5)))  # the melee soldier alone
	assert_eq(s.context_commands(d.sim, P, _at(Vector2i(10, 3))), [], "soldier on a node")
	assert_eq(s.context_commands(d.sim, P, _at(Vector2i(16, 2))), [Commands.move(P, [d.melee], Vector2i(16, 2))],
		"a hidden enemy's cell looks empty: move")
	assert_eq(s.context_commands(d.sim, P, _at(Vector2i(5, 5))), [], "on a friendly unit")
	assert_eq(s.context_commands(d.sim, P, _at(Vector2i(1, 1))), [], "on a friendly building")
	s.click(d.sim, P, _at(Vector2i(5, 5)))  # the worker alone
	assert_eq(s.context_commands(d.sim, P, _at(Vector2i(9, 5))), [], "worker on an enemy")
	s.click(d.sim, P, _at(Vector2i(1, 1)))  # the HQ
	assert_eq(s.context_commands(d.sim, P, _at(Vector2i(12, 8))), [], "a building cannot move")
	s.click(d.sim, P, _at(Vector2i(12, 8)))  # nothing
	assert_eq(s.context_commands(d.sim, P, _at(Vector2i(12, 8))), [], "empty selection")


# --- AC-73: HUD logic --------------------------------------------------------

func test_ac_73_train_buttons_disabled_with_reason() -> void:
	var sim: Simulation = Simulation.new(TestMaps.open(20, 12), 1, {"start_workers": 0, "start_wood": 50, "start_gold": 0})
	var hq: int = sim.hq_of(P)
	var b: Dictionary = HudModel.train_button(sim, hq, "worker")
	assert_true(b.enabled, "50 wood buys a worker")
	sim.submit(Commands.train(P, hq, "worker"))
	b = HudModel.train_button(sim, hq, "worker")
	assert_false(b.enabled)
	assert_string_contains(b.reason, "50 wood")
	var site: int = sim.place_building_unchecked("barracks", P, Vector2i(8, 5), false)
	b = HudModel.train_button(sim, site, "melee")
	assert_false(b.enabled)
	assert_string_contains(b.reason, "construction")


func test_ac_73_build_button_needs_a_worker_and_resources() -> void:
	var sim: Simulation = TestMaps.sim(TestMaps.open(20, 12))
	assert_false(HudModel.build_button(sim, P, []).enabled, "no worker selected")
	var w: int = sim.spawn_unit("worker", P, Vector2i(6, 6))
	assert_true(HudModel.build_button(sim, P, [w]).enabled, "200 wood, 100 gold is enough")
	sim.submit(Commands.build(P, w, "barracks", Vector2i(8, 6)))
	var b: Dictionary = HudModel.build_button(sim, P, [w])
	assert_false(b.enabled, "80 wood left")
	assert_string_contains(b.reason, "120 wood")


func test_ac_73_messages_fade_after_3_seconds() -> void:
	var log: MessageLog = MessageLog.new()
	log.add("Not enough wood", 10.0)
	assert_eq(log.entries(10.0).size(), 1)
	assert_eq(log.entries(10.0)[0].alpha, 1.0, "fully visible at first")
	var mid: float = log.entries(12.8)[0].alpha
	assert_true(mid > 0.0 and mid < 1.0, "fading near the end")
	assert_eq(log.entries(13.01).size(), 0, "gone after 3 seconds")


func test_ac_73_message_text_for_codes() -> void:
	assert_string_contains(HudModel.message_text({"type": "message", "code": "no_path"}), "path")
	assert_string_contains(HudModel.message_text({"type": "message", "code": "spawn_blocked"}), "blocked")
	assert_string_contains(HudModel.message_text({"type": "message", "code": "no_dropoff"}), "HQ")


# --- AC-76: camera -----------------------------------------------------------

func test_ac_76_camera_never_leaves_the_map() -> void:
	var map_px: Vector2 = Vector2(48 * 32, 48 * 32)
	var view: Vector2 = Vector2(1280, 720)
	assert_eq(CameraMath.clamp_center(Vector2(-500, -500), view, map_px), Vector2(640, 360))
	assert_eq(CameraMath.clamp_center(Vector2(5000, 5000), view, map_px), Vector2(1536 - 640, 1536 - 360))
	assert_eq(CameraMath.clamp_center(Vector2(800, 700), view, map_px), Vector2(800, 700), "inside: unchanged")
	# A map smaller than the screen is centred.
	assert_eq(CameraMath.clamp_center(Vector2(0, 0), view, Vector2(384, 256)), Vector2(192, 128))


func test_ac_76_edge_pan_direction() -> void:
	var view: Vector2 = Vector2(1280, 720)
	assert_eq(CameraMath.edge_direction(Vector2(2, 360), view), Vector2(-1, 0))
	assert_eq(CameraMath.edge_direction(Vector2(1279, 719), view), Vector2(1, 1))
	assert_eq(CameraMath.edge_direction(Vector2(640, 360), view), Vector2.ZERO)


# --- AC-74: menu, match, overlay, restart -----------------------------------

func test_ac_74_menu_starts_a_match_and_overlay_restarts_it() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(main)
	assert_true(main.is_menu_showing(), "starts on the main menu")
	main.start_match({"map": "generated", "seed": 74})
	assert_false(main.is_menu_showing())
	var game: Node = main.game
	var sim: Simulation = game.sim
	game.advance_ticks(10)
	assert_eq(sim.tick, 10)
	sim.destroy_entity(sim.hq_of("ai"))
	game.advance_ticks(1)
	assert_eq(sim.match_result, "victory_player")
	assert_true(game.hud.is_overlay_showing(), "victory overlay")
	assert_string_contains(game.hud.overlay_title(), "Victory")
	main.restart()
	assert_ne(main.game, game, "a new game")
	assert_eq(main.game.sim.tick, 0)
	assert_eq(main.game.sim.state_hash(), Simulation.new(MapGenerator.generate(74).map, 74, {}).state_hash(),
		"same as a fresh match")
	assert_eq(main.game.selection.selected, [], "no selection carried over")
	main.back_to_menu()
	assert_true(main.is_menu_showing())
