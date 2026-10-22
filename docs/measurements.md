# Measurements

Performance targets marked *(initial target)* in SPEC section 12, with the measured values.

| AC | Target | Measured | Date | Machine and method |
| --- | --- | --- | --- | --- |
| AC-18 | Worst-case 48 × 48 path ≤ 5 ms | **2.0 ms** (average of 20 runs, 1,175-step serpentine maze) | 2026-10-15 | Laptop, WSL2 Ubuntu 24.04, Godot 4.7.2 headless, `test_ac_18_worst_case_48_by_48_within_budget` |
| AC-83 | First-load transfer ≤ 20 MB (compressed) | **10.2 MB** (`index.wasm` 10.1 MB gzipped, `.js` 69 KB, `.pck` 26 KB) | 2026-10-15 | `curl` with `Accept-Encoding: gzip` against the container and GitHub Pages |
| AC-58 | Fog update for 80 units on 48 × 48 ≤ 2 ms | **0.8 ms** (average of 50 updates, both factions; was 4.1 ms with one byte per cell before switching to row bitmasks) | 2026-10-16 | Laptop, WSL2 Ubuntu 24.04, Godot 4.7.2 headless, `test_ac_58_update_for_80_units_within_2_ms` |
| AC-64 | Longest quiet stretch ≤ 200 ticks | **190 ticks** over 100 matches; every stuck event triggered the fallback | 2026-10-17 | Long suite, `test_ac_64_never_quiet_for_more_than_200_ticks_and_stuck_triggers_fallback` |
| AC-65 | Tutorial map: barracks and ≥ 3 soldiers by tick 6,000, 20 of 20 seeds | **20 / 20** (after decision D-34) | 2026-10-17 | Long suite, `test_ac_65_tutorial_barracks_and_three_soldiers_by_6000_ticks` |
| AC-66 | Balanced beats a passive opponent ≥ 95 of 100 within 18,000 ticks | **100 / 100**, slowest win at tick 2,748 (2 min 17 s of game time) | 2026-10-17 | Long suite, `test_ac_66_balanced_beats_a_passive_opponent` |
| AC-69 | A 30-minute match headless in ≤ 30 s | **7.8 s** per 36,000 ticks (Balanced vs Balanced, 3,311 ticks in 0.7 s, scaled) | 2026-10-17 | `test_ac_69_full_match_runs_at_least_60_times_real_time` |
| AC-70 | Wilson 95 % CI for 120 / 200 ≈ [0.531, 0.665] | **[0.531, 0.665]** (± 0.002) | 2026-10-17 | `test_ac_70_wilson_interval_120_of_200` |
| AC-71 | Balanced vs Balanced: no start-position bias (95 % CI contains 0.5) | Player start won **45 of 96** decided seeds, Wilson CI **[0.372, 0.568]**: contains 0.5 (re-run under the spacing rules of D-42; first run: 44 of 92, [0.379, 0.579]) (side A's own rate is 0.5 by construction, see `docs/experiment.md`) | 2026-10-17 | `tools/run_matches.gd`, 100 seeds × 2; `docs/experiment/balanced_vs_balanced.csv` |
| AC-77 | Desktop ≥ 60 FPS, web ≥ 30 FPS with 80 units | Desktop **82 to 85 FPS** average (1 % low 39 to 50); web **66 to 72 FPS** average (1 % low 23 to 30); current build with D-41 to D-43 | 2026-10-17 | Laptop, NVIDIA GeForce RTX 4050 Laptop GPU, Windows 11; benchmark mode (D-40): `MiniRTS.exe -- --bench` and Microsoft Edge with `?bench`, 1280 × 720, 15 s |
| AC-72 | Pairwise report over ≥ 200 matches each | Aggressive beats Balanced 0.857 [0.801, 0.899]; Balanced beats EconomyFirst 0.766; Aggressive beats EconomyFirst 0.964 [0.928, 0.983] | 2026-10-17 | `docs/experiment.md`, `docs/experiment-tables.md` |
| AC-80 | Container healthy, restarts after a crash, non-root | Healthy; after `kill 1` restarted (restart count 1) and healthy again within 7 s; runs as uid 101 (nginx) | 2026-10-17 | `docker compose ps`, `docker inspect`, `docker compose exec web id` |
| AC-82 | Headers, compression, CSP, no third-party requests | `.wasm` `application/wasm`; `.wasm`/`.pck`/`.js` gzip; CSP with script and style hashes; 7 requests, all to the same origin | 2026-10-17 | `curl -I`; headless Edge request log |
| AC-83 | First load ≤ 20 MB (compressed) | **9.99 MB** (container build, gzip) | 2026-10-17 | `curl --compressed` sizes of every first-load file |
| AC-83 | First load ≤ 20 MB (compressed) | **16.1 MB** (`index.wasm` 10.1 MB, `index.pck` 5.9 MB including 4.6 MB of music, the rest 0.2 MB; gzip -9) | 2026-10-17 | after D-41 (animated units, sound and music); local export, gzip sizes of every first-load file |
| AC-83 | First load ≤ 20 MB (compressed) | **19.1 MB** (`index.wasm` 10.1 MB, `index.pck` 8.8 MB: 4.6 MB music, 3D unit sheets and sprites stored as lossy WebP at quality 0.85; gzip -9) | 2026-10-20 | after D-50; it was 22.0 MB with lossless unit sheets, over the limit, so the sprite imports were switched to lossy |
| AC-83 | First load ≤ 20 MB (compressed) | **19.96 MB** (gzip -9 of `index.html`, `.js`, `.wasm`, `.pck`) | 2026-10-20 | after D-51 (cavalry sheets, farm, tower and stable sprites); only 0.04 MB below the limit, so the next art addition needs the sprite sheets made smaller |
| AC-83 | First load ≤ 20 MB (compressed) | **19.97 MB** (gzip -9 of `index.html`, `.js`, `.wasm`, `.pck`) | 2026-10-20 | after D-52 to D-55 (code only, no new art) |
| AC-83 | First load ≤ 20 MB (compressed) | **19.98 MB** (gzip -9 of `index.html`, `.js`, `.wasm`, `.pck`) | 2026-10-21 | after D-56 (code only) |
| AC-83 | First load ≤ 20 MB (compressed) | **19.98 MB** (19,982,090 bytes) | 2026-10-22 | after D-57 (code only) |
| AC-77 | Desktop ≥ 60 FPS with 80 units | **80 FPS** (two runs: 80.2 and 79.5; 1 % low 50 to 55), on mains power | 2026-10-22 | after D-56 and D-57 (larger units, extra effects); was about 100 FPS. On battery the laptop caps games at 30 FPS, so measure plugged in |
| AC-89 | Unit suite headless ≤ 2 min, fails the build on failure | **about 20 s** (179 tests); exit 1 on a failing test or a script error | 2026-10-17 | `tools/run_tests.sh`; GitHub Actions blocks the deploy |
