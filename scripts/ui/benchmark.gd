## Frame-rate benchmark for AC-77 (presentation layer, a measuring tool).
## Starts a match on the seed-42 map with exactly 80 units (each side: its
## 3 workers plus 37 soldiers placed around its HQ through the simulation's
## setup helper), sends both armies to the middle so they march and fight,
## and records frame times for 15 seconds with every unit drawn (no fog).
## Start it with `MiniRTS.exe -- --bench` (desktop) or `?bench` on the web
## address. The result is shown on screen and printed as one "BENCH" line.
class_name Benchmark
extends RefCounted

const UNITS_PER_SIDE: int = 40
const WARMUP: float = 2.0
const DURATION: float = 15.0

var game: Game
## Microseconds spent in named parts of the frame (filled only while a
## benchmark runs; drawing is recorded in the frame after its _process).
static var marks: Dictionary = {}
static var active: bool = false
var _marks: Array[Dictionary] = []
var _t: float = 0.0
var _frames: PackedFloat32Array = PackedFloat32Array()
var _min_units: int = 1 << 30
## Time spent running simulation ticks this frame (microseconds).
var sim_us: int = 0
var _sim: PackedInt32Array = PackedInt32Array()
## Per frame: render times (ms).
var _rcpu: PackedFloat32Array = PackedFloat32Array()
var _rgpu: PackedFloat32Array = PackedFloat32Array()
var done: bool = false
var result: Dictionary = {}


## True when this run was asked to benchmark (command line or web address).
static func requested() -> bool:
	if "--bench" in OS.get_cmdline_user_args():
		return true
	if OS.has_feature("web"):
		var search: Variant = JavaScriptBridge.eval("window.location.search")
		return search is String and (search as String).contains("bench")
	return false


func setup(p_game: Game) -> void:
	game = p_game
	active = true
	var sim: Simulation = game.sim
	var centre: Vector2i = Vector2i(sim.map.width / 2, sim.map.height / 2)
	for f: String in ["player", "ai"]:
		var hq: Entity = sim.entity(sim.hq_of(f))
		var have: int = 0
		for id: int in sim.unit_ids():
			if sim.entity(id).faction == f:
				have += 1
		var cells: Array[Vector2i] = sim.spawn_cells(hq, UNITS_PER_SIDE - have)
		var army: Array[int] = []
		for i: int in cells.size():
			army.append(sim.spawn_unit("ranged" if i % 3 == 2 else "melee", f, cells[i]))
		sim.submit(Commands.move(f, army, centre))
	sim.update_fog()
	RenderingServer.viewport_set_measure_render_time(game.get_viewport().get_viewport_rid(), true)
	game.camera.position = (Vector2(centre) + Vector2(0.5, 0.5)) * Consts.PIXELS_PER_CELL


## Called every frame with the frame's real duration.
func tick(delta: float) -> void:
	if done:
		return
	_t += delta
	if _t < WARMUP:
		return
	_frames.append(delta)
	_sim.append(sim_us)
	_marks.append(marks.duplicate())
	marks.clear()
	var vp: RID = game.get_viewport().get_viewport_rid()
	_rcpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu())
	_rgpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
	_min_units = mini(_min_units, game.sim.unit_ids().size())
	if _t >= WARMUP + DURATION:
		_finish()


func _finish() -> void:
	done = true
	var sorted: Array = Array(_frames)
	sorted.sort()
	var total: float = 0.0
	for d: float in sorted:
		total += d
	var worst_n: int = maxi(1, sorted.size() / 100)
	var worst: float = 0.0
	for i: int in worst_n:
		worst += sorted[sorted.size() - 1 - i]
	result = {
		"avg_fps": sorted.size() / total,
		"low1_fps": worst_n / worst,
		"frames": sorted.size(),
		"min_units": _min_units,
		"platform": "web" if OS.has_feature("web") else OS.get_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
	}
	# The slowest frames, with how much of each was simulation.
	var idx: Array = range(_frames.size())
	idx.sort_custom(func(a: int, b: int) -> bool: return _frames[a] > _frames[b])
	var worst_lines: PackedStringArray = PackedStringArray()
	for i: int in mini(8, idx.size()):
		var j: int = idx[i]
		worst_lines.append("%.1fms(sim %.1f rcpu %.1f rgpu %.1f %s | next %s)" % [_frames[j] * 1000.0, _sim[j] / 1000.0, _rcpu[j], _rgpu[j],
			_fmt(_marks[j]), _fmt(_marks[mini(j + 1, _marks.size() - 1)])])
	print("BENCH worst frames: ", ", ".join(worst_lines))
	var avg: Callable = func(a: PackedFloat32Array) -> float:
		var s: float = 0.0
		for v: float in a:
			s += v
		return s / maxf(a.size(), 1)
	print("BENCH mean render cpu %.1f ms, render gpu %.1f ms" % [avg.call(_rcpu), avg.call(_rgpu)])
	print("BENCH avg_fps=%.1f low1_fps=%.1f frames=%d min_units=%d platform=%s gpu=%s" % [
		result.avg_fps, result.low1_fps, result.frames, result.min_units, result.platform, result.gpu])


static func mark(key: String, since_usec: int) -> void:
	if active:
		marks[key] = marks.get(key, 0) + Time.get_ticks_usec() - since_usec


func _fmt(m: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for k: String in m:
		parts.append("%s %.1f" % [k, m[k] / 1000.0])
	return " ".join(parts)


func text() -> String:
	if not done:
		return "Benchmark: measuring... %d s" % int(maxf(WARMUP + DURATION - _t, 0.0))
	return "Benchmark: %.0f FPS average · %.0f FPS (1%% low) · %d+ units · %s" % [
		result.avg_fps, result.low1_fps, result.min_units, result.gpu]
