## Deterministic lockstep for two human players (decision D-60). Both
## machines run the same Simulation; only commands travel between them, never
## the game state. Time is cut into turns of TURN_TICKS ticks. A command given
## during turn T is sent as part of turn T + DELAY, and turn T runs only once
## both players' commands for T are known, so both machines submit the same
## commands at the same tick, in the same order (the "player" faction's
## first, each player's in the order given). The simulation is deterministic
## (AC-03), so both stay identical. A peer that has not heard from the other
## waits instead of guessing.
##
## Each turn message also carries the sender's state hash at the start of its
## current turn; a mismatch with our own hash for that turn means the two
## games have drifted apart (`desync`).
##
## Message: {"t": turn the commands belong to, "c": [commands],
##           "ht": turn the hash belongs to, "h": state hash}
class_name Lockstep
extends RefCounted

## 3 ticks = 150 ms per turn.
const TURN_TICKS: int = 3
## Commands run 2 turns (300 ms) after they are given: time for them to
## reach the other player.
const DELAY: int = 2
## The order commands of one turn are submitted in, on both machines.
const ORDER: Array[String] = ["player", "ai"]

var me: String
var other: String
## The next turn to run.
var turn: int = 0
var desync: bool = false
## Commands given since the last turn was closed.
var _local: Array[Dictionary] = []
## faction -> {turn: [commands]}
var _inbox: Dictionary = {}
## Our hash and theirs, by turn (kept only until compared).
var _my_hash: Dictionary = {}
var _their_hash: Dictionary = {}
## The turn during which we last closed (sent) a turn; -1 before the first.
var _closed_at: int = -1


func _init(p_me: String) -> void:
	me = p_me
	other = "ai" if me == "player" else "player"
	for f: String in ORDER:
		_inbox[f] = {}
		# The first DELAY turns are empty for both: nothing can reach the
		# other player in time for them.
		for t: int in DELAY:
			_inbox[f][t] = []


## A command from this player's interface, sent with the next closed turn.
func queue(cmd: Dictionary) -> void:
	_local.append(cmd)


## True when this turn's outgoing message has not been made yet.
func needs_close() -> bool:
	return _closed_at != turn


## Closes turn `turn + DELAY` with the commands given so far and returns the
## message to send. `state_hash` is the simulation's hash now, at the start of
## `turn`.
func close_turn(state_hash: int) -> Dictionary:
	_closed_at = turn
	var t: int = turn + DELAY
	# Through JSON and back, exactly as the other player will receive them
	# (numbers become floats), so both machines submit identical values.
	var cmds: Array = JSON.parse_string(JSON.stringify(_local))
	_local.clear()
	_inbox[me][t] = cmds
	_my_hash[turn] = state_hash
	_check(turn)
	return {"t": t, "c": cmds, "ht": turn, "h": state_hash}


## A message from the other player.
func receive(msg: Dictionary) -> void:
	_inbox[other][int(msg.t)] = msg.c
	_their_hash[int(msg.ht)] = int(msg.h)
	_check(int(msg.ht))


## Whether turn `turn` can run: both players' commands for it are known.
func can_run() -> bool:
	return _inbox[me].has(turn) and _inbox[other].has(turn)


## The commands of turn `turn`, in submission order; moves on to the next turn.
func take_turn() -> Array:
	var out: Array = []
	for f: String in ORDER:
		for c: Variant in _inbox[f].get(turn, []):
			out.append(c)
		_inbox[f].erase(turn)
	turn += 1
	return out


func _check(t: int) -> void:
	if _my_hash.has(t) and _their_hash.has(t):
		if _my_hash[t] != _their_hash[t]:
			desync = true
		_my_hash.erase(t)
		_their_hash.erase(t)
