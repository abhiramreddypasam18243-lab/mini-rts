## Turns real frame time into whole simulation ticks (presentation layer).
## Time is accumulated in integer microseconds, so frames that add up to exactly
## one second always give exactly 20 ticks, however they are split (AC-01).
class_name TickClock
extends RefCounted

const USEC_PER_TICK: int = 1_000_000 / Consts.TICKS_PER_SECOND
## A long stall (e.g. a hidden browser tab) runs at most this many ticks per frame.
const MAX_TICKS_PER_FRAME: int = 10

var _acc: int = 0


func advance_usec(usec: int) -> int:
	_acc += usec
	var n: int = _acc / USEC_PER_TICK
	_acc -= n * USEC_PER_TICK
	return n


## Frame helper for _process(delta): converts seconds once, then clamps.
func advance(delta: float) -> int:
	var n: int = advance_usec(roundi(delta * 1_000_000.0))
	if n > MAX_TICKS_PER_FRAME:
		_acc = 0
		return MAX_TICKS_PER_FRAME
	return n
