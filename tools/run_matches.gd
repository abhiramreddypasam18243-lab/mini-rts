## Headless match runner (SPEC 8, 16; AC-68).
##   godot --headless --script res://tools/run_matches.gd -- \
##       --policy-a balanced --policy-b aggressive --seeds 1-100 \
##       --max-ticks 36000 --out results/balanced_vs_aggressive.csv [--replay-dir results/replays]
## --matches N is accepted instead of --seeds: seeds 1..N/2, each played twice.
## --map-style classic|river|highlands picks the generated map style (D-53);
## a policy may carry a difficulty, e.g. balanced:hard (D-52).
## Every seed is played twice with the sides swapped; one CSV row per match,
## written as soon as the match ends (so a stopped run keeps its rows).
extends SceneTree


func _initialize() -> void:
	var a: Dictionary = _args(OS.get_cmdline_user_args())
	var policy_a: String = a.get("policy-a", "balanced")
	var policy_b: String = a.get("policy-b", "balanced")
	var max_ticks: int = int(a.get("max-ticks", str(Consts.DEFAULT_MAX_TICKS)))
	var out_path: String = a.get("out", "results.csv")
	var seeds: Array[int] = []
	if a.has("seeds"):
		var range_parts: PackedStringArray = (a.seeds as String).split("-")
		for s: int in range(int(range_parts[0]), int(range_parts[range_parts.size() - 1]) + 1):
			seeds.append(s)
	else:
		for s: int in range(1, int(a.get("matches", "200")) / 2 + 1):
			seeds.append(s)
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		printerr("cannot write ", out_path)
		quit(1)
		return
	f.store_line(Experiment.csv_header())
	var replay_dir: String = a.get("replay-dir", "")
	var t0: int = Time.get_ticks_msec()
	var done: Array[int] = [0]
	var total: int = seeds.size() * 2
	for s: int in seeds:
		var map: MapGrid = MapGenerator.generate(s, Consts.DEFAULT_MAP_SIZE, a.get("map-style", "classic")).map
		for a_slot: String in ["player", "ai"]:
			var b_slot: String = "ai" if a_slot == "player" else "player"
			var r: Dictionary = MatchRunner.run(map, s, {a_slot: policy_a, b_slot: policy_b}, max_ticks, replay_dir != "")
			var row: Dictionary = Experiment.make_row(r, s, map.map_name, policy_a, policy_b, a_slot)
			f.store_line(Experiment.csv_line(row))
			f.flush()
			if replay_dir != "":
				DirAccess.make_dir_recursive_absolute(replay_dir)
				var rf: FileAccess = FileAccess.open(replay_dir.path_join("seed%d_a_%s.replay.jsonl" % [s, a_slot]), FileAccess.WRITE)
				rf.store_string(r.replay)
				rf.close()
			done[0] += 1
			print("[%d/%d] seed %d, A=%s from the %s start: %s at tick %d" % [done[0], total, s, policy_a, a_slot, row.outcome + (" " + row.winner if row.winner != "" else ""), row.duration_ticks])
	f.close()
	print("wrote %d matches to %s in %.1f s" % [total, out_path, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)


func _args(list: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	var i: int = 0
	while i < list.size():
		var k: String = list[i]
		if k.begins_with("--") and i + 1 < list.size():
			out[k.trim_prefix("--")] = list[i + 1]
			i += 2
		else:
			i += 1
	return out
