## Draws everything on the board the player may see, every frame
## (presentation layer; reads the simulation, never changes it):
## remembered resource nodes, own and visible buildings, ghosts of enemy
## buildings in fog, own and visible units (sorted by height so lower ones
## overlap upper ones). Units are animated from what they are doing: a
## hop while walking, chopping while gathering, hammering while building, a
## lunge or cast when they attack, and slow breathing when idle. Rubble and
## fallen units from Effects are drawn under everything.
class_name WorldLayer
extends Node2D

const C: float = Consts.PIXELS_PER_CELL

var game: Game
## Per unit: walk-cycle phase and last drawn feet position (animation only).
var _walk: Dictionary = {}
var _last: Dictionary = {}


func _draw() -> void:
	if game == null or game.sim == null:
		return
	var t0: int = Time.get_ticks_usec()
	_draw_world()
	Benchmark.mark("world", t0)


func _draw_world() -> void:
	var sim: Simulation = game.sim
	var f: String = game.faction
	var t: float = game.time
	var mem: Dictionary = sim.fog.memory[f]
	game.effects.draw_ground(self)

	# Resource nodes, as the player remembers them (all of them when spectating).
	var nodes: Dictionary = mem
	if game.spectate:
		nodes = {}
		for id: int in sim.entities:
			var n: Entity = sim.entities[id]
			if n.is_node():
				nodes[id] = Fog.snapshot(n)
	for id: int in nodes:
		var g: Dictionary = nodes[id]
		if g.faction == "":
			var full_amount: int = Consts.WOOD_NODE_AMOUNT if g.kind == "wood" else Consts.GOLD_NODE_AMOUNT
			Art.node(self, _cell_center(g.cell), g.kind, float(g.amount) / full_amount, t)
			if id == game.hover_id or id == game.selection.inspected:
				_ring_rect(Rect2(Vector2(g.cell) * C, Vector2(C, C)), Color(Palette.resource(g.kind), 0.7))

	# Ghosts: enemy buildings remembered but not seen now.
	for id: int in mem:
		var g: Dictionary = mem[id]
		if g.faction == "" or g.faction == f or game.spectate:
			continue
		if sim.fog.any_visible(f, g.cell, g.size) and sim.entities.has(id):
			continue
		Art.building(self, Rect2(Vector2(g.cell) * C, Vector2(g.size) * C), g.kind, g.faction, t, g.complete, 1.0, true)

	# Buildings the player owns or sees.
	for id: int in sim.entities:
		var e: Entity = sim.entities[id]
		if not e.is_building() or not (e.faction == f or game.spectate or sim.fog.any_visible(f, e.cell, e.size)):
			continue
		var r: Rect2 = Rect2(Vector2(e.cell) * C, Vector2(e.size) * C)
		var progress: float = float(e.progress) / sim.stats[e.kind].build_time if not e.complete else 1.0
		Art.building(self, r, e.kind, e.faction, t, e.complete, progress, false, game.flash(id))
		var selected: bool = game.selection.selected.has(id) or game.selection.inspected == id
		if selected or id == game.hover_id:
			_ring_rect(r, Color(1, 1, 1, 0.85 if selected else 0.35))
		var max_hp: int = sim.stats[e.kind].health
		if e.hp < max_hp or selected:
			Art.bar(self, Rect2(r.position.x + 6, r.position.y - 9, r.size.x - 12, 4), float(e.hp) / max_hp, Palette.health(float(e.hp) / max_hp))
		if e.faction == f and not e.queue.is_empty():
			var item: Dictionary = e.queue[0]
			var total: int = sim.stats[item.type].build_time
			Art.bar(self, Rect2(r.position.x + 10, r.end.y + 4, r.size.x - 20, 3), 1.0 - float(item.remaining) / total, Palette.ACCENT)

	# Units, lower on screen drawn last.
	var shown: Array[Entity] = []
	for id: int in sim.entities:
		var e: Entity = sim.entities[id]
		if e.is_unit() and (e.faction == f or game.spectate or sim.fog.is_visible(f, e.unit_cell())):
			shown.append(e)
	shown.sort_custom(func(a: Entity, b: Entity) -> bool: return a.pos.y < b.pos.y or (a.pos.y == b.pos.y and a.id < b.id))
	var spread: Dictionary = _spread(shown)
	for e: Entity in shown:
		_draw_unit(e, sim, spread.get(e.id, Vector2.ZERO))


## Units may share a cell (D-04). Tokens standing on exactly the same spot
## are fanned out a little so each one can be seen (drawing only).
func _spread(units: Array[Entity]) -> Dictionary:
	var groups: Dictionary = {}
	for e: Entity in units:
		if not groups.has(e.pos):
			groups[e.pos] = []
		groups[e.pos].append(e.id)
	var out: Dictionary = {}
	for pos: Vector2i in groups:
		var ids: Array = groups[pos]
		if ids.size() < 2:
			continue
		ids.sort()
		for k: int in ids.size():
			out[ids[k]] = Vector2.from_angle(TAU * k / ids.size() - PI / 2.0) * 7.0
	return out


func _draw_unit(e: Entity, sim: Simulation, offset: Vector2 = Vector2.ZERO) -> void:
	# The unit's position is its cell centre; its feet are drawn a little below.
	var feet: Vector2 = game.draw_pos(e) + offset + Vector2(0, 8)
	var pose: Dictionary = _pose(e, feet)
	var body: Vector2 = feet + pose.get("shift", Vector2.ZERO)
	var r: float = Art.unit_radius(e.kind)
	var selected: bool = game.selection.selected.has(e.id)
	var inspected: bool = game.selection.inspected == e.id
	if selected or inspected or e.id == game.hover_id:
		_selection_ring(feet, r + 6.0, selected)
	Art.unit(self, body, e.kind, e.faction, 1.0, 1.0, game.flash(e.id), pose)
	var head: float = feet.y - 32.0
	if e.carry > 0:
		var cp: Vector2 = Vector2(body.x + (-10.0 if pose.flip else 10.0), head + 8 - pose.get("lift", 0.0))
		Art.icon(self, cp, e.carry_type, 0.36)
	var max_hp: int = sim.stats[e.kind].health
	if e.hp < max_hp or selected:
		var ratio: float = float(e.hp) / max_hp
		Art.bar(self, Rect2(feet.x - 12, head - 6, 24, 4), ratio, Palette.health(ratio))


## How to draw a unit this frame, from what it is doing.
func _pose(e: Entity, feet: Vector2) -> Dictionary:
	var t: float = game.time
	var last: Vector2 = _last.get(e.id, feet)
	_last[e.id] = feet
	var moved: Vector2 = feet - last
	var flip: bool = game.facing.get(e.id, e.faction == "ai")
	if absf(moved.x) > 0.05:
		flip = moved.x < 0.0
	var info: Dictionary = game.attack_info.get(e.id, {})
	var since: float = t - info.t if not info.is_empty() else 99.0
	if since < 0.6 and absf(info.dir.x) > 0.1:
		flip = info.dir.x < 0.0
	game.facing[e.id] = flip
	var sgn: float = -1.0 if flip else 1.0
	var pose: Dictionary = {"flip": flip}
	if moved.length() > 0.02:
		var ph: float = _walk.get(e.id, float(e.id)) + moved.length() * 0.3
		_walk[e.id] = ph
		var step: float = absf(sin(ph))
		pose.lift = step * 3.5
		pose.tilt = sin(ph) * 0.07
		pose.sy = 0.96 + 0.08 * step
		pose.sx = 1.04 - 0.06 * step
	elif e.phase == "gathering" or e.phase == "building":
		# Chop or hammer: wind up, then strike.
		var k: float = fmod(t * (2.2 if e.phase == "gathering" else 3.0) + e.id * 0.37, 1.0)
		var swing: float = sin(k * TAU) if k < 0.5 else sin(k * TAU) * 0.4
		pose.tilt = -0.22 * swing * sgn
		pose.sy = 1.0 - 0.04 * maxf(-swing, 0.0)
	else:
		var b: float = sin(t * 2.3 + e.id * 1.7)
		pose.sy = 1.0 + 0.022 * b
		pose.sx = 1.0 - 0.012 * b
	if since < 0.32:
		var a: float = sin(since / 0.32 * PI)
		if e.kind == "melee":
			pose.shift = info.dir * 7.0 * a
			pose.tilt = 0.32 * a * sgn
		else:
			pose.lift = 3.0 * a
			pose.sy = 1.0 + 0.08 * a
			pose.shift = -info.dir * 2.0 * a
	return pose


## A gold (selected) or white (hovered) dashed ring that slowly turns.
func _selection_ring(feet: Vector2, r: float, selected: bool) -> void:
	var col: Color = Color(1.0, 0.86, 0.35, 0.95) if selected else Color(1, 1, 1, 0.6)
	draw_set_transform(feet + Vector2(0, 3), 0.0, Vector2(1.0, 0.5))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(0, 0, 0, 0.3), 5.0, true)
	var spin: float = game.time * 1.4
	for i: int in 6:
		var a0: float = spin + i * TAU / 6.0
		draw_arc(Vector2.ZERO, r, a0, a0 + TAU / 6.0 * 0.62, 8, col, 2.6, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _cell_center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * C


func _ring_rect(r: Rect2, col: Color) -> void:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = col
	s.set_border_width_all(2)
	s.set_corner_radius_all(10)
	s.anti_aliasing = true
	draw_style_box(s, r.grow(2.0))
