## 32-bit FNV-1a over a stream of integers, used by Simulation.state_hash().
## Written by hand (not Godot's hash()) so the value is fixed by this file alone.
## h < 2^32 and the prime < 2^25, so h * prime < 2^57: no overflow.
class_name StateHasher
extends RefCounted

const OFFSET: int = 2166136261
const PRIME: int = 16777619
const MASK32: int = 0xFFFFFFFF

var h: int = OFFSET


## Feeds the 8 bytes of a 64-bit integer, low byte first.
func add_int(v: int) -> void:
	for i: int in 8:
		h ^= (v >> (8 * i)) & 0xFF
		h = (h * PRIME) & MASK32


func add_ints(values: PackedInt64Array) -> void:
	for v: int in values:
		add_int(v)


func add_bytes(values: PackedByteArray) -> void:
	for b: int in values:
		h ^= b
		h = (h * PRIME) & MASK32


func add_string(s: String) -> void:
	add_int(s.length())
	add_bytes(s.to_utf8_buffer())
