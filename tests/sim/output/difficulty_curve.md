# Difficulty curve simulation — seed 7

Sim horizon: **336.0 hours** (14.0 days). Tick: 60 s. Total events: 1066.

Final state: max tier **21**, prestige count **1**, total catches **57468**, RP **54598191**, gold **292Qi**.

> **ENDGAME REACHED** — the player cleared tier 20 (the design cap) and prestiged at least once. The catching progression curve has no further wall; remaining gameplay is prestige-cycle RP grind.

## Tier-completion timeline (first run)

| Tier | First completed at | Δ from prior tier | Note |
|---|---|---|---|
| Tier 1 | 0.05 h (0.00 d) | 0.05 h |  |
| Tier 2 | 5.23 h (0.22 d) | 5.18 h | **WALL** (103.7× median) |
| Tier 3 | 7.73 h (0.32 d) | 2.50 h | **WALL** (50.0× median) |
| Tier 4 | 7.78 h (0.32 d) | 0.05 h |  |
| Tier 5 | 7.82 h (0.33 d) | 0.03 h |  |
| Tier 6 | 7.87 h (0.33 d) | 0.05 h |  |
| Tier 7 | 7.93 h (0.33 d) | 0.07 h |  |

## Prestige timeline

| Prestige # | At | RP awarded | Max tier reached pre-prestige |
|---|---|---|---|
| 1 | 7.98 h | +20 | tier 1 |
| 1 | 9.13 h | +20 | tier 1 |
| 1 | 9.88 h | +20 | tier 1 |
| 1 | 10.42 h | +22 | tier 1 |
| 1 | 10.98 h | +38 | tier 1 |
| 1 | 11.37 h | +38 | tier 1 |
| 1 | 11.63 h | +41 | tier 1 |
| 1 | 11.83 h | +50 | tier 1 |
| 1 | 12.00 h | +63 | tier 1 |
| 1 | 12.17 h | +79 | tier 1 |
| 1 | 12.38 h | +242 | tier 1 |
| 1 | 12.60 h | +574 | tier 1 |
| 1 | 12.88 h | +1689 | tier 1 |
| 1 | 13.18 h | +5939 | tier 1 |
| 1 | 13.52 h | +17321 | tier 1 |
| 1 | 13.88 h | +53670 | tier 1 |
| 1 | 14.27 h | +260534 | tier 1 |
| 1 | 14.67 h | +776821 | tier 1 |
| 1 | 15.10 h | +2754904 | tier 1 |
| 1 | 15.55 h | +11384849 | tier 1 |
| 1 | 16.03 h | +39341722 | tier 1 |

## Net-acquisition timeline (first run)

| Net | Acquired at |
|---|---|
| basic_net | 0.00 h |
| tier2_net | 5.13 h |
| tier3_net | 7.67 h |
| wraith_net | 7.75 h |
| hedgewright_net | 7.90 h |

## Methodology

- Auto-catch only via `OfflineProgressSystem.compute()`. Tap-grinding is not modeled — would speed up tiers 1-3 by minutes only, irrelevant past that.
- Player AI is greedy: equips best owned net, crafts next net when gold + items + prereqs all available, buys cheapest affordable upgrade each tick. Prestige policy is patient: only when current_max_tier ≥ 8 AND projected_rp ≥ max(20, 2.0 × current_rp). The patient gate avoids a local minimum where a greedy AI cycles tier 1-4 forever (each prestige resets nets, threshold is met immediately, RP never stockpiles).
- `prestige_starting_net` upgrade is skipped: the sim re-equips `basic_net` at every prestige start regardless. In live play this upgrade is load-bearing.
- Battles are not simulated. Battle RP is a separate income stream that compounds prestige RP indirectly via rp_mult upgrades; sim under-reports total RP gain.
- Wall flags fire when a tier's Δ exceeds 3× the median tier-completion gap. Sprint flags fire below 1/3× median. Both ignore tier 1 (no prior delta).
- The **tier-2 wall flag is a known false positive** in this content layout: tier 2 requires the player to grind ~50 tier-1 drops + the gold cost to craft `tier2_net`, which inherently takes longer than later tiers (where the player has already accumulated resources mid-chain). Real walls — like the tier-3→tier-4 chicken-and-egg fixed in v0.13.4 by extending mid-tier net `targets_tiers` — show up as **multiple consecutive walls** or as a stall, not a single flagged tier.
- Re-run via `godot --headless --path . res://tests/sim/sim_runner.tscn -- --seed=N --hours=N --tick=N` to compare seeds.
