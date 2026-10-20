## Loads and validates data/units.json (AC-05, decision D-11).
## Every entity must have every field as a whole, non-negative number; "none" in
## the spec table is stored as 0 (decision D-25). Footprints are [w, h] >= 1.
## Results are {"stats": Dictionary or {}, "error": String ("" when valid)}.
class_name UnitStats
extends RefCounted

const ENTITIES: Array[String] = ["worker", "melee", "ranged", "cavalry", "hq", "barracks", "farm", "tower", "stable"]
const FIELDS: Array[String] = [
	"wood", "gold", "food", "health", "speed", "vision",
	"damage", "range", "cooldown", "build_time",
]


static func load_file(path: String) -> Dictionary:
	var err: Array = []
	var text: String = JsonUtil.read_text(path, err)
	if not err.is_empty():
		return {"stats": {}, "error": "units.json: " + str(err[0])}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"stats": {}, "error": "units.json: not a JSON object"}
	return parse(parsed)


static func parse(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for kind: String in ENTITIES:
		if not raw.has(kind) or typeof(raw[kind]) != TYPE_DICTIONARY:
			return _fail("'%s' is missing" % kind)
		var src: Dictionary = raw[kind]
		var e: Dictionary = {}
		for field: String in FIELDS:
			if not src.has(field):
				return _fail("'%s' is missing field '%s'" % [kind, field])
			if not JsonUtil.is_whole(src[field]):
				return _fail("'%s' field '%s' must be a whole number" % [kind, field])
			var v: int = JsonUtil.to_int(src[field])
			if v < 0:
				return _fail("'%s' field '%s' is negative (%d)" % [kind, field, v])
			e[field] = v
		if not src.has("footprint"):
			return _fail("'%s' is missing field 'footprint'" % kind)
		var fp: Variant = JsonUtil.to_cell(src.footprint)
		if fp == null:
			return _fail("'%s' field 'footprint' must be [width, height]" % kind)
		if (fp as Vector2i).x < 1 or (fp as Vector2i).y < 1:
			return _fail("'%s' field 'footprint' is negative or zero" % kind)
		e["footprint"] = fp
		out[kind] = e
	return {"stats": out, "error": ""}


static func _fail(msg: String) -> Dictionary:
	return {"stats": {}, "error": "units.json: " + msg}
