# SPEC.md: Mini Real-Time Strategy Game

**Version:** 1.0 (draft, based on *Mini Real-Time Strategy Game: Project Guide*)
**Last updated:** 2026-10-13
**Methodology:** Spec-Driven Development. Every requirement has an ID, and every acceptance criterion (AC) becomes at least one automated test or one recorded measurement.

> Numbers marked *initial* (stats, targets, thresholds) are starting values for play-testing. If you change one after measuring, record the change in the Decisions Log (section 19). The guide says the same about its balance table.

---

## 1. Overview

A small, playable 2D real-time strategy game. The player gathers wood and gold, builds a barracks, trains workers and soldiers, scouts a foggy map, and tries to destroy an AI opponent's headquarters (HQ) before the AI destroys theirs. The opponent is a documented finite-state machine that plays under the same rules and sees the map only through its own fog of war.

The game is built on one design decision that shapes everything else: **the rules live in a deterministic simulation that knows nothing about graphics.** The Godot scenes only draw what the simulation says and translate mouse clicks into commands. That makes every rule testable without opening a window, lets matches run headless at many times real speed, and makes the project more than a game: two AI policies can be compared in hundreds of repeatable matches (section 16).

### Aim

Build a complete, finishable mini RTS in Godot 4 that demonstrates grid navigation with A*, a resource economy, construction and production, combat, a rule-based AI opponent, and fog of war, backed by tests and measurable acceptance criteria, and deployed as a browser game you can open on your computer or local network.

### Inputs

| Input | Details |
| --- | --- |
| Player input | Mouse and keyboard: select, box-select, move, harvest, build, train, attack, pan the camera |
| Map files | JSON maps (section 8), plus seeds for the symmetric map generator |
| Unit and building data | `data/units.json` holding the stats of section 4 |
| AI configuration | An `AIConfig` preset (Balanced, Aggressive, EconomyFirst) or custom parameters |
| Match settings | Seed, map, maximum match length, faction controllers (human or AI) |
| Replay files | Recorded command logs, used for replays and tests |

### Outputs

| Output | Details |
| --- | --- |
| The game | A playable match with HUD, status messages, victory or defeat screen, and restart |
| Simulation events | Unit and building created or destroyed, resource changes, messages, match end |
| Replay files | A JSON-lines command log that reproduces a match exactly |
| Match results | One CSV row per headless match: winner, duration, first attack, resources gathered, units lost |
| Experiment report | Tables with confidence intervals comparing AI policies |
| Deployed service | The web build served by a container at `http://localhost:8080` (and on the local network) |

### Requirements at a glance

- **Functional:** FR-01 to FR-18 (section 11).
- **Asset and licence rules:** L1 to L3 (section 3).
- **Deployment:** D1 to D7 (section 10).
- **Non-functional:** determinism, performance, code quality (section 14).
- **Acceptance criteria:** AC-01 to AC-96 (section 12), mapped to the guide's twelve criteria in section 13.

## 2. Goals, Scope and Non-Goals

**Goals**
1. A grid map with walkable and blocked cells, resource nodes and two start positions.
2. Selecting units and issuing move, harvest, build, train and attack commands.
3. Resource costs, timed construction and timed unit production, with exact accounting.
4. A* pathfinding with clear failure handling.
5. Combat with health, range and cooldowns, and clean removal of destroyed entities.
6. An AI opponent built as a finite-state machine, which plays from its own observations only.
7. Fog of war with unexplored, explored and visible cells.
8. A deterministic simulation with replays and a headless match runner.
9. An experiment comparing AI policies, reported honestly.
10. A deployed web build, a README, and a viva-ready explanation of every algorithm.

**MVP (must finish first):** everything in goals 1 to 7, the win and loss condition, the HUD, restart, and the README.

**Required after the MVP passes** (the guide's "advanced differentiator"): goals 8 and 9.

**Stretch** (only after everything above passes): a minimap, sound effects and animations, multiple maps, a resource depot building, attack-move and shift-queued orders, line-of-sight fog, unit collision, and match statistics screens.

**Non-goals (v1):** online multiplayer, accounts, large maps with hundreds of units, 3D graphics, campaigns, large tech trees, and machine-learning opponents. A transparent rule-based AI is easier to defend in a viva.

## 3. Asset and Licence Rules

| ID | Rule |
| --- | --- |
| **L1 Recorded licences** | Every sprite, font and sound is either made by you or has a permissive licence (for example CC0), and each is listed in `ASSETS.md` with its source and licence. Simple shapes drawn in code need no outside file. |
| **L2 Allowlist check** | A CI check lists every file in `assets/` and fails unless it appears in `ASSETS.md`. |
| **L3 Borrowed code** | If you adapt code from a tutorial or an add-on, check its licence, record it in `ASSETS.md`, and attribute it. Test frameworks such as GUT are third-party and are listed there too. |

## 4. Conventions and Constants

**Space and time**
- The map is a grid of cells; `(0, 0)` is the top-left cell, `x` grows right and `y` grows down. One cell is 32 pixels on screen.
- The simulation advances in fixed **ticks** at **20 ticks per second**, independent of the frame rate.
- **All simulation quantities are integers.** Positions are in **milli-cells** (1,000 per cell), distances are compared as squared integers, and times are in ticks. There is no floating point in the simulation state, so results are identical on every platform. Floating point appears only in drawing.
- A cell `(x, y)` has its centre at `(x·1000 + 500, y·1000 + 500)` milli-cells.
- A building's anchor is its **top-left** cell; its footprint is the rectangle from there.
- Movement is **four-directional** (up, down, left, right) at a cost of 1 per step.

**Unit and building stats (initial)**

| Entity | Wood | Gold | Health | Speed (milli-cells per tick) | Vision (cells) | Damage | Range (milli-cells) | Cooldown (ticks) | Train or build time (ticks) | Footprint |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Worker | 50 | 0 | 40 | 150 (3.0 cells/s) | 6 | none | none | none | 160 (8 s) | 1 × 1 |
| Melee soldier | 60 | 20 | 100 | 125 (2.5 cells/s) | 6 | 10 | 1,500 | 20 (1.0 s) | 200 (10 s) | 1 × 1 |
| Ranged soldier | 40 | 50 | 50 | 125 | 7 | 8 | 5,000 | 24 (1.2 s) | 240 (12 s) | 1 × 1 |
| HQ | none | none | 500 | none | 8 | none | none | none | starts built | 3 × 3 |
| Barracks | 120 | 60 | 300 | none | 5 | none | none | none | 300 (15 s) | 2 × 2 |

**Other constants (initial)**

| Constant | Value |
| --- | --- |
| Starting resources (each faction) | 200 wood, 100 gold |
| Starting units | HQ, 3 workers |
| Wood node | 500 units, finite |
| Gold node | 300 units, finite |
| Worker carry capacity | 10 |
| Time to fill the carry capacity | 40 ticks (2 s) while adjacent to the node |
| Production queue capacity | 5 per building |
| Population cap (units, including queued) | 40 per faction |
| Maximum selection | 24 units |
| Default generated map | 48 × 48 |
| Default match limit | 36,000 ticks (30 minutes) |
| AI decision interval | every 10 ticks |

The HQ trains workers only. Soldiers are trained only at a **completed** barracks.

## 5. Game Rules

### 5.1 Map
- Each cell is walkable or blocked terrain. A cell may also hold a resource node or part of a building. Units stand on cells; **units do not block each other** while walking, but they do not stop on the same cell: a group sent to one cell spreads over neighbouring cells, a melee soldier attacks from a free cell next to its target, and units standing on a shared cell step apart (decision D-42, replacing part of D-04). Buildings and resource nodes block movement.
- Units and buildings cannot be placed on blocked or occupied cells.

### 5.2 Orders
- A unit has exactly one current order: `Idle`, `Move(cell)`, `Harvest(node)`, `Build(building)`, `Attack(target)` or `AttackMove(cell)` (build step 11). **A new order replaces the current one** (decision D-14); an order given with the `queue` flag (Shift) instead waits until the current and earlier queued orders end (decision D-44).
- If a unit's path becomes blocked (a building is placed on it), the unit re-plans; if no path exists, it stops, becomes `Idle`, and a message `no_path` is raised once.
- Only the owner faction can command a unit.

### 5.3 Economy
- A worker harvests while adjacent (including diagonally) to its node. After 40 ticks it carries 10 units, walks to the **nearest friendly HQ by path length**, and deposits them on arrival, then returns to the same node. If the node is exhausted, it looks for another node of the same type within 10 cells, and goes `Idle` with a message if none exists.
- A node with fewer than 10 units left gives its remaining amount in one trip, then disappears, and its cell becomes walkable.
- Carried resources are kept when the order changes, and are deposited on the next drop-off. If no friendly HQ exists, the worker idles holding them.
- **Every spend goes through one transaction:** check the amount is non-negative, check each resource is affordable, deduct once, then perform the action. A failed check changes nothing.

### 5.4 Construction and production
- **Construction.** `Build` places a building under construction. The cost is deducted **once, at placement**. Placement is valid only if every footprint cell is in bounds, walkable, free of buildings and resource nodes, free of units, and **explored** by the player. A building under construction blocks movement from the moment it is placed. Progress advances one tick per tick while a worker assigned to it is adjacent, and pauses (keeping its progress) otherwise. A completed barracks enables soldier training.
- **Production.** Training deducts the cost **at enqueue** and adds the unit to the building's queue (capacity 5, and the faction population cap applies). The first item counts down its training time; when it reaches 0 the unit spawns. Cancelling an item refunds its full cost once.
- **Spawn cell.** The unit spawns in the first walkable cell, free of buildings and nodes, found by scanning the ring of cells at distance 1, then 2, then 3 around the building's footprint in row-major order. If none exists, the item waits at the front of the queue with the status `spawn_blocked`, and spawns on the first tick a cell is free.
- A destroyed building takes its queue with it (no refund), and its footprint becomes walkable.

### 5.5 Combat
- A unit may attack only a living enemy within its attack range (distance between the unit's position and the nearest cell centre of the target's footprint) and only when its cooldown has expired. A unit's cooldown starts expired, so the first attack happens as soon as the target is in range.
- Within a tick, all attacks resolve against the state at the start of the tick, in order of entity ID, and deaths are removed **at the end of the tick**. Two units can therefore kill each other in the same tick.
- Dead entities are removed, and every order or selection that referenced them is cleared (the unit becomes `Idle`).
- Idle soldiers **auto-acquire**: if an enemy unit or building is visible within the soldier's vision, they attack it, and return to `Idle` when it dies or leaves their vision.
- Workers and buildings cannot attack.

### 5.6 Fog of war
- Each faction has a grid with three states per cell: `UNEXPLORED`, `EXPLORED` (seen before, not now) and `VISIBLE` (inside vision now).
- A cell is `VISIBLE` if its centre is within the vision radius (squared Euclidean distance in cells) of any of the faction's units or buildings. There is no line-of-sight blocking in v1. Vision is recomputed at least every 5 ticks.
- A faction sees enemy **units** only in `VISIBLE` cells. Enemy **buildings** once seen are remembered as ghosts (their last known state) until seen destroyed.
- A faction can issue an `Attack` order only against an enemy it currently sees, and can place buildings only on explored cells.
- Pathfinding uses the true terrain for both factions (decision D-15), a documented simplification. **Decisions** (what to target and where to scout) use observations only (section 7).

### 5.7 End of match
- A faction is defeated when its HQ is destroyed. The result (`victory` for the other faction) is raised **exactly once**; if both HQs fall in the same tick the result is `draw`. If the match limit is reached, the result is `timeout`.
- After the match ends, every command is rejected with `match_over`, and the game offers a restart.

## 6. Architecture

### 6.1 Two layers

| Layer | Contents | Rules |
| --- | --- | --- |
| **Simulation core** (`scripts/sim/`) | Plain GDScript classes extending `RefCounted`: map, entities, pathfinder, resource manager, production, combat, fog, AI | No scene tree, no nodes, no rendering, no `randf()`, no real clock. Integers only. Runs headless |
| **Presentation** (`scenes/`, `scripts/ui/`) | Godot scenes: map drawing, unit sprites, selection controller, HUD, menus | Reads simulation state, sends commands, and never changes state directly |

The guide's modules map onto this as follows.

| Guide module | Where it lives |
| --- | --- |
| GameManager | `Simulation` (match state, tick, end state) plus a thin scene script that drives it |
| MapGrid | `sim/map_grid.gd` |
| Unit, Building | `sim/entities.gd` |
| SelectionController | `ui/selection_controller.gd` (translates clicks into commands) |
| Pathfinder | `sim/pathfinder.gd` |
| ResourceManager | `sim/resource_manager.gd` |
| Building / ProductionQueue | `sim/production.gd` |
| CombatSystem | `sim/combat.gd` |
| EnemyAI | `sim/ai/enemy_ai.gd` |
| FogOfWar | `sim/fog.gd` |
| HUD | `ui/hud.gd` |

### 6.2 Simulation interface

| Member | Purpose |
| --- | --- |
| `Simulation.new(map, seed, config)` | Create a match from the map, seed and settings |
| `step()` | Advance exactly one tick |
| `submit(command) -> Result` | Validate and apply a command, or return an error code |
| `state_hash() -> int` | A hash of the whole state, for determinism tests |
| `events` | Created, destroyed, resource-changed, message and match-ended events for the UI |
| `observation(faction) -> Observation` | The faction's view of the world (section 7.2) |

**Commands:** `move(unit_ids, cell)`, `harvest(unit_ids, node_id)`, `build(worker_id, building_type, cell)`, `attack(unit_ids, target_id)`, `train(building_id, unit_type)`, `cancel_train(building_id, index)`; build step 11 adds `attack_move(unit_ids, cell)` and an optional `queue: true` on move, attack_move, attack and harvest (decision D-44).

**Result codes:** `ok`, `not_owner`, `unknown_entity`, `insufficient_resources`, `invalid_placement`, `not_explored`, `no_path`, `invalid_target`, `target_not_visible`, `invalid_unit_for_building`, `not_ready`, `queue_full`, `population_cap`, `invalid_amount`, `match_over`.

## 7. The Enemy AI

### 7.1 Finite-state machine

The AI decides every 10 ticks. At each decision it chooses its state by this **priority list**, then acts.

| Priority | Condition | State |
| --- | --- | --- |
| 1 | A threat exists: any visible enemy soldier within 8 cells of the HQ or within 6 cells of another own building (workers are not threats, D-34) | `DEFEND` |
| 2 | Currently `DEFEND`, and no threat for 100 ticks | back to the previous state (or `ECONOMY`) |
| 3 | Currently `ATTACK`, and army size is below `retreat_fraction` of the army size when the attack started, or no target is known | `RECOVER` |
| 4 | Army size is at least `army_threshold`, a target is known, and the state is `ECONOMY` or `RECOVER` | `ATTACK` |
| 5 | No barracks exists or is being built, workers are at least `build_worker_min`, and a barracks is affordable | `BUILD` |
| 6 | Otherwise | `ECONOMY` |

| State | Behaviour |
| --- | --- |
| `ECONOMY` | Train workers up to `worker_target`; assign idle workers to the nearest wood or gold node (target ratio 2 wood to 1 gold); train soldiers whenever a barracks is complete, following `unit_mix` |
| `BUILD` | Choose a worker, place a barracks at the first valid site found by scanning outward from the HQ, then return to `ECONOMY` when the order is accepted (or after 600 ticks as a fallback) |
| `DEFEND` | All soldiers attack the nearest threat; workers keep gathering |
| `ATTACK` | All army soldiers go to the nearest known enemy building (the HQ first if known) and attack what they meet |
| `RECOVER` | Soldiers gather at a rally cell near the HQ while the economy and production continue |

**Roles and order ownership.** Every AI unit has one role: `WORKER`, `ARMY` or `SCOUT`. In one decision, each unit receives **at most one** command, so states cannot issue conflicting orders. One soldier becomes the `SCOUT` and visits the map's possible start positions in order (both factions know where start positions may be, because they are listed in the map data).

**Fallback.** If the AI has idle units or an affordable action but issues no command for 200 ticks, it logs `stuck` with its state and counters and re-enters `ECONOMY`.

**Debug log.** Every state change is logged with its tick and the condition that caused it.

**Policies** are parameter sets for the same machine:

| Parameter | Balanced | Aggressive | EconomyFirst |
| --- | --- | --- | --- |
| `worker_target` | 6 | 4 | 10 |
| `build_worker_min` | 5 | 3 | 7 |
| `army_threshold` | 6 | 3 | 10 |
| `retreat_fraction` | 0.4 | 0.25 | 0.5 |
| `unit_mix` (melee : ranged) | 2 : 1 | 3 : 1 | 1 : 1 |

### 7.2 The observation firewall

The AI is a function `decide(observation) -> commands`. It holds **no reference to the simulation or the world**, so it cannot read hidden information.

An `Observation` contains only: the tick; the faction's resources; its own units, buildings and queues; the enemy units currently in `VISIBLE` cells; remembered enemy buildings (ghosts); the terrain; the possible start positions; the faction's fog grid; and the public stats table. The simulation rejects any AI command that targets an entity ID not in the observation, counts it as a **firewall violation**, and the test suite requires zero.

## 8. Data Formats

**Map file** (`data/maps/*.json`): `tiles` is one string per row (`.` walkable, `#` blocked), `starts` give each faction's HQ anchor, and `possible_starts` list where HQs may begin.

```json
{
  "name": "tutorial",
  "width": 12,
  "height": 8,
  "tiles": [
    "............", "............", "......##....", "......##....",
    "............", "............", "............", "............"
  ],
  "starts": [
    {"faction": "player", "cell": [1, 3]},
    {"faction": "ai", "cell": [8, 3]}
  ],
  "possible_starts": [[1, 3], [8, 3]],
  "nodes": [
    {"type": "wood", "cell": [5, 1], "amount": 500},
    {"type": "gold", "cell": [5, 6], "amount": 300}
  ]
}
```

(Every row string has exactly `width` characters, and there are exactly `height` rows.)

**Unit data** (`data/units.json`): one object per entity with the fields of the table in section 4. The loader rejects missing or negative fields with a clear message.

**Replay file** (`*.replay.jsonl`): a header line `{"version", "seed", "map", "ai_configs", "max_ticks"}`, then one line per command: `{"tick", "faction", "command", "args", "result"}`.

**Results file** (`results.csv`): `seed, map, side_a_policy, side_b_policy, a_is_player_start, winner, outcome, duration_ticks, first_attack_tick, wood_gathered_a, gold_gathered_a, units_lost_a, wood_gathered_b, gold_gathered_b, units_lost_b`.

## 9. Controls and HUD

| Input | Action |
| --- | --- |
| Left click on a friendly unit or building | Select it and show its details |
| Left drag | Box-select friendly units (maximum 24) |
| Left click on empty ground | Clear the selection |
| Right click | Context order: empty cell = move, resource node with workers selected = harvest, visible enemy = attack |
| `B` then click | Place a barracks (with a ghost preview that shows valid or invalid) |
| Buttons or `Q` / `W` / `E` | Train worker, melee soldier, ranged soldier at the selected building |
| `Esc` | Cancel placement or clear the selection |
| `WASD` or screen edges | Pan the camera (clamped to the map) |
| `F` then click (step 11) | Attack-move the selected units: walk there, fighting enemies met on the way (D-44) |
| `Shift` + an order (step 11) | Queue the order after the current ones instead of replacing them (D-44) |

The HUD shows the wood and gold counters, the selected entity's details and queue, enabled or disabled command buttons (disabled when the command would be rejected, with the reason on hover), a message log (each message fades after 3 seconds), and the victory or defeat overlay with a restart button. A main menu starts a match.

## 10. Production Deployment

The project must run as a deployed service. "Deployed" means: the game is exported to the web, built into a container image, and run as a long-lived service that you open in a browser on your own computer or from another device on the same network (intranet). It may also be published on a public static host, because the game contains no secrets.

| ID | Requirement |
| --- | --- |
| **D1 Web export** | The game exports with Godot's Web preset using the **Compatibility renderer**, with **thread support off**. Since Godot 4.3 single-thread web export is supported, and it means no cross-origin-isolation headers are needed (they are required only when thread support is on). The exported files keep the names set at export. |
| **D2 Container** | A `Dockerfile` builds the export in a build stage with a pinned, verified Godot version and its export templates, then serves the result with nginx in a final stage, as a non-root user (for example the `nginxinc/nginx-unprivileged` base image, which listens on port 8080). |
| **D3 One command** | `docker compose up -d` from a fresh clone builds and starts the service at `http://localhost:8080`. |
| **D4 Health and restart** | A health check (a static `/healthz` file) and automatic restart after a crash (`restart: unless-stopped`). |
| **D5 Serving details** | The `.wasm` file is served as `application/wasm`; `.wasm`, `.pck` and `.js` are compressed; a Content-Security-Policy restricts resources to the same origin; the page makes no third-party requests. |
| **D6 Network reach** | To open it from another device, visit `http://<this-computer's-LAN-IP>:8080`. The README documents any firewall step needed. |
| **D7 Optional public host** | The same export may be published on a free static host (for example itch.io or GitHub Pages). |

## 11. Functional Requirements

| ID | Requirement |
| --- | --- |
| FR-01 | A fixed-tick, integer-only, deterministic simulation with seeded randomness (sections 4 and 6). |
| FR-02 | Load and validate maps and unit data; generate symmetric maps from a seed. |
| FR-03 | A* pathfinding with clear failure results and re-planning. |
| FR-04 | Selection, context orders and the command interface. |
| FR-05 | Movement along paths. |
| FR-06 | Harvesting, drop-off, depletion and the resource transaction. |
| FR-07 | Building placement and construction. |
| FR-08 | Production queues, spawning and cancellation. |
| FR-09 | Combat, auto-acquire and removal of destroyed entities. |
| FR-10 | Fog of war for both factions. |
| FR-11 | The enemy AI and its observation firewall. |
| FR-12 | Match end handling and clean restart. |
| FR-13 | The HUD, menus, messages and camera. |
| FR-14 | Replay recording and playback. |
| FR-15 | The headless match runner and CSV results. |
| FR-16 | The AI strategy experiment with statistics (section 16). |
| FR-17 | Run as a containerised web service meeting section 10. |
| FR-18 | A README with setup, controls, design, test and deployment instructions, and known limitations. |

## 12. Acceptance Criteria

### Simulation foundation
- [x] **AC-01** (FR-01) `step()` advances exactly one tick. Running 20 ticks in one frame or spread over many frames gives the same state hash.
- [x] **AC-02** (FR-01) The simulation uses its own integer pseudo-random generator, seeded from the match seed (not Godot's global random functions), and a static check finds no call to `randf`, `randi`, `randomize` or the system clock inside `scripts/sim/`.
- [x] **AC-03** (FR-01) Two runs with the same seed and the same command log have identical state hashes every 100 ticks and at the end.
- [x] **AC-04** (FR-14) A recorded replay, played back, reproduces the final state hash and the result of the original match.
- [x] **AC-05** (FR-02) The stats loaded from `units.json` equal the constants of section 4, and a file with a missing or negative field fails with a message naming the field.
- [x] **AC-06** (FR-01) *Invariant checker.* After every tick of 1,000 simulations of 2,000 ticks each under random valid and invalid commands: no two buildings overlap, no unit stands on a blocked cell or inside a building, every order and selection refers only to living entities, all resources are at least 0, every queue has at most 5 items, population is at most 40, and at most one match result was raised.
- [x] **AC-07** (FR-06) *Conservation.* In the same simulations, for each resource type: the amount removed from nodes equals the amount carried plus the amount deposited, and the stockpile equals the starting amount plus deposits plus refunds minus spending.

### Map
- [x] **AC-08** (FR-02) The example map of section 8 loads with the right size, walkable and blocked cells, nodes and starts; a ragged row, an unknown tile character, a start or node on a blocked cell, or a node outside the map fails with a clear message.
- [x] **AC-09** (FR-02) Cell centre conversion round-trips: cell (3, 4) has centre (3,500, 4,500) milli-cells, and that position maps back to cell (3, 4); at 32 pixels per cell it draws at (112, 144).
- [x] **AC-10** (FR-02) For 1,000 seeds, the generated 48 × 48 map is point-symmetric (cell `(x, y)` matches `(47 − x, 47 − y)` in terrain, nodes and starts), the two HQs are connected by a walkable path, and each side has at least 2 wood nodes and 1 gold node within 15 cells of its HQ. If the generator cannot satisfy this in 50 tries it fails with `map_generation_failed`.
- [x] **AC-11** (FR-02) The same seed always generates the same map, and 100 different seeds generate at least 95 distinct maps.

### Pathfinding
- [x] **AC-12** (FR-03) On an empty 10 × 10 grid, the path from (0,0) to (9,9) has 18 steps (19 cells), every step moves to a neighbouring cell, and every cell is walkable.
- [x] **AC-13** (FR-03) With a wall at x = 5 blocking y = 0 to 8 (a gap at y = 9), the path from (0,0) to (9,0) has exactly **27** steps.
- [x] **AC-14** (FR-03) A fully enclosed destination, a blocked destination, and a blocked start each return `no_path` (never a partial path) after exploring no more than the reachable cells; start equal to goal returns a path of one cell and length 0.
- [x] **AC-15** (FR-03) On 1,000 random grids, the A* path length equals the breadth-first-search shortest length, or both report no path.
- [x] **AC-16** (FR-03) The Manhattan heuristic is admissible (never above the true distance) and consistent (`h(a) ≤ 1 + h(b)` for neighbours) on random grids.
- [x] **AC-17** (FR-03) Identical inputs give the identical path every time (fixed neighbour order and tie-breaking).
- [x] **AC-18** (FR-03) *(initial target)* The worst-case path on a 48 × 48 map takes at most **5 ms** in GDScript; the measured value is recorded.
- [x] **AC-19** (FR-05) When a building is placed on a moving unit's path, the unit re-plans around it; if no route exists it stops, becomes `Idle`, raises `no_path` once, and the game stays responsive.

### Selection and commands
- [x] **AC-20** (FR-04) A command for an unknown entity returns `unknown_entity`; a command for the other faction's unit returns `not_owner`; a negative amount returns `invalid_amount`; none of them changes the state hash.
- [x] **AC-21** (FR-04) Clicking a friendly unit selects it and shows its details; clicking an enemy shows its details but does not select it for commands; clicking empty ground clears the selection.
- [x] **AC-22** (FR-04) Box-select selects only friendly units inside the box, at most 24; a selected unit that dies is removed from the selection.
- [x] **AC-23** (FR-04) The context-order function maps a right click on an empty cell to `move`, on a resource node with workers selected to `harvest`, and on a visible enemy to `attack`; any other combination does nothing.
- [x] **AC-24** (FR-04) A new order replaces the current one: a unit never has two current orders, and issuing the same order twice leaves the same state as issuing it once.

### Movement
- [x] **AC-25** (FR-05) A worker (150 milli-cells per tick) sent along a straight 15-cell path arrives after exactly 100 ticks; a melee soldier (125) on the same path arrives after exactly 120 ticks.
- [x] **AC-26** (FR-05) Across random maps and orders, no unit is ever on a blocked cell.
- [x] **AC-27** (FR-05) Two units sent to the same cell both arrive, in different neighbouring cells: the one nearer the goal on it, the other on the nearest free cell around it (changed by D-42; was "and share it").
- [x] **AC-28** (FR-05) An unreachable destination sets the unit `Idle` and raises one `no_path` message, not one per tick.

### Economy
- [x] **AC-29** (FR-06) A worker adjacent to both a wood node and the HQ completes a trip in at most 41 ticks: the stockpile rises by exactly 10 wood and the node falls by exactly 10.
- [x] **AC-30** (FR-06) A node with 15 units left yields trips of 10 and 5 (total exactly 15), then disappears and its cell becomes walkable; the worker then moves to another node of the same type within 10 cells, or becomes `Idle` with a message if none exists.
- [x] **AC-31** (FR-06) With two HQs, a worker deposits at the nearer one by path length; if its HQ is destroyed it keeps the carried resources and becomes `Idle` with `no_dropoff`.
- [x] **AC-32** (FR-06) With 100 wood and 100 gold, training one melee soldier (60 wood, 20 gold) leaves 40 wood and 80 gold; a second one is rejected with `insufficient_resources` and the stockpile stays 40 and 80.
- [x] **AC-33** (FR-08) Queueing two workers from 200 wood leaves 100 wood; cancelling the second restores 50 (150 wood); cancelling the same item again is rejected and refunds nothing.
- [x] **AC-34** (FR-06) Changing a harvesting worker's order loses and duplicates nothing: its carried amount is kept and later deposited, and AC-07 still holds.
- [x] **AC-35** (FR-13) The HUD counters show the stockpile values of the same tick.

### Construction and production
- [x] **AC-36** (FR-07) Barracks placement returns the right code for each case: out of bounds, blocked terrain, overlapping a building, overlapping a resource node, overlapping a unit, an unexplored cell (`not_explored`), and insufficient resources. Each rejection leaves the stockpile unchanged.
- [x] **AC-37** (FR-07) A valid placement deducts 120 wood and 60 gold exactly once, and from that tick the footprint cells block pathfinding.
- [x] **AC-38** (FR-07) A barracks under construction completes after exactly 300 ticks with an adjacent worker; with no worker adjacent the progress holds, and it resumes from the same value when a worker returns. Soldier training is rejected with `not_ready` until it completes.
- [x] **AC-39** (FR-08) A melee soldier (200 ticks) is absent at tick 199 and present at tick 200; a second queued soldier appears at tick 400.
- [x] **AC-40** (FR-08) Training a soldier at the HQ returns `invalid_unit_for_building`; the sixth queue item returns `queue_full`; the 41st unit returns `population_cap`.
- [x] **AC-41** (FR-08) With every cell in the spawn rings blocked, a finished unit waits with `spawn_blocked` and a message; it spawns in the first tick a cell becomes free, in the documented ring and row-major order.
- [x] **AC-42** (FR-08) Destroying a building removes its queue without refund and makes its footprint walkable.

### Combat
- [x] **AC-43** (FR-09) A melee soldier at distance 2.0 cells deals no damage; at 1.0 cell it deals 10 damage on the first tick and again exactly 20 ticks later.
- [x] **AC-44** (FR-09) A ranged soldier hits at 5.0 cells and does not at 5.1 cells.
- [x] **AC-45** (FR-09) A 100-health target dies on the tenth melee hit, is removed in that same tick, and cannot attack afterwards; a unit cannot be damaged twice in the tick it dies.
- [x] **AC-46** (FR-09) Two soldiers that land lethal hits in the same tick both die (the end-of-tick removal rule).
- [x] **AC-47** (FR-09) Attacking a friendly unit returns `invalid_target`; a worker given an attack order is rejected.
- [x] **AC-48** (FR-09) When a target dies, every order that referenced it is cleared and no stale reference remains (checked by the invariant checker).
- [x] **AC-49** (FR-09) Soldiers can destroy buildings: a melee soldier needs 30 hits to destroy a 300-health barracks.
- [x] **AC-50** (FR-09) An idle soldier with an enemy in vision attacks it, chases it, and returns to `Idle` when it dies or leaves vision.

### End of match
- [x] **AC-51** (FR-12) Destroying an HQ raises exactly one `victory` or `defeat` event; both HQs destroyed in the same tick raises `draw`; reaching the tick limit raises `timeout`.
- [x] **AC-52** (FR-12) After the match ends, every command returns `match_over` and the state hash stops changing.
- [x] **AC-53** (FR-12) After a restart with the same seed, the state hash equals that of a fresh process, and no unit, timer, selection or message from the previous match remains.

### Fog of war
- [x] **AC-54** (FR-10) For a unit with vision 6 at (10,10): the cells (10,16) and (14,14) are `VISIBLE`, and (10,17) and (16,14) are not.
- [x] **AC-55** (FR-10) A cell that was visible and is no longer becomes `EXPLORED`, never `UNEXPLORED` again.
- [x] **AC-56** (FR-10) An enemy unit in an `EXPLORED` but not `VISIBLE` cell is not drawn and not in the player's observation; a seen enemy building stays as a ghost until it is seen destroyed.
- [x] **AC-57** (FR-10) The player's `Attack` order against a non-visible enemy returns `target_not_visible`.
- [x] **AC-58** (FR-10) Vision is recomputed at least every 5 ticks, and *(initial target)* the update for 80 units on a 48 × 48 map takes at most **2 ms**.

### Enemy AI
- [x] **AC-59** (FR-11) The AI receives only an `Observation` and holds no reference to the simulation; a static check finds no import or reference to the simulation or world classes in `scripts/sim/ai/`.
- [x] **AC-60** (FR-11) *Metamorphic test.* Two worlds that differ only in the positions of player units outside the AI's vision give the AI identical commands.
- [x] **AC-61** (FR-11) Over 100 headless matches there are **zero** firewall violations (no command targets an unobserved entity).
- [x] **AC-62** (FR-11) Each row of the transition priority list in section 7.1 has a unit test with a synthetic observation: a visible enemy near the HQ gives `DEFEND`; 5 workers, 120 wood, 60 gold and no barracks gives `BUILD`; 6 soldiers and a known target gives `ATTACK`; an army of 2 after starting an attack with 6 gives `RECOVER` (Balanced policy).
- [x] **AC-63** (FR-11) In any one decision, no unit receives more than one AI command.
- [x] **AC-64** (FR-11) Over 100 headless matches, the longest stretch in which the AI had idle units or an affordable action but issued nothing is at most 200 ticks, and every `stuck` event triggers the fallback.
- [x] **AC-65** (FR-11) *(initial target)* On the tutorial map, the Balanced AI has built a barracks and trained at least 3 soldiers within 6,000 ticks (5 minutes) in 20 of 20 seeds.
- [x] **AC-66** (FR-11) *(initial target)* Against an opponent that issues no commands, the Balanced AI wins at least 95 of 100 matches within 18,000 ticks (15 minutes).
- [x] **AC-67** (FR-11) Every AI state change is logged with its tick and the triggering condition.

### Replays, headless runner and experiments
- [x] **AC-68** (FR-15) The headless runner plays `N` matches for given policies and seeds, with sides swapped on each seed, and writes one CSV row per match with the columns of section 8.
- [x] **AC-69** (FR-15) *(initial target)* A full 30-minute simulated match runs headless in at most **30 seconds** (at least 60 times real time) on a laptop.
- [x] **AC-70** (FR-16) The Wilson 95% confidence interval function returns about **[0.531, 0.665]** for 120 wins out of 200 (± 0.002).
- [x] **AC-71** (FR-16) *Sanity check.* Balanced against Balanced over 200 matches (swapped sides on 100 seeds) gives a win rate for side A whose 95% confidence interval contains 0.5. If it does not, the map generator or the side set-up is biased and must be fixed before any other comparison is trusted.
- [x] **AC-72** (FR-16) The experiment report compares Aggressive, EconomyFirst and Balanced pairwise over at least 200 matches each, reporting win rate with its confidence interval, mean match duration, mean time to first attack, resources gathered and units lost, plus a discussion of limitations.

### User interface
- [x] **AC-73** (FR-13) The HUD shows both resource counters, the selected entity's details and queue, command buttons that are disabled (with the reason) when the command would be rejected, and messages that fade after 3 seconds.
- [x] **AC-74** (FR-13) A main menu starts a match, and the victory or defeat overlay offers a restart.
- [x] **AC-75** (FR-13) All controls in section 9 work, including placement preview with a valid or invalid colour.
- [x] **AC-76** (FR-13) The camera pans with the keys and screen edges and never leaves the map.
- [x] **AC-77** *(initial target)* On a laptop, the desktop build holds **60 frames per second** with 80 units on the map, and the web build at least **30 frames per second**; both are measured and recorded.
- [ ] **AC-78** (FR-13) The manual play-test checklist passes and is recorded: a new player can select and command a unit; a player can collect enough to produce a soldier; the AI makes progress without getting stuck; the player can win and lose; a restart leaves nothing from the previous match.

### Deployment and documentation
- [x] **AC-79** (D3) From a fresh clone with only Docker installed, `docker compose up -d` serves the game at `http://localhost:8080`, and a full match can be played in the browser.
- [x] **AC-80** (D2, D4) `docker compose ps` reports the container as healthy, killing the server process makes it restart and become healthy again, and the container runs as a non-root user.
- [x] **AC-81** (D1) The web export has thread support off and runs without cross-origin-isolation headers; the export settings are recorded in the README.
- [x] **AC-82** (D5) `.wasm` is served as `application/wasm`; `.wasm`, `.pck` and `.js` responses are compressed; the Content-Security-Policy is present; the browser's network panel shows no third-party request.
- [x] **AC-83** *(initial target)* The total transferred size of the web build on first load is at most **20 MB** (compressed); the measured size is recorded.
- [ ] **AC-84** (D6) From a second device on the same network, the game loads at `http://<LAN-IP>:8080` and a match is playable. This is a manual check: record the date and result in the README.
- [x] **AC-85** (L1, L2) The CI asset check passes: every asset file is listed in `ASSETS.md` with a source and licence.
- [x] **AC-86** *(Optional)* (D7) The export is published on a public static host and playable.
- [x] **AC-87** (FR-18) From a clean checkout, the README's instructions install the pinned Godot version, run the tests, run the game, export the web build and start the container, and all required assets are included.
- [x] **AC-88** (FR-18) The README lists the controls, the architecture, the final stats table, the AI state machine, the experiment results, and the known limitations.
- [x] **AC-89** The unit test suite runs headless from the command line (no window) in at most **2 minutes**, and fails the build on any failure.
- [x] **AC-90** The README's balance section records every change made to the initial stats and the play-test that motivated it.
- [x] **AC-91** The architecture document shows the two layers of section 6 and which module owns each rule.
- [x] **AC-92** The test plan document lists every acceptance criterion with its test name or manual check.
- [x] **AC-93** A short demo recording (or a scripted replay playing back in the browser) shows an economy, a barracks, a fight and a victory.
- [x] **AC-94** The README explains A* and the finite-state machine in your own words, with a worked example from the tests (AC-13 and AC-62).
- [x] **AC-95** The README states the simplifications of v1 (pathfinding ignores fog, units share cells, no line-of-sight, finite nodes).
- [x] **AC-96** Each decision in section 19 that you changed during the project is updated in the log with the reason.

## 13. Traceability to the Guide's Acceptance Criteria

| Guide criterion | Covered by |
| --- | --- |
| AC-01 Map | AC-08 to AC-11, AC-26 |
| AC-02 Selection | AC-20 to AC-24 |
| AC-03 Movement | AC-12 to AC-19, AC-25 to AC-28 |
| AC-04 Economy | AC-07, AC-29 to AC-35 |
| AC-05 Construction | AC-36 to AC-38 |
| AC-06 Production | AC-39 to AC-42 |
| AC-07 Combat | AC-43 to AC-50 |
| AC-08 AI | AC-62 to AC-67 |
| AC-09 Fog of war | AC-54 to AC-61 |
| AC-10 End state | AC-51 to AC-53 |
| AC-11 Persistence and config | AC-05, AC-87 |
| AC-12 Regression | AC-03, AC-06, AC-89 |

## 14. Non-Functional Requirements

| Area | Requirement |
| --- | --- |
| Determinism | Integer-only simulation state; one seeded generator; no clock or global random function in the simulation |
| Architecture | The simulation core has no scene-tree dependencies and runs headless; the UI never mutates simulation state |
| Language | Typed GDScript (type hints on all functions and variables in `scripts/sim/`) |
| Performance | The budgets in AC-18, AC-58, AC-69 and AC-77; optimise only after measuring |
| Code quality | Each module has one responsibility and a short comment on its rules; no module reaches into another's internals |
| Reproducibility | A pinned Godot version and a clean setup guide (AC-87) |
| Robustness | Invalid commands, empty selections and missing nodes never crash the game; they return a result code or a message |

## 15. Testing Strategy

| Layer | What it checks | Tooling |
| --- | --- | --- |
| Unit | Pathfinding, transactions, placement, production timers, combat arithmetic, fog radius, transition table | A headless GDScript test framework such as GUT (confirm the version for your Godot, or use gdUnit4; record the choice) |
| Property and fuzz | Invariants and conservation under random commands (AC-06, AC-07, AC-26); A* against breadth-first search (AC-15) | Seeded random tests in the same framework |
| Determinism | Same seed gives the same hash; replay reproduces the match (AC-03, AC-04) | The simulation's state hash |
| Metamorphic | AI output unchanged when hidden information changes (AC-60) | Paired worlds |
| Match-level | Whole headless matches: firewall violations, stuck time, AI milestones (AC-61, AC-64 to AC-66) | The headless runner |
| Experiment | Win rates with confidence intervals (AC-70 to AC-72) | The headless runner and a small analysis script |
| Manual | The play-test checklist, the second-device check, the browser network panel | A recorded checklist |
| Deployment | Container build, health, restart, headers, size | Docker and a smoke-test script |

Expected values come from the calculations in the acceptance criteria, not from copying the game's own output. The full list of tests and manual checks is kept in `docs/test-plan.md` (AC-92).

## 16. The Strategy Experiment

After the MVP passes, compare the three policies.

1. **Fair setup.** Maps are point-symmetric, and every seed is played twice with the two policies swapped between the start positions, so a start-position advantage cancels out. AC-71 checks this with identical policies on both sides.
2. **Controlled settings.** Same stats, same map seeds, same match limit for every pairing.
3. **Metrics.** Winner, outcome (including `timeout`), match duration, time to first attack, resources gathered, and units lost, recorded per match.
4. **Statistics.** Win rate with a Wilson 95% confidence interval; paired comparison across seeds; report draws and timeouts separately.
5. **Honest conclusions.** A policy that wins more often in this set of matches is better *under these rules and maps*, not universally. Discuss what the experiment cannot show (other maps, other stat balances, a human opponent, rule changes).

## 17. Edge Cases and Risks (from the guide, with the rule that handles each)

| Risk | Handled by |
| --- | --- |
| Insufficient resources | The single transaction rule (5.3), AC-32 |
| Blocked destination or no route | AC-14, AC-19, AC-28 |
| A unit dies while moving or attacking | AC-45, AC-48 |
| A building placement overlaps something | AC-36 |
| The spawn area is blocked | AC-41 |
| Repeated clicks issue duplicate orders | The replace-the-order rule (5.2), AC-24 |
| The AI becomes idle | The fallback rule (7.1), AC-64 |
| Fog-of-war leakage | The observation firewall (7.2), AC-59 to AC-61 |
| Scope creep | Stretch features stay frozen until every must-have AC passes |
| Performance | Small map and unit cap; budgets measured (AC-18, AC-58, AC-77) |

## 18. Build Order

Build in this order, because each step depends on the one before it. A step is done when its acceptance criteria pass. There are no time estimates; go as fast as the tests allow.

| Step | Build | Acceptance criteria |
| --- | --- | --- |
| 1 | Repo and Godot project setup, the test framework running headless, the simulation skeleton (tick, integer maths, seeded generator, state hash), map loading and the generator, and a walking-skeleton web export, `Dockerfile` and compose file serving a placeholder scene | AC-01 to AC-05, AC-08 to AC-11 |
| 2 | Entities, A* and movement, the command interface, the invariant checker | AC-06, AC-12 to AC-20, AC-25 to AC-28 |
| 3 | Resource manager, harvesting, depletion, drop-off | AC-07, AC-29 to AC-35 |
| 4 | Building placement, construction, production queues, spawning | AC-36 to AC-42 |
| 5 | Combat, auto-acquire, and the end-of-match rules | AC-43 to AC-53 |
| 6 | Fog of war and the observation | AC-54 to AC-58 |
| 7 | The presentation layer: map drawing, selection controller, HUD, menu, camera | AC-21 to AC-24, AC-73 to AC-78 |
| 8 | The enemy AI and its tests | AC-59 to AC-67 |
| 9 | Replays, the headless runner, the Wilson interval, and the strategy experiment | AC-68 to AC-72 |
| 10 | Production deployment and documentation: container, headers, size, README, architecture and test-plan documents, demo | AC-79 to AC-96 |
| 11 | Stretch: minimap, sound, more maps, attack-move, shift-queue, line-of-sight fog, unit collision | None required |

Steps 7 and 8 both depend only on step 6, so they can be built in either order or in parallel. Keep the container from step 1 working throughout: rebuild and open it after every step.

**If you need to cut scope, cut in this order:** all of step 11, the optional public host, the strategy experiment's third policy, then the experiment itself (step 9). Never cut the invariant checker, the determinism test, the observation firewall, or the asset rules.

## 19. Decisions Log

| ID | Date | Decision | Alternatives | Why |
| --- | --- | --- | --- | --- |
| D-01 | 2026-10-13 | Godot 4 with typed GDScript, as the guide recommends | Python with Pygame | Scenes, input and UI come built in, and Godot exports to the web for deployment; Pygame would suit a purely algorithmic project |
| D-02 | 2026-10-13 | A deterministic simulation core separate from presentation, with a fixed 20 Hz tick | Game logic inside scene scripts driven by frame time | Rules become testable without a window, headless matches run fast, and the experiment and replays become possible |
| D-03 | 2026-10-13 | Four-directional movement and A* with the Manhattan heuristic | Eight-directional movement; Dijkstra | The guide's recommendation; the heuristic is admissible and consistent, so paths are optimal (AC-15, AC-16) |
| D-04 | 2026-10-13 | Units do not block each other and may share a cell (the "share a cell" part replaced by D-42; units still pass through each other while walking) | One unit per cell with collision resolution | Avoids deadlocks and crowding code; unit collision is a stretch goal |
| D-05 | 2026-10-13 | Finite resource nodes that vanish when exhausted | Renewable nodes | Creates economic pressure, makes depletion a tested edge case, and bounds the match |
| D-06 | 2026-10-13 | Costs are deducted at placement and at enqueue, refunded once on cancel | Deduct when production starts | One clear rule and one place to test; matches the guide's "check, deduct once, act" |
| D-07 | 2026-10-13 | A finite-state machine with a priority list, roles and an observation firewall, parameterised into policies | Behaviour trees; scripted build orders; machine learning | Understandable, testable, and the same machine yields the policies for the experiment |
| D-08 | 2026-10-13 | Point-symmetric generated maps and side swapping | Hand-made asymmetric maps | Removes start-position bias so policy comparisons are fair (AC-71) |
| D-09 | 2026-10-13 | Web export with the Compatibility renderer and thread support off | Threads enabled | Since Godot 4.3 single-thread export works without cross-origin-isolation headers, so the game can be served by any static server |
| D-10 | 2026-10-13 | A headless GDScript test framework (GUT or gdUnit4), recorded in the README | In-game test scenes | Tests run in the command line and in CI |
| D-11 | 2026-10-13 | Stats in `data/units.json` | Constants in code | Balance changes need no code edits, and the file is validated (AC-05) |
| D-12 | 2026-10-13 | Replays as JSON-lines command logs | Recording state snapshots | Small, readable, and enough because the simulation is deterministic |
| D-13 | 2026-10-13 | Wilson intervals for win rates | Normal-approximation intervals | Stays valid for small samples and extreme rates |
| D-14 | 2026-10-13 | A new order replaces the current order (still the default; build step 11 adds Shift-queued orders, D-44) | Queue orders | Predictable and testable; queued orders are a stretch goal |
| D-15 | 2026-10-13 | Pathfinding uses true terrain, while all decisions use observations only | Fog-limited pathfinding | A common RTS simplification, documented; it does not leak enemy positions |
| D-16 | 2026-10-13 | Integer-only simulation (milli-cells and ticks) | Floating-point positions | Exact, platform-independent results, so hashes and replays always match |
| D-17 | 2026-10-13 | An unprivileged nginx container serving the web export | A Node or Godot server | The export is static files, so no server-side code is needed |
| D-18 | 2026-10-15 | Pin Godot **4.7.2-stable** (latest stable on 2026-10-15), the same version in README and Dockerfile | Godot 4.3 | Newest fixes for single-thread web export; one pinned number everywhere |
| D-19 | 2026-10-15 | GUT **9.6.1** as the test framework (listed in `ASSETS.md`) | gdUnit4 | Simple headless CLI; MIT licence |
| D-20 | 2026-10-15 | Two test suites: a fast suite (AC-89, ≤ 2 min, reduced iteration counts) and a long suite that runs the full counts of AC-06, AC-07, AC-10, AC-15, AC-61, AC-64 to AC-66 and records the results | Lower the counts; relax AC-89 | The full counts cannot fit in 2 minutes in GDScript; both suites run the same test code |
| D-21 | 2026-10-15 | Shapes drawn in code; default map stays 48 × 48 (the art part was replaced by D-38) | CC0 sprites; 32 × 32 map | No licence work; spec sizes unchanged |
| D-22 | 2026-10-15 | AC-10 symmetry compares footprints: a w × h building anchored at `(x, y)` mirrors to the anchor `(48 − w − x, 48 − h − y)` (a 3 × 3 HQ: `(45 − x, 45 − y)`) | Compare anchors with `(47 − x, 47 − y)` | Anchors are top-left cells, so mirroring a multi-cell footprint shifts the anchor |
| D-23 | 2026-10-15 | `retreat_fraction` stored as an integer percentage (40, 25, 50); the check is `army * 100 < pct * start_army` | Floating-point fraction | The AI is in `scripts/sim/`, which is integer-only |
| D-24 | 2026-10-15 | A non-soldier given an `attack` order returns `invalid_target` (AC-47) | A new result code | Uses an existing code |
| D-45 | 2026-10-17 | Phones and tablets (the user asked that the game work on all mobiles). Touch mode turns on for Android and iOS browsers and mobile builds, with `?touch` in the web address, or after the first real touch. One finger dragging pans the map; a tap on an own unit or building selects it; a tap anywhere else orders the selection there, the same as a right click (move, gather, attack); with nothing selected a tap shows what was tapped. A toolbar replaces the keys and the right mouse button: Box select (the next drag draws a selection box), All soldiers, Attack-move, Queue (Shift), Cancel (Esc). Barracks placement: the preview starts mid-screen, a tap moves it, a second tap on the same spot builds. Edge panning is off. The interface is laid out for at least 1180 x 560 virtual pixels (the bottom panel moves to the left so it never covers the minimap), the menu is compacted, a notice asks to turn the phone sideways in portrait, and the installed web app opens full screen in landscape. Presentation only; checked by `test_touch_d45.gd` and in a browser emulating an Android phone (844 x 390, touch only) | Long-press for orders; pinch zoom; a separate mobile build | Taps and one-finger drags are what every phone user knows; the simulation and its commands are unchanged, so touch play is exactly as fair and testable as mouse play |
| D-44 | 2026-10-17 | Attack-move and Shift-queued orders (build step 11). `attack_move(unit_ids, cell)`: the units get the same formation as a move; soldiers walk with the order `attack_move`, auto-acquire enemies in vision on the way like idle soldiers, fight, and when the target dies or leaves vision carry on to the destination (`am_cell` remembers it); workers just move. `queue: true` on move, attack_move, attack or harvest appends the order to the unit's queue (at most 8; a 9th returns `queue_full` and changes nothing) after being checked as far as it can be (a cell, or an existing node or enemy); an idle unit takes up an interrupted attack-move first, else its next queued order at the start of a tick, skipping orders that can no longer run (a target that died is also removed from every queue). A plain order clears the queue and ends an attack-move, so D-14 still holds. Building is not queueable (its cost is paid at placement, which a queue would delay). UI: `F` then click (also on the minimap), Shift to queue, dashed waypoint lines for the selection. Checked by `test_orders_d44.gd` | `A` for attack-move (taken by camera panning, WASD); queue build orders too | The two most common RTS order tools; both keep every rule of the simulation (same validation, deterministic, recorded in replays as ordinary commands) |
| D-43 | 2026-10-17 | Build step 11 started (at the user's request, while AC-78 and AC-84 still wait for their manual checks) with the minimap: bottom-right of the HUD, 176 px on its longest side; terrain (grass, forest, rock, roads), the player's fog (unexplored dark, explored dimmed), nodes and buildings as the player remembers them (ghosts for unseen enemy buildings), own units and only the enemy units visible now (everything in the demo), red pings at fights the player sees, and the camera's view as a frame. Left click or drag moves the camera; right click gives the selection the same context order as a right click on the map. Presentation only, checked by `test_minimap.gd` | A minimap that shows every unit; a separate minimap window | It must leak nothing the fog hides (the same rule as the main view, AC-56); orders through it use the same context-order path as the map, so no new command is needed |
| D-42 | 2026-10-17 | Spacing (`scripts/sim/spacing.gd`): units still pass through each other while walking (no blocking, so no jams or deadlocks) but do not stop on one cell. (1) A group move gives each unit its own cell: the unit nearest the goal stands on it, the rest fill free cells ring by ring, each taking the ring's free cell nearest to itself (a blocked goal still returns `no_path`, AC-28). (2) A melee soldier attacking a unit walks to the free cell next to the target nearest to itself (the target's own cell only if all eight are taken), re-planning when the target changes cell; attackers of a building head for a touching cell nobody holds. (3) Every 5 ticks, units standing still on a cell another (lower-id) unit stands on step to a free neighbour (straight neighbours first, then diagonals); an attacker only steps where its target stays in range. Gathering and building workers are left alone. AC-27 reworded accordingly; the demo replay was re-recorded, the strategy experiment re-run (same ranking; Balanced vs Balanced still shows no start bias) and the long suite re-run (184 / 184) under the new rules. On screen the camera zoom went from 1.35 to 1.6 with soldiers kept at the same screen size, so a soldier is a little smaller than a cell and neighbours do not overlap, and melee fighters are drawn standing back slightly from their enemy | Hard one-unit-per-cell collision with waiting and re-routing; spacing on screen only | The user found fights clumsy ("they are just merging into one another") and chose a rule change over a visual-only fix; soft spacing gives clear lines of fighters without the deadlocks of hard collision |
| D-41 | 2026-10-17 | Fights redone at the user's request (units did not really animate, fights looked like a blob, no sound, units too small): units are animated Liberated Pixel Cup characters (walk, sword slash, bow shot, axe chop, pickaxe mining, hammering, falling when killed; 4 directions), assembled from LPC parts by `tools/make_units.gd` in blue and red, drawn one sprite pixel per screen pixel (about 50 px tall); the ranged soldier is drawn as an archer whose arrows fly at the bow's release frame, and sword sparks come when the swing connects; nearby units push apart on screen (drawing only, D-04 unchanged, so AC-27 still holds); damage numbers only on buildings; CC0 sound effects (Kenney) and music (cynicmusic), the battle theme fading in while fighting is on screen, `M` to mute. The LPC art is CC-BY-SA 3.0, so `assets/lpc/CREDITS.md` and an in-game Credits screen name every artist (checked by a test) | Ninja Adventure pack (CC0, but a different art style for the whole game); keep the still Kenney units and animate them in code | The user chose LPC: the only medieval set with real frame-by-frame combat animations in four directions; CC-BY-SA is permitted by rule L1 as long as each source and licence is recorded |
| D-40 | 2026-10-17 | AC-77 is measured by a built-in benchmark mode (`-- --bench` on the desktop, `?bench` on the web): the seed-42 map with 80 units (40 per side, placed around each HQ by the simulation's setup helper, the same one the tests use), both armies sent to the middle, no AI, no fog, 15 s after a 2 s warm-up; it reports average FPS and the 1 % low. Unit shadows and team rings are stamped from two cached textures and world health bars are plain rectangles, instead of anti-aliased shapes tessellated every frame | Measure by hand with F3 during a match | Repeatable on any machine, desktop and web alike; the drawing change lifted the desktop result from 72 to 109 FPS (1 % low 29 to 50) |
| D-39 | 2026-10-17 | Visual polish, presentation layer only: animated units (walk hop, chop, hammer, attack lunge, idle breathing, falling when killed), magic bolts and sword hits with particles from Kenney's CC0 "Particle Pack" (resized to 128 px), floating damage and resource numbers, smoke and fire on damaged buildings, collapse debris, rubble and screen shake; terrain with worn roads, base clearings, flowers, swaying trees, a forest border and drifting cloud shadows (the ground is baked once into one texture); fog as drifting clouds over unexplored ground and a desaturated memory of explored ground; a colour grade and vignette; animated menu battle, screen fades, a pop-in end dialog, custom cursors and animated order markers. Effects use their own random generator, never the simulation's | Godot's GPUParticles2D; a different art pack (licence not CC0) | The user asked for much richer graphics; CPU particles drawn in code work the same on desktop and web with the Compatibility renderer; baking the ground keeps the frame cost low (measured about 5 ms instead of 120 ms for the terrain on a software renderer) |
| D-38 | 2026-10-17 | Replace the code-drawn look with Kenney's CC0 "Medieval RTS" sprites (units, castle HQ, barracks, trees, rocks, gold, grass) and "UI Pack: RPG Expansion" (wooden frames, parchment, buttons, bars), with the Cinzel and Alegreya Sans fonts (SIL OFL); the player is blue and the AI red; the world camera is zoomed 1.35×. Every file is listed in `ASSETS.md` (AC-85); team rings, banners, bars and effects are still drawn in code | Keep improving the code-drawn shapes; paid asset packs | The user found the code-drawn look too plain and dark; CC0 needs no attribution and the asset check still covers every file. Drawing only: the simulation is unchanged |
| D-37 | 2026-10-17 | Also offer a Streamlit Community Cloud link: `streamlit/streamlit_app.py` (Streamlit 1.66.0) shows the GitHub Pages build full-window in an iframe | Serve the Godot files from Streamlit itself | The user wanted a Streamlit-style link; embedding the tested Pages build keeps one source of truth and needs no Python port of the game |
| D-36 | 2026-10-17 | Besides the web link, ship the game as an installable web app (PWA, enabled in the Web preset) and as a single-file Windows `.exe` (Windows Desktop preset, data embedded) published on GitHub Releases; the app icon is rendered from the game's own art by `tools/make_icon.gd` | Only the web link; a signed installer | The user asked for an app as well as a link; both reuse the same pinned Godot and the same tested code |
| D-35 | 2026-10-17 | Experiment details: side A's win rate is wins over decisive matches (draws and timeouts reported separately); the paired comparison counts, per seed, whether A won both swapped matches, B won both, or they split, with a two-sided sign test on "won both"; the generated map for seed `s` is `MapGenerator.generate(s)`; the CSVs live in `docs/experiment/` (committed) and the tables are produced by `tools/analyze.gd`; a replay records firewall-rejected AI commands and playback re-counts them instead of applying them | Count draws as half wins; a paired t-test on durations | Keeps the report honest and reproducible from the committed CSVs |
| D-34 | 2026-10-17 | Only enemy **soldiers** count as threats in row 1 of the AI's priority list (was "any visible enemy unit") | Keep building while in DEFEND; run AC-65 on a 48 x 48 map | On the tutorial map the HQs are 4 cells apart, so the player's idle workers kept the AI in DEFEND forever and AC-65 could never pass; workers cannot attack, so they are not a threat |
| D-33 | 2026-10-17 | AI details the priority list leaves open: ATTACK continues until row 1 or row 3 applies, RECOVER until row 4 applies, DEFEND holds until 100 ticks without a threat, and BUILD ends when a barracks exists or after 600 ticks (then BUILD may not start again for 600 ticks); production and gathering run under every state, and BUILD reserves the barracks cost first; a scout exists only while no enemy building is known and stops 4 cells short of each possible start; the stuck fallback also sends one idle unit to explore; a firewall violation returns `unknown_entity` and is counted; the controller that links AI and simulation lives outside `scripts/sim/ai/` | Row 6 ending an attack on the next decision; a new result code | Read literally, row 6 would cancel every attack 10 ticks after it started |
| D-32 | 2026-10-17 | Interface details: clicking an enemy, a node or a ghost clears the selection and shows only its details; a building is selected alone; a right click on a node sends only the selected workers, on a visible enemy only the selected soldiers, and a hidden enemy's cell counts as empty ground (move); the selected worker nearest to a placement builds it; `W` trains a melee soldier while a building is selected and pans the camera otherwise; units standing on exactly the same spot are drawn fanned out (drawing only); the look is shapes drawn in code with the Chakra Petch font (OFL, in `ASSETS.md`; replaced by D-38); F3 shows frames per second, to measure AC-77 | Keep the selection when inspecting an enemy; a separate key for melee training | Matches the spec's controls with the fewest surprises; W was listed for both training and panning |
| D-31 | 2026-10-16 | Fog details: fog is recomputed when the tick is a multiple of 5 and at the start; a newly spawned unit or placed building reveals its circle at once; a building sees from the nearest cell of its footprint and a unit from the cell it stands on; each row is stored as a 64-bit mask (one bit per cell), so maps are at most 62 cells wide; the observation also holds resource nodes, remembered like enemy buildings (as last seen, forgotten when the site is seen empty), because the AI needs them to gather; attacking a building needs a currently visible footprint cell, so a ghost alone is not enough | Recompute every tick; one byte per cell; give the AI every node | Meets the 2 ms budget (measured 0.8 ms, was 4.1 ms with one byte per cell); nodes as last seen leak nothing about enemy harvesting |
| D-30 | 2026-10-16 | Combat details: one tick runs re-plan → auto-acquire → combat → unit orders and movement → construction and production → remove the dead → end-of-match check; attackers are chosen on the state at the start of the tick, then damage is applied in id order, skipping a target already at 0 health (it "cannot be damaged twice in the tick it dies") without using up that attacker's cooldown; a unit target's footprint is the cell holding its position; auto-acquire picks the nearest enemy unit or building within the soldier's own vision (squared cell distance, ties lowest id) until fog of war adds faction vision in step 6; a player-ordered attack chases until the target dies; a worker that dies carrying resources loses them (`lost` in the ledger, so conservation still balances); a faction is defeated when it has no HQ left | Resolve attacks one by one as they happen; let a skipped attack use its cooldown | Matches AC-45 and AC-46 exactly; simple and deterministic |
| D-29 | 2026-10-16 | Construction details: until fog of war exists (build step 6) every cell starts explored, and only the explored grid is built now (`fog.gd`); `build` on the anchor of one's own unfinished building of the same type resumes it at no cost; a placement is also rejected with `no_path` (nothing paid) if the builder could not reach the site once its footprint is solid; construction gains 1 progress per tick when at least one builder is beside it, however many there are; building health stays full during construction | Mark only cells near the HQ explored now; a separate resume command; let builders speed up construction | Keeps the fog [LEARN] module for step 6; resuming needs no new command; a paid-for site is always reachable |
| D-28 | 2026-10-16 | Economy details the spec leaves open: "adjacent" means any of the 8 cells touching a footprint (for harvesting and deposits); the nearest HQ by path length is found with one breadth-first search to every free cell touching a friendly HQ (ties: lowest HQ id); a replacement node is the nearest of the same type with squared Euclidean distance ≤ 100 cells² from the exhausted node; a worker gathering or walking to a node goes idle with `no_node` at once when none exists, while a worker already walking home deposits first; cancelling a queue index that does not exist returns `invalid_target` | A* to each HQ separately; distance from the worker; reject with `invalid_amount` | One search finds the nearest HQ exactly; the 10-cell radius uses the same measure as vision; the last load of an exhausted node is never lost (AC-30) |
| D-27 | 2026-10-15 | Command details the spec leaves open: checks run in the order `match_over`, unknown command, `unknown_entity`, `not_owner`, `invalid_amount`, then command rules, and nothing changes until all pass; one bad id rejects the whole command; repeated ids count once; a `move` to a group returns `ok` if at least one unit has a path (the others go idle with `no_path`); moving a building returns `invalid_target`; the 3 starting workers take the first 3 free spawn cells, one each | Reject a group if any unit has no path; stack starting workers on one cell | Predictable, testable rules; the state hash is unchanged by any rejected command (AC-20) |
| D-26 | 2026-10-15 | The public web build is **required** (AC-86 no longer optional): GitHub Pages from the public repo `mini-rts`, deployed by GitHub Actions on every push to `main` after the fast test suite passes; the course guide `.docx` stays out of the public repo | itch.io; private repo with a separate Pages repo | One shareable link that always matches `main`; no extra accounts; failing tests block the deploy |
| D-25 | 2026-10-15 | Clarifications: AC-25's "15-cell path" means 15 steps; AC-10's "within 15 cells" means path length; placement must be explored by the *placing faction*; "none" in `units.json` is stored as 0 | — | Removes ambiguity before writing tests |

## 20. Open Questions

- [x] Which exact Godot version will you pin (4.3 or later is needed for single-thread web export), and which release template source will the Docker build use? **Godot 4.7.2-stable; official GitHub release templates, SHA-512 verified (D-18).**
- [x] GUT or gdUnit4 for tests, and does the chosen version support your Godot version? **GUT 9.6.1, verified running on 4.7.2 (D-19).**
- [x] Placeholder shapes drawn in code, or CC0 sprites (for example from a public-domain asset pack)? Record any pack in `ASSETS.md`. **Shapes drawn in code (D-21), changed to Kenney CC0 sprites (D-38).**
- [x] Is 48 × 48 the right map size, or do you want smaller for faster matches? **48 × 48 (D-21).**
- [x] Do you want a minimap or sound before the strategy experiment, or after it? **After; sound and music added with the combat rework (D-41); minimap still to come.**
- [ ] Should the experiment include a fourth policy, such as a defensive one?

## 21. Definition of Done

- [ ] AC-01 to AC-85 and AC-87 to AC-96 pass or have a recorded measurement (AC-86 is optional).
- [ ] The invariant checker, determinism, replay and observation-firewall tests pass in the normal suite.
- [ ] The strategy experiment is run and honestly reported (AC-72).
- [ ] The game runs in its container on your computer, and you have opened it from a second device on your network.
- [ ] The README, architecture document and test plan are complete, with known limitations stated.
- [ ] You can explain every module and algorithm without notes.

## Appendix: Viva Checklist

The guide's questions, with the extra questions this design invites. Be ready to answer without notes.

1. Why is this a real-time strategy game, and what makes the simulation "real time" when it runs in fixed ticks?
2. How does A* work, what do `g`, `h` and `f` mean, why is Manhattan distance a good heuristic for four-way movement, and how did you check that your paths are shortest (AC-15, AC-16)?
3. Why use a finite-state machine for the AI, how does your transition priority list work, and how does it differ from a scripted sequence?
4. What stops two states from giving one unit conflicting orders (roles and order ownership)?
5. What is fog of war, and what is the observation firewall? How does your metamorphic test show that the AI is not cheating?
6. How do you prevent resource bugs? Walk through the single transaction rule, the conservation test and the exactly-once refund.
7. Why is the simulation separate from the graphics, and what did that make possible (headless tests, replays, the experiment)?
8. Why are all simulation values integers, and what would go wrong with floating point?
9. How do you know the game is complete? Point to the acceptance criteria, the traceability table and the test plan.
10. How did you make the AI comparison fair (symmetric maps, swapped sides, same seeds), what is a Wilson confidence interval, and what can the result not tell you?
11. How does the web export work, why is thread support off, and what does the container serve?
12. Which simplifications does v1 make (units share cells, pathfinding ignores fog, no line of sight), and how would you remove each?