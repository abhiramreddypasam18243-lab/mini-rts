## Replay files: a JSON-lines command log (SPEC 8, decision D-12).
## Line 1 is the header {"version", "seed", "map", "ai_configs", "max_ticks"};
## each further line is {"tick", "faction", "command", "args", "result"}.
## Because the simulation is deterministic, re-submitting the same commands at
## the same ticks reproduces the match exactly (AC-04).
class_name Replay
extends RefCounted


static func to_jsonl(header: Dictionary, log: Array[Dictionary]) -> String:
	var lines: PackedStringArray = [JSON.stringify(header)]
	for entry: Dictionary in log:
		lines.append(JSON.stringify(entry))
	return "\n".join(lines) + "\n"


## Returns {"header": Dictionary, "commands": Array, "error": String}.
static func parse(text: String) -> Dictionary:
	var lines: PackedStringArray = text.strip_edges().split("\n")
	if lines.is_empty() or lines[0].strip_edges() == "":
		return {"header": {}, "commands": [], "error": "replay: empty file"}
	var header: Variant = JSON.parse_string(lines[0])
	if typeof(header) != TYPE_DICTIONARY:
		return {"header": {}, "commands": [], "error": "replay: bad header"}
	for key: String in ["version", "seed", "map", "ai_configs", "max_ticks"]:
		if not (header as Dictionary).has(key):
			return {"header": {}, "commands": [], "error": "replay: header is missing '%s'" % key}
	var commands: Array = []
	for i: int in range(1, lines.size()):
		var entry: Variant = JSON.parse_string(lines[i])
		if typeof(entry) != TYPE_DICTIONARY or not JsonUtil.is_whole((entry as Dictionary).get("tick")):
			return {"header": {}, "commands": [], "error": "replay: bad command on line %d" % (i + 1)}
		commands.append(JsonUtil.ints_deep(entry))
	return {"header": JsonUtil.ints_deep(header), "commands": commands, "error": ""}


## Plays a replay on the given map. Returns {"sim": Simulation or null, "error": String}.
static func play(text: String, map: MapGrid) -> Dictionary:
	var r: Dictionary = parse(text)
	if r.error != "":
		return {"sim": null, "error": r.error}
	var header: Dictionary = r.header
	if str(header.map) != map.map_name:
		return {"sim": null, "error": "replay: recorded on map '%s', given '%s'" % [header.map, map.map_name]}
	var sim: Simulation = Simulation.new(map, int(header.seed), {
		"max_ticks": int(header.max_ticks),
		"ai_configs": header.ai_configs,
	})
	var commands: Array = r.commands
	var next: int = 0
	while sim.tick < sim.max_ticks and sim.match_result == "":
		while next < commands.size() and int(commands[next].tick) == sim.tick:
			apply(sim, commands[next])
			next += 1
		sim.step()
	while next < commands.size():
		apply(sim, commands[next])
		next += 1
	return {"sim": sim, "error": ""}


## A command the firewall rejected changed nothing but the violation count,
## so playback records it the same way instead of applying it.
static func apply(sim: Simulation, entry: Dictionary) -> void:
	if entry.get("firewall", false):
		sim.firewall_violations += 1
		sim.command_log.append(entry)
		return
	sim.submit({"faction": entry.faction, "command": entry.command, "args": entry.args})


## The map a replay header names: "tutorial", or "generated-<seed>".
static func map_for(map_name: String) -> MapGrid:
	if map_name.begins_with("generated-"):
		return MapGenerator.generate(int(map_name.trim_prefix("generated-"))).map
	return MapGrid.load_file("res://data/maps/%s.json" % map_name).map
