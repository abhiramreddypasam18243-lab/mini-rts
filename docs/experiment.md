# Strategy Experiment: Aggressive vs Balanced vs EconomyFirst

*SPEC section 16; AC-71 and AC-72. Run on 2026-10-17 with Godot 4.7.2, headless.*

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
| Player start won | 44 |
| AI start won | 48 |
| Timeout (no winner in 30 minutes) | 8 |
| **Player-start win rate** | **44 / 92 = 0.478, 95 % Wilson CI [0.379, 0.579]** |

The interval contains 0.5: **no start-position bias was detected**, so the comparisons below can be trusted. The other three pairings agree: in each, the player start won 47–50 % of decisive matches, every interval containing 0.5.

## Results (AC-72)

| Pairing (A vs B) | A wins / B wins | Timeouts | A win rate, 95 % CI | Paired seeds: A both / split / B both | Mean duration | Mean first attack | Mean resources A / B | Mean units lost A / B |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Aggressive vs Balanced | 168 / 28 | 4 | **0.857** [0.801, 0.899] | 72 / 26 / 2 | 208 s | 52 s | 1526 / 1596 | 6.9 / 20.7 |
| EconomyFirst vs Balanced | 44 / 144 | 12 | **0.234** [0.179, 0.300] | 8 / 37 / 55 | 323 s | 71 s | 2099 / 2106 | 25.9 / 12.5 |
| Aggressive vs EconomyFirst | 190 / 7 | 3 | **0.964** [0.928, 0.983] | 91 / 8 / 1 | 214 s | 52 s | 1607 / 1774 | 6.9 / 28.5 |
| *Balanced vs Balanced* | *92 / 92* | *16* | *0.500 (by construction)* | *0 / 100 / 0* | *348 s* | *64 s* | *2013 / 2013* | *18.6 / 18.6* |

No match ended in a draw. Every sign test on the paired seeds gives p < 0.0001.

**Ranking in this setting: Aggressive > Balanced > EconomyFirst**, consistently: the order holds in all three pairings, it is transitive, and none of the intervals comes near 0.5.

## Interpretation

- **Early pressure wins here.** Aggressive attacks with 3 soldiers and makes its first attack about 52 s in; the other policies are still building their economy. It wins *while losing far fewer units* (6.9 against 20.7 and 28.5). The likely reason (not measured directly) is that its attacks arrive before the defender has an army, so the defender's soldiers join the fight one by one as they are trained.
- **Economy did not convert into strength.** EconomyFirst gathers as much as or more than its opponents (2,099 vs 2,106 against Balanced; 1,774 vs 1,607 against Aggressive) but waits for 10 soldiers before attacking, and loses most of its army defending in the meantime. Gathering more did not help because the matches end in 3.5–5.5 minutes, before a larger economy pays off.
- **Matches are short and decisive.** Mean durations are 3.5–6 minutes of game time; only 19 of the 600 comparison matches reached the 30-minute limit.

## What the experiment cannot show

- **Only these rules and these maps.** The conclusion is "Aggressive beats the others *under these stats and on these generated 48 × 48 maps*". Bigger maps (longer walks to the enemy), more resources, cheaper workers, stronger defences (e.g. towers) or a different unit balance could reverse the ranking. Early attacks are typically weaker when travel times are long.
- **Only against these opponents.** All three policies are variations of one state machine with the same weaknesses (no scouting of enemy armies, no retreat during DEFEND, no focus fire). A human, or an AI that defends with workers or counter-attacks, was not tested.
- **One fixed implementation.** Every match is deterministic, so "100 seeds" means 100 maps, not 100 random repetitions of the same situation; the intervals describe variation *across maps*.
- **No player-skill measure.** Win rate says nothing about how fun or how hard each policy is for a person to play against.
- **Balanced vs Balanced** cannot test fairness by side A's win rate (it is 0.5 by construction); the start-position rate was used instead (above).
