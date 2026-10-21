## Parameters of the AI state machine (SPEC 7.1). The three policies are the
## same machine with different numbers. Integers only: the retreat fraction
## is a percentage (decision D-23), the unit mix is melee : ranged.
class_name AIConfig
extends RefCounted

var policy: String = "balanced"
var worker_target: int = 6
var build_worker_min: int = 5
var army_threshold: int = 6
var retreat_pct: int = 40
var mix_melee: int = 2
var mix_ranged: int = 1
## Difficulty (D-52): "easy", "normal" or "hard". Normal is the policy as
## it is; the others change how it plays, never what it can see.
var difficulty: String = "normal"
## The AI decides on every this-many-th decision tick (Easy: every 3rd).
var decide_every: int = 1
## Guard towers it builds, and whether it researches upgrades.
var max_towers: int = 1
var research: bool = true
## Soldiers needed before it researches.
var research_army: int = 3
## Hard tactics: focus fire on the weakest enemy in reach, pull back
## soldiers below wounded_pct % health, cavalry take enemy workers in reach first.
var focus_fire: bool = false
var wounded_pct: int = 0
var raid: bool = false
## Production: at most this many items queued per building (Easy: 1).
var max_queue: int = 2
## Peace time (D-56): the AI may not start an attack before this tick.
## 0 for the presets (the experiment and tests); games started from the
## menu use PEACE for their difficulty.
var peace_ticks: int = 0

## Peace time per difficulty in games played from the menu (D-56):
## 6, 3 and 1.5 minutes at 20 ticks per second.
const PEACE: Dictionary = {"easy": 7200, "normal": 3600, "hard": 1800}

const PRESETS: Dictionary = {
	"balanced": [6, 5, 6, 40, 2, 1],
	"aggressive": [4, 3, 3, 25, 3, 1],
	"economy_first": [10, 7, 10, 50, 1, 1],
}


const DIFFICULTIES: Array[String] = ["easy", "normal", "hard"]


## The opponent of a game started from the menu: the preset plus the
## difficulty's peace time (D-56).
static func for_game(spec: String) -> AIConfig:
	var c: AIConfig = preset(spec)
	c.peace_ticks = PEACE[c.difficulty]
	return c


## A policy, optionally with a difficulty after a colon ("balanced:hard").
static func preset(spec: String) -> AIConfig:
	var name: String = spec.get_slice(":", 0)
	var level: String = spec.get_slice(":", 1) if spec.contains(":") else "normal"
	assert(PRESETS.has(name), "unknown AI policy '%s'" % name)
	assert(level in DIFFICULTIES, "unknown difficulty '%s'" % level)
	var p: Array = PRESETS[name]
	var c: AIConfig = AIConfig.new()
	c.policy = name
	c.worker_target = p[0]
	c.build_worker_min = p[1]
	c.army_threshold = p[2]
	c.retreat_pct = p[3]
	c.mix_melee = p[4]
	c.mix_ranged = p[5]
	c.difficulty = level
	match level:
		# Tuned by playing each change against Normal (D-52): Easy reacts
		# slowly, keeps a small economy and attacks with a small army;
		# Hard fights better and attacks with 2 more soldiers.
		"easy":
			c.decide_every = 3
			c.worker_target = mini(c.worker_target, 4)
			c.army_threshold = maxi(c.army_threshold - 2, 2)
			c.max_towers = 0
			c.research = false
			c.max_queue = 1
		"hard":
			c.max_towers = 2
			c.focus_fire = true
			c.wounded_pct = 30
			c.raid = true
			c.army_threshold += 2
	return c
