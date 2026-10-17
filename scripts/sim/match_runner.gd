## Plays one whole match headless, as fast as the CPU allows (SPEC 6, 16).
## Each faction is driven by an AIController with the named policy, or
## issues no commands if no policy is given. Returns the result and the
## measurements the tests and the experiment need. Build step 9 adds the
## CSV runner on top of this.
class_name MatchRunner
extends RefCounted


## policies: faction -> policy name ("balanced", "aggressive", "economy_first").
## keep_replay: also return the match as replay text (SPEC 8, AC-04).
static func run(map: MapGrid, p_seed: int, policies: Dictionary, max_ticks: int, keep_replay: bool = false) -> Dictionary:
	var world: Simulation = Simulation.new(map, p_seed, {"max_ticks": max_ticks, "ai_configs": policies})
	var controllers: Dictionary = {}
	for f: String in Consts.FACTIONS:
		if policies.get(f, "") != "":
			controllers[f] = AIController.new(f, AIConfig.preset(policies[f]))
	var stats: Dictionary = {}
	for f: String in Consts.FACTIONS:
		stats[f] = {"first_barracks_tick": -1, "soldiers_trained": 0, "units_lost": 0}
	var first_attack: int = -1
	while world.match_result == "":
		for f: String in controllers:
			(controllers[f] as AIController).before_step(world)
		world.step()
		for ev: Dictionary in world.take_events():
			match ev.type:
				"completed":
					if stats[ev.faction].first_barracks_tick < 0:
						stats[ev.faction].first_barracks_tick = world.tick
				"trained":
					var u: Entity = world.entity(ev.entity_id)
					if u != null and u.is_soldier():
						stats[ev.faction].soldiers_trained += 1
				"attack":
					if first_attack < 0:
						first_attack = world.tick
				"destroyed":
					if ev.faction != "" and ev.kind in Entity.UNIT_KINDS:
						stats[ev.faction].units_lost += 1
	var out: Dictionary = {"seed": p_seed, "result": world.match_result, "ticks": world.tick,
		"first_attack_tick": first_attack, "hash": world.state_hash(), "commands": world.command_log.size()}
	if keep_replay:
		out.replay = Replay.to_jsonl(world.replay_header(), world.command_log)
	for f: String in Consts.FACTIONS:
		var s: Dictionary = stats[f]
		s.wood = world.bank.deposited[f].wood
		s.gold = world.bank.deposited[f].gold
		if controllers.has(f):
			var c: AIController = controllers[f]
			s.violations = c.violations
			s.multi_command_decisions = c.multi_command_decisions
			s.longest_quiet = c.longest_quiet
			s.stuck = c.ai.stuck_count
			s.fallbacks = c.ai.fallback_count
			s.history = c.ai.history
		out[f] = s
	return out
