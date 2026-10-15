## The one place where JSON numbers enter the simulation.
## Godot's JSON parser returns every number as a floating-point value; these
## helpers accept only whole numbers and turn them into ints, so no fractional
## value ever reaches simulation state (integers-only rule, SPEC section 4).
class_name JsonUtil
extends RefCounted


## True if v is a whole number (as parsed from JSON or already an int).
static func is_whole(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	if typeof(v) == TYPE_FLOAT:
		return int(v) == v
	return false


static func to_int(v: Variant) -> int:
	return int(v)


## Parses [x, y] into a Vector2i. Returns null if malformed.
static func to_cell(v: Variant) -> Variant:
	if typeof(v) != TYPE_ARRAY or (v as Array).size() != 2:
		return null
	var a: Array = v
	if not is_whole(a[0]) or not is_whole(a[1]):
		return null
	return Vector2i(int(a[0]), int(a[1]))


## Recursively converts whole JSON numbers to ints (used for replay arguments).
static func ints_deep(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return int(v) if is_whole(v) else v
		TYPE_ARRAY:
			var out: Array = []
			for item: Variant in v:
				out.append(ints_deep(item))
			return out
		TYPE_DICTIONARY:
			var d: Dictionary = {}
			for k: Variant in v:
				d[k] = ints_deep(v[k])
			return d
	return v


## Reads a whole text file; returns "" and sets error text in out[0] on failure.
static func read_text(path: String, out_error: Array) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		out_error.append("cannot open %s" % path)
		return ""
	return f.get_as_text()
