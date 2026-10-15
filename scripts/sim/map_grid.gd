## The terrain grid, resource nodes and start positions of a map (SPEC 5.1, 8).
## Rules: (0, 0) is the top-left cell; x grows right, y grows down.
## A cell (x, y) has its centre at (x*1000 + 500, y*1000 + 500) milli-cells.
## This class holds only static map data; buildings and units live in the
## simulation. Loading results are {"map": MapGrid or null, "error": String}.
class_name MapGrid
extends RefCounted

const HQ_SIZE: int = 3
const NODE_TYPES: Array[String] = ["wood", "gold"]

var map_name: String = ""
var width: int = 0
var height: int = 0
## 1 = blocked terrain, 0 = walkable; index y * width + x.
var blocked: PackedByteArray = PackedByteArray()
## Each node: {"type": String, "cell": Vector2i, "amount": int}.
var nodes: Array[Dictionary] = []
## Faction name -> HQ anchor (top-left cell of the 3 x 3 footprint).
var starts: Dictionary = {}
var possible_starts: Array[Vector2i] = []


func _init(p_width: int = 0, p_height: int = 0) -> void:
	width = p_width
	height = p_height
	blocked.resize(width * height)


# --- coordinates (AC-09) ----------------------------------------------------

static func cell_center(cell: Vector2i) -> Vector2i:
	return cell * Consts.MILLI_PER_CELL + Vector2i(500, 500)


## Floor division, so a position anywhere inside a cell maps to that cell.
static func milli_to_cell(pos: Vector2i) -> Vector2i:
	return Vector2i(
		(pos.x - posmod(pos.x, Consts.MILLI_PER_CELL)) / Consts.MILLI_PER_CELL,
		(pos.y - posmod(pos.y, Consts.MILLI_PER_CELL)) / Consts.MILLI_PER_CELL)


static func milli_to_pixel(pos: Vector2i) -> Vector2i:
	return pos * Consts.PIXELS_PER_CELL / Consts.MILLI_PER_CELL


# --- queries ----------------------------------------------------------------

func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


## Walkable terrain only (buildings and nodes are tracked by the simulation).
func is_walkable(cell: Vector2i) -> bool:
	return in_bounds(cell) and blocked[cell.y * width + cell.x] == 0


func set_blocked(cell: Vector2i, value: bool) -> void:
	blocked[cell.y * width + cell.x] = 1 if value else 0


## A stable text summary of the whole map, used to compare maps (AC-11).
func fingerprint() -> String:
	var parts: PackedStringArray = [str(width), str(height), blocked.hex_encode()]
	for node: Dictionary in nodes:
		parts.append("%s@%d,%d:%d" % [node.type, node.cell.x, node.cell.y, node.amount])
	for f: String in Consts.FACTIONS:
		if starts.has(f):
			parts.append("%s@%s" % [f, starts[f]])
	return "|".join(parts)


func add_to_hash(h: StateHasher) -> void:
	h.add_int(width)
	h.add_int(height)
	h.add_bytes(blocked)


# --- loading (AC-08) --------------------------------------------------------

static func load_file(path: String) -> Dictionary:
	var err: Array = []
	var text: String = JsonUtil.read_text(path, err)
	if not err.is_empty():
		return _fail(str(err[0]))
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail("%s is not a JSON object" % path)
	return from_dict(parsed)


static func from_dict(d: Dictionary) -> Dictionary:
	for key: String in ["width", "height", "tiles", "starts", "nodes"]:
		if not d.has(key):
			return _fail("missing field '%s'" % key)
	if not JsonUtil.is_whole(d.width) or not JsonUtil.is_whole(d.height) or int(d.width) < 1 or int(d.height) < 1:
		return _fail("width and height must be positive whole numbers")
	var m: MapGrid = MapGrid.new(int(d.width), int(d.height))
	m.map_name = str(d.get("name", ""))

	var tiles: Array = d.tiles
	if tiles.size() != m.height:
		return _fail("map has %d rows, expected height %d" % [tiles.size(), m.height])
	for y: int in m.height:
		var row: String = str(tiles[y])
		if row.length() != m.width:
			return _fail("row %d has %d characters, expected width %d (ragged row)" % [y, row.length(), m.width])
		for x: int in m.width:
			var ch: String = row[x]
			if ch == "#":
				m.set_blocked(Vector2i(x, y), true)
			elif ch != ".":
				return _fail("unknown tile character '%s' at (%d, %d)" % [ch, x, y])

	for s: Variant in d.starts:
		var faction: String = str((s as Dictionary).get("faction", ""))
		if not faction in Consts.FACTIONS:
			return _fail("start has unknown faction '%s'" % faction)
		var cell: Variant = JsonUtil.to_cell((s as Dictionary).get("cell"))
		if cell == null:
			return _fail("start for faction '%s' needs a cell [x, y]" % faction)
		for dy: int in HQ_SIZE:
			for dx: int in HQ_SIZE:
				var c: Vector2i = (cell as Vector2i) + Vector2i(dx, dy)
				if not m.in_bounds(c):
					return _fail("start for faction '%s' at %s: HQ footprint is outside the map" % [faction, cell])
				if not m.is_walkable(c):
					return _fail("start for faction '%s' at %s: HQ footprint is on a blocked cell %s" % [faction, cell, c])
		m.starts[faction] = cell
	for f: String in Consts.FACTIONS:
		if not m.starts.has(f):
			return _fail("missing start for faction '%s'" % f)

	for ps: Variant in d.get("possible_starts", []):
		var cell: Variant = JsonUtil.to_cell(ps)
		if cell == null or not m.in_bounds(cell):
			return _fail("possible start %s is not a cell inside the map" % [ps])
		m.possible_starts.append(cell)

	var nodes_raw: Array = d.nodes
	for i: int in nodes_raw.size():
		var n: Dictionary = nodes_raw[i]
		var type: String = str(n.get("type", ""))
		if not type in NODE_TYPES:
			return _fail("node %d has unknown type '%s'" % [i, type])
		var cell: Variant = JsonUtil.to_cell(n.get("cell"))
		if cell == null:
			return _fail("node %d needs a cell [x, y]" % i)
		if not m.in_bounds(cell):
			return _fail("node %d at %s is outside the map" % [i, cell])
		if not m.is_walkable(cell):
			return _fail("node %d at %s is on a blocked cell" % [i, cell])
		for f: String in m.starts:
			var a: Vector2i = m.starts[f]
			var c: Vector2i = cell
			if c.x >= a.x and c.x < a.x + HQ_SIZE and c.y >= a.y and c.y < a.y + HQ_SIZE:
				return _fail("node %d at %s is inside the %s HQ footprint" % [i, cell, f])
		if not JsonUtil.is_whole(n.get("amount")) or int(n.amount) < 0:
			return _fail("node %d amount must be a whole number >= 0" % i)
		m.nodes.append({"type": type, "cell": cell, "amount": int(n.amount)})
	return {"map": m, "error": ""}


static func _fail(msg: String) -> Dictionary:
	return {"map": null, "error": "map: " + msg}
