## The deterministic match simulation (SPEC 6.2). It knows nothing about
## graphics or real time: the presentation calls step() at 20 ticks per second,
## headless tools call it as fast as they like, and both get the same result.
##
## Step 1 skeleton: tick counter, seeded generator, command log, state hash.
## Entities, orders and rules are added by later build steps.
class_name Simulation
extends RefCounted

const REPLAY_VERSION: int = 1
## Each command and the argument that names the acting entity or entities.
const COMMAND_SUBJECT: Dictionary = {
	"move": "unit_ids",
	"harvest": "unit_ids",
	"attack": "unit_ids",
	"build": "worker_id",
	"train": "building_id",
	"cancel_train": "building_id",
}

var map: MapGrid
var seed_value: int
var config: Dictionary
var rng: SimRng
var stats: Dictionary
var tick: int = 0
var max_ticks: int
## "" while the match runs; later "victory_player", "victory_ai", "draw", "timeout".
var match_result: String = ""
## Events for the UI, appended during a tick (created, destroyed, message, ...).
var events: Array[Dictionary] = []
## Every submitted command with its result, for replays (SPEC 8).
var command_log: Array[Dictionary] = []
## Entity id -> entity. Empty until build step 2.
var entities: Dictionary = {}


func _init(p_map: MapGrid, p_seed: int, p_config: Dictionary = {}) -> void:
	map = p_map
	seed_value = p_seed
	config = p_config
	rng = SimRng.new(p_seed)
	max_ticks = int(p_config.get("max_ticks", Consts.DEFAULT_MAX_TICKS))
	var loaded: Dictionary = UnitStats.load_file(str(p_config.get("units_path", "res://data/units.json")))
	assert(loaded.error == "", loaded.error)
	stats = loaded.stats


## Advances exactly one tick (AC-01). Does nothing once the match is over.
func step() -> void:
	if match_result != "":
		return
	tick += 1


## Validates and applies a command; returns a result code (SPEC 6.2).
## Command: {"faction": String, "command": String, "args": Dictionary}.
func submit(cmd: Dictionary) -> String:
	var result: String = _apply(cmd)
	command_log.append({
		"tick": tick,
		"faction": cmd.get("faction", ""),
		"command": cmd.get("command", ""),
		"args": cmd.get("args", {}),
		"result": result,
	})
	return result


func _apply(cmd: Dictionary) -> String:
	if match_result != "":
		return "match_over"
	var name: String = str(cmd.get("command", ""))
	if not COMMAND_SUBJECT.has(name):
		return "invalid_target"
	var args: Dictionary = cmd.get("args", {})
	var subject: Variant = args.get(COMMAND_SUBJECT[name])
	var ids: Array = subject if typeof(subject) == TYPE_ARRAY else [subject]
	if ids.is_empty():
		return "unknown_entity"
	for id: Variant in ids:
		if not entities.has(id):
			return "unknown_entity"
	return "ok"


## A hash of the whole simulation state, for determinism tests (AC-01, AC-03).
func state_hash() -> int:
	var h: StateHasher = StateHasher.new()
	h.add_int(tick)
	h.add_int(max_ticks)
	h.add_int(rng.state)
	h.add_string(match_result)
	map.add_to_hash(h)
	return h.h


func replay_header() -> Dictionary:
	return {
		"version": REPLAY_VERSION,
		"seed": seed_value,
		"map": map.map_name,
		"ai_configs": config.get("ai_configs", {}),
		"max_ticks": max_ticks,
	}
