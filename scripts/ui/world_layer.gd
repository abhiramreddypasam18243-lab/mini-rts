## Draws everything on the board the player may see, every frame
## (presentation layer; reads the simulation, never changes it):
## remembered resource nodes, own and visible buildings, ghosts of enemy
## buildings in fog, own and visible units (sorted by height so lower ones
## overlap upper ones). Units play LPC animations (D-41) chosen from what
## they are doing: walking, chopping wood, mining gold, hammering at a
## building site, a sword swing or a bow shot when they attack, standing
## ready when idle. Units close together are pushed apart a little on
## screen (drawing only; the simulation still lets them share cells, D-04),
## so a fight reads as two lines, not a blob. Rubble and fallen units from
## Effects are drawn under everything.
class_name WorldLayer
extends Node2D

const C: float = Consts.PIXELS_PER_CELL

var game: Game
## Per unit: walk-cycle phase, last drawn feet position and on-screen
## separation offset (animation only).
var _walk: Dictionary = {}
var _last: Dictionary = {}
var _off: Dictionary = {}
var _last_time: float = 0.0
## Seconds an attack animation lasts.
const SLASH_TIME: float = 0.42
const SHOOT_TIME: float = 0.42
## Units closer than this (world px) push apart on screen, at most MAX_OFF.
const PERSONAL: float = 17.0
const MAX_OFF: float = 11.0
## How far a melee fighter is drawn back from its enemy (world px).
const STANCE: float = 7.0


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

	# Buildings, ghosts and units are drawn together, back to front by where
	# they stand (D-49): a unit behind a castle is hidden by its towers, one
	# in front is drawn over it.
	var items: Array[Array] = []
	for id: int in mem:
		var g: Dictionary = mem[id]
		if g.faction == "" or g.faction == f or game.spectate:
			continue
		if sim.fog.any_visible(f, g.cell, g.size) and sim.entities.has(id):
			continue
		items.append([float(g.cell.y + g.size.y) * C - 4.0, 0, id])
	for id: int in sim.entities:
		var e: Entity = sim.entities[id]
		if e.is_building() and (e.faction == f or game.spectate or sim.fog.any_visible(f, e.cell, e.size)):
			items.append([float(e.cell.y + e.size.y) * C - 4.0, 1, id])
	var shown: Array[Entity] = []
	for id: int in sim.entities:
		var e: Entity = sim.entities[id]
		if e.is_unit() and (e.faction == f or game.spectate or sim.fog.is_visible(f, e.unit_cell())):
			shown.append(e)
	_separate(shown)
	for e: Entity in shown:
		items.append([_feet(e).y, 2, e.id])
	items.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] or (x[0] == y[0] and (x[1] < y[1] or (x[1] == y[1] and x[2] < y[2]))))
	for it: Array in items:
		match it[1]:
			0:
				var g2: Dictionary = mem[it[2]]
				Art.building(self, Rect2(Vector2(g2.cell) * C, Vector2(g2.size) * C), g2.kind, g2.faction, t, g2.complete, 1.0, true)
			1:
				_draw_building(sim.entities[it[2]], sim)
			2:
				_draw_unit(sim.entities[it[2]], sim)
	_draw_hidden(shown, sim)


## Units standing behind a building are drawn again over it as a faint
## silhouette in their team colour, so they can still be seen and clicked.
func _draw_hidden(shown: Array[Entity], sim: Simulation) -> void:
	var covers: Array[Rect2] = []
	for id: int in sim.entities:
		var b: Entity = sim.entities[id]
		if b.is_building():
			var r: Rect2 = Rect2(Vector2(b.cell) * C, Vector2(b.size) * C)
			# The building's picture rises above its footprint.
			covers.append(Rect2(r.position.x - 4, r.position.y - r.size.y * (1.0 if b.kind == "hq" else 0.6), r.size.x + 8, r.size.y * (2.0 if b.kind == "hq" else 1.6)))
	for e: Entity in shown:
		var feet: Vector2 = _feet(e)
		for c: Rect2 in covers:
			if c.has_point(feet) and feet.y < c.end.y - C * 0.6:
				var a: Dictionary = _anim(e, feet)
				var tint: Color = Color(Palette.TEAM_LIGHT[e.faction], 0.55)
				UnitSprites.draw(self, feet, e.kind, e.faction, a.anim, a.dir, a.frame, UnitSprites.SCALE, tint)
				break


func _draw_building(e: Entity, sim: Simulation) -> void:
	var f: String = game.faction
	var id: int = e.id
	var r: Rect2 = Rect2(Vector2(e.cell) * C, Vector2(e.size) * C)
	var progress: float = float(e.progress) / sim.stats[e.kind].build_time if not e.complete else 1.0
	Art.building(self, r, e.kind, e.faction, game.time, e.complete, progress, false, game.flash(id))
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


## Where a unit's feet are drawn: its position (the cell centre) a little
## lower, plus its separation offset.
func _feet(e: Entity) -> Vector2:
	return game.draw_pos(e) + _off.get(e.id, Vector2.ZERO) + _stance(e) + Vector2(0, 8)


## A soldier fighting in melee stands back a little from its enemy (drawing
## only): the simulation puts melee fighters in neighbouring cells (D-42),
## and the sprites are a bit taller than a cell, so this keeps a visible gap
## between the two lines.
func _stance(e: Entity) -> Vector2:
	if e.order_type != "attack" or e.kind != "melee":
		return Vector2.ZERO
	var info: Dictionary = game.attack_info.get(e.id, {})
	if info.is_empty():
		return Vector2.ZERO
	var since: float = game.time - float(info.t)
	# Eased in over 0.15 s after a blow, out over the last 0.5 s.
	var w: float = minf(since / 0.15, 1.0) if since < 2.0 else clampf((2.5 - since) / 0.5, 0.0, 1.0)
	return -(info.dir as Vector2) * STANCE * w


## Units may share a cell (D-04). On screen, units closer than PERSONAL push
## each other apart (eased, capped at MAX_OFF), so groups spread into
## readable lines. Neighbours are found through a grid of cell buckets.
func _separate(units: Array[Entity]) -> void:
	var dt: float = clampf(game.time - _last_time, 0.0, 0.1)
	_last_time = game.time
	var base: Dictionary = {}
	var buckets: Dictionary = {}
	for e: Entity in units:
		var p: Vector2 = game.draw_pos(e)
		base[e.id] = p
		var key: Vector2i = Vector2i(floori(p.x / PERSONAL), floori(p.y / PERSONAL))
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(e.id)
	for e: Entity in units:
		var p: Vector2 = base[e.id]
		var push: Vector2 = Vector2.ZERO
		var key: Vector2i = Vector2i(floori(p.x / PERSONAL), floori(p.y / PERSONAL))
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				for other: int in buckets.get(key + Vector2i(dx, dy), []):
					if other == e.id:
						continue
					var d: Vector2 = p - base[other]
					var len: float = d.length()
					if len >= PERSONAL:
						continue
					if len < 0.01:
						d = Vector2.from_angle(float(e.id) * 2.39996)
						len = 0.01
					push += d / len * (PERSONAL - len) * 0.5
		var target: Vector2 = push.limit_length(MAX_OFF)
		_off[e.id] = (_off.get(e.id, Vector2.ZERO) as Vector2).lerp(target, minf(dt * 6.0, 1.0))


func _draw_unit(e: Entity, sim: Simulation) -> void:
	var feet: Vector2 = _feet(e)
	var a: Dictionary = _anim(e, feet)
	var r: float = Art.unit_radius(e.kind)
	var selected: bool = game.selection.selected.has(e.id)
	var inspected: bool = game.selection.inspected == e.id
	if selected or inspected or e.id == game.hover_id:
		_selection_ring(feet, r + 5.0, selected)
	Art.unit(self, feet, e.kind, e.faction, a.anim, a.dir, a.frame, 1.0, game.flash(e.id))
	var head: float = feet.y - 35.0
	if e.carry > 0:
		Art.icon(self, Vector2(feet.x + 10.0, head + 8.0), e.carry_type, 0.36)
	# Health bars only where they matter (D-48): units hit in the last 3 s,
	# selected or hovered; they fade out instead of cluttering a fight.
	var max_hp: int = sim.stats[e.kind].health
	var since_hit: float = game.time - float(game._hit_time.get(e.id, -100.0))
	var show: float = 1.0 if (selected or inspected or e.id == game.hover_id) else clampf((3.0 - since_hit) / 0.6, 0.0, 1.0)
	if e.hp < max_hp and show > 0.0:
		var ratio: float = float(e.hp) / max_hp
		var bar_col: Color = Palette.health(ratio)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		Art.bar(self, Rect2(feet.x - 11, head - 4, 22, 3), ratio, Color(bar_col, show))


## Which animation, direction and frame to draw, from what the unit does:
## an attack plays once (sword swing or bow shot towards the target), else
## walking cycles with distance moved, gathering and building loop their
## tool animation facing the work, and an idle unit stands facing its last
## direction.
func _anim(e: Entity, feet: Vector2) -> Dictionary:
	var t: float = game.time
	var last: Vector2 = _last.get(e.id, feet)
	_last[e.id] = feet
	var moved: Vector2 = feet - last
	var dir: int = game.facing.get(e.id, UnitSprites.RIGHT if e.faction == "player" else UnitSprites.LEFT)
	var out: Dictionary = {"anim": "walk", "dir": dir, "frame": 0}
	var info: Dictionary = game.attack_info.get(e.id, {})
	var since: float = t - info.t if not info.is_empty() else 99.0
	if e.kind == "melee" and since < SLASH_TIME:
		out.anim = "slash"
		out.dir = UnitSprites.dir_of(info.dir, dir)
		out.frame = int(since / SLASH_TIME * 6.0)
	elif e.kind == "ranged" and since < SHOOT_TIME:
		# Frames 4 to 12: draw, release (frame 8), recover.
		out.anim = "shoot"
		out.dir = UnitSprites.dir_of(info.dir, dir)
		out.frame = 4 + int(since / SHOOT_TIME * 9.0)
	elif moved.length() > 0.03:
		var ph: float = _walk.get(e.id, 0.0) + moved.length() / 4.5
		_walk[e.id] = ph
		out.dir = UnitSprites.dir_of(moved, dir)
		out.frame = 1 + int(ph) % 8
	elif e.phase == "gathering":
		out.anim = "chop" if e.harvest_type == "wood" else "mine"
		var node_p: Vector2 = (Vector2(e.harvest_cell) + Vector2(0.5, 0.5)) * C
		out.dir = UnitSprites.dir_of(node_p - game.draw_pos(e), dir)
		out.frame = int(t * 7.0 + e.id * 1.3) % 6
	elif e.phase == "building":
		var b: Entity = game.sim.entity(e.order_target)
		out.anim = "hammer"
		if b != null:
			out.dir = UnitSprites.dir_of((Vector2(b.cell) + Vector2(b.size) / 2.0) * C - game.draw_pos(e), dir)
		out.frame = int(t * 8.0 + e.id * 1.3) % 6
	elif since < 2.0 and e.kind == "ranged":
		# Between shots an archer keeps the bow raised towards the target.
		out.anim = "shoot"
		out.dir = UnitSprites.dir_of(info.dir, dir)
		out.frame = 4
	elif since < 2.0:
		out.dir = UnitSprites.dir_of(info.dir, dir)
	game.facing[e.id] = out.dir
	return out


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
