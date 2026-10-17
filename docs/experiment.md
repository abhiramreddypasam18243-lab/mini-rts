# Strategy Experiment: Aggressive vs Balanced vs EconomyFirst

*SPEC section 16; AC-71 and AC-72. Run on 2026-10-17 with Godot 4.7.2, headless; re-run the same day under the spacing rules of decision D-42 (units no longer stop on one cell). The numbers below are from the re-run; the earlier run gave the same ranking.*

## Set-up

- **Policies:** the same state machine with three parameter sets (SPEC 7.1): Aggressive (army of 3, 4 workers), Balanced (army of 6, 6 workers), EconomyFirst (army of 10, 10 workers).
- **Maps:** the point-symmetric generated 48 × 48 map of each seed 1 to 100.
- **Fair sides:** every seed is played twice, the policies swapping start positions, so 200 matches per pairing. "Side A" is always the first-named policy, wherever it starts.
- **Controls:** the same stats (`data/units.json`), maps, seeds and match limit (36,000 ticks = 30 minutes) for every pairing.
- **Metrics per match** (`docs/experiment/*.csv`): winner, outcome, duration, time to first attack, wood and gold gathered, units lost.
- **Statistics:** win rate over decisive matches with a Wilson 95 % interval; draws and timeouts reported separately; a paired comparison per seed (A won both, split, B won both) with a two-sided sign test.
- **Reproduce:** `tools/run_matches.gd` for each pairing, then `tools/analyze.gd` (commands in `CLAUDE.md`). The full tables are in [`experiment-tables.md`](experiment-tables.md).

## Sanity check first (AC-71): is either start position favoured?

Balanced vs Balanced, 100 seeds × 2.

**A subtlety.** Both sides run the same deterministic policy, so the two matches of a seed are the *same game* with the labels A and B swapped (verified: all 100 pairs had identical outcomes and durations). Side A therefore wins exactly one match of every decided seed, and its win rate is 0.500 (92 / 92) **by construction**: that number cannot detect a bias.

The informative quantity is how often each **start position** wins, counting each seed once:

| | Seeds |
| --- | --- |
| Player start won | 45 |
| AI start won | 51 |
| Timeout (no winner in 30 minutes) | 4 |
| **Player-start win rate** | **45 / 96 = 0.469, 95 % Wilson CI [0.372, 0.568]** |

The interval contains 0.5: **no start-position bias was detected**, so the comparisons below can be trusted. In the other pairings the player start won 46.5 % (Aggressive vs Balanced) and 50.0 % (Aggressive vs EconomyFirst) of decisive matches, both intervals containing 0.5; in **EconomyFirst vs Balanced it won 41.9 %, interval [0.351, 0.490], which does not contain 0.5** (about p = 0.025 for that one pairing). With four such checks, one result this low is not unusual by chance (it would not pass a Bonferroni correction, threshold 0.0125), so it is reported, not treated as proven bias. A possible cause worth testing: the spacing rules of D-42 break ties in row-major order, which is not mirror-symmetric between the two start corners.

## Results (AC-72)

| Pairing (A vs B) | A wins / B wins | Timeouts | A win rate, 95 % CI | Paired seeds: A both / split / B both | Mean duration | Mean first attack | Mean resources A / B | Mean units lost A / B |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Aggressive vs Balanced | 182 / 16 | 2 | **0.919** [0.873, 0.950] | 83 / 16 / 1 | 183 s | 52 s | 1481 / 1530 | 5.4 / 20.9 |
| EconomyFirst vs Balanced | 49 / 142 | 9 | **0.257** [0.200, 0.323] | 7 / 43 / 50 | 304 s | 70 s | 2108 / 2091 | 25.7 / 12.0 |
| Aggressive vs EconomyFirst | 194 / 4 | 2 | **0.980** [0.949, 0.992] | 95 / 5 / 0 | 204 s | 52 s | 1602 / 1770 | 6.9 / 28.5 |
| *Balanced vs Balanced* | *96 / 96* | *8* | *0.500 (by construction)* | *0 / 100 / 0* | *298 s* | *65 s* | *2024 / 2024* | *18.4 / 18.4* |

No match ended in a draw. Every sign test on the paired seeds gives p < 0.0001.

**Ranking in this setting: Aggressive > Balanced > EconomyFirst**, consistently: the order holds in all three pairings, it is transitive, and none of the intervals comes near 0.5.

## Interpretation

- **Early pressure wins here.** Aggressive attacks with 3 soldiers and makes its first attack about 52 s in; the other policies are still building their economy. It wins *while losing far fewer units* (5.4 against 20.9 and 6.9 against 28.5). The likely reason (not measured directly) is that its attacks arrive before the defender has an army, so the defender's soldiers join the fight one by one as they are trained.
- **Economy did not convert into strength.** EconomyFirst gathers as much as or more than its opponents (2,108 vs 2,091 against Balanced; 1,770 vs 1,602 against Aggressive) but waits for 10 soldiers before attacking, and loses most of its army defending in the meantime. Gathering more did not help because the matches end in 3.5–5.5 minutes, before a larger economy pays off.
- **Matches are short and decisive.** Mean durations are 3–5 minutes of game time; only 13 of the 600 comparison matches reached the 30-minute limit.
- **Spacing (D-42) sharpened the result.** With soldiers fighting from separate cells, Aggressive's win rates rose (0.857 → 0.919 against Balanced, 0.964 → 0.980 against EconomyFirst); the ranking did not change.

## What the experiment cannot show

- **Only these rules and these maps.** The conclusion is "Aggressive beats the others *under these stats and on these generated 48 × 48 maps*". Bigger maps (longer walks to the enemy), more resources, cheaper workers, stronger defences (e.g. towers) or a different unit balance could reverse the ranking. Early attacks are typically weaker when travel times are long.
- **Only against these opponents.** All three policies are variations of one state machine with the same weaknesses (no scouting of enemy armies, no retreat during DEFEND, no focus fire). A human, or an AI that defends with workers or counter-attacks, was not tested.
- **One fixed implementation.** Every match is deterministic, so "100 seeds" means 100 maps, not 100 random repetitions of the same situation; the intervals describe variation *across maps*.
- **No player-skill measure.** Win rate says nothing about how fun or how hard each policy is for a person to play against.
- **Balanced vs Balanced** cannot test fairness by side A's win rate (it is 0.5 by construction); the start-position rate was used instead (above).
