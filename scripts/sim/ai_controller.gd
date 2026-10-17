## Connects one EnemyAI to the simulation (SPEC 7.2). This is the only code
## that touches both: every 10 ticks it builds the faction's Observation,
## asks the AI to decide, and submits the commands through the firewall,
## which rejects any command naming an entity the observation did not contain.
## It also records the AI's behaviour for AC-61, AC-63 and AC-64.
class_name AIController
extends RefCounted

var faction: String
var ai: EnemyAI
## Commands that named an entity outside the observation (AC-61 requires 0).
var violations: int = 0
## Decisions in which some unit was named by two commands (AC-63 requires 0).
var multi_command_decisions: int = 0
## Longest stretch, in ticks, with idle units or an affordable purchase but
## no command issued (AC-64 requires at most 200).
var longest_quiet: int = 0
var decisions: int = 0
var commands: int = 0
var _last_issue: int = 0


func _init(p_faction: String, config: AIConfig) -> void:
	faction = p_faction
	ai = EnemyAI.new(p_faction, config)


## Call before every sim.step(). Returns the commands issued (empty when
## this tick is not a decision tick).
func before_step(world: Simulation) -> Array[Dictionary]:
	var issued: Array[Dictionary] = []
	if world.match_result != "" or world.tick % Consts.AI_DECISION_INTERVAL != 0:
		return issued
	var obs: Observation = world.observation(faction)
	issued = ai.decide(obs)
	decisions += 1
	var named: Dictionary = {}
	var twice: bool = false
	for cmd: Dictionary in issued:
		for id: int in EnemyAI.unit_ids_of(cmd):
			twice = twice or named.has(id)
			named[id] = true
	if twice:
		multi_command_decisions += 1
	var known: Dictionary = obs.known_ids()
	for cmd: Dictionary in issued:
		if world.submit_observed(cmd, known) == "firewall":
			violations += 1
	commands += issued.size()
	# Quiet-stretch measurement (AC-64).
	if not issued.is_empty():
		_last_issue = world.tick
	elif _has_work(obs):
		longest_quiet = maxi(longest_quiet, world.tick - _last_issue)
	return issued


## Idle units, or a worker the HQ could train now.
func _has_work(obs: Observation) -> bool:
	for u: Dictionary in obs.own_units:
		if u.order_type == "idle":
			return true
	for b: Dictionary in obs.own_buildings:
		if b.kind == "hq" and b.queue.size() < 2 \
				and obs.resources.wood >= obs.stats.worker.wood and obs.resources.gold >= obs.stats.worker.gold:
			return true
	return false
