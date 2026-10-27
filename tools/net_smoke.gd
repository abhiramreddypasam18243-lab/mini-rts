## End-to-end check of online play (D-60, AC-114): two complete game screens
## in one process, each with its own WebSocket connection to a running relay.
## One hosts, the other joins with the code; both give random orders through
## the normal Game.issue() path; every tick both reached must have the same
## state hash. Then the guest leaves and the host must be told.
##   node relay/server.js &   (PORT=8090)
##   godot --headless --script res://tools/net_smoke.gd -- --relay=ws://127.0.0.1:8090 [--seconds=20]
## Exits with code 0 on success, 1 on any failure.
extends SceneTree

var _seconds: float = 20.0
var _games: Dictionary = {}
## side -> {tick: state hash}
var _hashes: Dictionary = {"player": {}, "ai": {}}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--seconds="):
			_seconds = float(a.trim_prefix("--seconds="))
	_rng.seed = 5
	_run.call_deferred()


func _fail(text: String) -> void:
	printerr("NET SMOKE FAILED: ", text)
	quit(1)


func _run() -> void:
	var host: NetClient = NetClient.new()
	var guest: NetClient = NetClient.new()
	root.add_child(host)
	root.add_child(guest)
	var starts: Dictionary = {}
	for c: NetClient in [host, guest]:
		c.started.connect(func(you: String, setup: Dictionary) -> void: starts[you] = [c, setup])
		c.failed.connect(func(t: String) -> void: print("client failed: ", t))
	host.open()
	host.host({"map": "river", "seed": 4242})
	var code: Array = [""]
	host.hosted.connect(func(c: String) -> void: code[0] = c)
	var t0: int = Time.get_ticks_msec()
	while code[0] == "" and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	if code[0] == "":
		return _fail("no room code from the relay")
	print("hosted with code ", code[0])
	guest.open()
	guest.join(code[0])
	while starts.size() < 2 and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	if starts.size() < 2:
		return _fail("the match did not start for both")
	for side: String in ["player", "ai"]:
		var g: Game = Game.new()
		var setup: Dictionary = starts[side][1]
		g.setup({"mode": "online", "net": starts[side][0], "you": side, "map": setup.map, "seed": int(setup.seed)})
		root.add_child(g)
		_games[side] = g
	print("both games running; giving random orders for %.0f s" % _seconds)
	var end: int = Time.get_ticks_msec() + int(_seconds * 1000.0)
	var next_order: float = 0.0
	while Time.get_ticks_msec() < end:
		await process_frame
		for side: String in _games:
			var g: Game = _games[side]
			_hashes[side][g.sim.tick] = g.sim.state_hash()
		next_order -= 1.0 / 60.0
		if next_order <= 0.0:
			next_order = 0.25
			for side: String in _games:
				_random_order(_games[side], side)
	var compared: int = 0
	for t: int in _hashes["player"]:
		if _hashes["ai"].has(t):
			compared += 1
			if _hashes["player"][t] != _hashes["ai"][t]:
				return _fail("state hashes differ at tick %d" % t)
	var ticks: Array = [_games["player"].sim.tick, _games["ai"].sim.tick]
	print("ticks reached: ", ticks, "; ticks compared: ", compared)
	if compared < 100:
		return _fail("too few ticks compared (%d)" % compared)
	for side: String in _games:
		if _games[side].lockstep.desync:
			return _fail("%s reported a desync" % side)
	var own: int = 0
	for id: int in _games["ai"].sim.entities:
		if _games["ai"].sim.entities[id].faction == "ai" and _games["ai"].sim.entities[id].is_unit():
			own += 1
	print("red units on both machines: ", own)
	# The guest leaves: the host is told and its match ends.
	_games["ai"].queue_free()
	var t1: int = Time.get_ticks_msec()
	while not _games["player"]._result_shown and Time.get_ticks_msec() - t1 < 10000:
		await process_frame
	if not _games["player"]._result_shown:
		return _fail("the host was not told that the guest left")
	print("NET SMOKE PASSED")
	quit(0)


## A random order for `side`'s own units or HQ, as a player would click.
func _random_order(g: Game, side: String) -> void:
	var mine: Array[int] = []
	for id: int in g.sim.entities:
		var e: Entity = g.sim.entities[id]
		if e.faction == side and e.is_unit():
			mine.append(id)
	var cell: Vector2i = Vector2i(_rng.randi_range(0, 47), _rng.randi_range(0, 47))
	match _rng.randi_range(0, 3):
		0, 1:
			if not mine.is_empty():
				g.issue(Commands.move(side, [mine[_rng.randi_range(0, mine.size() - 1)]], cell), true)
		2:
			g.issue(Commands.train(side, g.sim.hq_of(side), "worker"), true)
		3:
			if not mine.is_empty():
				g.issue(Commands.attack_move(side, mine, cell), true)
