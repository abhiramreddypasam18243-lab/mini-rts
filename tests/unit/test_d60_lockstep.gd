## AC-111 (lockstep: both machines run the same commands on the same tick)
## and AC-112 (stalls, ordering and desync detection), decision D-60.
extends GutTest


## Two peers wired by in-memory queues; each drives its own Simulation of the
## same map and seed. `lag` delays every message by that many turns.
class Pair:
	var sims: Dictionary = {}
	var steps: Dictionary = {}
	var wire: Dictionary = {"player": [], "ai": []}  # messages waiting for that faction

	func _init(seed: int) -> void:
		for f: String in ["player", "ai"]:
			sims[f] = Simulation.new(MapGenerator.generate(seed).map, seed, {})
			steps[f] = Lockstep.new(f)

	## One attempt by `f` to run its next turn; true if it ran.
	func pump(f: String) -> bool:
		var other: String = "ai" if f == "player" else "player"
		var ls: Lockstep = steps[f]
		var sim: Simulation = sims[f]
		if ls.needs_close():
			wire[other].append(ls.close_turn(sim.state_hash()))
		while not wire[f].is_empty():
			ls.receive(wire[f].pop_front())
		if not ls.can_run():
			return false
		for c: Dictionary in ls.take_turn():
			sim.submit(c)
		for i: int in Lockstep.TURN_TICKS:
			sim.step()
		return true


## Random orders for `f`'s own units (some valid, some not), as a player clicks.
func _random_orders(sim: Simulation, f: String, rng: SimRng) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var mine: Array[int] = []
	for id: int in sim.entities:
		if sim.entities[id].faction == f and sim.entities[id].is_unit():
			mine.append(id)
	if mine.is_empty():
		return out
	var u: int = mine[rng.range_int(mine.size())]
	var cell: Vector2i = Vector2i(rng.range_int(48), rng.range_int(48))
	match rng.range_int(3):
		0:
			out.append(Commands.move(f, [u], cell))
		1:
			out.append(Commands.train(f, sim.hq_of(f), "worker"))
		2:
			out.append(Commands.attack_move(f, [u], cell))
	return out


func test_ac_111_two_peers_stay_identical() -> void:
	# Both peers give random orders at random moments and run at different
	# paces; after every turn both have run, their state hashes are equal.
	var p: Pair = Pair.new(7)
	var rng: SimRng = SimRng.new(99)
	var turns: int = TestCounts.pick(120, 600)
	# faction -> {turn: state hash after that turn ran}
	var hashes: Dictionary = {"player": {}, "ai": {}}
	while p.steps["player"].turn < turns or p.steps["ai"].turn < turns:
		for f: String in ["player", "ai"]:
			if rng.range_int(4) == 0:
				for c: Dictionary in _random_orders(p.sims[f], f, rng):
					p.steps[f].queue(c)
			# The ai peer runs slower: it tries only every other time.
			if (f == "player" or rng.range_int(2) == 0) and p.pump(f):
				hashes[f][p.steps[f].turn] = p.sims[f].state_hash()
	for t: int in range(1, turns + 1):
		assert_eq(hashes["player"][t], hashes["ai"][t], "turn %d" % t)
	assert_ne(hashes["player"][1], hashes["player"][turns], "the game moved on")
	assert_false(p.steps["player"].desync or p.steps["ai"].desync)


func test_ac_111_a_command_runs_delay_turns_later_on_both() -> void:
	# A worker queued during turn 0 is sent as part of turn DELAY (2): both
	# peers pay its 50 wood at the start of turn 2, not before.
	var p: Pair = Pair.new(3)
	p.steps["player"].queue(Commands.train("player", p.sims["player"].hq_of("player"), "worker"))
	for i: int in Lockstep.DELAY:
		assert_true(p.pump("player"), "turn %d (player)" % i)
		assert_true(p.pump("ai"), "turn %d (ai)" % i)
	for f: String in ["player", "ai"]:
		assert_eq(p.sims[f].bank.stock["player"].wood, 200, "%s: not paid before turn DELAY" % f)
	assert_true(p.pump("player"))
	assert_true(p.pump("ai"))
	for f: String in ["player", "ai"]:
		assert_eq(p.sims[f].bank.stock["player"].wood, 150, "%s: paid at turn DELAY" % f)


func test_ac_112_a_peer_never_runs_ahead_of_the_other() -> void:
	# Without the other's input for a turn, a peer stops: it can run at most
	# DELAY turns (the empty starting turns) on its own.
	var p: Pair = Pair.new(5)
	var ran: int = 0
	for i: int in 20:
		if p.pump("player"):
			ran += 1
	assert_eq(ran, Lockstep.DELAY)
	assert_false(p.steps["player"].can_run())


func test_ac_112_commands_run_in_faction_order_whatever_arrives_first() -> void:
	var a: Lockstep = Lockstep.new("player")
	var b: Lockstep = Lockstep.new("ai")
	var mine: Dictionary = Commands.move("player", [1], Vector2i(1, 1))
	var theirs: Dictionary = Commands.move("ai", [2], Vector2i(2, 2))
	a.queue(mine)
	b.queue(theirs)
	var ma: Dictionary = a.close_turn(0)
	var mb: Dictionary = b.close_turn(0)
	a.receive(mb)
	b.receive(ma)
	for i: int in Lockstep.DELAY:
		a.take_turn()
		b.take_turn()
		a.receive(b.close_turn(0))
		b.receive(a.close_turn(0))
	# Turn DELAY holds both commands; the player's comes first on both peers
	# (compared as JSON: they travel as JSON, so numbers come back as floats).
	var want: String = JSON.stringify(JSON.parse_string(JSON.stringify([mine, theirs])))
	assert_eq(JSON.stringify(a.take_turn()), want)
	assert_eq(JSON.stringify(b.take_turn()), want)


func test_ac_112_a_hash_mismatch_is_reported_as_desync() -> void:
	var a: Lockstep = Lockstep.new("player")
	var b: Lockstep = Lockstep.new("ai")
	a.receive(b.close_turn(111))
	assert_false(a.desync)
	# a's own hash for turn 0 differs from b's.
	a.close_turn(222)
	assert_true(a.desync, "the peers' states differ at turn 0")
