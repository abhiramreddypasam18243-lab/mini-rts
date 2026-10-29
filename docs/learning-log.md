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

---

## Step 3: Resource manager, harvesting, depletion, drop-off (AC-07, AC-29 to AC-35)

*[LEARN] module: the resource transaction and the production queue accounting. You chose "you write it", so Claude wrote `resource_manager.gd` and the train/cancel accounting in `simulation.gd`. Read both with this entry.*

**What was built**
- `ResourceManager.spend(faction, cost)`: the one transaction. (1) every amount a whole number ≥ 0 naming wood or gold, else `invalid_amount`; (2) every resource affordable, else `insufficient_resources`; (3) deduct all at once. A failed check returns before anything changes.
- A ledger per faction: `deposited`, `spent`, `refunded`, `removed` (taken out of nodes).
- Harvesting as three phases on the worker: `to_node` → `gathering` (40 ticks) → `to_dropoff` → deposit → back to `to_node`.
- `train` pays at enqueue; `cancel_train` removes the item and refunds its full cost.
- `destroy_entity()`: removes an entity and clears every reference to it (used now for exhausted nodes and in tests for a destroyed HQ; combat uses it in step 5).
- `Invariants.check()` now also checks conservation every tick.

**Why it is designed this way (worked examples)**
- AC-32: 100 wood, 100 gold. Melee costs 60 wood + 20 gold → check passes → 40 wood, 80 gold. A second melee needs 60 wood but there are only 40 → `insufficient_resources` and *nothing* is deducted (not even the 20 gold, which would be affordable). That is why both resources are checked before either is deducted.
- AC-33: two workers from 200 wood → 100. Cancel item 1 → item removed, +50 → 150. Cancel item 1 again → there is no item 1 any more → rejected, still 150. The refund can only happen once because the item it belongs to is deleted in the same step.
- AC-07 conservation, per faction and resource: `removed = carried + deposited`, and `stockpile = start + deposited + refunded − spent`. Also, what the nodes lost equals what both factions' workers removed. If any rule in the economy duplicated or lost even 1 unit, one of these equations would break on that tick.
- The worker carries its load through order changes (AC-34): a move order keeps `carry`; the next harvest order first walks to an HQ and deposits.

**One thing that could go wrong**
Refunding without removing the queue item would let a player cancel the same item many times and print money. We planted exactly that bug: AC-33 failed (200 wood instead of 150).

**Quiz questions**
1. Why must `spend()` check that *both* wood and gold are affordable before deducting *either*? Give a cost and stockpile where checking one at a time would go wrong.
2. A node has 15 wood. Two workers gather from it at the same time. How much does each carry home, and which equation in the conservation check would break if the second worker also took 10?
3. Why does the invariant checker recompute carried totals from the units, instead of trusting a counter kept by the simulation?

---

## Step 4: Building placement, construction, production queues, spawning (AC-36 to AC-42)

**What was built**
- `Simulation.placement_check(faction, kind, anchor)`: every footprint cell inside the map, walkable, free of buildings, nodes and units, and explored; then affordable. It changes nothing, so the UI's ghost preview (step 7) can call it every frame.
- `build`: check placement → check the builder can reach the site → pay once through `ResourceManager.spend` → place the building (solid at once) → send the worker.
- Construction: +1 progress per tick while a builder stands beside the building; complete at 300 for a barracks.
- Production: each finished building counts down the first queue item; at 0 the unit spawns in the first free cell of rings 1, 2, 3 around the footprint, row by row.
- `fog.gd`: only the explored grid for now (every cell explored until step 6).

**Why it is designed this way (worked examples)**
- AC-39: train at tick 0 with a 200-tick melee soldier. Each tick removes 1 from `remaining`; after the 200th tick it is 0 and the soldier spawns, so it is absent at tick 199 and present at tick 200. The second item only starts counting on the next tick, so it appears at 400.
- AC-41: if every spawn cell is solid, the finished item stays at the front with status `spawn_blocked` (one message, not one per tick). Its `remaining` stays 0, so it spawns on the very first tick a cell frees. Ring 1 is scanned before ring 2 even if a ring-2 cell is in an earlier row.
- AC-37: the footprint is solid from the placement tick, so moving units re-plan at once (the AC-19 rule from step 2).
- AC-42: a destroyed building takes its queue with it. The money was already counted as `spent`, so the ledger still balances without a refund.

**One thing that could go wrong**
If construction progressed without a builder beside it, a player could place a barracks and walk away. We planted that bug: AC-38 failed (progress 180 instead of holding at 100).

**Quiz questions**
1. A barracks is placed at tick 50 and the builder is already beside it. At which tick does it complete, and at which tick can a melee soldier trained right then appear at the earliest?
2. Why does `build` test the builder's path on a copy of the grid with the footprint already solid, before paying?
3. Two cells free up in the same tick: one in ring 2 at row 3, one in ring 1 at row 4. Where does the waiting unit spawn, and why?

---

## Step 5: Combat, auto-acquire, end of match (AC-43 to AC-53)

**What was built**
- `attack(unit_ids, target_id)`: soldiers only, enemy units or buildings only. A soldier walks towards its target and stops as soon as it is in range.
- Combat in two passes each tick: (1) pick every soldier whose cooldown has run out and whose target is in range *at the start of the tick*; (2) apply the damage in id order.
- Removal of the dead at the end of the tick, through `destroy_entity`, which clears every order that pointed at them.
- Auto-acquire: an idle soldier attacks the nearest enemy within its vision and gives up when the target leaves it.
- End of match: no HQ left → defeat; both in the same tick → `draw`; tick limit → `timeout`. After that, every command returns `match_over` and `step()` does nothing.

**Why it is designed this way (worked examples)**
- Range uses squared integers: melee range 1,500 milli-cells, so 1.0 cell (1,000² = 1,000,000 ≤ 2,250,000) hits and 2.0 cells (4,000,000) does not (AC-43). Ranged 5,000: 5.0 cells hits, 5.1 cells (26,010,000 > 25,000,000) does not (AC-44).
- Cooldown 20: a hit on tick 1 sets it to 20; it counts down once per tick and the next hit lands on tick 21, exactly 20 ticks later. So 300-health barracks ÷ 10 damage = 30 hits, on ticks 1, 21, …, 581 (AC-49).
- Two-pass combat: if A and B (10 health each) both hit each other on the same tick, both were alive at the start of the tick, so both attacks count and both die (AC-46). If they were resolved one by one, the lower id would always win, which is unfair and order-dependent.
- Restart is simply a new `Simulation` from the same map and seed. Because the simulation never modifies the map and keeps no global state, the new one has exactly the hash of a fresh process (AC-53).

**One thing that could go wrong**
Letting an attacker that was killed earlier in the same tick skip its own attack makes the result depend on entity ids. We planted that bug: AC-46 failed ("a died" was false).

**Quiz questions**
1. Three melee soldiers attack a 40-health worker, all in range from tick 1. On which tick does it die, and how many hits land in total?
2. Why must deaths be removed at the end of the tick rather than as soon as health reaches 0?
3. Why does the state hash stop changing after the match ends, and which test checks it?

---

## Step 6: Fog of war and the observation (AC-54 to AC-58)

*[LEARN] module: fog-of-war visibility. You chose "you write it", so Claude wrote `fog.gd` and `observation.gd`. Read both with this entry.*

**What was built**
- `Fog`: per faction, two bitmasks per map row: `visible` and `explored`. `state_of(cell)` reads them as UNEXPLORED / EXPLORED / VISIBLE.
- `update(faction, ...)`, every 5 ticks: rebuild `visible` from scratch from every unit and building, then `explored |= visible`; refresh the memory of enemy buildings and nodes.
- `reveal()`: a new unit or building adds its circle at once.
- `Observation`: the only view the AI will get (step 8): copies of its own units and buildings, visible enemy units, ghosts, remembered nodes, terrain, start positions, its fog grid, the stats.
- `attack` now returns `target_not_visible` for an enemy the faction cannot see now.

**How the visibility test works (worked example, AC-54)**
A cell is visible if `dx² + dy² ≤ vision²` (squared cells, integers only). Unit with vision 6 at (10, 10):
- (10, 16): 0 + 36 = 36 ≤ 36 → visible. (14, 14): 16 + 16 = 32 → visible.
- (10, 17): 49 > 36 → not. (16, 14): 36 + 16 = 52 → not.

**Why it is designed this way**
- *Bitmask rows.* On row offset `dy`, a circle covers one run of cells, `w` either side, where `w` is the largest integer with `w² + dy² ≤ r²` (for r = 6: w = 6, 5, 5, 5, 4, 3, 0 for dy = 0..6). Marking that run is a single OR with a mask of 1-bits from `x0` to `x1`. The first version wrote one byte per cell and took 4.1 ms for 80 units; the bitmask version takes 0.8 ms (AC-58 target 2 ms).
- *Rebuild, then OR.* Rebuilding `visible` from scratch automatically turns cells nobody sees any more into "not visible"; `explored |= visible` means a cell, once seen, can never become UNEXPLORED again (AC-55).
- *Ghosts.* An enemy building is stored as it looked when last seen. It disappears from memory only when its site is visible and the building is gone, so the player never learns about a hidden destruction (AC-56).
- *Observation as copies.* The AI gets duplicates, so it cannot change the game through them, and anything not in the observation (hidden units) simply does not exist for it.

**One thing that could go wrong**
If `update()` started from the old `visible` rows instead of empty ones, cells would stay visible forever after a unit walked past. That leaks hidden enemies into the observation. We planted it: eight checks across AC-55 to AC-58 failed (e.g. "hidden enemy not observed", "last seen health, not the hidden truth").

**Quiz questions**
1. For vision 7, list the half-widths `w` for dy = 0 to 7.
2. A barracks is destroyed while no enemy unit can see it. What does the enemy's observation show for it, and what must happen before the ghost disappears?
3. Why is it acceptable for fog to be up to 5 ticks old, and what would break if it were 100 ticks old?

---

## Step 7: The presentation layer (AC-21 to AC-24, AC-73 to AC-78)

**What was built**
- `Main` → `MainMenu` → `Game`. Restart throws the old `Game` away and builds a new one from the same settings, so nothing can leak between matches.
- `Game` runs the simulation from real time with `TickClock`, turns input into commands with `Selection`, and draws through four layers: `TerrainLayer` (drawn once), `WorldLayer` (units, buildings, nodes, effects), `FogLayer` (soft fog), `OverlayLayer` (drag box, placement ghost, order markers). `Hud` shows counters, the details card, command buttons, the queue, messages and the end screen.
- Pure logic, tested headless: `Selection` (click, box, context orders), `HudModel` (button states and reasons, texts), `MessageLog` (3-second fade), `CameraMath` (clamping, edge panning).
- `Art`: every unit, building, node and icon drawn with shapes in code, shared by the map, the HUD and the menu.

**Why it is designed this way**
- *The UI never changes the game.* It reads the simulation and calls `sim.submit()`. Selection, the camera and effects live only in the UI, so the simulation stays testable and replays stay exact.
- *What you see is what your faction knows.* The world layer draws enemy units only on visible cells and enemy buildings in fog as ghosts from memory (AC-56), and the details card shows a ghost's last-seen health, not the real one.
- *Smooth at any frame rate.* The simulation moves in 20 Hz steps; units are drawn between their last two positions using `TickClock.fraction()`, so movement looks smooth at 60 FPS without changing the simulation.
- *Soft fog for almost nothing.* One texture pixel per cell, stretched with linear filtering and a small blur shader. The GPU does the smoothing.
- *Disabled buttons explain themselves.* `HudModel.train_button()` asks the simulation's own `train_check()` (the same check `train` runs), so the reason shown is exactly the reason the command would be rejected.

**One thing that could go wrong**
In Godot, `set_anchors_preset()` keeps a new control's current size (zero), so "fill the screen" produced nothing; the fix was `set_anchors_and_offsets_preset()`. It was only found by looking at a real screenshot: all headless tests passed, which is why the UI is also checked by eye.

**Quiz questions**
1. Why does a right click on an enemy you cannot see send a move order instead of an attack order?
2. The simulation runs at 20 ticks per second but the screen at 60 frames per second. How are units drawn smoothly, and why does this not affect the state hash?
3. Why is restarting done by building a new `Game` and `Simulation` instead of resetting the old ones?

---

## Step 8: The enemy AI and its tests (AC-59 to AC-67)

*[LEARN] module: the AI's transition function and the observation firewall. You chose "you write it", so Claude wrote `scripts/sim/ai/enemy_ai.gd`, `ai_config.gd`, `scripts/sim/ai_controller.gd` and `Simulation.submit_observed()`. Read them with this entry.*

**What was built**
- `EnemyAI.decide(observation) -> commands`: picks a state by the priority list, then acts. `next_state()` is the transition function on its own, so each row can be tested with a hand-made observation.
- `AIConfig`: the three policies as numbers (Balanced, Aggressive, EconomyFirst).
- `AIController`: every 10 ticks builds the observation, asks the AI, and submits through `Simulation.submit_observed()`, the firewall.
- `MatchRunner`: a whole match headless, for the tests and (in step 9) the experiment.
- The game now has a real opponent, chosen on the main menu; F3 also shows its current state.

**How the transition function works (worked example, AC-62)**
Rows are checked top to bottom; the first that matches wins.
- A visible enemy *soldier* within 8 cells of the HQ → `DEFEND` (row 1; workers are not threats, D-34).
- In `ATTACK` with 6 soldiers at the start (Balanced, retreat 40 %): with 2 left, `2 × 100 = 200 < 40 × 6 = 240` → `RECOVER`; with 3 left, `300 ≥ 240` → keep attacking. Integers only: no 0.4 anywhere.
- 6 soldiers and a known enemy building, in `ECONOMY` → `ATTACK`; 5 workers with 120 wood and 60 gold and no barracks → `BUILD`.

**Why it is designed this way**
- *The firewall has two walls.* (1) The AI's files never mention the simulation; a test reads the source and fails if they do (AC-59). (2) The simulation checks every AI command: any id not in that decision's observation is rejected and counted (AC-61: zero in every match).
- *One command per unit.* Every command is recorded against the units it names, and later behaviours skip those units, so DEFEND and ECONOMY can never give one soldier two orders (AC-63).
- *Sticky states.* Read literally, "otherwise ECONOMY" would cancel an attack 10 ticks after it starts, so ATTACK and RECOVER continue until a row that ends them applies (D-33).
- *Production underneath.* Gathering and training run in every state, so a defending AI still grows its economy; BUILD reserves the barracks money first so training cannot spend it.

**One thing that could go wrong**
If `observation()` leaked hidden enemy units, the AI would be cheating. We planted that leak: the hidden-enemy test (AC-56) and the observation-contents test failed. The metamorphic test (AC-60) did *not* catch it, because this AI happens not to react to far-away enemies: a metamorphic test only catches leaks that change behaviour, which is why the firewall needs several kinds of tests.

**Spec conflict found and resolved (D-34)**
On the tutorial map the two HQs are only 4 cells apart, so with "any visible enemy unit" the player's idle workers kept the AI in DEFEND forever and AC-65 could never pass. Only soldiers count as threats now.

**Quiz questions**
1. The AI is in ATTACK with Aggressive settings (retreat 25 %), started with 4 soldiers, and has 1 left. Does it retreat? Show the integer comparison.
2. Why must `decide()` take only an `Observation` and not the `Simulation`, and how do the tests prove it does?
3. Why did the metamorphic test not catch the planted observation leak, and which test did?

---

## Step 9: Replays, the headless runner, the Wilson interval and the experiment (AC-04, AC-68 to AC-72)

**What was built**
- Replays of real AI matches: `MatchRunner.run(..., keep_replay = true)` returns the JSON-lines log; `Replay.play()` re-submits every command at its tick and reaches the same final hash and result. `Replay.map_for()` rebuilds the map from its name.
- `Experiment`: plays each seed twice with the two policies swapped between the start positions, one CSV row per match with the columns of SPEC 8.
- `tools/run_matches.gd` (the command-line runner, writes rows as matches finish) and `tools/analyze.gd` (the report tables).
- `Stats.wilson()` (95 % Wilson score interval) and `Stats.sign_test()` for the paired comparison.

**Why it is designed this way**
- *Replays are just command logs.* The simulation is deterministic, so the seed, the map and the commands with their ticks are enough to rebuild a whole match; the AI does not need to be re-run. The one subtlety: a command the firewall rejected must not be applied on playback, so it is logged with `"firewall": true` and only re-counted.
- *Swapped sides on every seed.* The maps are point-symmetric, but one start may still be luckier (e.g. which side reaches the middle first). Playing every seed twice, once from each start, cancels that out, and Balanced vs Balanced checks it: its interval must contain 0.5 (AC-71).
- *Wilson, not the normal approximation.* For 0 wins out of 10 the normal approximation gives [0, 0], claiming certainty; Wilson gives [0, 0.28]. It stays inside [0, 1] and is still right for small samples and extreme rates (D-13).
- *Speed.* A full 30-minute match runs headless in about 7.8 s (AC-69), so hundreds of matches take minutes, not days.

**One thing that could go wrong**
Mixing up which side won: the simulation reports "victory_player" or "victory_ai" (start positions), but the experiment needs "A" or "B" (policies), which swap starts every other match. A swapped mapping would silently invert every conclusion. A dedicated test pins the mapping, and we planted the swap to check it fails.

---

## Step 10: Production deployment and documentation (AC-79 to AC-96)

**What was built**
- A strict Content-Security-Policy: `tools/csp_hash.gd` runs in the Docker build after the export, hashes the page's one inline `<script>` and one inline `<style>` (SHA-256, base64), and writes the header nginx includes. No `'unsafe-inline'`.
- An asset-licence check (`test_assets.gd`) that fails CI if a file in `assets/` is not in `ASSETS.md`.
- The demo (AC-93): `tools/make_demo.gd` records an Aggressive vs Balanced match; the main menu's **Watch demo** plays it back at 2× with fog off and a camera that follows the fighting; the viewer cannot issue commands.
- `README.md`, `docs/architecture.md`, `docs/test-plan.md` (generated from the spec and the test names), and tests that keep them complete.

**Why it is designed this way**
- *Hashes instead of 'unsafe-inline'.* 'unsafe-inline' would let any injected script run. A hash allows exactly the code Godot generated and nothing else. The hash changes whenever the exported page changes (the page embeds build details), so it is computed during the build, never by hand.
- *The demo is a replay, not a video.* Because the simulation is deterministic, the 19 KB command log rebuilds the whole match in any browser, and the same file is checked by a test.
- *Documents are tested too.* The test plan must list every acceptance test that exists, so adding a test without documenting it fails the build.

**One thing that could go wrong**
Playing back a replay while the viewer can still issue commands would change the match and break the replay. In demo mode `Game.issue()` refuses every command, and a test checks it.

---

## Step 11 (stretch): the minimap (decision D-43)

**What was built**
- `scripts/ui/minimap.gd`: a small picture of the whole map in the HUD's bottom-right corner. Terrain is drawn once into a tiny image (one pixel per cell, scaled up); the fog is a second tiny image recoloured only when the simulation's fog changes; units, buildings and nodes are small squares drawn every frame; a white frame shows what the camera sees; red rings ping fights.
- Left click or drag moves the camera; right click sends the selected units there with the same context order as a right click on the map.

**Why it is designed this way**
- *The minimap obeys the fog exactly like the main view.* `markers()` uses the same rules: nodes and enemy buildings as the player remembers them, enemy units only in cells visible now. A minimap that showed everything would let the player cheat in a way the AI cannot (the AI's observation firewall, AC-59 to AC-61); a test checks that no hidden enemy unit appears.
- *Orders reuse the existing path.* A right click on the minimap converts the minimap position to a world position and calls the same function as a right click on the map, so move, harvest and attack keep their rules, and the simulation needs no new command.
- *Cheap to draw.* The two images are the size of the map in cells (48 × 48 pixels), so updating them costs almost nothing; only the markers change every frame.

**One thing that could go wrong**
The camera frame and the click mapping depend on the zoom. If the zoom changes (as it did from 1.35 to 1.6 in D-42) and only one of them is updated, clicks land beside where the frame says. Both use `Game.view_rect()` / `to_world()` from the same numbers, and a test clicks the minimap's centre and checks the camera ends up at the map's centre.

---

## Step 11 (stretch): attack-move and Shift-queued orders (decision D-44)

**What was built**
- A new command, `attack_move(unit_ids, cell)`, and an optional `queue: true` flag on move, attack-move, attack and gather orders.
- In the simulation: soldiers on an attack-move scan for enemies every tick like idle soldiers do; when they fight, `am_cell` remembers where they were going, so they carry on afterwards. Each unit has a small queue (`orders`, at most 8); at the start of each tick an idle unit resumes an interrupted attack-move, or else takes its next queued order.
- In the game: `F` then click (also on the minimap) attack-moves the selection; holding Shift queues any order; dashed lines show each selected unit's route.

**Why it is designed this way**
- *A plain order still replaces everything* (D-14). Only an order that explicitly says `queue` waits, so every earlier test and the AI behave exactly as before.
- *Queued orders are ordinary commands.* They are checked twice: as far as possible when given (is the cell a cell, does the target exist), and fully when they run (is the target still visible, is there a path). An order that cannot run any more is skipped, never half-applied.
- *Dead targets leave the queue at once*, in the same place that clears current orders, so "every order refers to a living entity" (AC-06, AC-48) also holds for queued orders.
- *Replays need nothing new.* The queue flag is part of the command's arguments, which the replay already records; the simulation is deterministic, so playback queues the same orders at the same ticks (a test runs a match twice and compares the state hash).

**One thing that could go wrong**
An attack-move soldier that loses sight of its target and goes idle could also be picked up by the "step aside" spacing rule (D-42) or by a queued order. Order matters: at the start of a tick an interrupted attack-move is resumed *before* the queue is read, and spacing only moves units that are still idle later in the tick, so the soldier always carries on with its attack-move first.

---

## Step 11 (stretch): phone and tablet controls (decision D-45)

**What was built**
- `scripts/ui/touch_input.gd` decides when touch mode is on (Android or iOS browser, a mobile build, `?touch` in the address, or the first real touch) and scales the interface for small screens.
- In `game.gd`: one finger dragging pans the map; a tap selects your own unit or building, and a tap anywhere else orders the selected units there with the same context order as a right click. A toolbar (Box select, All soldiers, Attack-move, Queue, Cancel) replaces the keys and the right mouse button. Building takes two taps: the first places the preview, the second on the same spot builds.
- The menu is compacted on phones, the bottom panel moves to the left, and a notice asks to turn the phone sideways in portrait.

**Why it is designed this way**
- *Touch arrives as mouse events.* Godot turns each touch into left-button mouse events by default, so every HUD button, the minimap and the menu work unchanged; only taps and drags on the map needed new rules.
- *Tap = select own, order elsewhere.* A phone has no right button, so "tap my unit" and "tap where it should go" must both be single taps. The rule is simple to explain: your own things are selected, everything else is a destination or a target.
- *Two taps to build.* A finger covers the spot it touches, so the first tap shows the barracks (green or red, with the reason) where it would go, and only a second tap on the same spot spends the resources.
- *No new simulation commands.* Touch only changes how commands are made, so the rules, the AI and every acceptance test stay the same.

**One thing that could go wrong**
Edge panning reads the mouse position. On a phone the "mouse" stays where the finger last touched, so a tap near the screen edge would pan the map forever. Edge panning is switched off in touch mode.

---

## Fix: the game closing on iPhones (decision D-46)

**What happened**
On an iPhone, Safari showed "A problem repeatedly occurred". iOS closes a web page that uses too much memory and reloads it; when that keeps happening it gives up with that message. The emulated phone on a laptop did not show it, because a laptop browser has far more memory.

**What was measured and changed**
- A match drawn at an iPhone's real resolution (2532 x 1170, three screen pixels per point) used about 180 MB of graphics memory; the pre-drawn ground alone was 33 MB.
- Phones now render at normal density (844 x 390), the ground is pre-drawn at 1x, the full-screen colour grade is skipped, and the ground's thousands of drawing commands are freed once drawn. A match now uses about 70 MB.

**One thing that could go wrong**
Testing on a desktop browser that pretends to be a phone checks the layout and the controls, not the phone's limits: memory, speed and graphics drivers. Only a real phone can confirm those.


---

## More gameplay: food, farms, guard tower, cavalry, upgrades (decision D-51)

**What was built**
- **Food**, a third resource (start 100). A worker builds a **farm** like a barracks; a finished farm holds 400 food that its own side's workers gather like a node (10 per trip), and it disappears when empty.
- A **guard tower** shoots the nearest enemy unit within 6 cells for 6 damage every 30 ticks.
- A **stable** trains **cavalry**: the fastest unit (4 cells/s), 120 health, paid in gold and food.
- **Forging** (+2 soldier damage) and **Armour** (−2 damage taken per hit, never below 1), researched once at a barracks.
- The AI builds all of these and uses them; the strategy experiment was re-run on the new rules.
- Art: the farm, tower and stable are rendered from Kenney's 3D kits; cavalry is the KayKit knight seated on Quaternius's CC0 horse, with the knight's sitting legs combined with the sword swing.

**Why it is designed this way**
- *Nothing old changed.* Existing units cost no food, and a cost lists food only when it is above 0, so all 96 earlier acceptance criteria keep their numbers.
- *A farm is a building that also acts like a node.* Harvesting asks `is_harvestable()` (a node, or a finished farm), so the harvest, drop-off and replacement code is shared instead of copied.
- *Conservation still holds.* Food enters the world when a farm is finished (`node_added`) and leaves it when a farm is destroyed with food left (`node_razed`); the invariant checks `start + added − razed − left == removed by workers`.
- *Research uses the production queue*, so paying, refunding on cancel and the queue limit all reuse the code tested for training. Research items do not count towards the population.
- *A tower is a building with a target.* It reuses the combat step: the same cooldown, the same "damage after everyone has chosen" rule.

**One thing that could go wrong**
The AI's extra buildings cost resources it used to spend on soldiers, so a policy can become weaker without any rule being wrong. That is why the experiment was re-run instead of assuming the old results still hold.

---

## Difficulty, map styles, conveniences and the auto-economy supervisor (D-52 to D-55)

**What was built**
- **Difficulty** Easy / Normal / Hard on top of any AI policy, chosen in the menu.
- Two more **map styles**: *River crossing* (three fords) and *Highlands* (ridges and extra gold).
- **Conveniences:** control groups, an idle-worker key and button, rally points, and "Under attack!" alerts.
- **Auto economy:** a helper AI that runs the player's economy while the player commands the army.

**Why it is designed this way**
- *Difficulty never cheats.* Every level sees only its Observation; Hard plays better instead of seeing more or gathering faster.
- *Measure, don't assume.* Each Hard idea was played against Normal before it was kept. Three of them (chasing the weakest enemy anywhere, cavalry raids, early research) made the AI lose more, so they were dropped. The final Hard is only slightly stronger, and the report says so.
- *The supervisor is the enemy AI with fewer jobs.* `EconomyHelper` extends `EnemyAI` and reuses its gathering and building code, and it goes through the same firewall, so it cannot touch the army or see hidden things.
- *Conveniences change no rules.* Rally points and groups only create ordinary commands, so replays and determinism are unaffected.
- *New maps reuse the generator's checks.* They mirror every cell through the centre, and the same connectivity and resource checks apply, so fairness can be measured the same way.

**One thing that could go wrong**
A helper that issues commands for the player can fight the player's own orders: a worker the player just moved could be sent to gather again. The helper only touches workers that are *idle*, so an order the player gives is never overridden.

---

## Making the game easier to play (decision D-56)

**What was built**
- **Peace time:** in games from the menu, the AI may not attack for 6 / 3 / 1.5 minutes (Easy / Normal / Hard), with a countdown. The menu starts on Easy, and Easy now trains one unit at a time per building.
- **Less micro-management:** new workers and builders who finish a building start gathering by themselves. Double-click selects all units of that kind on screen, Ctrl+A selects every soldier, and the click area round a unit is larger.
- **Easier to see:** units are drawn about 30 % larger, the mouse wheel zooms, units have bold team rings (enemies an extra red ring), and health bars always show during fights.

**Why it is designed this way**
- *Peace time belongs to the game, not the rules.* It is set only for games started from the menu (`AIConfig.for_game`). The presets used by the experiment and the tests keep 0, so every measured result stays valid.
- *A test found a hole.* The first version only blocked the AI's ATTACK state, but its scout still walked to the player's base and fought there at about 50 seconds. The test checks the first hit on the player, not just the state, so it caught this; now there is no scouting during peace time either.
- *Auto-gather is a presentation helper.* It issues ordinary harvest commands for the player, like the rally point, and it only chooses nodes the player has seen, so it reveals nothing the fog hides.

**One thing that could go wrong**
The fast test suite is close to its 2-minute limit (AC-89), because each new AI feature adds whole matches to the tests. A duplicate test was removed and one count lowered. More match-level tests should go in the long suite.

---

## Better fight scenes and the cavalry charge (decision D-57)

**What was built**
- **One rule:** a cavalry charge. The first hit after a cavalry unit has moved at least 3 cells since its last hit deals double damage.
- **Impact:** soldiers lunge into each swing and the unit hit is knocked back a few pixels. Kills on screen jolt the camera slightly. Charging cavalry raise a dust trail and show "Charge!".
- **Cinematic camera:** an HQ falls in slow motion with the camera on it. Finished battles are summarised ("Battle won: 4 enemies killed, 1 of yours lost"). A battle camera (K) drifts to the biggest fight when the player leaves the camera alone.

**Why it is designed this way**
- *The charge is an integer the simulation tracks.* `Entity.charge` adds up the milli-cells moved and is reset by any hit, so the rule stays deterministic and is part of the state hash. The visuals read the same number, so the dust trail appears exactly when the next hit will be doubled.
- *Everything else changes only the drawing.* Lunges and knock-backs move the sprite, not the unit, so combat ranges and tests are unaffected. Slow motion only slows how fast the presentation feeds ticks to the simulation, never the rules.
- *A battle is a cluster in space and time.* `BattleTracker` groups hits and deaths within 8 cells and ends a battle after 4 quiet seconds. It is plain logic with no drawing, so it is tested headless.

**One thing that could go wrong**
An automatic camera can fight the player for control. The battle camera moves only after 5 seconds without camera input, and never while the player is dragging, placing a building or aiming. It can be switched off with K.

---

## New grass texture (decision D-58)

**What was built**
The ground's grass texture is now ambientCG Grass007 (clover, weeds and twigs) instead of Grass004. The roads, earth patches, colour grade and game rules are unchanged.

**Why it is designed this way**
- *The choice was made from in-game screenshots.* Eight candidates were rendered on the same map and seed, with only the texture swapped, so the comparison showed exactly what the player would see.
- *Only one file changed.* The ground shader tiles whatever image is in `assets/textures/grass.jpg`, so a texture change needs no code change. Its source and licence are recorded in `ASSETS.md`.
- *Tall wind-swaying grass was tried and dropped.* Separate tufts drawn on top of the ground looked like clumps stuck on, not a field.

**One thing that could go wrong**
A busier texture can hide small things on the ground, such as pebbles and dropped details, and make a large field look repetitive. The shader samples the texture at two scales and blends them, which hides the tiling.

---

## Soldiers help each other (decision D-59)

**What was built**
When something of the player's is hit, every idle soldier of the player's within 10 cells attack-moves to the fight. They go to the attacker if the player can see it, otherwise to the unit that was hit.

**Why it is designed this way**
- *The cause was vision, not a bug in combat.* An idle soldier reacts only to enemies inside its own 6-cell vision. An archer shoots from 5 cells, so a teammate standing a few cells away often never saw the attacker and stood still.
- *It is a player-side helper, like auto-gather.* `CommandAids.help_command` reads the hit event and builds one ordinary attack-move command. The simulation's rules do not change, so the AI, the replays and the experiment are unaffected.
- *Only idle soldiers are sent.* A soldier the player has given an order keeps it. Once the helpers are on their way they are no longer idle, so the next hit does not order them again.

**One thing that could go wrong**
A weak unit hit far from the main army can pull nearby idle soldiers into a bad fight, for example into range of an enemy tower. The 10-cell radius keeps this local, and the player can always give new orders.

---

## Online play against a friend (decision D-60)

**What was built**
- **Lockstep** (`scripts/net/lockstep.gd`): both computers run the same simulation and send each other only their commands, cut into turns of 3 ticks (150 ms).
- **A relay server** (`relay/server.js`): it pairs the two players by a 4-letter room code and forwards their messages.
- **A menu panel** to host or join a match. The host plays Blue, the guest Red.

**Why it is designed this way**
- *Determinism made it cheap.* The simulation was integer-only and deterministic from step 1 (D-02, D-16). The same commands at the same ticks always give the same game, so only commands need to travel, a few bytes per turn, never the positions of units.
- *Commands run 2 turns late.* A command given in turn T is sent as part of turn T + 2, which gives it 300 ms to reach the other computer. Turn T runs only when both players' commands for it are known, so neither computer ever guesses.
- *Both sides submit identical values.* Commands travel as JSON, where numbers become floats, so the sender also passes its own commands through JSON before running them. That way both computers submit exactly the same data.
- *Drift is detected, not hoped away.* Every turn message carries the sender's state hash. If the hashes for the same turn differ, the game shows a "went out of step" warning.
- *The relay is dumb on purpose.* It never looks inside the messages, so it cannot cheat, and the game's rules are tested where they always were.

**One thing that could go wrong**
Anything that changes the simulation outside the shared commands would make the two games drift. The auto-economy helper used to submit straight to the simulation. In online matches its commands now go through the lockstep like the player's, and the end-to-end test (`tools/net_smoke.gd`) compares the two games' state at every tick.

---

## Soldiers fight back on the move (decision D-61)

**What was built**
A soldier of yours that is walking somewhere and gets hit now turns and attacks the enemy that hit it. If you then order it to move again, it retreats and does not turn back until it arrives.

**Why it is designed this way**
- *The rule was strict on purpose.* SPEC 5.5 lets only idle soldiers and attack-moves pick fights, so a plain move means "go there, whatever happens". That is predictable, but players expect a soldier being hit to defend itself.
- *A retreat must stay possible.* If every hit turned a soldier around, you could never pull an army out of a lost fight. So a move given while a soldier is fighting back counts as a retreat (`CommandAids.note_retreat`).
- *It is a player-side helper, like D-59.* `CommandAids.fight_back_command` turns a hit event into one ordinary attack command. The simulation rules, the AI and the experiment do not change, and in online games the command goes through the lockstep like any click.

**One thing that could go wrong**
A soldier walking past an enemy tower could be dragged into a hopeless fight. Hits from buildings therefore never turn a soldier; only enemy units do.

---

## The whole battalion answers a hit soldier (decision D-62)

**What was built**
When one of your soldiers is hit, every idle soldier of yours, anywhere on the map, attack-moves to the fight. A hit worker or building still calls only idle soldiers within 10 cells.

**Why it is designed this way**
- *It is one condition in the existing helper.* `CommandAids.help_command` already gathered idle soldiers near a hit. It now skips the distance check when the victim is a soldier.
- *Your orders still win.* Only idle soldiers are sent, so soldiers you have sent elsewhere keep going, and a soldier already on its way is not ordered again by the next hit.
- *Workers keep the local rule.* An enemy archer picking at a woodcutter should not pull the whole army away from the base.

**One thing that could go wrong**
Every idle soldier leaving for one skirmish leaves the base empty. A feint at one corner can draw the army away from the real attack. Keep a few defenders busy, for example on a Shift-queued patrol route, if that matters.
