## Records the demo replay (AC-93): an Aggressive (player start, blue) vs
## Balanced (AI start, red) match that shows an economy, a barracks, a
## fight and a victory. Tries seeds in order and keeps the first match the
## blue side wins after a real fight (both sides lose at least 5 units),
## lasting 2.5 to 5 minutes of game time.
##   godot --headless --script res://tools/make_demo.gd -- data/replays/demo.replay.jsonl
extends SceneTree


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "data/replays/demo.replay.jsonl"
	for s: int in range(1, 200):
		var m: MapGrid = MapGenerator.generate(s).map
		var r: Dictionary = MatchRunner.run(m, s, {"player": "aggressive", "ai": "balanced"}, 36000, true)
		var ok: bool = r.result == "victory_player" and r.ticks >= 3000 and r.ticks <= 6000 \
			and r.player.units_lost >= 5 and r.ai.units_lost >= 5 and r.player.first_barracks_tick > 0
		print("seed %d: %s at tick %d, lost %d / %d%s" % [s, r.result, r.ticks, r.player.units_lost, r.ai.units_lost, "  <- chosen" if ok else ""])
		if ok:
			DirAccess.make_dir_recursive_absolute(out.get_base_dir())
			var f: FileAccess = FileAccess.open(out, FileAccess.WRITE)
			f.store_string(r.replay)
			f.close()
			print("wrote ", out)
			quit(0)
			return
	printerr("no suitable seed found")
	quit(1)
