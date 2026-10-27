# Mini RTS — Complete Session Transcript

**Date:** 2026-10-27  
**Topic:** Mini RTS Project Deep-Dive, Codebase Review, Architecture, and Viva Defense Preparation  
**Engine:** Godot 4.7.2-stable (GDScript)  
**Status:** Verified (252/252 GUT unit tests passing)

---

## Turn 1

### User
once completely go through this project

### Assistant
I have inspected the environment, verified the workspace, and executed the automated test suite headless via Godot 4.7.2 and GUT 9.6.1 in WSL:

- **Test Scripts:** 30
- **Total Tests:** 252 (covering AC-01 to AC-109)
- **Passing Tests:** 252 (100% pass rate)
- **Total Assertions Verified:** 29,188
- **Working Tree:** Clean (all commits tracked, no untracked diffs)

### Architecture Summary (Two-Layer Pattern)
The codebase strictly separates the deterministic mathematical simulation from visual presentation:
1. **Simulation Core (`scripts/sim/`):** Extends `RefCounted` only (no Nodes, no SceneTree, no Godot clock, no `randi()` / `randf()`). Operates in discrete ticks at 20 Hz. Positions are stored as integer milli-cells (1,000 milli-cells = 1 grid cell), distances are compared as squared integers, and time is measured in ticks. Deterministic PRNG via a custom Linear Congruential Generator (`SimRng`) and custom 64-bit FNV-1a hashing (`StateHasher`).
2. **Presentation Layer (`scripts/ui/`, `scenes/`):** Inherits Godot UI and 2D nodes. Converts real delta time into integer ticks using `TickClock`. Interpolates entity positions between simulation ticks using `TickClock.fraction()` for 60+ FPS visuals. Never mutates simulation state directly; communicates strictly via `sim.submit(command)`.

---

## Turn 2

### User
once explain me this project

### Assistant
Here is a clear, viva-ready walkthrough of **Mini RTS**: what it is, how it works under the hood, why it was designed this way, and the core concepts you need to know.

### 1. The 30-Second Pitch
**Mini RTS** is a deterministic, real-time strategy game built in **Godot 4.7.2** (GDScript). You command workers to gather resources (wood, gold, food), construct buildings (barracks, farms, guard towers, stables), train an army (swordsmen, archers, cavalry), research upgrades (forging, armour), scout through fog of war, and destroy the enemy Headquarters (HQ).

Beyond being a playable game, it is an **algorithmic testbed**:
- The game rules are completely decoupled from graphics in a **pure deterministic mathematical simulation**.
- It runs automated matches **200× faster than real-time** without a display.
- It includes a documented **800-match academic experiment** comparing AI policies using statistical confidence intervals.

### 2. The Core Architecture: The Two-Layer Pattern
- **Simulation Core (`scripts/sim/`):** Pure RefCounted classes, 20 ticks/sec, integer math only (milli-cells, ticks, squared distances), seeded `SimRng`, FNV-1a state hashing, invariant checks.
- **Presentation (`scripts/ui/`):** Godot Nodes, floating-point drawing, camera math, interpolation smoothing, input handling.

### 3. Key Algorithms & Systems
- **A\* Pathfinding (`pathfinder.gd`):** 4-way orthogonal grid using Manhattan distance heuristic (admissible and consistent). Binary min-heap packing $(f, h, \text{seq})$ into a single 64-bit integer for single-comparison ordering and deterministic tie-breaking.
- **Resource Manager & Conservation (`resource_manager.gd`, `invariants.gd`):** Atomic spend checks; invariant equations verify every tick that resources in stockpiles, nodes, worker carry, and lost items strictly balance.
- **Fog of War (`fog.gd`):** Rows stored as 64-bit integer bitmasks. Recomputed every 5 ticks. Memory ghosts track buildings outside vision until scouted.
- **Enemy AI & Firewall (`enemy_ai.gd`, `observation.gd`):** FSM evaluating states in priority: DEFEND, RECOVER, ATTACK, BUILD, ECONOMY. Observation firewall guarantees the AI cannot cheat through fog.
- **Two-Pass Combat (`simulation.gd`):** Simultaneous calculation of attackers followed by damage application in ID order, preventing lower ID bias.

### 4. Scientific Experiment
800 headless matches showed: Aggressive won 86.4% vs Balanced, Balanced won 70.9% vs EconomyFirst, and Aggressive won 95.9% vs EconomyFirst. On small maps, early rushing beats economic booming.

---

## Turn 3

### User
what are sources from whuich data is taken

### Assistant
All data, assets, and rules come from well-documented, openly licensed sources, strictly allowlisted in `ASSETS.md` and verified by automated CI tests (`test_assets.gd`):

1. **Game Rules, Specifications & Balance Data:**
   - **Project Guide:** `docs/Mini_Real_Time_Strategy_Game_Project_Guide.docx` codified into `SPEC.md`.
   - **Unit & Building Stats:** `data/units.json` defining costs, HP, speed, vision, damage, range, cooldown, build times, footprints.
   - **Maps:** `data/maps/tutorial.json` and algorithmic procedural generation (`map_generator.gd`).
   - **Replay Data:** `data/replays/demo.replay.jsonl`.
2. **Visual & Audio Assets (`assets/`):**
   - **3D Character Models:** KayKit Adventurers 1.0 (Barbarian, Knight, Rogue) by Kay Lousberg (CC0 1.0).
   - **Cavalry Horse:** Lowpoly Animated Farm Animals by Quaternius (CC0 1.0).
   - **Pre-rendered Sprites:** Rendered into 8 directions with soft shadows via `tools/render_3d.gd`.
   - **Buildings & Props:** Kenney 3D Castle Kit, Fantasy Town Kit, Nature Kit (CC0 1.0).
   - **Terrain Textures:** ambientCG PBR maps (Ground054, Grass004, Ground037) (CC0 1.0).
   - **UI & Particles:** Kenney UI Pack: RPG Expansion & Particle Pack 1.1 (CC0 1.0).
   - **Audio & Music:** Kenney Impact, RPG, and Interface Sounds; Music by cynicmusic ("Town Theme RPG", "Battle Theme A") (CC0 1.0).
   - **Fonts:** Cinzel and Alegreya Sans (SIL Open Font License 1.1).
3. **Experimental Research Data (`docs/experiment/`):**
   - 800 automated headless simulations across 100 seeds generated by `tools/run_matches.gd` and analyzed via `tools/analyze.gd`.
4. **Software & Dependencies:**
   - Godot Engine 4.7.2-stable (MIT), GUT 9.6.1 (MIT), Nginx unprivileged container (BSD-2-Clause).

---

## Turn 4

### User
how does this project works

### Assistant
A detailed walkthrough of the game's execution lifecycle:

1. **Initialization:** `MainMenu` instantiates `Game.gd`, which constructs `Simulation.gd`. The map is generated or loaded, starter HQs, workers, and resource nodes are placed, and fog of war is initialized.
2. **The 20 Hz Heartbeat (`TickClock`):** In `_process(delta)`, `TickClock.advance(delta)` counts microseconds and calculates the integer simulation ticks due. For each tick due, the AI decides (every 10 ticks) and `sim.step()` runs.
3. **Inside `sim.step()`:**
   - Re-plans blocked paths if terrain changed.
   - Executes queued orders and resumes interrupted attack-moves.
   - Auto-acquires visible enemies for idle soldiers.
   - Resolves two-pass simultaneous combat.
   - Ticks units in ID order (movement, harvesting, building, attacking, cavalry charge).
   - Resolves unit spacing (`step_aside()`) every 2 ticks.
   - Progresses building construction, countdown queues, and spawns units.
   - Removes dead entities and cleans references.
   - Checks victory/defeat/timeout conditions.
   - Updates fog of war every 5 ticks.
4. **Input Pipeline:** Mouse click $\to$ Screen-to-world conversion $\to$ Context mapping in `Selection.gd` $\to$ Command construction in `Commands.gd` $\to$ `sim.submit()` $\to$ Simulation validation $\to$ State mutation.
5. **Smooth 60+ FPS Visuals:** Units are rendered at interpolated positions between the last tick and the current tick using `TickClock.fraction()` via linear interpolation (`lerp`).

---

## Turn 5

### User
how the enemy works

### Assistant
The enemy AI in `scripts/sim/ai/enemy_ai.gd` is a rule-based Finite State Machine (FSM) acting on an isolated `Observation` every 10 ticks (0.5 s):

1. **State Machine Hierarchy (Priority Order):**
   - **DEFEND:** Visible enemy soldier near base ($\le 8$ cells from HQ, $\le 6$ from buildings).
   - **DEFEND Hold:** Remains in DEFEND until 100 ticks pass without threat.
   - **RECOVER:** In ATTACK, but army dropped below retreat threshold ($<40\%$) or enemy base lost.
   - **ATTACK:** Army size $\ge$ threshold (e.g. 6 in Balanced, 3 in Aggressive) and enemy building known.
   - **BUILD:** No barracks yet, worker count met, and barracks affordable.
   - **ECONOMY:** Default gathering and expansion.
2. **Underlying Subroutines:**
   - Farms built when food runs low (1 per 5 workers); 2 workers assigned per farm.
   - Remaining workers balanced ~2:1 on wood vs gold.
   - Mirror-symmetric building placement via flipped Chebyshev search (`_find_site`).
   - One soldier detached to scout until an enemy building is found.
   - Researches Forging (+2 damage) and Armour (-2 damage taken) once it has 3 soldiers.
3. **Tactics & Difficulty:**
   - *Normal:* Attacks nearest enemy.
   - *Hard:* Focuses fire on the lowest HP enemy in reach, retreats wounded soldiers below 30% HP, raids workers with cavalry, and builds 2 guard towers.
4. **The Observation Firewall:**
   - AI receives only an `Observation` snapshot of visible units and ghosts.
   - `Simulation.submit_observed()` checks every command; targeting hidden entities is rejected and logged. In 100 test matches, firewall violations were strictly 0.

---

## Turn 6

### User
what is seeding and how does it work

### Assistant
**Seeding** is the technique of giving a single starting integer (the **seed**) to a Pseudo-Random Number Generator (PRNG) so it produces a predictable, 100% repeatable sequence of numbers.

1. **Why Seeding is Critical in Mini RTS:**
   - **Procedural Map Generation:** A single seed number generates the exact same forest, rock, and gold mine distribution on any machine or browser.
   - **Deterministic Replay System:** Matches are recorded as small `.jsonl` command logs containing only the match seed and timed input clicks. Replaying from the same seed reconstructs the identical match tick-by-tick.
   - **Fair AI Benchmarking:** Matches are played twice per seed, swapping start positions to eliminate positional bias.
2. **Mathematical Implementation (`sim_rng.gd`):**
   - **Seed Scrambling (`mix32`):** Applies a bit-shift hash so neighboring seeds (e.g., 1 and 2) diverge completely on the first roll:
     $$v = (v \oplus (v \gg 16)) \times \text{0x45d9f3b} \pmod{2^{32}}$$
   - **Linear Congruential Generator (LCG):**
     $$\text{state}_{\text{next}} = (\text{state} \times 1{,}664{,}525 + 1{,}013{,}904{,}223) \pmod{2^{32}}$$
   - **Upper-16-Bit Extraction (`>> 16`):** The lower bits of an LCG repeat in short cycles. The generator discards the bottom 16 bits and keeps only the high 16 bits for maximum randomness.

---

## Turn 7

### User
how are the fighting scenes created

### Assistant
Fighting scenes are created by bridging **deterministic simulation mechanics** with **rich visual and audio choreography**:

1. **Deterministic Simulation Core:**
   - Range checking uses squared integer distance ($dx^2 + dy^2 \le \text{range}^2$).
   - Cooldowns: Swordsmen (20 ticks / 1.0 s), Archers (24 ticks / 1.2 s), Guard Towers (30 ticks / 1.5 s).
   - Two-pass simultaneous damage calculation avoids lower ID bias.
   - **Cavalry Charge:** Galloping $\ge 3$ cells deals double damage ($2 \times 9 = 18$) on the first strike.
2. **Visual Choreography (`world_layer.gd`):**
   - 8-directional pre-rendered KayKit 3D character sprites with animation states (Idle, Walk, Slash, Shoot, Hurt).
   - **Micro-Separation:** Units close together push apart slightly on screen so battles form clear fighting lines instead of overlapping blobs.
   - **Physical Lunges & Knock-backs:** Attackers lunge forward 0.42 s; targets stagger backward when taking damage.
   - **Parabolic Arrows:** Fired arrows curve along quadratic bezier arcs.
3. **FX, Particles & Audio (`effects.gd`, `sound.gd`):**
   - Kenney particle bursts for metal sparks, sword slashes, and dirt impacts.
   - Galloping cavalry raise dust clouds and show floating "Charge!" text.
   - Camera micro-jolts on kills.
   - Dynamic music transitions from acoustic "Town Theme" to orchestral "Battle Theme A".
4. **Cinematic Cameras & Summaries (`battle_tracker.gd`):**
   - Clusters combat within 8 cells into ongoing battles.
   - Generates tactical summaries after skirmishes (*"Battle won: 4 enemies killed, 1 of yours lost"*).
   - **Battle Camera (`K`):** Drifts to the biggest fight when the player leaves the camera idle for 5 seconds.
   - Slow-motion HQ collapse when the final blow lands on a base.

---

## Turn 8

### User
What is A pathfinding?*

### Assistant
**A\*** is an optimal pathfinding algorithm that finds the shortest path between two points on a grid while avoiding obstacles.

1. **The Core Formula:**
   $$f(n) = g(n) + h(n)$$
   - **$g(n)$ (Past Cost):** Exact steps taken from the start to cell $n$.
   - **$h(n)$ (Heuristic Guess):** Estimated remaining distance from cell $n$ to the goal.
   - **$f(n)$ (Total Estimated Cost):** Total projected path length through cell $n$.
2. **Admissibility & Consistency:**
   - For A\* to guarantee the shortest path, $h(n)$ must be **admissible** (never overestimate true distance) and **consistent** (satisfies triangle inequality).
3. **Implementation in Mini RTS (`pathfinder.gd`):**
   - **Manhattan Distance ($|dx| + |dy|$):** On a 4-directional grid where diagonal moves are illegal, Manhattan distance represents the exact minimum step count on an open grid.
   - **Worked Example (AC-13):** On a $10 \times 10$ grid with a wall at $x=5$ and a gap at $y=9$, navigating from $(0, 0)$ to $(9, 0)$ takes exactly 27 steps (9 down, 9 right, 9 up).
   - **64-Bit Binary Min-Heap:** Packs $(f, h, \text{seq})$ into a single integer key for deterministic tie-breaking and sub-2 ms execution.

---

## Turn 9

### User
Whyand where did you use a binary heap

### Assistant
1. **WHERE:** Inside `scripts/sim/pathfinder.gd` (lines 51–86), as the **Open Set (Priority Queue)** for A\* pathfinding.
2. **WHY:**
   - **$O(\log N)$ vs $O(N)$ Complexity:** Finding the minimum $f$-score in a basic array requires scanning every element ($O(N)$). A binary min-heap retrieves the minimum at index 0 in $O(1)$ and extracts/inserts in $O(\log N)$.
   - **Contiguous Flat Arrays:** Stored in flat parallel arrays (`PackedInt64Array` keys, `PackedInt32Array` cells) using index math ($2i+1$, $2i+2$). This maximizes CPU cache locality and avoids object pointer overhead.
   - **Deterministic 3-Tier Sorting:** Keys pack `(f << 42) | (h << 26) | seq` into a 64-bit integer, resolving primary cost, heuristic tie-breaking, and FIFO order in a single integer comparison.
   - **Lazy Deletion:** When a shorter route to a cell is found, a new key is pushed; old keys are discarded in $O(1)$ when popped if `closed[ci] == 1`.
3. **Measured Result:** A 1,175-step serpentine maze is solved in **1.0 to 2.0 ms**, well within the 5 ms performance budget.

---

## Turn 10

### User
What happens when no path exist

### Assistant
1. **Algorithm Level (`pathfinder.gd`):**
   - **Never returns a partial path (AC-14):** Returns an empty array `[]`.
   - **Immediate Early Exit:** If start or goal is blocked or out of bounds, returns immediately with 0 cells expanded.
2. **Unit & Simulation Level (`simulation.gd`):**
   - **Move Orders:** The unit remains in place, is set to `Idle`, emits exactly **one** `"no_path"` HUD notification message (AC-28), and returns `"no_path"`.
   - **Dynamic Obstruction (AC-19):** If a building is placed across a moving unit's path, the unit attempts to re-plan. If completely blocked, it stops, idles, and raises one `"no_path"` message.
   - **Construction Orders:** If a worker cannot path to a designated construction site, the build command is rejected with `"no_path_to_site"`, and **zero resources are deducted**.

---

## Turn 11

### User
What is Nginx

### Assistant
**Nginx** is a high-performance, lightweight web server and reverse proxy.

In Mini RTS, Nginx hosts the exported Godot HTML5/WebAssembly game inside a Docker container (`docker compose up -d`) on port 8080:

1. **WebAssembly MIME Type:** Maps `.wasm` to `Content-Type: application/wasm` so browsers compile and execute the engine at native speed.
2. **Gzip Compression (AC-83):** Compresses `.wasm` and `.pck` files from ~20 MB down to **~10 MB**, enabling 2-second load times.
3. **Hardened Security & CSP (AC-82):** Enforces a strict same-origin Content Security Policy with SHA-256 hashes generated during build time for inline scripts, banning unsafe inline execution.
4. **Health Monitoring (`/healthz`):** Exposes an endpoint polled every 15 s by Docker for automatic crash recovery (AC-80).
5. **Unprivileged Execution:** Runs inside Alpine Linux as non-root user ID 101.

---

## Turn 12

### User
How would you scale the game to hundreds or thousands of units?

### Assistant
To scale from 80 units to 5,000+ units, we would re-architect the game across 5 pillars:

1. **Pathfinding $\to$ Flow Fields (Vector Fields):** Run a single reverse Dijkstra search from the target cell once; all units in the group read the local directional vector in $O(1)$ time, eliminating individual A\* spikes.
2. **Spatial Partitioning $\to$ Spatial Hash Grid:** Partition the map into bucket grids, reducing collision, range, and target acquisition checks from $O(N^2)$ to $O(N)$ linear time.
3. **Simulation Core $\to$ C++ / Rust ECS (GDExtension):** Replace GDScript `RefCounted` objects with Data-Oriented Design (Struct of Arrays) in C++, utilizing SIMD vector registers and contiguous CPU cache lines.
4. **Local Avoidance $\to$ ORCA / RVO2:** Implement Optimal Reciprocal Collision Avoidance for continuous velocity-obstacle steering, letting massive armies flow through chokepoints without gridlock.
5. **Rendering $\to$ GPU Instancing (`MultiMeshInstance2D`):** Issue a single GPU draw call per unit type using a shared sprite atlas texture, combined with viewport frustum culling and Level of Detail (LOD) downscaling.

---

## Turn 13

### User
other than thse what can be possible questions in viva

### Assistant
Top 11 high-probability viva defense questions and concise answers:

1. **Determinism & Desync:** A simulation is deterministic when identical seeds and inputs produce identical states. Prevented by integer milli-cells, fixed 20 Hz ticks, seeded `SimRng`, and sorting entity iteration by ID.
2. **Lockstep Multiplayer:** Transmit only timestamped player input commands rather than unit coordinates, relying on identical local simulation ticks.
3. **Procedural Map Fairness:** Point-symmetry ($(x, y) \to (47-x, 47-y)$) combined with automated BFS verifying connected HQs and symmetric starting resource nodes.
4. **Building Anchor Mirroring Bug (D-22):** Mirroring a $3 \times 3$ HQ's top-left anchor to $(47-x, 47-y)$ is wrong because the top-left mirrors to the bottom-right; the correct formula is $(45-x, 45-y)$.
5. **64-Bit Bitmask Fog Optimization:** Storing rows as 64-bit integers allows line-of-sight marking via bitwise OR, dropping update time from 4.1 ms to 0.8 ms ($5\times$ speedup).
6. **Building Ghosts:** Memory snapshots of buildings that persist until directly scouted, preventing hidden information leaks.
7. **Invariant Checker vs. Unit Tests:** Unit tests check individual input/output cases; invariant checkers run after every tick in randomized fuzz runs to verify conservation laws and spatial rules.
8. **Metamorphic Testing:** Verified that moving hidden player units behind fog does not alter AI command output, proving zero observation leakage.
9. **Wilson Score Interval vs. Wald:** Inverts the score test to stay bounded in $[0, 1]$ and handle extreme 0% or 100% win rates accurately.
10. **800-Match Balance Conclusion:** Aggressive beat Balanced (86.4%) and Balanced beat EconomyFirst (70.9%), proving rushing beats booming on compact maps.
11. **Single-Threaded Web Export:** Avoids browser requirements for `SharedArrayBuffer` and COOP/COEP isolation headers, enabling cross-origin iframe embedding and universal static hosting.
