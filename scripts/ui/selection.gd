## Selection and context orders (SPEC 9; AC-21 to AC-23). Presentation layer:
## it reads the simulation and returns commands, and never changes the state.
##
## Rules (decision D-32):
## - Click a friendly unit or building: it becomes the selection.
## - Click an enemy, a node or a remembered building: show its details only.
## - Click empty ground: clear everything.
## - Box: friendly units whose position is inside, lowest ids first, at most 24.
## - Only what the player can see can be clicked: an enemy unit in fog is
##   invisible, an enemy building in fog shows its last-seen ghost.
## - Right click: an empty cell moves every selected unit; a resource node
##   sends the selected workers to harvest; a visible enemy sends the
##   selected soldiers to attack; anything else does nothing.
class_name Selection
extends RefCounted

## Click radius around a unit's position: 0.42 cells (in milli-cells, squared).
const PICK_RADIUS_SQ: int = 420 * 420

## Friendly units, or a single friendly building.
var selected: Array[int] = []
## Entity whose details are shown (may be an enemy, a node or a ghost); 0 = none.
var inspected: int = 0


## The entity at a point (milli-cells) that `faction` can see, or 0. Units
## first (nearest within the click radius), then the building or node on
## the cell, then a remembered building or node.
static func pick(sim: Simulation, faction: String, p: Vector2i) -> int:
	var best: int = 0
	var best_d: int = PICK_RADIUS_SQ + 1
	for id: int in sim.entities:
		var e: Entity = sim.entities[id]
		if not e.is_unit():
			continue
		if e.faction != faction and not sim.fog.is_visible(faction, e.unit_cell()):
			continue
		var d: Vector2i = e.pos - p
		var dd: int = d.x * d.x + d.y * d.y
		if dd < best_d:
			best = id
			best_d = dd
	if best != 0:
		return best
	var cell: Vector2i = MapGrid.milli_to_cell(p)
	if not sim.map.in_bounds(cell):
		return 0
	var occ: int = sim.occupant_at(cell)
	if occ != 0:
		var e: Entity = sim.entity(occ)
		if e.faction == faction or sim.fog.any_visible(faction, e.cell, e.size):
			return occ
	for gid: int in sim.fog.memory[faction]:
		var g: Dictionary = sim.fog.memory[faction][gid]
		var c: Vector2i = g.cell
		var s: Vector2i = g.size
		if cell.x >= c.x and cell.y >= c.y and cell.x < c.x + s.x and cell.y < c.y + s.y:
			return gid
	return 0


func click(sim: Simulation, faction: String, p: Vector2i) -> void:
	var id: int = pick(sim, faction, p)
	selected = []
	inspected = id
	var e: Entity = sim.entity(id)
	if e != null and e.faction == faction:
		selected = [id]


func box(sim: Simulation, faction: String, a: Vector2i, b: Vector2i) -> void:
	var lo: Vector2i = Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var hi: Vector2i = Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	selected = []
	for id: int in sim.entities:
		var e: Entity = sim.entities[id]
		if e.is_unit() and e.faction == faction and selected.size() < Consts.MAX_SELECTION \
				and e.pos.x >= lo.x and e.pos.x <= hi.x and e.pos.y >= lo.y and e.pos.y <= hi.y:
			selected.append(id)
	inspected = selected[0] if not selected.is_empty() else 0


## Drops dead entities from the selection (AC-22).
func prune(sim: Simulation) -> void:
	selected = selected.filter(func(id: int) -> bool: return sim.entities.has(id))
	if inspected != 0 and not sim.entities.has(inspected):
		var remembered: bool = false
		for f: String in sim.fog.memory:
			remembered = remembered or (sim.fog.memory[f] as Dictionary).has(inspected)
		if not remembered:
			inspected = 0


func clear() -> void:
	selected = []
	inspected = 0


func units(sim: Simulation) -> Array[int]:
	var out: Array[int] = []
	for id: int in selected:
		var e: Entity = sim.entity(id)
		if e != null and e.is_unit():
			out.append(id)
	return out


func of_kind(sim: Simulation, test: Callable) -> Array[int]:
	var out: Array[int] = []
	for id: int in units(sim):
		if test.call(sim.entity(id)):
			out.append(id)
	return out


func building(sim: Simulation) -> Entity:
	if selected.size() == 1:
		var e: Entity = sim.entity(selected[0])
		if e != null and e.is_building():
			return e
	return null


## The commands a right click at `p` gives (AC-23); [] means do nothing.
func context_commands(sim: Simulation, faction: String, p: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var mine: Array[int] = units(sim)
	if mine.is_empty():
		return out
	var cell: Vector2i = MapGrid.milli_to_cell(p)
	if not sim.map.in_bounds(cell):
		return out
	var id: int = pick(sim, faction, p)
	if id == 0:
		out.append(Commands.move(faction, mine, cell))
		return out
	var t: Entity = sim.entity(id)
	if t == null or t.faction == faction:
		return out  # a ghost, or a friendly unit or building
	if t.is_node():
		var workers: Array[int] = of_kind(sim, func(e: Entity) -> bool: return e.kind == "worker")
		if not workers.is_empty():
			out.append(Commands.harvest(faction, workers, id))
		return out
	var seen: bool = sim.fog.is_visible(faction, t.unit_cell()) if t.is_unit() else sim.fog.any_visible(faction, t.cell, t.size)
	if seen:
		var soldiers: Array[int] = of_kind(sim, func(e: Entity) -> bool: return e.is_soldier())
		if not soldiers.is_empty():
			out.append(Commands.attack(faction, soldiers, id))
	return out
