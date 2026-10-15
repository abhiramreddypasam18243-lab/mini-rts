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
		if e.order_type == "idle" and not e.path.is_empty():
			problems.append("idle unit %d still has a path" % id)

	for f: String in sim.resources:
		for r: String in sim.resources[f]:
			if sim.resources[f][r] < 0:
				problems.append("%s %s is negative (%d)" % [f, r, sim.resources[f][r]])
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
