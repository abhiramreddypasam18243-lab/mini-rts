# CLAUDE.md: Mini Real-Time Strategy Game

@SPEC.md

The spec above is the source of truth. If the code and the spec disagree, stop and tell me which one should change. Do not quietly change either. The original assignment guide is `docs/Mini_Real_Time_Strategy_Game_Project_Guide.docx`; the spec's section 13 maps its criteria onto the spec's.

## About me and this project

I am an undergraduate student building this as a graded project. I will be quizzed on it in a viva, so I must understand every module. I want to finish as fast as possible, so keep the pace high and the explanations short.

## How to work

1. **Follow the build order in section 18 of the spec**, one step at a time. Finish a step (all its acceptance criteria passing) before starting the next. Do not stop in the middle of a step unless you are blocked, a **[LEARN]** module comes up, or the spec has an open question you need me to answer.
2. **Tests first.** For each acceptance criterion, write the failing test, then the code that makes it pass. Name each test after its AC ID (for example `test_ac_13_wall_with_gap`).
3. **Derive expected values by calculation**, as the acceptance criteria do. Never copy the game's own output into a test as the expected answer, and never edit a test value or a threshold to make a test pass. If a test seems wrong, tell me.
4. **Run the tests headless** after every change, and fix failures before moving on. Show me the test results at the end of each step.
5. **Move fast.** Do not pause for review between modules. At the end of each step, give me a short summary: files changed, tests passing, anything I should check.
6. **Ask before deciding.** If the spec leaves a choice open (section 20), ask me. When we decide, add a row to the Decisions Log in `SPEC.md`.
7. **Do not add features** that are not in the spec. Suggest them at the end instead, and keep the stretch list frozen until the must-have criteria pass.

## Learning rules

- At the end of each step, add a short entry to `docs/learning-log.md`: what was built, why it is designed that way, one thing that could go wrong, and 3 quiz questions for me (no answers; I will answer them myself).
- These modules are marked **[LEARN]**. For them, first explain the design and the key edge cases in a few sentences, then let me write the first version myself and review it afterwards:
  - The A* pathfinder (spec sections 5.2 and 12, AC-12 to AC-17)
  - The resource transaction and the production queue accounting (AC-32, AC-33, AC-07)
  - The AI's transition function and the observation firewall (spec section 7, AC-59 to AC-62)
  - Fog-of-war visibility (spec section 5.6, AC-54 to AC-57)
- If I say "you write it" for a **[LEARN]** module, write it, and still add its learning-log entry.
- If I ask "why", explain with a small concrete example, not just a definition.

## Project rules

- **Two layers:** the simulation core in `scripts/sim/` extends `RefCounted` only. No scene tree, no nodes, no rendering, no real clock, no `randf`, `randi` or `randomize`. The UI reads state and sends commands; it never changes simulation state directly.
- **Integers only** in simulation state: positions in milli-cells, distances compared as squared integers, times in ticks. No floating point in `scripts/sim/`. Floating point is allowed only when drawing.
- **Typed GDScript:** type hints on every function and variable in `scripts/sim/`.
- **AI firewall:** the AI receives an `Observation` and returns commands. It must never import, reference or receive the simulation or world. The simulation rejects commands that target unobserved entities and counts them as violations.
- **Every spend** goes through the one transaction in `resource_manager.gd`: check non-negative, check affordable, deduct once, then act.
- **Determinism:** the same seed and commands must give the same state hash. Do not iterate over unordered collections in ways that change results; process entities in ID order.
- **Assets and licences:** never add an asset or borrowed code without recording its source and licence in `ASSETS.md`. Prefer shapes drawn in code.
- **Dependencies and versions:** pin the Godot version and the test framework version. Ask before adding an add-on.
- **Deployment:** the game must always run as a container (spec section 10). Build the walking-skeleton web export, `Dockerfile` and `docker-compose.yml` in step 1, keep them working, and rebuild after each step. Export with the Compatibility renderer and thread support off. The container must run as a non-root user and serve on port 8080.

## Commands

Pinned: Godot 4.7.2-stable, GUT 9.6.1 (verified 2026-10-15). In WSL the binary is `~/godot/godot`; templates are in `~/.local/share/godot/export_templates/4.7.2.stable/`.

- Run the fast unit tests headless (verified): `GODOT=~/godot/godot tools/run_tests.sh` (runs `--import`, then `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -ginclude_subdirs -gexit`)
- Run the long suite with full counts (verified): `GODOT=~/godot/godot tools/run_tests.sh --long`
- Run headless matches (not yet built, step 9): `godot --headless --script res://tools/run_matches.gd -- --matches 200 --out results.csv`
- Export the web build: `godot --headless --export-release "Web" build/web/index.html`
- Run the deployed service: `docker compose up -d --build` (from WSL), then open `http://localhost:8080`

## Git

Commit after each completed step, with a message that names the AC IDs, for example `Add A* pathfinder and movement (AC-12 to AC-19)`.