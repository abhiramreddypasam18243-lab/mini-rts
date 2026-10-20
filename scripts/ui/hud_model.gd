## The data the HUD shows, read from the simulation each frame (presentation
## layer; read-only). Kept apart from drawing so it can be tested headless
## (AC-35, AC-73).
class_name HudModel
extends RefCounted

const KIND_NAMES: Dictionary = {
	"worker": "Worker", "melee": "Melee soldier", "ranged": "Ranged soldier",
	"hq": "Headquarters", "barracks": "Barracks", "wood": "Wood", "gold": "Gold",
	"cavalry": "Cavalry", "farm": "Farm", "tower": "Guard tower", "stable": "Stable", "food": "Food",
	"forging": "Forging", "armour": "Armour",
}
## What each upgrade does (D-51), for button tooltips and the queue.
const UPGRADE_TEXT: Dictionary = {
	"forging": "Soldiers deal +2 damage",
	"armour": "Soldiers take 2 less damage per hit",
}
const MESSAGES: Dictionary = {
	"no_path": "No path to that spot",
	"no_node": "Resource used up: worker is idle",
	"no_dropoff": "No HQ left to bring resources to",
	"spawn_blocked": "Spawn area blocked: clear a space",
	"insufficient_resources": "Not enough resources",
	"invalid_placement": "Can't build there",
	"not_explored": "Explore that ground first",
	"target_not_visible": "You can't see that target",
	"queue_full": "Queue is full",
	"population_cap": "Population cap reached",
	"not_ready": "Still under construction",
	"invalid_target": "Can't do that",
	"match_over": "The match is over",
	"already_researched": "Already researched",
}


## The stockpile of the same tick the simulation is on (AC-35).
static func resources(sim: Simulation, faction: String) -> Dictionary:
	return {"wood": sim.resources[faction].wood, "gold": sim.resources[faction].gold, "food": sim.resources[faction].food}


## An entity's or upgrade's cost (D-51 adds food).
static func cost_of(sim: Simulation, kind: String) -> Dictionary:
	if Consts.UPGRADES.has(kind):
		return sim.upgrade_cost(kind)
	return {"wood": sim.stats[kind].wood, "gold": sim.stats[kind].gold, "food": sim.stats[kind].food}


## "Need 60 wood · 20 gold" style text, listing only what is needed.
static func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for r: String in ["wood", "gold", "food"]:
		if int(cost.get(r, 0)) > 0:
			parts.append("%d %s" % [cost[r], r])
	return " · ".join(parts) if not parts.is_empty() else "free"


static func reason_text(code: String, cost: Dictionary) -> String:
	match code:
		"insufficient_resources":
			return "Need " + cost_text(cost)
		"not_ready":
			return "Under construction"
		"queue_full":
			return "Queue is full (%d)" % Consts.QUEUE_CAPACITY
		"population_cap":
			return "Population cap reached (%d)" % Consts.POPULATION_CAP
		"match_over":
			return "The match is over"
		"invalid_unit_for_building":
			return "Not trained here"
		"already_researched":
			return "Already researched"
	return MESSAGES.get(code, code)


## A train button: {"enabled", "reason", "cost"} (AC-73).
static func train_button(sim: Simulation, building_id: int, unit_type: String) -> Dictionary:
	var cost: Dictionary = cost_of(sim, unit_type)
	var b: Entity = sim.entity(building_id)
	var code: String = "invalid_target" if b == null else sim.train_check(b, unit_type)
	return {"enabled": code == "ok", "reason": "" if code == "ok" else reason_text(code, cost), "cost": cost}


## A research button (D-51): {"enabled", "reason", "cost"}.
static func research_button(sim: Simulation, building_id: int, upgrade: String) -> Dictionary:
	var cost: Dictionary = cost_of(sim, upgrade)
	var b: Entity = sim.entity(building_id)
	var code: String = "invalid_target" if b == null else sim.research_check(b, upgrade)
	return {"enabled": code == "ok", "reason": UPGRADE_TEXT[upgrade] if code == "ok" else reason_text(code, cost), "cost": cost}


## A build button (barracks, farm, tower or stable): needs a selected worker
## and the resources.
static func build_button(sim: Simulation, faction: String, worker_ids: Array, kind: String = "barracks") -> Dictionary:
	var cost: Dictionary = cost_of(sim, kind)
	var code: String = "ok"
	if sim.match_result != "":
		code = "match_over"
	elif worker_ids.is_empty():
		return {"enabled": false, "reason": "Select a worker first", "cost": cost}
	else:
		code = sim.bank.check(faction, sim.cost_of(kind))
	return {"enabled": code == "ok", "reason": "" if code == "ok" else reason_text(code, cost), "cost": cost}


## Text for a simulation event, or "" if the event is not shown.
static func message_text(event: Dictionary) -> String:
	match event.type:
		"message":
			return MESSAGES.get(event.code, event.code)
		"completed":
			return "Building complete"
		"researched":
			return "%s researched" % KIND_NAMES.get(event.get("upgrade", ""), "Upgrade")
		"trained":
			return "Unit ready"
	return ""


static func population(sim: Simulation, faction: String) -> String:
	return "%d / %d" % [sim.population(faction), Consts.POPULATION_CAP]


static func clock_text(tick: int) -> String:
	var s: int = tick / Consts.TICKS_PER_SECOND
	return "%02d:%02d" % [s / 60, s % 60]


## What a unit is doing, in words.
static func status_text(sim: Simulation, e: Entity) -> String:
	match e.order_type:
		"move":
			return "Moving"
		"harvest":
			var r: String = "food" if e.harvest_type == "farm" else e.harvest_type
			match e.phase:
				"gathering":
					return "Gathering %s  %d%%" % [r, e.timer * 100 / Consts.HARVEST_TICKS]
				"to_dropoff":
					return "Carrying %d %s home" % [e.carry, e.carry_type]
			return "Heading to %s" % r
		"build":
			return "Building" if e.phase == "building" else "Walking to the site"
		"attack":
			var t: Entity = sim.entity(e.order_target)
			return "Attacking " + (KIND_NAMES[t.kind].to_lower() if t != null else "")
	if e.carry > 0:
		return "Idle · carrying %d %s" % [e.carry, e.carry_type]
	return "Idle"


## Everything the details card shows about the inspected entity, as the
## player is allowed to see it: real data for own and visible things, the
## remembered snapshot for ghosts.
static func details(sim: Simulation, faction: String, id: int) -> Dictionary:
	var e: Entity = sim.entity(id)
	var mem: Dictionary = sim.fog.memory[faction]
	var seen: bool = e != null and (e.faction == faction or (
		sim.fog.is_visible(faction, e.unit_cell()) if e.is_unit() else sim.fog.any_visible(faction, e.cell, e.size)))
	if not seen:
		if not mem.has(id):
			return {}
		var g: Dictionary = mem[id]
		var max_hp: int = sim.stats[g.kind].health if sim.stats.has(g.kind) else 0
		return {"id": id, "kind": g.kind, "name": KIND_NAMES[g.kind], "faction": g.faction, "hp": g.hp,
			"max_hp": max_hp, "status": "Last seen", "ghost": true, "amount": g.amount}
	var d: Dictionary = {"id": id, "kind": e.kind, "name": KIND_NAMES[e.kind], "faction": e.faction,
		"hp": e.hp, "max_hp": sim.stats[e.kind].health if sim.stats.has(e.kind) else 0, "ghost": false,
		"amount": e.amount}
	if e.is_node():
		d.status = "%d left" % e.amount
	elif e.is_building():
		if not e.complete:
			d.status = "Under construction  %d%%" % (e.progress * 100 / sim.stats[e.kind].build_time)
		elif not e.queue.is_empty():
			var item: String = e.queue[0].type
			d.status = ("Researching %s" if Consts.UPGRADES.has(item) else "Training %s") % KIND_NAMES[item].to_lower()
		elif e.kind == "farm":
			d.status = "%d food left" % e.amount
		else:
			d.status = "Ready"
	else:
		d.status = status_text(sim, e) if e.faction == faction else "Enemy"
	return d
