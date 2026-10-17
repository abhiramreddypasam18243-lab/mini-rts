## The AC-77 frame-rate benchmark sets up the scene it promises to measure.
extends GutTest


func test_ac_77_benchmark_starts_with_80_units_and_no_fog() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(main)
	main.start_match({"map": "generated", "seed": 42, "mode": "bench"})
	var game: Game = main.game
	assert_not_null(game.bench)
	assert_true(game.spectate, "every unit is drawn (the worst case)")
	assert_null(game.opponent, "no AI: both armies are sent to the middle")
	var per_side: Dictionary = {"player": 0, "ai": 0}
	for id: int in game.sim.unit_ids():
		per_side[game.sim.entity(id).faction] += 1
	# AC-77: 80 units on the map, 40 per side (the population cap).
	assert_eq(per_side, {"player": 40, "ai": 40})
