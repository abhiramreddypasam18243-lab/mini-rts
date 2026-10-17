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
