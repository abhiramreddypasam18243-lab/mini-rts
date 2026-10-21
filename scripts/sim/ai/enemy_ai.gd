## The enemy AI: a finite-state machine (SPEC 7.1; AC-59 to AC-67).
##
## decide(observation) -> commands. The AI receives only an Observation (a
## copy of what its faction may know) and holds no reference to the game
## world, so it cannot read hidden information (the observation firewall,
## SPEC 7.2). It keeps a little memory of its own: its state, when it last
## saw a threat, the army size when an attack started, its scout.
##
## Each decision (every 10 ticks) first picks the state by this priority
## list, then acts (decision D-33 for the sticky states):
##   1. a visible enemy soldier within 8 cells of the HQ or 6 of another
##      own building (workers cannot attack, so they are no threat; D-34)
##                                                             -> DEFEND
##   2. in DEFEND: hold until 100 ticks without a threat, then back to the
##      state before DEFEND
##   3. in ATTACK: army below retreat_pct % of the army at the start of the
##      attack, or no enemy building known                     -> RECOVER
##      (otherwise ATTACK continues)
##   4. army >= army_threshold, an enemy building known, and in ECONOMY or
##      RECOVER                                                -> ATTACK
##      (otherwise RECOVER continues)
##   5. no barracks, workers >= build_worker_min, a barracks affordable
##                                                             -> BUILD
##      (BUILD ends when a barracks exists, or after 600 ticks)
##   6. otherwise                                              -> ECONOMY
##
## Underneath ECONOMY, RECOVER and ATTACK, once a barracks stands (D-51):
## farms when food runs short, one guard tower, a stable for cavalry, and
## Forging then Armour at a barracks while an army exists.
##
## Roles: workers gather and build; soldiers form the ARMY, except one SCOUT
## while no enemy building is known. Every command is recorded against the
## units it names, and a unit already named is skipped, so in one decision
## each unit receives at most one command (AC-63).
class_name EnemyAI
extends RefCounted

const ECONOMY: String = "ECONOMY"
const BUILD: String = "BUILD"
const DEFEND: String = "DEFEND"
const ATTACK: String = "ATTACK"
const RECOVER: String = "RECOVER"

const THREAT_HQ_SQ: int = 64
const THREAT_BUILDING_SQ: int = 36
const DEFEND_HOLD: int = 100
const BUILD_TIMEOUT: int = 600
const STUCK_TICKS: int = 200
## D-51: a guard tower is built from this tick on; workers per farm.
const TOWER_TICK: int = 1500
const FARMERS_PER_FARM: int = 2
## Army soldiers engage visible enemy units within 7 cells on their way.
const ENGAGE_SQ: int = 49
## Fog grid values (Fog.UNEXPLORED / EXPLORED / VISIBLE).
const UNEXPLORED: int = 0
const VISIBLE: int = 2

var config: AIConfig
var faction: String
var state: String = ECONOMY
var previous: String = ECONOMY
var last_threat_tick: int = -1000000
var attack_start_army: int = 0
var build_since: int = 0
var build_blocked_until: int = 0
var scout_id: int = 0
var scout_index: int = 0
var last_issue_tick: int = 0
var stuck_count: int = 0
var fallback_count: int = 0
## Every state change and stuck event: {"tick", "from", "to", "reason"} (AC-67).
var history: Array[Dictionary] = []

# Facts about the current observation, rebuilt by _read() each decision.
var _obs: Observation
var _hq: Dictionary
var _workers: Array[Dictionary] = []
var _soldiers: Array[Dictionary] = []
var _army: Array[Dictionary] = []
var _barracks: Array[Dictionary] = []
## D-51: own farms, towers and stables (finished or not).
var _farms: Array[Dictionary] = []
var _towers: Array[Dictionary] = []
var _stables: Array[Dictionary] = []
var _threats: Array[Dictionary] = []
var _target: Dictionary = {}
var _node_kind: Dictionary = {}


func _init(p_faction: String, p_config: AIConfig) -> void:
	faction = p_faction
	config = p_config


# --- reading the observation --------------------------------------------------

func _read(obs: Observation) -> void:
	_obs = obs
	_hq = {}
	_workers = []
	_soldiers = []
	_barracks = []
	_farms = []
	_towers = []
	_stables = []
	for b: Dictionary in obs.own_buildings:
		if b.kind == "hq" and _hq.is_empty():
			_hq = b
		elif b.kind == "barracks":
			_barracks.append(b)
		elif b.kind == "farm":
			_farms.append(b)
		elif b.kind == "tower":
			_towers.append(b)
		elif b.kind == "stable":
			_stables.append(b)
	for u: Dictionary in obs.own_units:
		if u.kind == "worker":
			_workers.append(u)
		else:
			_soldiers.append(u)
	_node_kind = {}
	for n: Dictionary in obs.nodes:
		_node_kind[n.id] = n.kind
	# The target: the enemy HQ if known, else the known enemy building
	# nearest to our HQ (ties: lowest id).
	_target = {}
	var best: int = -1
	for g: Dictionary in obs.ghosts:
		var d: int = _dist_sq_rect(_hq_center(), g.cell, g.size)
		if g.kind == "hq":
			d -= 1000000
		if best == -1 or d < best:
			best = d
			_target = g
	# Threats: visible enemy soldiers near our buildings (D-34).
	_threats = []
	for e: Dictionary in obs.enemy_units:
		if e.kind == "worker":
			continue
		for b: Dictionary in obs.own_buildings:
			var limit: int = THREAT_HQ_SQ if b.kind == "hq" else THREAT_BUILDING_SQ
			if _dist_sq_rect(e.cell, b.cell, b.size) <= limit:
				_threats.append(e)
				break
	# The scout exists only while no enemy building is known, and not during
	# peace time (D-56): a scout would fight whatever it meets at the enemy base.
	if not _target.is_empty() or _soldiers.is_empty() or obs.tick < config.peace_ticks:
		scout_id = 0
	elif _find(_soldiers, scout_id).is_empty():
		scout_id = _soldiers[0].id
		scout_index = 0
	_army = _soldiers.filter(func(u: Dictionary) -> bool: return u.id != scout_id)


# --- the transition function (AC-62) --------------------------------------------

## Applies the priority list to `obs` and returns the new state.
func next_state(obs: Observation) -> String:
	_read(obs)
	var tick: int = obs.tick
	if not _threats.is_empty():
		last_threat_tick = tick
		if state != DEFEND:
			previous = state
			_change(DEFEND, tick, "%d enemy soldier(s) near our buildings" % _threats.size())
		return state
	if state == DEFEND:
		if tick - last_threat_tick >= DEFEND_HOLD:
			_change(previous, tick, "no threat for %d ticks" % DEFEND_HOLD)
		return state
	var army: int = _army.size()
	if state == ATTACK:
		if army * 100 < config.retreat_pct * attack_start_army:
			_change(RECOVER, tick, "army %d below %d%% of %d" % [army, config.retreat_pct, attack_start_army])
		elif _target.is_empty():
			_change(RECOVER, tick, "no enemy building known")
		return state
	# No attack during peace time (D-56; 0 outside games from the menu).
	if army >= config.army_threshold and not _target.is_empty() and (state == ECONOMY or state == RECOVER) \
			and tick >= config.peace_ticks:
		attack_start_army = army
		_change(ATTACK, tick, "army %d >= %d and target %s known" % [army, config.army_threshold, _target.kind])
		return state
	if state == RECOVER:
		return state
	if state == BUILD:
		if not _barracks.is_empty():
			_change(ECONOMY, tick, "barracks placed")
		elif tick - build_since >= BUILD_TIMEOUT:
			build_blocked_until = tick + BUILD_TIMEOUT
			_change(ECONOMY, tick, "no barracks after %d ticks" % BUILD_TIMEOUT)
		return state
	if _barracks.is_empty() and _workers.size() >= config.build_worker_min \
			and _affordable(obs.resources, "barracks") and tick >= build_blocked_until:
		build_since = tick
		_change(BUILD, tick, "%d workers and %d wood, %d gold" % [_workers.size(), obs.resources.wood, obs.resources.gold])
		return state
	if state != ECONOMY:
		_change(ECONOMY, tick, "nothing else applies")
	return state


func _change(to: String, tick: int, reason: String) -> void:
	if to == state:
		return
	history.append({"tick": tick, "from": state, "to": to, "reason": reason})
	state = to


# --- deciding -----------------------------------------------------------------

## One decision: the state, then commands for that state, with the economy
## and production running underneath every state.
func decide(obs: Observation) -> Array[Dictionary]:
	next_state(obs)
	var out: Array[Dictionary] = []
	var used: Dictionary = {}
	var res: Dictionary = obs.resources.duplicate()
	match state:
		BUILD:
			_do_build(out, used, res)
		DEFEND:
			_do_defend(out, used)
		ATTACK:
			_do_attack(out, used)
	if state != DEFEND and state != BUILD:
		_do_expand(out, used, res)
	_do_research(out, res)
	if state != DEFEND and state != ATTACK:
		_do_rally(out, used)
	_do_scout(out, used)
	_do_gather(out, used)
	_do_production(out, res)
	_check_stuck(obs, out, used)
	if not out.is_empty():
		last_issue_tick = obs.tick
	return out


## The unit ids a command names (not buildings).
static func unit_ids_of(cmd: Dictionary) -> Array[int]:
	var out: Array[int] = []
	if cmd.args.has("unit_ids"):
		for id: Variant in cmd.args.unit_ids:
			out.append(int(id))
	elif cmd.args.has("worker_id"):
		out.append(int(cmd.args.worker_id))
	return out


func _issue(out: Array[Dictionary], used: Dictionary, cmd: Dictionary) -> void:
	for id: int in unit_ids_of(cmd):
		used[id] = true
	out.append(cmd)


func _free(used: Dictionary, list: Array[Dictionary]) -> Array[Dictionary]:
	return list.filter(func(u: Dictionary) -> bool: return not used.has(u.id))


func _do_build(out: Array[Dictionary], used: Dictionary, res: Dictionary) -> void:
	if not _barracks.is_empty() or _hq.is_empty():
		return
	var free: Array[Dictionary] = _free(used, _workers)
	if free.is_empty():
		return
	var site: Variant = _find_site()
	if site == null:
		return
	# Prefer an idle worker; otherwise the one nearest the site.
	var builder: Dictionary = free[0]
	var best: int = -1
	for w: Dictionary in free:
		var d: int = _dist_sq(w.cell, site) - (100000 if w.order_type == "idle" else 0)
		if best == -1 or d < best:
			best = d
			builder = w
	_spend(res, "barracks")
	_issue(out, used, Commands.build(faction, builder.id, "barracks", site))


## D-51: at most one new building per decision, and only one of each kind
## under construction at a time: a farm when the farms with food (or being
## built) are fewer than one per 5 workers, one guard tower from tick 1500,
## then a stable once a farm exists. All wait for a finished barracks.
func _do_expand(out: Array[Dictionary], used: Dictionary, res: Dictionary) -> void:
	if _hq.is_empty() or not _barracks.any(func(b: Dictionary) -> bool: return b.complete):
		return
	var kind: String = ""
	var live_farms: int = _farms.filter(func(f: Dictionary) -> bool: return not f.complete or f.amount > 0).size()
	if live_farms < _workers.size() / 5 and _farms.all(func(f: Dictionary) -> bool: return f.complete):
		kind = "farm"
	elif _towers.size() < config.max_towers and _towers.all(func(t: Dictionary) -> bool: return t.complete) and _obs.tick >= TOWER_TICK:
		kind = "tower"
	elif _stables.is_empty() and not _farms.is_empty():
		kind = "stable"
	if kind == "" or not _affordable(res, kind):
		return
	var free: Array[Dictionary] = _free(used, _workers)
	if free.is_empty():
		return
	var site: Variant = _find_site(kind)
	if site == null:
		return
	var builder: Dictionary = _nearest(site, free)
	_spend(res, kind)
	_issue(out, used, Commands.build(faction, builder.id, kind, site))


## D-51: Forging, then Armour, at a finished barracks with a free queue slot,
## once the army has 3 soldiers.
func _do_research(out: Array[Dictionary], res: Dictionary) -> void:
	if not config.research or _soldiers.size() < config.research_army:
		return
	for up: String in ["forging", "armour"]:
		if _obs.upgrades.has(up) or _researching(up):
			continue
		if not _affordable_cost(res, _upgrade_cost(up)):
			return
		for b: Dictionary in _barracks:
			if b.complete and b.queue.size() < 2:
				_spend_cost(res, _upgrade_cost(up))
				out.append(Commands.research(faction, b.id, up))
				return
		return


func _researching(up: String) -> bool:
	for b: Dictionary in _barracks:
		if _queued(b, up) > 0:
			return true
	return false


func _upgrade_cost(up: String) -> Dictionary:
	var u: Dictionary = Consts.UPGRADES[up]
	return {"wood": u.wood, "gold": u.gold, "food": u.food}


## The valid site nearest the HQ (see below for the order). A site must lie on walkable, explored
## ground, keep one free cell from our buildings and from resource nodes,
## and be clear of every unit the AI can see.
func _find_site(kind: String = "barracks") -> Variant:
	var size: Vector2i = _obs.stats[kind].footprint
	var blocked: Dictionary = {}
	for b: Dictionary in _obs.own_buildings:
		for y: int in range(b.cell.y - 1, b.cell.y + b.size.y + 1):
			for x: int in range(b.cell.x - 1, b.cell.x + b.size.x + 1):
				blocked[Vector2i(x, y)] = true
	for n: Dictionary in _obs.nodes:
		for y: int in range(n.cell.y - 1, n.cell.y + 2):
			for x: int in range(n.cell.x - 1, n.cell.x + 2):
				blocked[Vector2i(x, y)] = true
	for g: Dictionary in _obs.ghosts:
		for y: int in range(g.cell.y, g.cell.y + g.size.y):
			for x: int in range(g.cell.x, g.cell.x + g.size.x):
				blocked[Vector2i(x, y)] = true
	for u: Dictionary in _obs.own_units + _obs.enemy_units:
		blocked[u.cell] = true
	# The site whose centre is nearest the HQ (Chebyshev, in half cells),
	# ties broken row-major in the AI's own frame: flipped for a start in the
	# bottom-right half, so both start corners choose mirror-image sites on
	# the point-symmetric maps (D-51; plain row-major order made the start
	# positions unequal).
	var f: int = _flip()
	var hc2: Vector2i = _hq.cell * 2 + _hq.size
	var best: Variant = null
	var best_key: Vector3i = Vector3i.ZERO
	for y: int in range(_hq.cell.y - 13, _hq.cell.y + _hq.size.y + 13):
		for x: int in range(_hq.cell.x - 13, _hq.cell.x + _hq.size.x + 13):
			var a: Vector2i = Vector2i(x, y)
			var k: Vector2i = (a * 2 + size - hc2) * f
			var key: Vector3i = Vector3i(maxi(absi(k.x), absi(k.y)), k.y, k.x)
			if key.x > 26 or (best != null and not _less(key, best_key)):
				continue
			if _site_ok(a, size, blocked):
				best = a
				best_key = key
	return best


static func _less(a: Vector3i, b: Vector3i) -> bool:
	return a.x < b.x or a.x == b.x and (a.y < b.y or a.y == b.y and a.z < b.z)


## +1 for a start in the top-left half of the map, -1 in the bottom-right
## half: scans run in this AI's own frame, so mirrored starts act alike.
func _flip() -> int:
	if _hq.is_empty():
		return 1
	var hc2: Vector2i = _hq.cell * 2 + _hq.size
	if hc2.x != _obs.width:
		return 1 if hc2.x < _obs.width else -1
	return 1 if hc2.y < _obs.height else -1


func _site_ok(anchor: Vector2i, size: Vector2i, blocked: Dictionary) -> bool:
	for y: int in range(anchor.y, anchor.y + size.y):
		for x: int in range(anchor.x, anchor.x + size.x):
			var p: Vector2i = Vector2i(x, y)
			if not _walkable(p) or blocked.has(p) or _obs.fog[y * _obs.width + x] == UNEXPLORED:
				return false
	return true


## All soldiers attack the threat nearest to each of them.
func _do_defend(out: Array[Dictionary], used: Dictionary) -> void:
	var groups: Dictionary = {}
	for s: Dictionary in _free(used, _soldiers):
		var t: Dictionary = _pick_enemy(s, _threats)
		used[s.id] = true  # a defender is not also sent scouting or rallying
		if t.is_empty() or (s.order_type == "attack" and s.order_target == t.id):
			continue
		if not groups.has(t.id):
			groups[t.id] = []
		groups[t.id].append(s.id)
	for tid: int in groups:
		_issue(out, used, Commands.attack(faction, groups[tid], tid))


## Army soldiers attack visible enemies they meet, attack the target building
## when they can see it, and otherwise march to it.
func _do_attack(out: Array[Dictionary], used: Dictionary) -> void:
	if _target.is_empty():
		return
	var target_seen: bool = _any_visible(_target.cell, _target.size)
	var march: Array[int] = []
	var hit_target: Array[int] = []
	var engage: Dictionary = {}
	_do_tactics(out, used)
	for s: Dictionary in _free(used, _army):
		var near: Dictionary = _pick_enemy(s, _obs.enemy_units)
		if not near.is_empty() and _dist_sq(s.cell, near.cell) <= ENGAGE_SQ:
			if not (s.order_type == "attack" and s.order_target == near.id):
				if not engage.has(near.id):
					engage[near.id] = []
				engage[near.id].append(s.id)
			used[s.id] = true
		elif target_seen:
			if not (s.order_type == "attack" and s.order_target == _target.id):
				hit_target.append(s.id)
			used[s.id] = true
		elif s.order_type != "move":
			march.append(s.id)
	for tid: int in engage:
		_issue(out, used, Commands.attack(faction, engage[tid], tid))
	if not hit_target.is_empty():
		_issue(out, used, Commands.attack(faction, hit_target, _target.id))
	if not march.is_empty():
		var goal: Variant = _approach_cell(_target)
		if goal != null:
			_issue(out, used, Commands.move(faction, march, goal))


## Which enemy a soldier fights: the nearest; on Hard (D-52) the weakest
## one it can already reach (within its attack range plus one cell; lowest
## health, then lowest id), so wounded enemies are finished first, and
## cavalry take an enemy worker in reach first.
func _pick_enemy(s: Dictionary, enemies: Array[Dictionary]) -> Dictionary:
	if config.raid and s.kind == "cavalry":
		var workers: Array[Dictionary] = enemies.filter(func(e: Dictionary) -> bool: return e.kind == "worker")
		var w: Dictionary = _nearest(s.cell, workers)
		if not w.is_empty() and _dist_sq(s.cell, w.cell) <= ENGAGE_SQ:
			return w
	if not config.focus_fire:
		return _nearest(s.cell, enemies)
	var best: Dictionary = {}
	var reach: int = int(_obs.stats[s.kind].range) / 1000 + 1
	for e: Dictionary in enemies:
		if _dist_sq(s.cell, e.cell) > reach * reach:
			continue
		if best.is_empty() or e.hp < best.hp or e.hp == best.hp and e.id < best.id:
			best = e
	return best if not best.is_empty() else _nearest(s.cell, enemies)


## Hard (D-52): soldiers below wounded_pct % of their health with an enemy
## in reach walk back to the rally cell.
func _do_tactics(out: Array[Dictionary], used: Dictionary) -> void:
	if config.wounded_pct > 0:
		var rally: Variant = _rally_cell()
		var back: Array[int] = []
		for s: Dictionary in _free(used, _army):
			var hurt: bool = s.hp * 100 < config.wounded_pct * int(_obs.stats[s.kind].health)
			var near: Dictionary = _nearest(s.cell, _obs.enemy_units)
			if hurt and rally != null and not near.is_empty() and _dist_sq(s.cell, near.cell) <= ENGAGE_SQ:
				used[s.id] = true
				if s.order_type != "move":
					back.append(s.id)
		if not back.is_empty():
			_issue(out, used, Commands.move(faction, back, rally))


## In ECONOMY, BUILD and RECOVER, idle army soldiers gather at a rally cell
## next to the HQ, on the side facing the map centre.
func _do_rally(out: Array[Dictionary], used: Dictionary) -> void:
	if _hq.is_empty():
		return
	var rally: Variant = _rally_cell()
	if rally == null:
		return
	var go: Array[int] = []
	for s: Dictionary in _free(used, _army):
		if _dist_sq(s.cell, rally) > 4 and (s.order_type == "idle" or state == RECOVER and s.order_type != "move"):
			go.append(s.id)
	if not go.is_empty():
		_issue(out, used, Commands.move(faction, go, rally))


## The scout visits the possible enemy start positions in order, stopping
## 4 cells short (close enough to see an HQ there), until a building is seen.
func _do_scout(out: Array[Dictionary], used: Dictionary) -> void:
	if scout_id == 0 or used.has(scout_id):
		return
	var s: Dictionary = _find(_soldiers, scout_id)
	var goals: Array[Vector2i] = _scout_goals()
	if goals.is_empty():
		return
	scout_index = scout_index % goals.size()
	var goal: Vector2i = goals[scout_index]
	if _dist_sq(s.cell, goal) <= 4:
		scout_index = (scout_index + 1) % goals.size()
		goal = goals[scout_index]
	elif s.order_type == "move":
		return
	_issue(out, used, Commands.move(faction, [scout_id], goal))


func _scout_goals() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var mid: Vector2i = Vector2i(_obs.width / 2, _obs.height / 2)
	for p: Vector2i in _obs.possible_starts:
		var centre: Vector2i = p + Vector2i(1, 1)
		if not _hq.is_empty() and _dist_sq(centre, _hq_center()) <= 9:
			continue  # our own start
		var step: Vector2i = Vector2i(signi(mid.x - centre.x), signi(mid.y - centre.y))
		var c: Variant = _walkable_near(centre + step * 4)
		if c != null:
			out.append(c)
	return out


## Idle workers gather from the nearest remembered node, keeping roughly
## 2 workers on wood for each on gold.
func _do_gather(out: Array[Dictionary], used: Dictionary) -> void:
	if _obs.nodes.is_empty() and _farms.is_empty():
		return
	var on: Dictionary = {"wood": 0, "gold": 0, "food": 0}
	var farms: Array[Dictionary] = _farms.filter(func(f: Dictionary) -> bool: return f.complete and f.amount > 0)
	var farm_ids: Dictionary = {}
	for f: Dictionary in farms:
		farm_ids[f.id] = true
	for w: Dictionary in _workers:
		if w.order_type == "harvest" and _node_kind.has(w.order_target):
			on[_node_kind[w.order_target]] += 1
		elif w.order_type == "harvest" and farm_ids.has(w.order_target):
			on.food += 1
	for w: Dictionary in _free(used, _workers):
		if w.order_type != "idle":
			continue
		# D-51: up to 2 workers on each farm with food.
		if on.food < FARMERS_PER_FARM * farms.size():
			on.food += 1
			_issue(out, used, Commands.harvest(faction, [w.id], _nearest(w.cell, farms).id))
			continue
		var want: String = "gold" if on.gold * 2 < on.wood else "wood"
		var n: Dictionary = _nearest_node(w.cell, want)
		if n.is_empty():
			n = _nearest_node(w.cell, "gold" if want == "wood" else "wood")
		if n.is_empty():
			continue
		on[n.kind] += 1
		_issue(out, used, Commands.harvest(faction, [w.id], n.id))


## Workers up to worker_target at the HQ; soldiers at every finished barracks
## following unit_mix. At most 2 items queued per building, so resources are
## not locked up early. `res` is a local copy, spent as orders are made.
func _do_production(out: Array[Dictionary], res: Dictionary) -> void:
	if not _hq.is_empty() and _hq.complete:
		var workers: int = _workers.size() + _queued(_hq, "worker")
		if workers < config.worker_target and _hq.queue.size() < config.max_queue and _affordable(res, "worker"):
			_spend(res, "worker")
			out.append(Commands.train(faction, _hq.id, "worker"))
	var melee: int = 0
	var ranged: int = 0
	for s: Dictionary in _soldiers:
		if s.kind == "melee":
			melee += 1
		elif s.kind == "ranged":
			ranged += 1
	for b: Dictionary in _barracks:
		melee += _queued(b, "melee")
		ranged += _queued(b, "ranged")
	for b: Dictionary in _barracks:
		if not b.complete or b.queue.size() >= config.max_queue:
			continue
		var kind: String = "melee" if melee * config.mix_ranged <= ranged * config.mix_melee else "ranged"
		if not _affordable(res, kind):
			continue
		_spend(res, kind)
		out.append(Commands.train(faction, b.id, kind))
		if kind == "melee":
			melee += 1
		else:
			ranged += 1
	# D-51: cavalry at every finished stable.
	for b: Dictionary in _stables:
		if b.complete and b.queue.size() < config.max_queue and _affordable(res, "cavalry"):
			_spend(res, "cavalry")
			out.append(Commands.train(faction, b.id, "cavalry"))


## The fallback (SPEC 7.1): idle units or an affordable action, but nothing
## issued for 200 ticks -> log "stuck", re-enter ECONOMY and send one idle
## unit to explore, so the AI does something.
func _check_stuck(obs: Observation, out: Array[Dictionary], used: Dictionary) -> void:
	if not out.is_empty() or obs.tick - last_issue_tick < STUCK_TICKS:
		return
	var idle: Array[Dictionary] = _free(used, obs.own_units).filter(func(u: Dictionary) -> bool: return u.order_type == "idle")
	var can_buy: bool = not _hq.is_empty() and _hq.queue.size() < 2 and _affordable(obs.resources, "worker")
	if idle.is_empty() and not can_buy:
		return
	stuck_count += 1
	history.append({"tick": obs.tick, "from": state, "to": ECONOMY,
		"reason": "stuck: %d idle units, %d wood, %d gold, state %s" % [idle.size(), obs.resources.wood, obs.resources.gold, state]})
	state = ECONOMY
	# During peace time (D-56) nobody is sent out exploring.
	var goal: Variant = _explore_cell() if obs.tick >= config.peace_ticks else null
	if not idle.is_empty() and goal != null:
		_issue(out, used, Commands.move(faction, [idle[0].id], goal))
	elif can_buy:
		out.append(Commands.train(faction, _hq.id, "worker"))
	if not out.is_empty():
		fallback_count += 1


## Somewhere worth exploring: the next scouting goal, else the first
## unexplored walkable cell found from the map centre outwards.
func _explore_cell() -> Variant:
	var goals: Array[Vector2i] = _scout_goals()
	if not goals.is_empty():
		scout_index = (scout_index + 1) % goals.size()
		return goals[scout_index]
	var mid: Vector2i = Vector2i(_obs.width / 2, _obs.height / 2)
	for r: int in maxi(_obs.width, _obs.height):
		for y: int in range(mid.y - r, mid.y + r + 1):
			for x: int in range(mid.x - r, mid.x + r + 1):
				if _walkable(Vector2i(x, y)) and _obs.fog[y * _obs.width + x] == UNEXPLORED:
					return Vector2i(x, y)
	return null


# --- small helpers ------------------------------------------------------------

func _cost(kind: String) -> Dictionary:
	return {"wood": _obs.stats[kind].wood, "gold": _obs.stats[kind].gold, "food": _obs.stats[kind].get("food", 0)}


func _affordable(res: Dictionary, kind: String) -> bool:
	return _affordable_cost(res, _cost(kind))


func _spend(res: Dictionary, kind: String) -> void:
	_spend_cost(res, _cost(kind))


func _affordable_cost(res: Dictionary, c: Dictionary) -> bool:
	for r: String in c:
		if int(res.get(r, 0)) < int(c[r]):
			return false
	return true


func _spend_cost(res: Dictionary, c: Dictionary) -> void:
	for r: String in c:
		res[r] = int(res.get(r, 0)) - int(c[r])


func _queued(b: Dictionary, kind: String) -> int:
	var n: int = 0
	for item: Dictionary in b.queue:
		if item.type == kind:
			n += 1
	return n


func _find(list: Array[Dictionary], id: int) -> Dictionary:
	for u: Dictionary in list:
		if u.id == id:
			return u
	return {}


func _hq_center() -> Vector2i:
	return _hq.cell + _hq.size / 2 if not _hq.is_empty() else Vector2i(_obs.width / 2, _obs.height / 2)


static func _dist_sq(a: Vector2i, b: Vector2i) -> int:
	var d: Vector2i = a - b
	return d.x * d.x + d.y * d.y


## Squared distance in cells from `c` to the nearest cell of a footprint.
static func _dist_sq_rect(c: Vector2i, anchor: Vector2i, size: Vector2i) -> int:
	var dx: int = maxi(maxi(anchor.x - c.x, c.x - (anchor.x + size.x - 1)), 0)
	var dy: int = maxi(maxi(anchor.y - c.y, c.y - (anchor.y + size.y - 1)), 0)
	return dx * dx + dy * dy


func _nearest(c: Vector2i, list: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = {}
	var best_d: int = -1
	for u: Dictionary in list:
		var d: int = _dist_sq(c, u.cell)
		if best_d == -1 or d < best_d:
			best = u
			best_d = d
	return best


func _nearest_node(c: Vector2i, kind: String) -> Dictionary:
	var best: Dictionary = {}
	var best_d: int = -1
	for n: Dictionary in _obs.nodes:
		if n.kind != kind or n.amount <= 0:
			continue
		var d: int = _dist_sq(c, n.cell)
		if best_d == -1 or d < best_d:
			best = n
			best_d = d
	return best


func _walkable(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < _obs.width and p.y < _obs.height and _obs.terrain[p.y * _obs.width + p.x] == 0


func _any_visible(anchor: Vector2i, size: Vector2i) -> bool:
	for y: int in range(anchor.y, anchor.y + size.y):
		for x: int in range(anchor.x, anchor.x + size.x):
			if x >= 0 and y >= 0 and x < _obs.width and y < _obs.height and _obs.fog[y * _obs.width + x] == VISIBLE:
				return true
	return false


## The walkable terrain cell nearest to `c` that is not inside a known building
## or node (ties: row-major order).
func _walkable_near(c: Vector2i) -> Variant:
	var taken: Dictionary = {}
	for b: Dictionary in _obs.own_buildings + _obs.ghosts:
		for y: int in range(b.cell.y, b.cell.y + b.size.y):
			for x: int in range(b.cell.x, b.cell.x + b.size.x):
				taken[Vector2i(x, y)] = true
	for n: Dictionary in _obs.nodes:
		taken[n.cell] = true
	var f: int = _flip()
	for r: int in 8:
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				var p: Vector2i = c + Vector2i(dx, dy) * f
				if maxi(absi(dx), absi(dy)) == r and _walkable(p) and not taken.has(p):
					return p
	return null


func _rally_cell() -> Variant:
	var mid: Vector2i = Vector2i(_obs.width / 2, _obs.height / 2)
	var centre: Vector2i = _hq_center()
	var step: Vector2i = Vector2i(signi(mid.x - centre.x), signi(mid.y - centre.y))
	return _walkable_near(centre + step * 4)


## A free cell beside the target building, on the side nearest our HQ.
func _approach_cell(t: Dictionary) -> Variant:
	var toward: Vector2i = _hq_center()
	var near: Vector2i = Vector2i(clampi(toward.x, t.cell.x - 1, t.cell.x + t.size.x), clampi(toward.y, t.cell.y - 1, t.cell.y + t.size.y))
	return _walkable_near(near)
