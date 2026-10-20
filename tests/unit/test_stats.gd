## AC-05: data/units.json matches SPEC section 4 and bad files fail clearly.
extends GutTest

# The table of SPEC section 4, typed in from the spec ("none" stored as 0, D-25).
## SPEC section 4 (food and the D-51 rows added 2026-10-20).
const SPEC_TABLE: Dictionary = {
	"worker":   {"wood": 50,  "gold": 0,  "food": 0,  "health": 40,  "speed": 150, "vision": 6, "damage": 0,  "range": 0,    "cooldown": 0,  "build_time": 160, "footprint": Vector2i(1, 1)},
	"melee":    {"wood": 60,  "gold": 20, "food": 0,  "health": 100, "speed": 125, "vision": 6, "damage": 10, "range": 1500, "cooldown": 20, "build_time": 200, "footprint": Vector2i(1, 1)},
	"ranged":   {"wood": 40,  "gold": 50, "food": 0,  "health": 50,  "speed": 125, "vision": 7, "damage": 8,  "range": 5000, "cooldown": 24, "build_time": 240, "footprint": Vector2i(1, 1)},
	"cavalry":  {"wood": 0,   "gold": 70, "food": 60, "health": 120, "speed": 200, "vision": 6, "damage": 9,  "range": 1500, "cooldown": 20, "build_time": 260, "footprint": Vector2i(1, 1)},
	"hq":       {"wood": 0,   "gold": 0,  "food": 0,  "health": 500, "speed": 0,   "vision": 8, "damage": 0,  "range": 0,    "cooldown": 0,  "build_time": 0,   "footprint": Vector2i(3, 3)},
	"barracks": {"wood": 120, "gold": 60, "food": 0,  "health": 300, "speed": 0,   "vision": 5, "damage": 0,  "range": 0,    "cooldown": 0,  "build_time": 300, "footprint": Vector2i(2, 2)},
	"farm":     {"wood": 80,  "gold": 0,  "food": 0,  "health": 200, "speed": 0,   "vision": 3, "damage": 0,  "range": 0,    "cooldown": 0,  "build_time": 150, "footprint": Vector2i(2, 2)},
	"tower":    {"wood": 80,  "gold": 60, "food": 0,  "health": 400, "speed": 0,   "vision": 7, "damage": 6,  "range": 6000, "cooldown": 30, "build_time": 250, "footprint": Vector2i(1, 1)},
	"stable":   {"wood": 150, "gold": 40, "food": 0,  "health": 300, "speed": 0,   "vision": 5, "damage": 0,  "range": 0,    "cooldown": 0,  "build_time": 300, "footprint": Vector2i(2, 2)},
}


func _valid_raw() -> Dictionary:
	var r: Dictionary = {}
	for kind: String in SPEC_TABLE:
		var e: Dictionary = (SPEC_TABLE[kind] as Dictionary).duplicate()
		var fp: Vector2i = e.footprint
		e.footprint = [fp.x, fp.y]
		r[kind] = e
	return r


func test_ac_05_loaded_stats_equal_spec_table() -> void:
	var r: Dictionary = UnitStats.load_file("res://data/units.json")
	assert_eq(r.error, "")
	var stats: Dictionary = r.stats
	assert_eq(stats.size(), SPEC_TABLE.size())
	for kind: String in SPEC_TABLE:
		for field: String in SPEC_TABLE[kind]:
			assert_eq(stats[kind][field], SPEC_TABLE[kind][field], "%s.%s" % [kind, field])
			assert_true(typeof(stats[kind][field]) in [TYPE_INT, TYPE_VECTOR2I], "%s.%s is integer" % [kind, field])


func test_ac_05_missing_field_is_named() -> void:
	var raw: Dictionary = _valid_raw()
	(raw.melee as Dictionary).erase("damage")
	var r: Dictionary = UnitStats.parse(raw)
	assert_true(r.error.contains("melee") and r.error.contains("damage") and r.error.contains("missing"), r.error)


func test_ac_05_negative_field_is_named() -> void:
	var raw: Dictionary = _valid_raw()
	raw.ranged.cooldown = -5
	var r: Dictionary = UnitStats.parse(raw)
	assert_true(r.error.contains("ranged") and r.error.contains("cooldown") and r.error.contains("negative"), r.error)


func test_ac_05_missing_entity_is_named() -> void:
	var raw: Dictionary = _valid_raw()
	raw.erase("barracks")
	var r: Dictionary = UnitStats.parse(raw)
	assert_true(r.error.contains("barracks"), r.error)


func test_ac_05_fractional_value_rejected() -> void:
	var raw: Dictionary = _valid_raw()
	raw.worker.speed = 150.5
	var r: Dictionary = UnitStats.parse(raw)
	assert_true(r.error.contains("worker") and r.error.contains("speed"), r.error)
