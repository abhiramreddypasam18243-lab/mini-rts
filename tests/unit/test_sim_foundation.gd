## AC-01 to AC-04: ticks, seeded randomness, determinism and replays.
extends GutTest

const TUTORIAL: String = "res://data/maps/tutorial.json"


func _tutorial() -> MapGrid:
	var r: Dictionary = MapGrid.load_file(TUTORIAL)
	assert_eq(r.error, "", "tutorial map loads")
	return r.map


func _new_sim(p_seed: int) -> Simulation:
	return Simulation.new(_tutorial(), p_seed, {})


# A small fixed command log: (tick, faction, command, args).
func _command_log() -> Array[Dictionary]:
	return [
		{"tick": 3, "faction": "player", "command": "move", "args": {"unit_ids": [99], "cell": [2, 2]}},
		{"tick": 40, "faction": "ai", "command": "train", "args": {"building_id": 7, "unit_type": "worker"}},
		{"tick": 150, "faction": "player", "command": "attack", "args": {"unit_ids": [1, 2], "target_id": 5}},
	]


func _run(p_seed: int, ticks: int, commands: Array[Dictionary]) -> Array[int]:
	var sim: Simulation = _new_sim(p_seed)
	var hashes: Array[int] = []
	var next: int = 0
	for t: int in ticks:
		while next < commands.size() and commands[next].tick == sim.tick:
			sim.submit(commands[next])
			next += 1
		sim.step()
		if sim.tick % 100 == 0:
			hashes.append(sim.state_hash())
	hashes.append(sim.state_hash())
	return hashes


func test_ac_01_step_advances_exactly_one_tick() -> void:
	var sim: Simulation = _new_sim(1)
	assert_eq(sim.tick, 0)
	sim.step()
	assert_eq(sim.tick, 1)
	for i: int in 19:
		sim.step()
	assert_eq(sim.tick, 20)


func test_ac_01_one_frame_or_many_frames_same_hash() -> void:
	# A: 20 ticks in a single frame.
	var a: Simulation = _new_sim(7)
	for i: int in 20:
		a.step()
	# B: the same second of real time split into uneven frames (microseconds).
	var b: Simulation = _new_sim(7)
	var clock: TickClock = TickClock.new()
	var frames: Array[int] = [16_667, 16_666, 33_333, 1_000, 49_000, 83_334, 300_000, 500_000]
	var total: int = 0
	for usec: int in frames:
		total += usec
		for i: int in clock.advance_usec(usec):
			b.step()
	assert_eq(total, 1_000_000, "frames add up to exactly one second")
	assert_eq(b.tick, 20, "one second at 20 ticks per second")
	assert_eq(a.state_hash(), b.state_hash())


func test_ac_02_rng_is_seeded_and_repeatable() -> void:
	var r1: SimRng = SimRng.new(42)
	var r2: SimRng = SimRng.new(42)
	var r3: SimRng = SimRng.new(43)
	var same: bool = true
	var differs: bool = false
	for i: int in 100:
		var v1: int = r1.next_u32()
		var v3: int = r3.next_u32()
		same = same and v1 == r2.next_u32()
		differs = differs or v1 != v3
		assert_true(v1 >= 0 and v1 < 4294967296, "32-bit output")
	assert_true(same, "same seed gives same sequence")
	assert_true(differs, "different seed gives a different sequence")


func test_ac_02_rng_known_values() -> void:
	# Expected values computed by hand from the LCG definition:
	# state0 = mix32(0) = 0; step: state = (state * 1664525 + 1013904223) mod 2^32.
	# state1 = 1013904223 -> top16 = 15470
	# state2 = (1013904223 * 1664525 + 1013904223) mod 2^32 = 1196435762 -> top16 = 18256
	assert_eq(SimRng.mix32(0), 0)
	var r: SimRng = SimRng.new(0)
	assert_eq(r.next_u32(), (15470 << 16) | 18256)


func test_ac_02_static_check_no_global_random_or_clock() -> void:
	var banned: RegEx = RegEx.new()
	banned.compile("\\b(randf|randi|randf_range|randi_range|randfn|randomize|RandomNumberGenerator|Time\\.|OS\\.get_ticks|OS\\.get_unix_time|OS\\.get_system_time)")
	var files: Array[String] = _gd_files("res://scripts/sim")
	assert_gt(files.size(), 0, "found simulation scripts")
	for path: String in files:
		var text: String = FileAccess.get_file_as_string(path)
		var lines: PackedStringArray = text.split("\n")
		for i: int in lines.size():
			var code: String = lines[i].split("#")[0]
			var m: RegExMatch = banned.search(code)
			assert_null(m, "%s:%d uses a banned call: %s" % [path, i + 1, lines[i].strip_edges()])


func test_ac_03_same_seed_same_commands_same_hashes() -> void:
	var ticks: int = 1000
	var h1: Array[int] = _run(123, ticks, _command_log())
	var h2: Array[int] = _run(123, ticks, _command_log())
	assert_eq(h1.size(), ticks / 100 + 1, "a hash every 100 ticks plus the end")
	assert_eq(h1, h2)


func test_ac_04_replay_reproduces_hash_and_result() -> void:
	# A match with a 300-tick limit, played to its end with a command log.
	var sim: Simulation = Simulation.new(_tutorial(), 99, {"max_ticks": 300})
	var log: Array[Dictionary] = _command_log()
	var next: int = 0
	while sim.tick < sim.max_ticks:
		while next < log.size() and log[next].tick == sim.tick:
			sim.submit(log[next])
			next += 1
		sim.step()
	var text: String = Replay.to_jsonl(sim.replay_header(), sim.command_log)
	var lines: PackedStringArray = text.strip_edges().split("\n")
	assert_eq(lines.size(), 1 + log.size(), "header plus one line per command")
	var played: Dictionary = Replay.play(text, _tutorial())
	assert_eq(played.error, "")
	var replayed: Simulation = played.sim
	assert_eq(replayed.tick, sim.tick)
	assert_eq(replayed.state_hash(), sim.state_hash())
	assert_eq(replayed.match_result, sim.match_result)
	assert_eq(replayed.command_log.size(), sim.command_log.size())
	for i: int in sim.command_log.size():
		assert_eq(replayed.command_log[i].result, sim.command_log[i].result)


func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	for f: String in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for d: String in dir.get_directories():
		out.append_array(_gd_files(dir_path.path_join(d)))
	return out
