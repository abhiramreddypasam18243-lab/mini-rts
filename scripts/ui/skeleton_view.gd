## Walking-skeleton view (build step 1): generates a map with the simulation
## and draws it, while ticking the simulation in real time. It only reads
## simulation state. Replaced by the real game scene in build step 7.
extends Node2D

const BG: Color = Color("12171f")
const GROUND_A: Color = Color("1a2330")
const GROUND_B: Color = Color("1d2735")
const ROCK: Color = Color("3b4554")
const ROCK_EDGE: Color = Color("4a5566")
const WOOD: Color = Color("4cc38a")
const GOLD: Color = Color("f2c14e")
const FACTION: Dictionary = {"player": Color("2ec4b6"), "ai": Color("ff6b6b")}
const TEXT: Color = Color("e6edf3")
const MUTED: Color = Color("8b98a9")

var sim: Simulation
var clock: TickClock = TickClock.new()
var map_seed: int = 2026


func _ready() -> void:
	var r: Dictionary = MapGenerator.generate(map_seed)
	sim = Simulation.new(r.map, map_seed, {})
	get_viewport().size_changed.connect(queue_redraw)


func _process(delta: float) -> void:
	var n: int = clock.advance(delta)
	for i: int in n:
		sim.step()
	if n > 0:
		queue_redraw()


func _draw() -> void:
	var view: Vector2 = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), BG)
	var m: MapGrid = sim.map
	var cell: float = floorf(minf((view.x - 64.0) / m.width, (view.y - 140.0) / m.height))
	var origin: Vector2 = Vector2(floorf((view.x - cell * m.width) / 2.0), 104.0)
	var font: Font = ThemeDB.fallback_font

	draw_string(font, Vector2(origin.x, 52), "MINI RTS", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, TEXT)
	draw_string(font, Vector2(origin.x, 80),
		"Walking skeleton  ·  map %s  ·  tick %d  (%d s)" % [m.map_name, sim.tick, sim.tick / Consts.TICKS_PER_SECOND],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MUTED)

	# Board with a soft shadow.
	var board: Rect2 = Rect2(origin, Vector2(cell * m.width, cell * m.height))
	draw_rect(board.grow(10).grow_individual(0, 0, 0, 4), Color(0, 0, 0, 0.35))
	for y: int in m.height:
		for x: int in m.width:
			var r: Rect2 = Rect2(origin + Vector2(x, y) * cell, Vector2(cell, cell))
			if m.is_walkable(Vector2i(x, y)):
				draw_rect(r, GROUND_A if (x + y) % 2 == 0 else GROUND_B)
			else:
				draw_rect(r, ROCK_EDGE)
				draw_rect(r.grow(-1.0), ROCK)
	for id: int in sim.entities:
		var e: Entity = sim.entities[id]
		if e.is_node():
			var c: Vector2 = origin + (Vector2(e.cell) + Vector2(0.5, 0.5)) * cell
			var col: Color = WOOD if e.kind == "wood" else GOLD
			draw_circle(c, cell * 0.42, col.darkened(0.45))
			draw_circle(c, cell * 0.32, col)
		elif e.is_building():
			var r: Rect2 = Rect2(origin + Vector2(e.cell) * cell, Vector2(e.size) * cell).grow(-cell * 0.12)
			draw_rect(r.grow(cell * 0.12), Color(FACTION[e.faction], 0.18))
			draw_rect(r, FACTION[e.faction])
			draw_rect(r.grow(-cell * 0.35), FACTION[e.faction].darkened(0.35))
		elif e.is_unit():
			# Positions are milli-cells; convert to floats only for drawing.
			var p: Vector2 = origin + Vector2(e.pos) / float(Consts.MILLI_PER_CELL) * cell
			draw_circle(p + Vector2(0, cell * 0.08), cell * 0.3, Color(0, 0, 0, 0.35))
			draw_circle(p, cell * 0.3, FACTION[e.faction].lightened(0.15))
			draw_circle(p, cell * 0.16, FACTION[e.faction].darkened(0.3))
