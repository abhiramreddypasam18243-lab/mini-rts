## The invariant checker (AC-06). Recomputes everything from the entities
## themselves rather than trusting the simulation's own caches, and returns
## one message per broken rule (an empty list means the state is valid).
## Selection lives in the UI and is checked there (build step 7).
class_name Invariants
extends RefCounted


static func check(sim: Simulation) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var m: MapGrid = sim.map
	var cover: PackedInt32Array = PackedInt32Array()
	cover.resize(m.width * m.height)
	var population: Dictionary = {"player": 0, "ai": 0}

	# Buildings and nodes: inside the map, on walkable terrain, no overlap.
	for id: int in sim.entities:
		var e: Entity = sim.entities[id]
		if e.is_building() or e.is_node():
			for c: Vector2i in e.footprint():
				if not m.in_bounds(c):
					problems.append("entity %d footprint outside the map at %s" % [id, c])
					continue
				if not m.is_walkable(c):
					problems.append("entity %d stands on blocked terrain at %s" % [id, c])
				cover[c.y * m.width + c.x] += 1
				if cover[c.y * m.width + c.x] == 2:
					problems.append("buildings or nodes overlap at %s" % c)
		if e.is_building():
			if e.queue.size() > Consts.QUEUE_CAPACITY:
				problems.append("building %d queue has %d items" % [id, e.queue.size()])
			population[e.faction] += e.queue.size()
		if e.is_unit():
			population[e.faction] += 1

	# Units: on walkable cells outside every footprint; orders refer to the living.
	for id: int in sim.entities:
		var e: Entity = sim.entities[id]
		if not e.is_unit():
			continue
		var c: Vector2i = e.unit_cell()
		if not m.is_walkable(c):
			problems.append("unit %d on blocked terrain at %s" % [id, c])
		elif cover[c.y * m.width + c.x] > 0:
			problems.append("unit %d inside a building or node at %s" % [id, c])
		if e.order_target != 0:
			var t: Entity = sim.entities.get(e.order_target)
			if t == null or t.hp <= 0 and not t.is_node():
				problems.append("unit %d order refers to missing entity %d" % [id, e.order_target])
		if e.dropoff_id != 0 and not sim.entities.has(e.dropoff_id):
			problems.append("unit %d drop-off refers to missing entity %d" % [id, e.dropoff_id])
		if e.order_type == "idle" and not e.path.is_empty():
			problems.append("idle unit %d still has a path" % id)

	for f: String in sim.resources:
		for r: String in sim.resources[f]:
			if sim.resources[f][r] < 0:
				problems.append("%s %s is negative (%d)" % [f, r, sim.resources[f][r]])

	# Conservation (AC-07), for each faction and resource:
	#   removed from nodes == carried + deposited
	#   stockpile == start + deposited + refunded - spent
	# and overall: resource missing from nodes == removed by both factions.
	var carried: Dictionary = {"player": {"wood": 0, "gold": 0}, "ai": {"wood": 0, "gold": 0}}
	var in_nodes: Dictionary = {"wood": 0, "gold": 0}
	for id: int in sim.entities:
		var e: Entity = sim.entities[id]
		if e.is_unit() and e.carry > 0:
			carried[e.faction][e.carry_type] += e.carry
		elif e.is_node():
			in_nodes[e.kind] += e.amount
	var b: ResourceManager = sim.bank
	for r: String in ResourceManager.TYPES:
		var removed_total: int = 0
		for f: String in Consts.FACTIONS:
			removed_total += b.removed[f][r]
			if b.removed[f][r] != carried[f][r] + b.deposited[f][r]:
				problems.append("%s %s: removed %d != carried %d + deposited %d" % [f, r, b.removed[f][r], carried[f][r], b.deposited[f][r]])
		if sim.initial_node_total[r] - in_nodes[r] != removed_total:
			problems.append("%s: nodes lost %d but workers removed %d" % [r, sim.initial_node_total[r] - in_nodes[r], removed_total])
	for f: String in Consts.FACTIONS:
		if not b.balanced(f):
			problems.append("%s stockpile does not balance: %s" % [f, b.stock[f]])
	for f: String in population:
		if population[f] > Consts.POPULATION_CAP:
			problems.append("%s population %d exceeds %d" % [f, population[f], Consts.POPULATION_CAP])
	if sim.results_raised > 1:
		problems.append("%d match results raised" % sim.results_raised)

	# The simulation's solid grid must match terrain plus footprints.
	for i: int in m.width * m.height:
		var expected: int = 1 if m.blocked[i] == 1 or cover[i] > 0 else 0
		if sim.solid[i] != expected:
			problems.append("solid grid out of date at (%d, %d)" % [i % m.width, i / m.width])
			break
	return problems
