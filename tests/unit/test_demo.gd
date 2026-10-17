## AC-93: the demo is a scripted replay that plays back in the game (and so
## in the browser) and shows an economy, a barracks, a fight and a victory.
extends GutTest

const DEMO: String = "res://data/replays/demo.replay.jsonl"


func test_ac_93_demo_replay_shows_economy_barracks_fight_and_victory() -> void:
	var text: String = FileAccess.get_file_as_string(DEMO)
	var header: Dictionary = Replay.parse(text).header
	var played: Dictionary = Replay.play(text, Replay.map_for(header.map))
	assert_eq(played.error, "")
	var sim: Simulation = played.sim
	var seen: Dictionary = {}
	for e: Dictionary in sim.events:
		if e.get("faction", "") == "player" or e.type in ["attack", "match_ended"]:
			seen[e.type] = seen.get(e.type, 0) + 1
	assert_gt(seen.get("deposit", 0), 10, "an economy: the player (blue) deposits resources")
	assert_gt(seen.get("completed", 0), 0, "a barracks is completed")
	assert_gt(seen.get("trained", 0), 3, "units are trained")
	assert_gt(seen.get("attack", 0), 20, "a fight")
	assert_eq(sim.match_result, "victory_player", "a victory")
	assert_eq(sim.firewall_violations, 0)


func test_ac_93_demo_plays_in_the_game_screen_to_the_end() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(main)
	main.start_match({"mode": "demo"})
	var game: Game = main.game
	assert_true(game.demo)
	assert_null(game.opponent, "no AI runs: the replay supplies every command")
	assert_eq(game.issue(Commands.move("player", [1], Vector2i(5, 5))), "demo", "the viewer cannot change the match")
	var guard: int = 0
	while game.sim.match_result == "" and guard < 400:
		game.advance_ticks(20)
		guard += 1
	assert_eq(game.sim.match_result, "victory_player")
	assert_true(game.hud.is_overlay_showing())
	assert_eq(game.hud.overlay_title(), "Blue wins")
