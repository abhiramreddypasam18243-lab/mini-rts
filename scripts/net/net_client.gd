## The connection to the relay server for online matches (decision D-60).
## A WebSocket, which works in the browser build and the desktop app alike.
## It only carries messages; the game logic is in Lockstep and Game. The
## relay's protocol is described in relay/server.js.
class_name NetClient
extends Node

signal hosted(code: String)
## Both players are in: `you` is "player" (the host, blue) or "ai" (the guest, red).
signal started(you: String, setup: Dictionary)
signal received(d: Dictionary)
signal opponent_left
signal failed(text: String)

## Where the relay runs (a free Render web service; see relay/README.md).
## `--relay=ws://host:port` on the command line, or `?relay=...` in the web
## address, points the game at another relay (tests and local play).
const DEFAULT_URL: String = "wss://mini-rts-relay.onrender.com"
## Both players must run the same rules: bump this when a rule changes.
const VERSION: int = 1

var ws: WebSocketPeer = WebSocketPeer.new()
var _outbox: Array[String] = []
var _state: int = WebSocketPeer.STATE_CLOSED
var _open: bool = false
var _done: bool = false


static func relay_url() -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--relay="):
			return a.trim_prefix("--relay=")
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('relay')", true)
		if q != null and str(q) != "":
			return str(q)
	return DEFAULT_URL


## Opens the connection. A free server that was asleep can take up to a
## minute to wake; the connection simply waits for it.
func open(url: String = relay_url()) -> void:
	var err: Error = ws.connect_to_url(url)
	if err != OK:
		_fail("Could not reach the game server (%s)." % error_string(err))


func host(setup: Dictionary) -> void:
	var s: Dictionary = setup.duplicate()
	s.v = VERSION
	_send({"op": "host", "setup": s})


func join(code: String) -> void:
	_send({"op": "join", "code": code.strip_edges().to_upper(), "v": VERSION})


## Passes `d` to the other player.
func relay(d: Dictionary) -> void:
	_send({"op": "relay", "d": d})


## Leaves the game and closes the connection (the other player is told).
func leave() -> void:
	_done = true
	if _open:
		ws.send_text(JSON.stringify({"op": "leave"}))
	ws.close()


func is_open() -> bool:
	return _open


func _send(m: Dictionary) -> void:
	var text: String = JSON.stringify(m)
	if _open:
		ws.send_text(text)
	else:
		_outbox.append(text)


func _process(_delta: float) -> void:
	if _done:
		return
	ws.poll()
	var s: int = ws.get_ready_state()
	if s == WebSocketPeer.STATE_OPEN and not _open:
		_open = true
		for text: String in _outbox:
			ws.send_text(text)
		_outbox.clear()
	while ws.get_available_packet_count() > 0:
		var m: Variant = JSON.parse_string(ws.get_packet().get_string_from_utf8())
		if m is Dictionary:
			_dispatch(m)
	if s == WebSocketPeer.STATE_CLOSED and _state != WebSocketPeer.STATE_CLOSED:
		_fail("The connection to the other player was lost." if _open else "Could not reach the game server. Check your internet connection and try again.")
	_state = s


func _dispatch(m: Dictionary) -> void:
	match str(m.get("op", "")):
		"hosted":
			hosted.emit(str(m.code))
		"start":
			started.emit(str(m.you), m.setup)
		"relay":
			received.emit(m.d)
		"left":
			_done = true
			opponent_left.emit()
		"error":
			failed.emit(str(m.msg))


func _fail(text: String) -> void:
	if _done:
		return
	_done = true
	failed.emit(text)
