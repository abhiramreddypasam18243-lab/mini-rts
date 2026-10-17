## Visual effects (presentation layer only): a small CPU particle system
## using Kenney's CC0 Particle Pack (decision D-39), arrows that fly in an arc to
## their target, floating numbers, rubble left where buildings fell, and
## fallen units. It reads nothing from the simulation; Game feeds it events.
## Its random numbers come from its own generator, so the simulation's
## seeded generator (and determinism) is never touched.
class_name Effects
extends RefCounted

const DIR: String = "res://assets/kenney/particles/"
const MAX_PARTICLES: int = 1600

## Particles. Each: p, v (px/s), age, life, s0, s1 (start/end size), rot,
## spin, col, tex ("" = a small square chip), add (additive), grav, drag, fade_in.
var parts: Array[Dictionary] = []
## Ground marks under everything (rubble, scorch): p, size, rot, t0, life.
var decals: Array[Dictionary] = []
## Fallen units (they play the LPC fall animation, then fade): p, kind, faction, t0.
var corpses: Array[Dictionary] = []
## Arrows in flight: a, b, t0, life, target, damage, faction.
var arrows: Array[Dictionary] = []
## Arrows that reached their target this frame (Game flashes the target).
var landed: Array[Dictionary] = []
## Effects waiting for their moment (timed to an animation): at, call.
var pending: Array[Dictionary] = []
## Floating texts: p, text, col, t0, life, size, icon.
var texts: Array[Dictionary] = []
var time: float = 0.0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

static var _tex: Dictionary = {}


func _init() -> void:
	rng.randomize()  # drawing only


static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load(DIR + name + ".png")
	return _tex[name]


func update(dt: float) -> void:
	time += dt
	var keep: Array[Dictionary] = []
	for q: Dictionary in parts:
		q.age += dt
		if q.age >= q.life:
			continue
		q.v = q.v * maxf(1.0 - q.drag * dt, 0.0) + Vector2(0, q.grav * dt)
		q.p += q.v * dt
		q.rot += q.spin * dt
		keep.append(q)
	parts = keep
	landed.clear()
	var flying: Array[Dictionary] = []
	for b: Dictionary in arrows:
		if time < b.t0:
			flying.append(b)  # not released yet
			continue
		var k: float = (time - b.t0) / b.life
		if k >= 1.0:
			landed.append(b)
			impact(b.b)
			continue
		flying.append(b)
	arrows = flying
	var waiting: Array[Dictionary] = []
	for w: Dictionary in pending:
		if time >= w.at:
			(w.call as Callable).call()
		else:
			waiting.append(w)
	pending = waiting
	decals = decals.filter(func(d: Dictionary) -> bool: return time - d.t0 < d.life)
	corpses = corpses.filter(func(c: Dictionary) -> bool: return time - c.t0 < 2.2)
	texts = texts.filter(func(t: Dictionary) -> bool: return time - t.t0 < t.life)


## An arrow's position along its arc, k from 0 (bow) to 1 (target).
static func arrow_pos(b: Dictionary, k: float) -> Vector2:
	var arc: float = 4.0 * k * (1.0 - k) * minf(b.a.distance_to(b.b) * 0.22, 34.0)
	return b.a.lerp(b.b, k) - Vector2(0, arc)


## Runs `call` after `delay` seconds (to time an effect to an animation).
func later(delay: float, call: Callable) -> void:
	pending.append({"at": time + delay, "call": call})


func emit(t: String, p: Vector2, v: Vector2, life: float, s0: float, s1: float, col: Color,
		add: bool = false, grav: float = 0.0, drag: float = 0.0, spin: float = 0.0, fade_in: float = 0.0) -> void:
	if parts.size() >= MAX_PARTICLES:
		return
	parts.append({"tex": t, "p": p, "v": v, "age": 0.0, "life": life, "s0": s0, "s1": s1,
		"rot": rng.randf() * TAU, "spin": spin, "col": col, "add": add, "grav": grav, "drag": drag, "fade_in": fade_in})


func _jitter(r: float) -> Vector2:
	return Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r))


func _dir(speed_lo: float, speed_hi: float, up_bias: float = 0.0) -> Vector2:
	return Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(speed_lo, speed_hi) + Vector2(0, -up_bias)


# --- effect recipes --------------------------------------------------------------

## A melee hit: a spray of sparks off the armour and a little dust (the
## sword swing itself is in the unit's animation).
func hit(p: Vector2, from: Vector2) -> void:
	var d: Vector2 = (p - from).normalized() if p != from else Vector2.RIGHT
	emit("light_01", p, Vector2.ZERO, 0.12, 10.0, 26.0, Color(1, 0.9, 0.7, 0.55), true)
	for i: int in 9:
		emit("spark_04", p, d.rotated(rng.randf_range(-1.0, 1.0)) * rng.randf_range(70, 170), 0.28, 5.0, 1.0,
			Color(1.0, 0.85, 0.5), true, 300.0, 3.0)
	dust(p + Vector2(0, 10), 2, 5.0, 9.0)


## An arrow from `a` to `b`, released after `delay` (the bow's release
## frame); it lands after its flight time.
func arrow(a: Vector2, b: Vector2, faction: String, target: int, damage: int, delay: float = 0.0) -> void:
	arrows.append({"a": a, "b": b, "t0": time + delay, "life": clampf(a.distance_to(b) / 430.0, 0.14, 0.4),
		"target": target, "damage": damage, "faction": faction})


func impact(p: Vector2) -> void:
	for i: int in 6:
		emit("spark_01", p, _dir(40, 110), 0.28, 5.0, 1.0, Color(1, 0.92, 0.7), true, 200.0, 2.5)
	dust(p + Vector2(0, 8), 1, 3.0, 8.0)


## A floating number or label.
func float_text(p: Vector2, text: String, col: Color, size: int = 15, icon: String = "") -> void:
	texts.append({"p": p + Vector2(rng.randf_range(-5, 5), 0), "text": text, "col": col, "t0": time,
		"life": 0.95, "size": size, "icon": icon})


func wood_chips(p: Vector2) -> void:
	for i: int in 3:
		emit("", p + _jitter(4), _dir(40, 90, 70), 0.55, 3.5, 2.5, Color("a8743c").lerp(Color("e0b070"), rng.randf()),
			false, 380.0, 1.0, rng.randf_range(-12, 12))


func gold_glint(p: Vector2) -> void:
	emit("star_04", p + _jitter(9), Vector2(0, -12), 0.5, 3.0, 12.0, Color(1.0, 0.92, 0.5), true, 0.0, 0.0, 3.0)
	if rng.randf() < 0.6:
		emit("", p + _jitter(4), _dir(30, 70, 60), 0.5, 2.5, 2.0, Color("ffd34d"), false, 360.0, 1.0, 8.0)


func dust(p: Vector2, n: int = 1, spread: float = 4.0, size: float = 10.0) -> void:
	for i: int in n:
		emit("smoke_04", p + _jitter(spread), _dir(4, 18, 6), rng.randf_range(0.5, 0.9), size * 0.6, size * 1.6,
			Color(0.78, 0.68, 0.5, 0.35), false, 0.0, 1.5, rng.randf_range(-1, 1), 0.15)


func hammer(p: Vector2) -> void:
	for i: int in 3:
		emit("spark_04", p, _dir(40, 100, 50), 0.28, 5.0, 1.0, Color(1, 0.8, 0.4), true, 300.0, 2.0)
	dust(p + Vector2(0, 6), 1, 6.0, 12.0)


func smoke(p: Vector2, scale: float = 1.0, dark: float = 0.0) -> void:
	var g: float = lerpf(0.55, 0.18, dark)
	emit("smoke_0%d" % [1, 4, 8][rng.randi_range(0, 2)], p + _jitter(5.0 * scale), Vector2(rng.randf_range(4, 12), rng.randf_range(-34, -22)) * scale,
		rng.randf_range(1.6, 2.4), 18.0 * scale, 60.0 * scale, Color(g, g * 0.97, g * 0.95, 0.85), false, -4.0, 0.3, rng.randf_range(-0.6, 0.6), 0.15)


func fire(p: Vector2, scale: float = 1.0) -> void:
	emit("flame_03" if rng.randf() < 0.5 else "fire_01", p + _jitter(4.0 * scale), Vector2(rng.randf_range(-6, 6), rng.randf_range(-48, -30)) * scale,
		rng.randf_range(0.35, 0.6), 18.0 * scale, 5.0 * scale, Color(1.0, rng.randf_range(0.45, 0.7), 0.2, 0.85), true, -30.0, 0.5, rng.randf_range(-2, 2))
	if rng.randf() < 0.35:
		emit("spark_01", p + _jitter(6.0 * scale), Vector2(rng.randf_range(-20, 20), rng.randf_range(-90, -50)), 0.9, 4.0, 1.0,
			Color(1, 0.7, 0.3), true, -20.0, 0.6, 0.0)


## A unit falls: its sprite tips over and fades; a little dust and a team flash.
func unit_died(p: Vector2, kind: String, faction: String) -> void:
	corpses.append({"p": p, "kind": kind, "faction": faction, "t0": time})
	dust(p, 4, 8.0, 12.0)
	for i: int in 6:
		emit("spark_01", p + Vector2(0, -14), _dir(40, 110, 40), 0.45, 6.0, 1.0, Palette.TEAM_LIGHT[faction], true, 200.0, 2.0)


## A building collapses: a flash, a dust ring, flying debris, rising smoke
## and a scorched patch of rubble left on the ground.
func building_died(r: Rect2) -> void:
	var c: Vector2 = r.get_center()
	var s: float = r.size.x / 64.0
	emit("light_01", c, Vector2.ZERO, 0.35, 40.0 * s, 160.0 * s, Color(1, 0.75, 0.4, 0.9), true)
	for i: int in 14:
		emit("smoke_0%d" % [1, 4, 8][i % 3], c + _jitter(r.size.x * 0.35), _dir(30, 80, 25) * s, rng.randf_range(1.2, 2.2),
			24.0 * s, 80.0 * s, Color(0.55, 0.48, 0.4, 0.6), false, -6.0, 1.2, rng.randf_range(-1, 1), 0.05)
	for i: int in 22:
		var col: Color = [Color("8a8f99"), Color("6b4a2b"), Color("b8743a"), Color("a9a9a9")][i % 4]
		emit("", c + _jitter(r.size.x * 0.3), _dir(80, 220, 120), rng.randf_range(0.6, 1.0), rng.randf_range(3, 7), 3.0,
			col, false, 520.0, 0.6, rng.randf_range(-14, 14))
	for i: int in 12:
		fire(c + _jitter(r.size.x * 0.3), 1.2 * s)
	decals.append({"p": c, "size": r.size.x * 1.25, "rot": rng.randf() * TAU, "t0": time, "life": 40.0, "rubble": true})


# --- drawing -----------------------------------------------------------------------

## Ground layer: rubble and scorch marks, then fallen units.
func draw_ground(ci: CanvasItem) -> void:
	for d: Dictionary in decals:
		var a: float = clampf((d.life - (time - d.t0)) / 6.0, 0.0, 1.0)
		var s: float = d.size
		ci.draw_set_transform(d.p, d.rot, Vector2.ONE)
		ci.draw_texture_rect(tex("scorch_02"), Rect2(-s / 2.0, -s / 2.0, s, s), false, Color(0.12, 0.08, 0.05, 0.75 * a))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if d.get("rubble", false):
			for i: int in 5:
				var off: Vector2 = Vector2.from_angle(d.rot + i * 1.3) * s * (0.12 + 0.05 * i)
				var rs: float = s * (0.28 - 0.025 * i)
				ci.draw_texture_rect(Art.tex("rock_pair" if i % 2 == 0 else "pebble"), Rect2(d.p + off - Vector2(rs, rs) / 2.0, Vector2(rs, rs)), false, Color(0.75, 0.7, 0.65, a))
	for c: Dictionary in corpses:
		var age: float = time - c.t0
		var a2: float = clampf((2.2 - age) / 0.9, 0.0, 1.0)
		Art.unit(ci, c.p, c.kind, c.faction, "hurt", 0, int(age / 0.08), a2, 0.0, UnitSprites.SCALE, false)


## Particle layer: `additive` picks the glowing particles (drawn by a node
## with additive blending) or the normal ones.
func draw_particles(ci: CanvasItem, additive: bool) -> void:
	for q: Dictionary in parts:
		if q.add != additive:
			continue
		var k: float = q.age / q.life
		var a: float = 1.0 - k
		if q.fade_in > 0.0:
			a *= clampf(k / q.fade_in, 0.0, 1.0)
		var s: float = lerpf(q.s0, q.s1, k)
		var col: Color = Color(q.col, q.col.a * a)
		ci.draw_set_transform(q.p, q.rot, Vector2.ONE)
		if q.tex == "":
			ci.draw_rect(Rect2(-s / 2.0, -s / 2.0, s, s * 0.7), col)
		else:
			ci.draw_texture_rect(tex(q.tex), Rect2(-s / 2.0, -s / 2.0, s, s), false, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if not additive:
		for b: Dictionary in arrows:
			if time < b.t0:
				continue
			var k3: float = (time - b.t0) / b.life
			var head: Vector2 = arrow_pos(b, k3)
			var tail: Vector2 = arrow_pos(b, maxf(k3 - 0.06, 0.0))
			var dirv: Vector2 = (head - tail).normalized() if head != tail else (b.b - b.a).normalized()
			ci.draw_line(head - dirv * 22.0, head - dirv * 12.0, Color(1, 1, 1, 0.25), 2.0, true)
			ci.draw_line(head - dirv * 13.0, head, Color("5a3d24"), 1.6, true)
			ci.draw_line(head - dirv * 13.0, head - dirv * 10.0, Color("f3efe2"), 2.6, true)
			ci.draw_colored_polygon(PackedVector2Array([head + dirv * 3.5, head + dirv.orthogonal() * 2.2, head - dirv.orthogonal() * 2.2]), Color("c9ced6"))


## Floating numbers, popping in then drifting up.
func draw_texts(ci: CanvasItem) -> void:
	var font: Font = UiTheme.font("bold")
	for t: Dictionary in texts:
		var k: float = (time - t.t0) / t.life
		var pop: float = 1.0 + 0.5 * maxf(1.0 - k * 6.0, 0.0)
		var size: int = int(t.size * pop)
		var p: Vector2 = t.p + Vector2(0, -30.0 * ease(k, 0.5))
		var a: float = clampf((1.0 - k) * 2.5, 0.0, 1.0)
		var w: float = font.get_string_size(t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var x: float = p.x - w / 2.0
		if t.icon != "":
			x += 7.0
			Art.icon(ci, Vector2(x - 9.0, p.y - size * 0.35), t.icon, 0.42)
		ci.draw_string_outline(font, Vector2(x, p.y), t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(0.12, 0.07, 0.03, 0.85 * a))
		ci.draw_string(font, Vector2(x, p.y), t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(t.col, a))
