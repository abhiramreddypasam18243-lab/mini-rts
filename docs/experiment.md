# Strategy Experiment: Aggressive vs Balanced vs EconomyFirst

*SPEC section 16; AC-71 and AC-72. First run 2026-10-17 with Godot 4.7.2, headless; re-run on 2026-10-20 under the D-51 rules (food, farms, guard towers, stables and cavalry, upgrades, all used by the AI). The numbers below are from the 2026-10-20 run; earlier runs gave the same ranking.*

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
| AI start won | 50 |
| Timeout (no winner in 30 minutes) | 5 |
| **Player-start win rate** | **45 / 95 = 0.474, 95 % Wilson CI [0.376, 0.573]** |

The interval contains 0.5: **no start-position bias was detected**, so the comparisons below can be trusted.

**This check caught a real bug.** The first run under the D-51 rules failed it: the player start won only 37 % of decisive matches (interval [0.303, 0.441]). The AI looked for building sites and rally cells in plain row-major order, which is not mirror-symmetric between the two start corners, and D-51 added three more buildings placed that way. The scans now run in each AI's own frame (flipped for the bottom-right start), and every pairing was re-run.

In the other pairings the player start won 47.5 % (Aggressive vs Balanced) and 47.2 % (Aggressive vs EconomyFirst) of decisive matches, both intervals containing 0.5. In **EconomyFirst vs Balanced it won 42.4 %, interval [0.353, 0.497], just below 0.5**, much as before D-51 (41.9 %). With four such checks, one result this low is not unusual by chance (it would not pass a Bonferroni correction, threshold 0.0125), so it is reported, not treated as proven bias.

## Results (AC-72)

| Pairing (A vs B) | A wins / B wins | Timeouts | A win rate, 95 % CI | Paired seeds: A both / split / B both | Mean duration | Mean first attack | Mean resources A / B | Mean units lost A / B |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Aggressive vs Balanced | 172 / 26 | 2 | **0.869** [0.815, 0.909] | 74 / 24 / 2 | 191 s | 54 s | 1405 / 1412 | 5.7 / 16.5 |
| EconomyFirst vs Balanced | 46 / 131 | 23 | **0.260** [0.201, 0.329] | 4 / 55 / 41 | 419 s | 72 s | 2087 / 1961 | 16.9 / 9.7 |
| Aggressive vs EconomyFirst | 183 / 10 | 7 | **0.948** [0.907, 0.972] | 83 / 17 / 0 | 265 s | 55 s | 1591 / 1827 | 7.0 / 25.2 |
| *Balanced vs Balanced* | *95 / 95* | *10* | *0.500 (by construction)* | *0 / 100 / 0* | *297 s* | *68 s* | *1818 / 1818* | *12.3 / 12.3* |

No match ended in a draw. Every sign test on the paired seeds gives p < 0.0001.

**Ranking in this setting: Aggressive > Balanced > EconomyFirst**, consistently: the order holds in all three pairings, it is transitive, and none of the intervals comes near 0.5.

## Interpretation

- **Early pressure still wins.** Aggressive attacks with 3 soldiers about 54 s in, while the other policies are still building their economy, and it wins *while losing far fewer units* (5.7 against 16.5, and 7.0 against 25.2). The likely reason (not measured directly) is that its attacks arrive before the defender has an army, so the defender's soldiers join the fight one by one as they are trained.
- **Economy still did not convert into strength.** EconomyFirst gathers more than its opponents (2,087 vs 1,961 against Balanced; 1,827 vs 1,591 against Aggressive) but waits for 10 soldiers before attacking. Matches end in 3–7 minutes, before a larger economy pays off.
- **D-51 slowed the rush a little.** Guard towers, cavalry and upgrades help the defender: Aggressive's win rates fell (0.919 → 0.869 against Balanced, 0.980 → 0.948 against EconomyFirst), and longer games produced more timeouts (EconomyFirst vs Balanced: 9 → 23). The ranking did not change.
- **Matches are short and decisive.** Only 32 of the 600 comparison matches reached the 30-minute limit, and none ended in a draw.

## What the experiment cannot show

- **Only these rules and these maps.** The conclusion is "Aggressive beats the others *under these stats and on these generated 48 × 48 maps*". Bigger maps (longer walks to the enemy), more resources, cheaper workers, stronger defences (more towers than the AI builds) or a different unit balance could reverse the ranking. Early attacks are typically weaker when travel times are long.
- **Only against these opponents.** All three policies are variations of one state machine with the same weaknesses (no scouting of enemy armies, no retreat during DEFEND, no focus fire). A human, or an AI that defends with workers or counter-attacks, was not tested.
- **One fixed implementation.** Every match is deterministic, so "100 seeds" means 100 maps, not 100 random repetitions of the same situation; the intervals describe variation *across maps*.
- **No player-skill measure.** Win rate says nothing about how fun or how hard each policy is for a person to play against.
- **Balanced vs Balanced** cannot test fairness by side A's win rate (it is 0.5 by construction); the start-position rate was used instead (above).
