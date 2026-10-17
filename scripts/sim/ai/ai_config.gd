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

const PRESETS: Dictionary = {
	"balanced": [6, 5, 6, 40, 2, 1],
	"aggressive": [4, 3, 3, 25, 3, 1],
	"economy_first": [10, 7, 10, 50, 1, 1],
}


static func preset(name: String) -> AIConfig:
	assert(PRESETS.has(name), "unknown AI policy '%s'" % name)
	var p: Array = PRESETS[name]
	var c: AIConfig = AIConfig.new()
	c.policy = name
	c.worker_target = p[0]
	c.build_worker_min = p[1]
	c.army_threshold = p[2]
	c.retreat_pct = p[3]
	c.mix_melee = p[4]
	c.mix_ranged = p[5]
	return c
