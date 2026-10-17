## Draws everything on the board the player may see, every frame
## (presentation layer; reads the simulation, never changes it):
## remembered resource nodes, own and visible buildings, ghosts of enemy
## buildings in fog, own and visible units (sorted by height so lower ones
## overlap upper ones), and short combat effects.
class_name WorldLayer
extends Node2D

const C: float = Consts.PIXELS_PER_CELL

var game: Game


func _draw() -> void:
	if game == null or game.sim == null:
		return
	var sim: Simulation = game.sim
	var f: String = game.faction
	var t: float = game.time
	var mem: Dictionary = sim.fog.memory[f]

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

	_draw_effects()


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
	var p: Vector2 = game.draw_pos(e) + offset
	var r: float = Art.unit_radius(e.kind)
	var selected: bool = game.selection.selected.has(e.id)
	var inspected: bool = game.selection.inspected == e.id
	if selected or inspected or e.id == game.hover_id:
		var pulse: float = 0.75 + 0.2 * sin(game.time * 5.0)
		var col: Color = Color(1, 1, 1, pulse) if selected else Color(Palette.TEAM_LIGHT[e.faction], 0.5)
		draw_set_transform(p + Vector2(0, r * 0.55), 0.0, Vector2(1.0, 0.55))
		draw_arc(Vector2.ZERO, r + 6.0, 0.0, TAU, 40, col, 2.2, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	Art.unit(self, p, e.kind, e.faction, r, 1.0, game.flash(e.id))
	if e.carry > 0:
		var cp: Vector2 = p + Vector2(r * 0.78, -r * 0.7)
		draw_circle(cp, 4.2, Palette.BG, true, -1.0, true)
		draw_circle(cp, 3.2, Palette.resource(e.carry_type), true, -1.0, true)
	var max_hp: int = sim.stats[e.kind].health
	if e.hp < max_hp or selected:
		var ratio: float = float(e.hp) / max_hp
		Art.bar(self, Rect2(p.x - 11, p.y - r - 8, 22, 3), ratio, Palette.health(ratio))


func _draw_effects() -> void:
	var font: Font = UiTheme.font("bold")
	for fx: Dictionary in game.fx:
		var age: float = game.time - fx.t0
		var k: float = clampf(age / fx.life, 0.0, 1.0)
		match fx.type:
			"tracer":
				var a: Vector2 = fx.a
				var b: Vector2 = fx.b
				var head: Vector2 = a.lerp(b, minf(k * 1.4, 1.0))
				var tail: Vector2 = a.lerp(b, maxf(k * 1.4 - 0.35, 0.0))
				draw_line(tail, head, Color(Palette.TEAM_LIGHT[fx.faction], 1.0 - k), 2.0, true)
			"slash":
				var c: Vector2 = fx.b
				draw_arc(c, 9.0 + 6.0 * k, -2.4, -0.6, 10, Color(1, 1, 1, 0.9 * (1.0 - k)), 2.2, true)
			"puff":
				draw_arc(fx.a, 6.0 + 22.0 * k, 0.0, TAU, 32, Color(fx.color, 0.7 * (1.0 - k)), 3.0 * (1.0 - k) + 0.5, true)
				draw_circle(fx.a, 10.0 * (1.0 - k), Color(fx.color, 0.25 * (1.0 - k)), true, -1.0, true)
			"float":
				var p: Vector2 = fx.a + Vector2(0, -24.0 * k)
				var s: String = fx.text
				var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
				draw_string_outline(font, p - Vector2(w / 2.0, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.7 * (1.0 - k)))
				draw_string(font, p - Vector2(w / 2.0, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(fx.color, 1.0 - k))


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
