## Units, buildings and resource nodes (SPEC 4, 5).
## One class with a `kind`, so every entity lives in one id-ordered table and
## the simulation can process them in id order (determinism rule).
##   units:     worker, melee, ranged   (faction "player" or "ai")
##   buildings: hq, barracks            (faction "player" or "ai")
##   nodes:     wood, gold              (faction "")
## A unit has exactly one current order (SPEC 5.2, decision D-14).
class_name Entity
extends RefCounted

const UNIT_KINDS: Array[String] = ["worker", "melee", "ranged"]
const BUILDING_KINDS: Array[String] = ["hq", "barracks"]
const NODE_KINDS: Array[String] = ["wood", "gold"]
const KIND_CODE: Dictionary = {"worker": 1, "melee": 2, "ranged": 3, "hq": 4, "barracks": 5, "wood": 6, "gold": 7}
const ORDER_CODE: Dictionary = {"idle": 0, "move": 1, "harvest": 2, "build": 3, "attack": 4}
const FACTION_CODE: Dictionary = {"": 0, "player": 1, "ai": 2}

var id: int
var kind: String
var faction: String
## Buildings and nodes: top-left cell of the footprint.
var cell: Vector2i
var size: Vector2i = Vector2i(1, 1)
## Units: position in milli-cells.
var pos: Vector2i
var hp: int = 0
## Nodes: resource left.
var amount: int = 0

# --- the unit's single current order --------------------------------------
var order_type: String = "idle"
## Entity the order refers to (harvest node, build site, attack target); 0 = none.
var order_target: int = 0
var order_cell: Vector2i
var path: Array[Vector2i] = []
## Index in `path` of the next cell centre to walk to.
var path_i: int = 0

# --- harvesting (workers; SPEC 5.3) ----------------------------------------
## Harvest sub-phase: "to_node", "gathering" or "to_dropoff" ("" otherwise).
var phase: String = ""
## Ticks spent gathering in the current trip.
var timer: int = 0
## What the worker carries. Kept when the order changes (AC-34).
var carry: int = 0
var carry_type: String = ""
## HQ the worker is walking to; 0 = none.
var dropoff_id: int = 0
## Type and cell of the node being harvested, used to find a replacement
## when it runs out.
var harvest_type: String = ""
var harvest_cell: Vector2i

# --- buildings ------------------------------------------------------------
var complete: bool = true
var progress: int = 0
var queue: Array[Dictionary] = []


func _init(p_id: int, p_kind: String, p_faction: String) -> void:
	id = p_id
	kind = p_kind
	faction = p_faction


func is_unit() -> bool:
	return kind in UNIT_KINDS


func is_building() -> bool:
	return kind in BUILDING_KINDS


func is_node() -> bool:
	return kind in NODE_KINDS


func unit_cell() -> Vector2i:
	return MapGrid.milli_to_cell(pos)


func footprint() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy: int in size.y:
		for dx: int in size.x:
			out.append(cell + Vector2i(dx, dy))
	return out


## Clears the order. A carried load is kept (SPEC 5.3).
func set_idle() -> void:
	order_type = "idle"
	order_target = 0
	order_cell = Vector2i.ZERO
	path.clear()
	path_i = 0
	phase = ""
	timer = 0
	dropoff_id = 0


## The smallest Chebyshev distance from `c` to this entity's footprint:
## 1 means touching it, diagonals included.
func chebyshev_to(c: Vector2i) -> int:
	var dx: int = maxi(maxi(cell.x - c.x, c.x - (cell.x + size.x - 1)), 0)
	var dy: int = maxi(maxi(cell.y - c.y, c.y - (cell.y + size.y - 1)), 0)
	return maxi(dx, dy)


func add_to_hash(h: StateHasher) -> void:
	h.add_int(id)
	h.add_int(KIND_CODE[kind])
	h.add_int(FACTION_CODE[faction])
	h.add_int(cell.x)
	h.add_int(cell.y)
	h.add_int(pos.x)
	h.add_int(pos.y)
	h.add_int(hp)
	h.add_int(amount)
	h.add_int(ORDER_CODE[order_type])
	h.add_int(order_target)
	h.add_int(order_cell.x)
	h.add_int(order_cell.y)
	h.add_int(path_i)
	h.add_int(path.size())
	for c: Vector2i in path:
		h.add_int(c.x)
		h.add_int(c.y)
	h.add_string(phase)
	h.add_int(timer)
	h.add_int(carry)
	h.add_string(carry_type)
	h.add_int(dropoff_id)
	h.add_string(harvest_type)
	h.add_int(harvest_cell.x)
	h.add_int(harvest_cell.y)
	h.add_int(1 if complete else 0)
	h.add_int(progress)
	h.add_int(queue.size())
	for item: Dictionary in queue:
		h.add_int(KIND_CODE[item.type])
		h.add_int(item.remaining)
		h.add_string(item.status)
