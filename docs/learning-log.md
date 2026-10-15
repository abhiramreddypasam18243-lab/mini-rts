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
