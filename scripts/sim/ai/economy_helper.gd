## The auto-economy supervisor (decision D-55): runs the player's economy
## while the player commands the army. It reuses the enemy AI's gathering
## and building code, and like the enemy AI it only ever sees an
## Observation and its commands pass through the same firewall.
##
## Each decision it may:
##   - send idle workers to gather (2 per farm with food, then wood and gold
##     about 2 : 1), exactly as the enemy AI does;
##   - train a worker at the HQ while there are fewer than WORKER_TARGET
##     (at most 2 queued);
##   - build a farm when food is below LOW_FOOD and no farm has food or is
##     being built.
## It never commands a soldier, never trains soldiers and never builds
## anything but farms, so the army stays entirely the player's.
class_name EconomyHelper
extends EnemyAI

const WORKER_TARGET: int = 10
const LOW_FOOD: int = 60


func _init(p_faction: String) -> void:
	super(p_faction, AIConfig.preset("balanced"))


func decide(obs: Observation) -> Array[Dictionary]:
	_read(obs)
	var out: Array[Dictionary] = []
	var used: Dictionary = {}
	var res: Dictionary = obs.resources.duplicate()
	_do_farm(out, used, res)
	_do_gather(out, used)
	_do_workers(out, res)
	return out


func _do_farm(out: Array[Dictionary], used: Dictionary, res: Dictionary) -> void:
	if _hq.is_empty() or int(res.get("food", 0)) >= LOW_FOOD or not _affordable(res, "farm"):
		return
	if _farms.any(func(f: Dictionary) -> bool: return not f.complete or f.amount > 0):
		return
	var free: Array[Dictionary] = _free(used, _workers)
	if free.is_empty():
		return
	var site: Variant = _find_site("farm")
	if site == null:
		return
	_spend(res, "farm")
	_issue(out, used, Commands.build(faction, _nearest(site, free).id, "farm", site))


func _do_workers(out: Array[Dictionary], res: Dictionary) -> void:
	if _hq.is_empty() or not _hq.complete or _hq.queue.size() >= 2:
		return
	if _workers.size() + _queued(_hq, "worker") >= WORKER_TARGET or not _affordable(res, "worker"):
		return
	_spend(res, "worker")
	out.append(Commands.train(faction, _hq.id, "worker"))
