## Phone and tablet support (presentation layer, decision D-45).
## Touch mode is on for Android and iOS browsers and mobile builds, when the
## web address has `?touch`, or after the first real touch on the screen.
## In touch mode: one finger drags the map, a tap selects your own units or
## orders the selected units to the tapped spot (move, gather or attack),
## and a toolbar replaces the keys and the right mouse button. The interface
## is scaled for small screens: at least 1180 x 560 virtual pixels, which
## keeps text readable and leaves room for every HUD panel side by side.
class_name TouchInput
extends RefCounted

## The smallest virtual screen in touch mode (see the class comment).
const MIN_SIZE: Vector2i = Vector2i(1180, 560)

## Set by tests or by the first touch event; null = not decided yet.
static var _forced: Variant = null
static var _seen_touch: bool = false


## True on phones and tablets (or when forced, e.g. by `?touch`).
static func enabled() -> bool:
	if _forced != null:
		return bool(_forced)
	if _seen_touch:
		return true
	if OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile"):
		return true
	if OS.has_feature("web"):
		var search: Variant = JavaScriptBridge.eval("window.location.search")
		return search is String and (search as String).contains("touch")
	return false


## Forces touch mode on or off (tests); null goes back to detection.
static func force(on: Variant) -> void:
	_forced = on


## Notes a real touch (a laptop with a touchscreen switches to touch mode).
static func saw_touch() -> void:
	_seen_touch = true


## Scales the interface for small screens (call once at start).
static func apply_layout(tree: SceneTree) -> void:
	if enabled():
		tree.root.content_scale_size = MIN_SIZE
		print("Touch mode: window %s (phones render at normal density, D-46)" % [DisplayServer.window_get_size()])
