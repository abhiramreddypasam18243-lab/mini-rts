## Fog of war state per faction (SPEC 5.6).
##
## Build step 4 needs only the "explored" grid, because buildings may be
## placed only on cells the faction has explored (AC-36, `not_explored`).
## Until build step 6 adds vision, every cell starts explored (decision D-29);
## step 6 replaces reveal_all() with real visibility from units and buildings.
class_name Fog
extends RefCounted

var width: int
var height: int
## Faction -> PackedByteArray, 1 = explored.
var explored: Dictionary = {}


func _init(p_width: int, p_height: int, factions: Array[String]) -> void:
	width = p_width
	height = p_height
	for f: String in factions:
		var g: PackedByteArray = PackedByteArray()
		g.resize(width * height)
		explored[f] = g


## Placeholder until build step 6: the whole map counts as explored.
func reveal_all() -> void:
	# Packed arrays are values: fill a copy, then store it back.
	for f: String in explored:
		var g: PackedByteArray = explored[f]
		g.fill(1)
		explored[f] = g


func is_explored(faction: String, cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
		return false
	return explored[faction][cell.y * width + cell.x] == 1


func set_explored(faction: String, cell: Vector2i, value: bool) -> void:
	explored[faction][cell.y * width + cell.x] = 1 if value else 0


func add_to_hash(h: StateHasher) -> void:
	for f: String in Consts.FACTIONS:
		h.add_bytes(explored[f])
