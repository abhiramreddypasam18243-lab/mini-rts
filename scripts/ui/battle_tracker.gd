## Groups fighting into battles (decision D-57, presentation layer): hits
## and deaths within BATTLE_RADIUS of a battle's centre belong to it. A
## battle ends when nothing has happened in it for QUIET seconds; if at
## least MIN_DEATHS units died, it is summarised for the player. The
## battle camera follows the hottest battle (most hits in the last 3 s).
## Positions are world pixels, times seconds.
class_name BattleTracker
extends RefCounted

const BATTLE_RADIUS: float = 8.0 * 32.0
const QUIET: float = 4.0
const MIN_DEATHS: int = 3
const HOT_WINDOW: float = 3.0

## Each battle: {"centre": Vector2, "last": float, "hits": Array[float],
## "lost": {"player": int, "ai": int}}.
var battles: Array[Dictionary] = []


func _battle_at(p: Vector2, now: float) -> Dictionary:
	for b: Dictionary in battles:
		if (b.centre as Vector2).distance_to(p) <= BATTLE_RADIUS:
			return b
	var b: Dictionary = {"centre": p, "last": now, "hits": [], "lost": {"player": 0, "ai": 0}}
	battles.append(b)
	return b


func add_hit(p: Vector2, now: float) -> void:
	var b: Dictionary = _battle_at(p, now)
	# The centre drifts towards where the fighting is.
	b.centre = (b.centre as Vector2).lerp(p, 0.2)
	b.last = now
	(b.hits as Array).append(now)


func add_death(p: Vector2, faction: String, now: float) -> void:
	var b: Dictionary = _battle_at(p, now)
	b.last = now
	if b.lost.has(faction):
		b.lost[faction] += 1


## Ends quiet battles; returns the summaries of those worth reporting:
## {"centre", "player_lost", "ai_lost"}.
func update(now: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in range(battles.size() - 1, -1, -1):
		var b: Dictionary = battles[i]
		b.hits = (b.hits as Array).filter(func(t: float) -> bool: return now - t <= HOT_WINDOW)
		if now - float(b.last) < QUIET:
			continue
		battles.remove_at(i)
		if int(b.lost.player) + int(b.lost.ai) >= MIN_DEATHS:
			out.append({"centre": b.centre, "player_lost": b.lost.player, "ai_lost": b.lost.ai})
	return out


## The centre of the battle with the most hits in the last HOT_WINDOW
## seconds (at least `min_hits`), or null.
func hottest(now: float, min_hits: int = 4) -> Variant:
	var best: Variant = null
	var most: int = min_hits - 1
	for b: Dictionary in battles:
		var n: int = (b.hits as Array).filter(func(t: float) -> bool: return now - t <= HOT_WINDOW).size()
		if n > most:
			most = n
			best = b.centre
	return best


## The message for a finished battle, from the player's point of view.
static func summary_text(s: Dictionary) -> String:
	var won: bool = int(s.ai_lost) > int(s.player_lost)
	var lost: bool = int(s.player_lost) > int(s.ai_lost)
	var head: String = "Battle won" if won else ("Battle lost" if lost else "Battle even")
	return "%s: %d enemies killed, %d of yours lost" % [head, s.ai_lost, s.player_lost]
