## Iteration counts for the two suites (decision D-20).
## The fast suite (default) keeps the whole run under 2 minutes (AC-89);
## the long suite (environment RTS_LONG=1) runs the full counts from the spec.
class_name TestCounts
extends RefCounted


static func is_long() -> bool:
	return OS.get_environment("RTS_LONG") == "1"


static func pick(fast: int, full: int) -> int:
	return full if is_long() else fast
