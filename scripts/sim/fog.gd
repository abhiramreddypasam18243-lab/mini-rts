## Fog of war for each faction (SPEC 5.6; AC-54 to AC-58).
##
## Each cell is UNEXPLORED (never seen), EXPLORED (seen before, not now) or
## VISIBLE (seen now). A cell is VISIBLE when its centre is within the vision
## radius of one of the faction's units or buildings, measured as squared
## distance in cells to the nearest cell of that entity's footprint:
##   dx^2 + dy^2 <= vision^2        (no line of sight in v1)
##
## Storage: one 64-bit integer per map row and faction, one bit per cell
## (bit x = column x), so maps may be at most 62 cells wide (decision D-31).
## A vision circle covers, on each row it reaches, one run of cells
## [x0, x1]; marking it is a single OR with the mask of that run. On row
## offset dy, the run reaches w = the largest w with w^2 <= r^2 - dy^2 cells
## either side.
##
## update() recomputes a faction's view from scratch: the visible rows are
## rebuilt, then `explored |= visible`, so a cell that was seen stays
## EXPLORED and never returns to UNEXPLORED. The simulation calls it every
## 5 ticks; reveal() adds one new viewer at once (a unit is never born blind).
##
## Memory: enemy buildings and resource nodes are remembered as they were last
## seen ("ghosts") and forgotten only when their site is seen empty.
class_name Fog
extends RefCounted

const UNEXPLORED: int = 0
const EXPLORED: int = 1
const VISIBLE: int = 2
const MAX_WIDTH: int = 62

var width: int
var height: int
## Faction -> PackedInt64Array, one bitmask per row.
var visible: Dictionary = {}
var explored: Dictionary = {}
## Faction -> {entity id -> snapshot Dictionary}, in the order first seen.
var memory: Dictionary = {}
## Vision radius -> PackedInt32Array of half-widths, indexed by row offset dy.
var _half_cache: Dictionary = {}
## Working buffer for one update. Packed arrays are values in GDScript (a copy
## passed to a function is not the caller's array), so _mark() writes into
## this member and update()/reveal() store it back afterwards.
var _rows: PackedInt64Array


func _init(p_width: int, p_height: int, factions: Array[String]) -> void:
	assert(p_width <= MAX_WIDTH, "fog rows are 64-bit masks: maps may be at most %d cells wide" % MAX_WIDTH)
	width = p_width
	height = p_height
	for f: String in factions:
		var v: PackedInt64Array = PackedInt64Array()
		v.resize(height)
		visible[f] = v
		explored[f] = v.duplicate()
		memory[f] = {}


# --- queries ----------------------------------------------------------------

func state_of(faction: String, cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
		return UNEXPLORED
	if (visible[faction][cell.y] >> cell.x) & 1 == 1:
		return VISIBLE
	if (explored[faction][cell.y] >> cell.x) & 1 == 1:
		return EXPLORED
	return UNEXPLORED


func is_visible(faction: String, cell: Vector2i) -> bool:
	return state_of(faction, cell) == VISIBLE


func is_explored(faction: String, cell: Vector2i) -> bool:
	return state_of(faction, cell) != UNEXPLORED


## True if any cell of the rectangle is VISIBLE.
func any_visible(faction: String, anchor: Vector2i, size: Vector2i) -> bool:
	var x0: int = maxi(anchor.x, 0)
	var x1: int = mini(anchor.x + size.x - 1, width - 1)
	if x0 > x1:
		return false
	var mask: int = _span(x0, x1)
	var rows: PackedInt64Array = visible[faction]
	for y: int in range(maxi(anchor.y, 0), mini(anchor.y + size.y, height)):
		if rows[y] & mask != 0:
			return true
	return false


## The whole grid as one byte per cell (UNEXPLORED / EXPLORED / VISIBLE).
func grid(faction: String) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(width * height)
	var v: PackedInt64Array = visible[faction]
	var e: PackedInt64Array = explored[faction]
	for y: int in height:
		for x: int in width:
			if (v[y] >> x) & 1 == 1:
				out[y * width + x] = VISIBLE
			elif (e[y] >> x) & 1 == 1:
				out[y * width + x] = EXPLORED
	return out


## Test helper: forces a cell's explored flag (AC-36). Unexploring a cell
## also hides it.
func set_explored(faction: String, cell: Vector2i, value: bool) -> void:
	var e: PackedInt64Array = explored[faction]
	var v: PackedInt64Array = visible[faction]
	var bit: int = 1 << cell.x
	if value:
		e[cell.y] |= bit
	else:
		e[cell.y] &= ~bit
		v[cell.y] &= ~bit
	explored[faction] = e
	visible[faction] = v


# --- updates ----------------------------------------------------------------

## Recomputes `faction`'s view. viewers: the faction's units and buildings.
## remembered: every enemy building and resource node that exists now.
## vision: entity kind -> vision radius in cells.
func update(faction: String, viewers: Array[Entity], remembered: Array[Entity], vision: Dictionary) -> void:
	_rows = PackedInt64Array()
	_rows.resize(height)
	for v: Entity in viewers:
		_mark(v, vision[v.kind])
	_store(faction)
	_remember(faction, remembered)


## Marks one new viewer's circle VISIBLE without recomputing the rest.
func reveal(faction: String, viewer: Entity, r: int) -> void:
	_rows = visible[faction]
	_mark(viewer, r)
	_store(faction)


## visible = _rows; explored |= visible.
func _store(faction: String) -> void:
	visible[faction] = _rows
	var e: PackedInt64Array = explored[faction]
	for y: int in height:
		e[y] |= _rows[y]
	explored[faction] = e


## ORs a viewer's circle into _rows. A unit's footprint is the cell it
## stands on; a building's is its rectangle, and distance is measured to the
## nearest footprint cell, so each row's run is widened by the footprint.
func _mark(v: Entity, r: int) -> void:
	var lo: Vector2i = v.unit_cell() if v.is_unit() else v.cell
	var hi: Vector2i = lo if v.is_unit() else v.cell + v.size - Vector2i.ONE
	var half: PackedInt32Array = _half_widths(r)
	for y: int in range(maxi(lo.y - r, 0), mini(hi.y + r, height - 1) + 1):
		var dy: int = maxi(maxi(lo.y - y, y - hi.y), 0)
		var w: int = half[dy]
		var x0: int = maxi(lo.x - w, 0)
		var x1: int = mini(hi.x + w, width - 1)
		if x0 <= x1:
			_rows[y] |= _span(x0, x1)


## Bits x0..x1 set (x1 <= 61, so no shift reaches the sign bit).
static func _span(x0: int, x1: int) -> int:
	return ((1 << (x1 + 1)) - 1) & ~((1 << x0) - 1)


## half[dy] = largest w with w^2 + dy^2 <= r^2, for dy = 0..r (integers only).
func _half_widths(r: int) -> PackedInt32Array:
	if _half_cache.has(r):
		return _half_cache[r]
	var out: PackedInt32Array = PackedInt32Array()
	for dy: int in r + 1:
		var w: int = 0
		while (w + 1) * (w + 1) + dy * dy <= r * r:
			w += 1
		out.append(w)
	_half_cache[r] = out
	return out


## Refreshes snapshots of everything now visible, and forgets remembered
## things whose site is visible but which no longer exist (seen destroyed).
func _remember(faction: String, remembered: Array[Entity]) -> void:
	var mem: Dictionary = memory[faction]
	var alive: Dictionary = {}
	for e: Entity in remembered:
		alive[e.id] = true
		if any_visible(faction, e.cell, e.size):
			mem[e.id] = snapshot(e)
	for id: int in mem.keys():
		var s: Dictionary = mem[id]
		if not alive.has(id) and any_visible(faction, s.cell, s.size):
			mem.erase(id)


static func snapshot(e: Entity) -> Dictionary:
	return {
		"id": e.id, "kind": e.kind, "faction": e.faction, "cell": e.cell, "size": e.size,
		"hp": e.hp, "complete": e.complete, "amount": e.amount,
	}


func add_to_hash(h: StateHasher) -> void:
	for f: String in Consts.FACTIONS:
		for y: int in height:
			h.add_int(visible[f][y])
			h.add_int(explored[f][y])
		var mem: Dictionary = memory[f]
		h.add_int(mem.size())
		for id: int in mem:
			h.add_int(id)
			h.add_int(mem[id].hp)
			h.add_int(mem[id].amount)
