## Player conveniences (decision D-54), kept apart from drawing so they can
## be tested headless. Presentation layer: these read the simulation and
## build ordinary commands; they never change simulation state themselves.
##   - control groups: Ctrl+1..9 stores the selection, 1..9 recalls it;
##   - idle workers: "." cycles through them;
##   - rally points: units trained at a building walk to its rally point
##     (a worker sent to wood, gold or the player's own farm gathers there);
##   - attack alerts: at most one "under attack" warning every ALERT_GAP s.
class_name CommandAids
extends RefCounted

const ALERT_GAP: float = 8.0


## Stores a copy of `ids` as group `n` (1 to 9).
static func assign(groups: Dictionary, n: int, ids: Array[int]) -> void:
	groups[n] = ids.duplicate()


## The group's units that are still alive and still the faction's.
static func recall(groups: Dictionary, n: int, sim: Simulation, faction: String) -> Array[int]:
	var out: Array[int] = []
	for id: int in groups.get(n, []):
		var e: Entity = sim.entity(id)
		if e != null and e.faction == faction and e.is_unit():
			out.append(id)
	groups[n] = out.duplicate()
	return out


## The faction's idle workers, in id order.
static func idle_workers(sim: Simulation, faction: String) -> Array[int]:
	var out: Array[int] = []
	for id: int in sim.entities:
		var e: Entity = sim.entities[id]
		if e.kind == "worker" and e.faction == faction and e.order_type == "idle":
			out.append(id)
	return out


## The next idle worker after `after` (wrapping round), or 0 if none.
static func next_idle(sim: Simulation, faction: String, after: int) -> int:
	var idle: Array[int] = idle_workers(sim, faction)
	if idle.is_empty():
		return 0
	for id: int in idle:
		if id > after:
			return id
	return idle[0]


## The order for a unit just trained at a building whose rally point is
## `cell`: a worker gathers if the cell holds a node or the faction's own
## finished farm; otherwise the unit walks there.
static func rally_command(sim: Simulation, faction: String, unit_id: int, cell: Vector2i) -> Dictionary:
	var u: Entity = sim.entity(unit_id)
	var target: Entity = sim.entity(sim.occupant_at(cell))
	if u != null and u.kind == "worker" and target != null and target.is_harvestable() \
			and (target.is_node() or target.faction == faction):
		return Commands.harvest(faction, [unit_id], target.id)
	return Commands.move(faction, [unit_id], cell)


## Whether an attack on one of the faction's things should raise an alert:
## the target is the faction's, out of view, and the last alert was at least
## ALERT_GAP seconds ago.
static func should_alert(sim: Simulation, faction: String, event: Dictionary, in_view: bool, now: float, last: float) -> bool:
	var t: Entity = sim.entity(int(event.get("target", 0)))
	return t != null and t.faction == faction and not in_view and now - last >= ALERT_GAP
