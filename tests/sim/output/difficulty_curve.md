# Difficulty curve simulation — seed 42

Sim horizon: **336.0 hours** (14.0 days). Tick: 60 s. Total events: 699.

Final state: max tier **21**, prestige count **1**, total catches **31138**, RP **54598552**, gold **292Qi**.

> **ENDGAME REACHED** — the player cleared tier 20 (the design cap) and prestiged at least once. The catching progression curve has no further wall; remaining gameplay is prestige-cycle RP grind.

## Tier-completion timeline (first run)

| Tier | First completed at | Δ from prior tier | Note |
|---|---|---|---|
| Tier 1 | 0.05 h (0.00 d) | 0.05 h |  |
| Tier 2 | 0.92 h (0.04 d) | 0.87 h | **WALL** (17.3× median) |
| Tier 3 | 0.97 h (0.04 d) | 0.05 h |  |
| Tier 4 | 1.02 h (0.04 d) | 0.05 h |  |
| Tier 5 | 1.05 h (0.04 d) | 0.03 h |  |
| Tier 6 | 1.10 h (0.05 d) | 0.05 h |  |
| Tier 7 | 1.17 h (0.05 d) | 0.07 h |  |

## Prestige timeline

| Prestige # | At | RP awarded | Max tier reached pre-prestige |
|---|---|---|---|
| 1 | 1.18 h | +267 | tier 1 |
| 1 | 1.43 h | +465 | tier 1 |
| 1 | 1.73 h | +1775 | tier 1 |
| 1 | 2.03 h | +5939 | tier 1 |
| 1 | 2.37 h | +17321 | tier 1 |
| 1 | 2.73 h | +53670 | tier 1 |
| 1 | 3.12 h | +260534 | tier 1 |
| 1 | 3.52 h | +776821 | tier 1 |
| 1 | 3.95 h | +2754904 | tier 1 |
| 1 | 4.40 h | +11384849 | tier 1 |
| 1 | 4.88 h | +39341722 | tier 1 |

## Net-acquisition timeline (first run)

| Net | Acquired at |
|---|---|
| basic_net | 0.00 h |
| tier2_net | 0.82 h |
| tier3_net | 0.90 h |
| wraith_net | 0.98 h |
| hedgewright_net | 1.13 h |

## Methodology

- Auto-catch only via `OfflineProgressSystem.compute()`. Tap-grinding is not modeled — would speed up tiers 1-3 by minutes only, irrelevant past that.
- Player AI is greedy: equips best owned net, crafts next net when gold + items + prereqs all available, buys cheapest affordable upgrade each tick. Prestige policy is patient: only when current_max_tier ≥ 8 AND projected_rp ≥ max(20, 2.0 × current_rp). The patient gate avoids a local minimum where a greedy AI cycles tier 1-4 forever (each prestige resets nets, threshold is met immediately, RP never stockpiles).
- `prestige_starting_net` upgrade is skipped: the sim re-equips `basic_net` at every prestige start regardless. In live play this upgrade is load-bearing.
- Battles are not simulated. Battle RP is a separate income stream that compounds prestige RP indirectly via rp_mult upgrades; sim under-reports total RP gain.
- Wall flags fire when a tier's Δ exceeds 3× the median tier-completion gap. Sprint flags fire below 1/3× median. Both ignore tier 1 (no prior delta).
- The **tier-2 wall flag is a known false positive** in this content layout: tier 2 requires the player to grind ~50 tier-1 drops + the gold cost to craft `tier2_net`, which inherently takes longer than later tiers (where the player has already accumulated resources mid-chain). Real walls — like the tier-3→tier-4 chicken-and-egg fixed in v0.13.4 by extending mid-tier net `targets_tiers` — show up as **multiple consecutive walls** or as a stall, not a single flagged tier.
- Re-run via `godot --headless --path . res://tests/sim/sim_runner.tscn -- --seed=N --hours=N --tick=N` to compare seeds.
