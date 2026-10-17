## Batches of headless matches between two AI policies (SPEC 8, 16; AC-68).
## Every seed is played twice with the policies swapped between the two
## start positions, so an advantage of one start cancels out (decision D-08).
## "Side A" is always policy_a, wherever it starts.
class_name Experiment
extends RefCounted

const COLUMNS: Array[String] = [
	"seed", "map", "side_a_policy", "side_b_policy", "a_is_player_start", "winner", "outcome",
	"duration_ticks", "first_attack_tick", "wood_gathered_a", "gold_gathered_a", "units_lost_a",
	"wood_gathered_b", "gold_gathered_b", "units_lost_b",
]
const TEXT_COLUMNS: Array[String] = ["map", "side_a_policy", "side_b_policy", "winner", "outcome"]


## Plays each seed twice (A from the player start, then from the AI start)
## on the generated map of that seed. `on_row` is called after each match.
static func run_batch(seeds: Array, policy_a: String, policy_b: String, max_ticks: int,
		on_row: Callable = Callable()) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for s: Variant in seeds:
		var map: MapGrid = MapGenerator.generate(int(s)).map
		for a_slot: String in ["player", "ai"]:
			var b_slot: String = "ai" if a_slot == "player" else "player"
			var slots: Dictionary = {a_slot: policy_a, b_slot: policy_b}
			var r: Dictionary = MatchRunner.run(map, int(s), slots, max_ticks)
			var row: Dictionary = make_row(r, int(s), map.map_name, policy_a, policy_b, a_slot)
			row.slots = slots
			rows.append(row)
			if on_row.is_valid():
				on_row.call(row)
	return rows


## One CSV row from a MatchRunner result.
static func make_row(r: Dictionary, p_seed: int, map_name: String, policy_a: String, policy_b: String, a_slot: String) -> Dictionary:
	var b_slot: String = "ai" if a_slot == "player" else "player"
	var winner: String = ""
	var outcome: String = r.result
	if r.result.begins_with("victory_"):
		outcome = "victory"
		winner = "A" if r.result == "victory_" + a_slot else "B"
	return {
		"seed": p_seed, "map": map_name, "side_a_policy": policy_a, "side_b_policy": policy_b,
		"a_is_player_start": a_slot == "player", "winner": winner, "outcome": outcome,
		"duration_ticks": r.ticks, "first_attack_tick": r.first_attack_tick,
		"wood_gathered_a": r[a_slot].wood, "gold_gathered_a": r[a_slot].gold, "units_lost_a": r[a_slot].units_lost,
		"wood_gathered_b": r[b_slot].wood, "gold_gathered_b": r[b_slot].gold, "units_lost_b": r[b_slot].units_lost,
	}


## Only the CSV columns of a row.
static func csv_fields(row: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for c: String in COLUMNS:
		out[c] = row[c]
	return out


static func csv_header() -> String:
	return ",".join(COLUMNS)


static func csv_line(row: Dictionary) -> String:
	var parts: PackedStringArray = []
	for c: String in COLUMNS:
		parts.append(str(row[c]).to_lower() if typeof(row[c]) == TYPE_BOOL else str(row[c]))
	return ",".join(parts)


static func to_csv(rows: Array[Dictionary]) -> String:
	var lines: PackedStringArray = [csv_header()]
	for r: Dictionary in rows:
		lines.append(csv_line(r))
	return "\n".join(lines) + "\n"


static func from_csv(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lines: PackedStringArray = text.strip_edges().split("\n")
	var header: PackedStringArray = lines[0].strip_edges().split(",")
	for i: int in range(1, lines.size()):
		var cells: PackedStringArray = lines[i].strip_edges().split(",")
		var row: Dictionary = {}
		for k: int in header.size():
			var name: String = header[k]
			var v: String = cells[k] if k < cells.size() else ""
			if name in TEXT_COLUMNS:
				row[name] = v
			elif name == "a_is_player_start":
				row[name] = v == "true"
			else:
				row[name] = int(v)
		out.append(row)
	return out
