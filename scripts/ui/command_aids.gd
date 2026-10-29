## Player conveniences (decision D-54), kept apart from drawing so they can
## be tested headless. Presentation layer: these read the simulation and
## build ordinary commands; they never change simulation state themselves.
##   - control groups: Ctrl+1..9 stores the selection, 1..9 recalls it;
##   - idle workers: "." cycles through them;
##   - rally points: units trained at a building walk to its rally point
##     (a worker sent to wood, gold or the player's own farm gathers there);
##   - attack alerts: at most one "under attack" warning every ALERT_GAP s;
##   - D-56: new workers and finished builders start gathering by
##     themselves; double-click selects every unit of that kind in view;
##     Ctrl+A selects every soldier;
##   - D-59, D-62: when something of the player's is hit, idle soldiers
##     come to help (an attack-move to the fight): all of them for a hit
##     soldier, those within 10 cells for a hit worker or building;
##   - D-61: a moving soldier that is hit fights back, unless the player
##     ordered it away while it was fighting back (a retreat).
class_name CommandAids
extends RefCounted

const ALERT_GAP: float = 8.0
## Idle soldiers within this many cells of a hit come to help (D-59).
const HELP_RADIUS: int = 10


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


## The order that puts an idle worker to work (D-56): gather from
## `prefer` if it is the faction's own finished farm with food, else from
## the nearest resource node the faction knows about (ties: lowest id).
## {} when there is none.
static func auto_gather(sim: Simulation, faction: String, worker_id: int, prefer: int = 0) -> Dictionary:
	var w: Entity = sim.entity(worker_id)
	if w == null or w.kind != "worker":
		return {}
	var p: Entity = sim.entity(prefer)
	if p != null and p.kind == "farm" and p.faction == faction and p.is_harvestable() and p.amount > 0:
		return Commands.harvest(faction, [worker_id], p.id)
	var best: int = 0
	var best_d: int = -1
	for id: int in sim.fog.memory[faction]:
		var n: Entity = sim.entity(id)
		if n == null or not n.is_node():
			continue
		var d: Vector2i = MapGrid.cell_center(n.cell) - w.pos
		var dd: int = d.x * d.x + d.y * d.y
		if best_d == -1 or dd < best_d or dd == best_d and id < best:
			best = id
			best_d = dd
	return {} if best == 0 else Commands.harvest(faction, [worker_id], best)


## The faction's units of `kind` whose position lies in `view` (world
## pixels), in id order (double-click, D-56).
static func same_kind_in(sim: Simulation, faction: String, kind: String, view: Rect2) -> Array[int]:
	var out: Array[int] = []
	for id: int in sim.entities:
		var e: Entity = sim.entities[id]
		if e.kind == kind and e.faction == faction and view.has_point(Vector2(e.pos) * Consts.PIXELS_PER_CELL / 1000.0):
			out.append(id)
	return out


## Every soldier of the faction, in id order (Ctrl+A, D-56).
static func all_soldiers(sim: Simulation, faction: String) -> Array[int]:
	var out: Array[int] = []
	for id: int in sim.entities:
		var e: Entity = sim.entities[id]
		if e.is_soldier() and e.faction == faction:
			out.append(id)
	return out


## Whether an attack on one of the faction's things should raise an alert:
## the target is the faction's, out of view, and the last alert was at least
## ALERT_GAP seconds ago.
static func should_alert(sim: Simulation, faction: String, event: Dictionary, in_view: bool, now: float, last: float) -> bool:
	var t: Entity = sim.entity(int(event.get("target", 0)))
	return t != null and t.faction == faction and not in_view and now - last >= ALERT_GAP


## Help for a hit (D-59, D-62): when one of `faction`'s soldiers is attacked,
## every idle soldier of the faction comes, wherever it is (the whole
## battalion); when a worker or building is attacked, only idle soldiers
## within HELP_RADIUS cells of it (squared cell distance, the same measure as
## vision). They attack-move to the fight: to the attacker's cell if it
## is a unit the faction sees, otherwise to the victim's own cell. Soldiers
## with an order, the victim itself and workers are left alone. Returns {}
## when nobody is sent. Only idle soldiers, so a soldier already on its way
## is not ordered again.
static func help_command(sim: Simulation, faction: String, event: Dictionary) -> Dictionary:
	var t: Entity = sim.entity(int(event.get("target", 0)))
	if t == null or t.faction != faction:
		return {}
	var a: Entity = sim.entity(int(event.get("attacker", 0)))
	var where: Vector2i = t.unit_cell() if t.is_unit() else t.cell + t.size / 2
	var dest: Vector2i
	if a != null and a.is_unit() and sim.fog.is_visible(faction, a.unit_cell()):
		dest = a.unit_cell()
	elif t.is_unit():
		dest = where
	else:
		return {}
	var ids: Array[int] = []
	for id: int in sim.entities:
		var e: Entity = sim.entities[id]
		if e.faction != faction or not e.is_soldier() or e.order_type != "idle" or id == t.id:
			continue
		var d: Vector2i = e.unit_cell() - where
		if t.is_soldier() or d.x * d.x + d.y * d.y <= HELP_RADIUS * HELP_RADIUS:
			ids.append(id)
	if ids.is_empty():
		return {}
	return Commands.attack_move(faction, ids, dest)


## Fighting back (D-61): when a soldier of `faction` walking on a plain move
## is hit by an enemy unit the faction sees, it attacks that unit. Not for a
## soldier in `retreating`, one with Shift-queued orders (the route is kept),
## idle ones (auto-acquire handles them), attack-moves or attacks (already
## fighting), or a hit from a building (a tower is not worth turning for).
static func fight_back_command(sim: Simulation, faction: String, event: Dictionary, retreating: Dictionary) -> Dictionary:
	var t: Entity = sim.entity(int(event.get("target", 0)))
	var a: Entity = sim.entity(int(event.get("attacker", 0)))
	if t == null or a == null or t.faction != faction or a.faction == faction:
		return {}
	if not t.is_soldier() or t.order_type != "move" or not t.orders.is_empty() or retreating.has(t.id):
		return {}
	if not a.is_unit() or not sim.fog.is_visible(faction, a.unit_cell()):
		return {}
	return Commands.attack(faction, [t.id], a.id)


## Remembers the soldiers a fight-back command turned.
static func note_fight_back(cmd: Dictionary, fought: Dictionary) -> void:
	for id: Variant in cmd.args.unit_ids:
		fought[int(id)] = true


## The player's own move: soldiers that were fighting back now retreat.
static func note_retreat(cmd: Dictionary, fought: Dictionary, retreating: Dictionary) -> void:
	if cmd.get("command", "") != "move":
		return
	for id: Variant in cmd.args.get("unit_ids", []):
		if fought.has(int(id)):
			fought.erase(int(id))
			retreating[int(id)] = true


## Forgets soldiers that died, stopped fighting back, or finished retreating.
static func prune_fight_back(sim: Simulation, fought: Dictionary, retreating: Dictionary) -> void:
	for id: int in fought.keys():
		var e: Entity = sim.entity(id)
		if e == null or e.order_type != "attack":
			fought.erase(id)
	for id: int in retreating.keys():
		var e: Entity = sim.entity(id)
		if e == null or e.order_type != "move":
			retreating.erase(id)
