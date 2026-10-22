# Strategy Experiment: Aggressive vs Balanced vs EconomyFirst

*SPEC section 16; AC-71 and AC-72. First run 2026-10-17 with Godot 4.7.2, headless; re-run on 2026-10-20 under the D-51 rules (food, farms, guard towers, stables and cavalry, upgrades, all used by the AI) and on 2026-10-22 under D-57 (the cavalry charge). The numbers below are from the 2026-10-22 run; earlier runs gave the same ranking.*

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

The interval contains 0.5: **no start-position bias was detected**, so the comparisons below can be trusted.

**This check caught a real bug.** The first run under the D-51 rules failed it: the player start won only 37 % of decisive matches (interval [0.303, 0.441]). The AI looked for building sites and rally cells in plain row-major order, which is not mirror-symmetric between the two start corners, and D-51 added three more buildings placed that way. The scans now run in each AI's own frame (flipped for the bottom-right start), and every pairing was re-run.

In the other pairings the player start won 48.0 % (Aggressive vs Balanced), 47.2 % (Aggressive vs EconomyFirst) and 43.4 % (EconomyFirst vs Balanced, interval [0.363, 0.508]) of decisive matches; all three intervals contain 0.5. (Before D-57 the last pairing was just below 0.5, at 42.4 %, interval [0.353, 0.497]; with four such checks one value that low is not unusual by chance.)

## Results (AC-72)

| Pairing (A vs B) | A wins / B wins | Timeouts | A win rate, 95 % CI | Paired seeds: A both / split / B both | Mean duration | Mean first attack | Mean resources A / B | Mean units lost A / B |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Aggressive vs Balanced | 171 / 27 | 2 | **0.864** [0.809, 0.905] | 73 / 25 / 2 | 192 s | 54 s | 1410 / 1412 | 5.9 / 16.4 |
| EconomyFirst vs Balanced | 51 / 124 | 25 | **0.291** [0.229, 0.363] | 7 / 55 / 38 | 433 s | 72 s | 2102 / 1980 | 16.6 / 10.5 |
| Aggressive vs EconomyFirst | 185 / 8 | 7 | **0.959** [0.920, 0.979] | 85 / 15 / 0 | 266 s | 55 s | 1598 / 1830 | 6.9 / 25.6 |
| *Balanced vs Balanced* | *96 / 96* | *8* | *0.500 (by construction)* | *0 / 100 / 0* | *280 s* | *68 s* | *1807 / 1807* | *12.1 / 12.1* |

No match ended in a draw. Every sign test on the paired seeds gives p < 0.0001.

**Ranking in this setting: Aggressive > Balanced > EconomyFirst**, consistently: the order holds in all three pairings, it is transitive, and none of the intervals comes near 0.5.

## Interpretation

- **Early pressure still wins.** Aggressive attacks with 3 soldiers about 54 s in, while the other policies are still building their economy, and it wins *while losing far fewer units* (5.9 against 16.4, and 6.9 against 25.6). The likely reason (not measured directly) is that its attacks arrive before the defender has an army, so the defender's soldiers join the fight one by one as they are trained.
- **Economy still did not convert into strength.** EconomyFirst gathers more than its opponents (2,102 vs 1,980 against Balanced; 1,830 vs 1,598 against Aggressive) but waits for 10 soldiers before attacking. Matches end in 3–7 minutes, before a larger economy pays off.
- **D-51 slowed the rush a little.** Guard towers, cavalry and upgrades help the defender: Aggressive's win rates fell (0.919 → 0.869 against Balanced, 0.980 → 0.948 against EconomyFirst), and longer games produced more timeouts (EconomyFirst vs Balanced: 9 → 23). The ranking did not change.
- **The cavalry charge (D-57) changed little.** The AI trains only a few cavalry, so the win rates moved by at most 0.03 (Aggressive vs Balanced 0.869 → 0.864, EconomyFirst vs Balanced 0.260 → 0.291, Aggressive vs EconomyFirst 0.948 → 0.959), all within the intervals.
- **Matches are short and decisive.** Only 34 of the 600 comparison matches reached the 30-minute limit, and none ended in a draw.

## Difficulty and map styles (D-52, D-53)

Run on 2026-10-20, 50 seeds × 2 (sides swapped) each, generated with `tools/run_matches.gd` (`--policy-a balanced:hard`, `--map-style river`, ...); tables in [`experiment-d52/tables.md`](experiment-d52/tables.md).

| Check | A wins / B wins | Timeouts | Win rate, 95 % CI |
| --- | --- | --- | --- |
| Easy vs Normal (Balanced; re-run after D-56 made Easy queue one item at a time) | 32 / 66 | 2 | **0.327** [0.242, 0.424] |
| Hard vs Normal (Balanced) | 52 / 45 | 3 | **0.536** [0.437, 0.632] |
| River, Balanced v Balanced: player-start win rate | 26 / 23 seeds | 1 seed | **0.531** [0.433, 0.626] |
| Highlands, Balanced v Balanced: player-start win rate | 23 / 26 seeds | 1 seed | **0.469** [0.374, 0.567] |

Easy is clearly weaker than Normal. Hard's interval contains 0.5: **Hard is at most slightly stronger than Normal**, so the difficulty step from Normal to Hard is small. Both new map styles pass the fairness check.

## What the experiment cannot show

- **Only these rules and these maps.** The conclusion is "Aggressive beats the others *under these stats and on these generated 48 × 48 maps*". Bigger maps (longer walks to the enemy), more resources, cheaper workers, stronger defences (more towers than the AI builds) or a different unit balance could reverse the ranking. Early attacks are typically weaker when travel times are long.
- **Only against these opponents.** All three policies are variations of one state machine with the same weaknesses (no scouting of enemy armies, no retreat during DEFEND, no focus fire). A human, or an AI that defends with workers or counter-attacks, was not tested.
- **One fixed implementation.** Every match is deterministic, so "100 seeds" means 100 maps, not 100 random repetitions of the same situation; the intervals describe variation *across maps*.
- **No player-skill measure.** Win rate says nothing about how fun or how hard each policy is for a person to play against.
- **Balanced vs Balanced** cannot test fairness by side A's win rate (it is 0.5 by construction); the start-position rate was used instead (above).
