## Status messages that fade after 3 seconds (SPEC 9; AC-73).
## Times are real seconds (presentation layer, so floats are fine here).
class_name MessageLog
extends RefCounted

const LIFE: float = 3.0
const FADE: float = 0.6
const MAX_SHOWN: int = 6

var _items: Array[Dictionary] = []


func add(text: String, now: float, kind: String = "info") -> void:
	# The same text twice in a row refreshes the old line instead of stacking.
	if not _items.is_empty() and _items[_items.size() - 1].text == text:
		_items[_items.size() - 1].t = now
		return
	_items.append({"text": text, "t": now, "kind": kind})
	if _items.size() > MAX_SHOWN:
		_items.pop_front()


## The live messages with their opacity: 1 until the last 0.6 s, then fading
## to 0 at 3 s, after which they are dropped.
func entries(now: float) -> Array[Dictionary]:
	_items = _items.filter(func(m: Dictionary) -> bool: return now - m.t < LIFE)
	var out: Array[Dictionary] = []
	for m: Dictionary in _items:
		var age: float = now - m.t
		var alpha: float = 1.0 if age < LIFE - FADE else (LIFE - age) / FADE
		out.append({"text": m.text, "kind": m.kind, "alpha": alpha})
	return out


func clear() -> void:
	_items.clear()
