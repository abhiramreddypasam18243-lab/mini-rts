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

Press **F3** in a match to show frames per second and the unit count. Measure with 80 units on the map (40 per side; reachable once the AI trains units in step 8).

| Build | Target | Measured | Machine | Date |
| --- | --- | --- | --- | --- |
| Desktop | ≥ 60 FPS | pending | | |
| Web (browser) | ≥ 30 FPS | pending | | |

## Screens checked during build step 7

Screenshots were taken of the main menu, the game at start, box selection, gathering, barracks placement (green ghost), construction, the HQ training queue, a skirmish and the victory overlay (headless Edge with WebGL for the web build, and `tools/ui_snapshot.gd` for staged scenes).
