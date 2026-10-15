# Learning Log

One entry per build step: what was built, why, one thing that could go wrong, and three quiz questions (answer them yourself).

---

## Step 1: Project setup, simulation skeleton, maps, container (AC-01 to AC-05, AC-08 to AC-11)

**What was built**
- `Simulation` (`scripts/sim/simulation.gd`): a tick counter, the match seed's generator, `submit()` that records every command with its result code, and `state_hash()`.
- `SimRng`: our own 32-bit linear congruential generator, `state = (state · 1664525 + 1013904223) mod 2³²`, with the seed scrambled first.
- `StateHasher`: FNV-1a over integers, written by hand so the hash depends only on our code.
- `UnitStats` loads `data/units.json`; `MapGrid` loads and validates JSON maps; `MapGenerator` makes point-symmetric 48 × 48 maps.
- `Replay`: JSON-lines command logs that replay to the same hash.
- `TickClock` (UI layer): turns frame time into whole ticks, counting in integer microseconds.
- Web export preset (Compatibility renderer, threads off), a two-stage `Dockerfile`, nginx config, `docker-compose.yml`.

**Why it is designed this way**
- Everything that affects the game is an integer and comes from the seed plus the commands. So a match is a pure function of (seed, map, commands), which is what makes replays, determinism tests and the AI experiment possible.
- The generator keeps every product below 2⁶³ (`state < 2³²`, multiplier `< 2²¹`), so there is never an integer overflow, and every platform gives the same numbers.
- JSON numbers arrive as floating-point values in Godot. `JsonUtil` is the single gate that accepts only whole numbers and converts them to `int`.
- The map generator mirrors every rock and node through the map centre, and only accepts a map when an independent check passes (HQs connected, 2 wood + 1 gold within 15 path steps). Then neither side starts with an advantage.

**One thing that could go wrong**
Mirroring a multi-cell building by its anchor is wrong: a 3 × 3 HQ anchored at `(x, y)` mirrors to `(45 − x, 45 − y)`, not `(47 − x, 47 − y)`, because the anchor is the top-left cell and the mirror's top-left comes from the original's bottom-right (decision D-22).

**Quiz questions**
1. If the browser drops to 10 frames per second for one second, how many ticks run in that second, and why does the state hash still match a run at 60 frames per second?
2. Why do we use the top 16 bits of the generator's state rather than the bottom bits?
3. Why must the two HQs in a generated map be checked for a connecting path, and why is a breadth-first search enough for that check?

---

## Step 2: Entities, A* and movement, commands, invariant checker (AC-06, AC-12 to AC-20, AC-25 to AC-28)

*[LEARN] module A\*: you chose "you write it", so Claude wrote `pathfinder.gd`. Read it with this entry before the viva.*

**What was built**
- `Pathfinder.find_path(w, h, solid, start, goal)`: A* on a 4-direction grid; returns the path (start to goal) and how many cells it expanded.
- `Entity`: one class for units, buildings and resource nodes, each with a single current order.
- `Movement`: walks a unit from cell centre to cell centre at its speed (milli-cells per tick).
- `Commands`: builders for the six commands; `Simulation.submit()` validates them in a fixed order.
- `Invariants.check(sim)`: recomputes the rules from scratch every tick in the fuzz test.

**How A\* works (worked example, AC-13)**
- Each cell `n` has `g(n)` = steps from the start, `h(n)` = Manhattan distance `|dx| + |dy|` to the goal, and `f = g + h`.
- The open set is a min-heap ordered by `f`, then `h`, then insertion order. Repeatedly take the smallest; if it is the goal, follow `came_from` back to the start. Otherwise try its neighbours (up, right, down, left) and record any shorter `g`.
- 10 × 10 grid, wall at x = 5 for y = 0..8. From (0, 0) to (9, 0), `h(start) = 9`, but the wall forces the route down to the gap (5, 9): 9 down + 9 right + 9 up = **27 steps**. A* expands cells with `f = 9` first, finds the wall, and the `f` values grow until the route through the gap is the cheapest.
- Manhattan never overestimates for 4-way moves (admissible), and changes by at most 1 per step (consistent). So the first time a cell leaves the heap its `g` is final, and the path is shortest. AC-15 checks this against breadth-first search on 200 (fast) / 1,000 (long) random grids.

**Why it is designed this way**
- The open-set key packs `(f, h, seq)` into one integer, so one comparison orders it and ties always break the same way (AC-17).
- Old heap entries are skipped when popped ("lazy deletion") instead of being updated in place: simpler, and still correct.
- Movement carries leftover distance round corners, so a unit covers exactly `speed × ticks` along the path. 15 cells × 1,000 / 150 = 100 ticks (AC-25).
- When a building is placed, every moving unit checks the rest of its path; if a cell turned solid it re-plans, and if no route is left it goes idle with one `no_path` (AC-19).

**Measured:** worst-case 48 × 48 path (a serpentine maze, 1,175 steps) takes **2.0 ms** on average in GDScript (AC-18 target ≤ 5 ms).

**One thing that could go wrong**
An inadmissible heuristic (one that overestimates, e.g. `3 × Manhattan`) makes A* faster but returns paths that are too long. We planted exactly this bug and the test suite failed (exit code 1), so the tests guard against it.

**Quiz questions**
1. In the AC-13 grid, what is `f` of the start cell, and what is `f` of the gap cell (5, 9) when it is first reached by the shortest route?
2. Why can a heap contain two entries for the same cell, and why is it safe to skip the second one when it is popped?
3. A worker is halfway between two cells when you give it a new order. Which cell does the new path start from, and why does it never step through a blocked cell?
