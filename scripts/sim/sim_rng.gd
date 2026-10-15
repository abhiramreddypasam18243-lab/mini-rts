## The simulation's own seeded pseudo-random generator (AC-02).
## Godot's global randf/randi are never used in scripts/sim/.
##
## A 32-bit linear congruential generator: state = (state * A + C) mod 2^32.
## state < 2^32 and A < 2^21, so state * A < 2^53: no 64-bit overflow, and the
## same seed gives the same sequence on every platform.
## The low bits of an LCG repeat quickly, so each draw uses the top 16 bits of
## two steps. The seed is scrambled first so neighbouring seeds diverge at once.
class_name SimRng
extends RefCounted

const A: int = 1664525
const C: int = 1013904223
const MASK32: int = 0xFFFFFFFF

var state: int


func _init(p_seed: int) -> void:
	state = mix32(p_seed & MASK32)


## A 32-bit integer hash used to scramble seeds (each product stays below 2^59).
static func mix32(x: int) -> int:
	var v: int = x & MASK32
	v ^= v >> 16
	v = (v * 0x45d9f3b) & MASK32
	v ^= v >> 16
	v = (v * 0x45d9f3b) & MASK32
	v ^= v >> 16
	return v


func _step16() -> int:
	state = (state * A + C) & MASK32
	return state >> 16


## A 32-bit integer in [0, 2^32).
func next_u32() -> int:
	return (_step16() << 16) | _step16()


## An integer in [0, n). n must be positive.
func range_int(n: int) -> int:
	assert(n > 0, "range_int needs n > 0")
	return next_u32() % n


## An integer in [lo, hi], both inclusive.
func between(lo: int, hi: int) -> int:
	return lo + range_int(hi - lo + 1)
