## Dev tool: renders staged game scenes and saves screenshots, to check the
## look of states that are hard to reach by hand (a battle, the end screen).
## Needs a display (not --headless):
##   godot --rendering-driver opengl3 --script res://tools/ui_snapshot.gd -- <out_dir> [seed]
## It sets up scenes through the simulation's own setup helpers, as the tests do.
extends SceneTree

var _out: String = "user://snapshots"
var _seed: int = 79407


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_seed = int(args[1])
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
	print("saved ", _out.path_join(name + ".png"))


func _frames(n: int) -> void:
	for i: int in n:
		await process_frame


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(30)
	await _shot("00_menu")
	main.start_match({"map": "generated", "seed": _seed})
	await _frames(5)
	await _shot("00_start_%d" % _seed)
	var game: Game = main.game
	var sim: Simulation = game.sim
	# A skirmish next to the player's base.
	var hq: Entity = sim.entity(sim.hq_of("player"))
	var base: Vector2i = hq.cell + Vector2i(5, 1)
	var mine: Array[int] = []
	for i: int in 4:
		mine.append(sim.spawn_unit(["melee", "ranged"][i % 2], "player", base + Vector2i(i % 2, i / 2)))
	for i: int in 4:
		var e: int = sim.spawn_unit(["melee", "ranged"][i % 2], "ai", base + Vector2i(4 + i % 2, i / 2))
		sim.entity(e).hp -= 30
	sim.place_building_unchecked("barracks", "ai", base + Vector2i(7, -1), true)
	sim.update_fog()
	game.selection.selected = mine.duplicate()
	game.selection.inspected = mine[0]
	await _frames(70)
	await _shot("10_battle")
	game.selection.selected = [mine[1]]
	game.selection.inspected = mine[1]
	await _frames(20)
	await _shot("11_unit_card")
	# D-51: a farm being worked, a guard tower, a stable and cavalry.
	main.start_match({"map": "generated", "seed": _seed})
	await _frames(5)
	game = main.game
	sim = game.sim
	hq = sim.entity(sim.hq_of("player"))
	var placed: Dictionary = {}
	for kind: String in ["farm", "stable", "tower"]:
		var spot: Variant = _site(sim, kind, hq.cell + (Vector2i(1, 5) if kind == "tower" else Vector2i(1, 1)))
		if spot != null:
			placed[kind] = sim.place_building_unchecked(kind, "player", spot, true)
	var workers: Array[int] = []
	for id: int in sim.entities:
		if sim.entity(id).kind == "worker" and sim.entity(id).faction == "player":
			workers.append(id)
	if placed.has("farm"):
		sim.submit(Commands.harvest("player", workers.slice(0, 2), placed.farm))
	if placed.has("stable"):
		var st: Entity = sim.entity(placed.stable)
		for c: Vector2i in sim.spawn_cells(st, 3):
			sim.spawn_unit("cavalry", "player", c)
		game.selection.selected = [placed.stable]
		game.selection.inspected = placed.stable
	sim.update_fog()
	game.camera.position = (Vector2(hq.cell) + Vector2(3.5, 3.0)) * Consts.PIXELS_PER_CELL
	game.advance_ticks(60)
	await _frames(40)
	await _shot("14_economy")
	if workers.size() > 2:
		game.selection.selected = [workers[2]]
		game.selection.inspected = workers[2]
	await _frames(10)
	await _shot("15_worker_buttons")
	# Let the AI play for 2,000 ticks (100 s), then look at its base.
	main.start_match({"map": "generated", "seed": _seed, "ai_policy": "balanced"})
	await _frames(5)
	game = main.game
	sim = game.sim
	game.advance_ticks(2000)
	var ai_hq: Entity = sim.entity(sim.hq_of("ai"))
	game.camera.position = (Vector2(ai_hq.cell) + Vector2(1.5, 1.5)) * Consts.PIXELS_PER_CELL
	sim.fog.reveal("player", ai_hq, 14)  # snapshot only: let the camera see the AI base
	sim.update_fog()
	game.hud.toggle_fps()
	await _frames(40)
	await _shot("13_ai_base")
	sim.destroy_entity(sim.hq_of("ai"))
	game.advance_ticks(1)
	await _frames(60)
	await _shot("12_victory")
	quit()


## The first spot in rings around `from` where `kind` can be placed.
func _site(sim: Simulation, kind: String, from: Vector2i) -> Variant:
	for d: int in range(2, 10):
		for y: int in range(from.y - d, from.y + d + 1):
			for x: int in range(from.x - d, from.x + d + 1):
				if maxi(absi(x - from.x), absi(y - from.y)) == d and sim.placement_check("player", kind, Vector2i(x, y)) == "ok":
					return Vector2i(x, y)
	return null
