# Manual Play-Test Checklist (AC-77, AC-78)

Run these by hand and record the date and result. The automated tests cannot judge feel, readability or frame rate.

## AC-78 Play-test checklist

| # | Check | How | Result | Date |
| --- | --- | --- | --- | --- |
| 1 | A new player can select and command a unit | Start a random map; click a worker, right-click the ground | pending | |
| 2 | A player can collect enough to produce a soldier | Gather wood and gold, build a barracks (B), train a melee soldier (W) | pending | |
| 3 | The AI makes progress without getting stuck | Start a match, press F3 to see the AI state; watch it move through ECONOMY → BUILD → ATTACK over about 3 minutes | pending | |
| 4 | The player can win and lose | Destroy the AI HQ; in another match do nothing (the Balanced AI attacked a passive player at about 2:06 in testing) | pending | |
| 5 | A restart leaves nothing from the previous match | Play a while, press Restart: resources 200/100, 3 workers, clock 00:00, nothing selected | pending | |

## AC-77 Frame rate

Measured with the built-in benchmark (decision D-40): the seed-42 map with exactly 80 units (each side's 3 workers plus 37 soldiers), both armies marching into each other and fighting, every unit drawn (no fog), all effects on, 15 seconds after a 2-second warm-up, 1280 × 720. Start it with `MiniRTS.exe -- --bench` (desktop) or by adding `?bench` to the web address; the result appears on screen and in the log as a `BENCH` line. Press **F3** in any match to see the live frame rate.

| Build | Target | Average | 1 % low | Machine | Date |
| --- | --- | --- | --- | --- | --- |
| Desktop (`MiniRTS.exe`, Windows 11) | ≥ 60 FPS | **85 FPS** | 54 FPS | Laptop, NVIDIA GeForce RTX 4050 Laptop GPU, OpenGL 3.3 | 2026-10-17 |
| Web (Microsoft Edge, WebGL 2) | ≥ 30 FPS | **70 to 73 FPS** (two runs) | 26 to 35 FPS | Same laptop | 2026-10-17 |

These are the results with the animated LPC units, sound and music (D-41). Before D-41 the same benchmark gave 109 FPS desktop and 80 FPS web: the animated units, the on-screen separation and the sound cost about 2 to 6 ms a frame.

Before the drawing fix of D-40 the desktop build measured 72 FPS average (29 FPS 1 % low); world drawing then took 5 to 12 ms a frame and now takes 1 to 4 ms. The 1 % low (the average of the slowest 1 % of frames) shows occasional slower frames below 60 on the desktop; the average meets the target.

## Screens checked during build step 7

Screenshots were taken of the main menu, the game at start, box selection, gathering, barracks placement (green ghost), construction, the HQ training queue, a skirmish and the victory overlay (headless Edge with WebGL for the web build, and `tools/ui_snapshot.gd` for staged scenes).
