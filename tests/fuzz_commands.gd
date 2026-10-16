## Random commands for the fuzz tests (AC-06, AC-07, AC-26), from a seeded
## test generator. `valid` builds commands a sensible player could give
## (own units, real nodes, cells inside the map); `any` mixes those with
## nonsense: fake ids, enemy units, cells outside the map, bad indexes.
class_name FuzzCommands
extends RefCounted

const COMMANDS: Array[String] = ["move", "harvest", "build", "attack", "train", "cancel_train"]


static func any(rng: SimRng, sim: Simulation) -> Dictionary:
	return valid(rng, sim) if rng.range_int(2) == 0 else invalid(rng, sim)


static func valid(rng: SimRng, sim: Simulation) -> Dictionary:
	var f: String = Consts.FACTIONS[rng.range_int(2)]
	var workers: Array = []
	var units: Array = []
	var nodes: Array = []
	var buildings: Array = []
	for id: int in sim.entities:
		var e: Entity = sim.entities[id]
		if e.is_node():
			nodes.append(id)
		elif e.faction == f and e.is_unit():
			units.append(id)
			if e.kind == "worker":
				workers.append(id)
		elif e.faction == f and e.is_building():
			buildings.append(id)
	var roll: int = rng.range_int(10)
	if roll < 5 and not workers.is_empty() and not nodes.is_empty():
		return Commands.harvest(f, _some(rng, workers), nodes[rng.range_int(nodes.size())])
	if roll < 7 and not buildings.is_empty():
		var b: int = buildings[rng.range_int(buildings.size())]
		var kind: String = "worker" if sim.entity(b).kind == "hq" else ["melee", "ranged"][rng.range_int(2)]
		return Commands.train(f, b, kind)
	if roll < 8 and not buildings.is_empty():
		var b: int = buildings[rng.range_int(buildings.size())]
		return Commands.cancel_train(f, b, rng.range_int(3))
	var cell: Vector2i = Vector2i(rng.range_int(sim.map.width), rng.range_int(sim.map.height))
	return Commands.move(f, _some(rng, units), cell)


static func invalid(rng: SimRng, sim: Simulation) -> Dictionary:
	var ids: Array = sim.entities.keys()
	var f: String = Consts.FACTIONS[rng.range_int(2)]
	var pick: Callable = func() -> int:
		return 9999 if rng.range_int(10) == 0 else ids[rng.range_int(ids.size())]
	var some: Array = []
	for i: int in rng.between(0, 4):
		some.append(pick.call())
	var cell: Vector2i = Vector2i(rng.between(-2, sim.map.width + 1), rng.between(-2, sim.map.height + 1))
	match COMMANDS[rng.range_int(COMMANDS.size())]:
		"move":
			return Commands.move(f, some, cell)
		"harvest":
			return Commands.harvest(f, some, pick.call())
		"build":
			return Commands.build(f, pick.call(), "barracks", cell)
		"attack":
			return Commands.attack(f, some, pick.call())
		"train":
			return Commands.train(f, pick.call(), ["worker", "melee", "ranged", "hq"][rng.range_int(4)])
		_:
			return Commands.cancel_train(f, pick.call(), rng.between(-2, 6))


static func _some(rng: SimRng, from: Array) -> Array:
	var out: Array = []
	if from.is_empty():
		return out
	for i: int in rng.between(1, mini(4, from.size())):
		out.append(from[rng.range_int(from.size())])
	return out
