# Difficulty curve simulation — seed 42

Sim horizon: **336.0 hours** (14.0 days). Tick: 60 s. Total events: 37.

Final state: max tier **4**, prestige count **0**, total catches **120534**, RP **0**, gold **17.3M**.

> **STALLED** — no progress event fired for 24 sim-hours. The player has hit a hard progression wall. See the diagnosis at the bottom of this report.

## Tier-completion timeline (first run)

| Tier | First completed at | Δ from prior tier | Note |
|---|---|---|---|
| Tier 1 | 0.05 h (0.00 d) | 0.05 h |  |
| Tier 2 | 5.23 h (0.22 d) | 5.18 h |  |
| Tier 3 | 7.73 h (0.32 d) | 2.50 h |  |

## Prestige timeline

_No prestiges occurred within the sim horizon._

## Net-acquisition timeline (first run)

| Net | Acquired at |
|---|---|
| basic_net | 0.00 h |
| tier2_net | 5.13 h |
| tier3_net | 7.67 h |

## Methodology

- Auto-catch only via `OfflineProgressSystem.compute()`. Tap-grinding is not modeled — would speed up tiers 1-3 by minutes only, irrelevant past that.
- Player AI is greedy: equips best owned net, crafts next net when gold + items + prereqs all available, buys cheapest affordable upgrade each tick. Prestige policy is patient: only when current_max_tier ≥ 8 AND projected_rp ≥ max(20, 2.0 × current_rp). The patient gate avoids a local minimum where a greedy AI cycles tier 1-4 forever (each prestige resets nets, threshold is met immediately, RP never stockpiles).
- `prestige_starting_net` upgrade is skipped: the sim re-equips `basic_net` at every prestige start regardless. In live play this upgrade is load-bearing.
- Battles are not simulated. Battle RP is a separate income stream that compounds prestige RP indirectly via rp_mult upgrades; sim under-reports total RP gain.
- Wall flags fire when a tier's Δ exceeds 3× the median tier-completion gap. Sprint flags fire below 1/3× median. Both ignore tier 1 (no prior delta).
- Re-run via `godot --headless --path . res://tests/sim/sim_runner.tscn -- --seed=N --hours=N --tick=N` to compare seeds.

## Stall diagnosis

The simulator terminated early after a 24-hour silent window. State at stall:

- Active net: `tier3_net` (targets tiers `[2, 3]`)
- current_max_tier: `4`
- Gold available: `17.3M`
- Rancher Points: `0`

Next net the AI tried to craft: `wraith_net` (recipe `recipe_wraith_net`):

- Tier required: `4` (current_max_tier OK)
- Gold cost: `4.65K` (have `17.3M`)
- Item inputs:
    - `wraith_cinder` × `50` (have `0`) — drops from tiers [4]
- Prereq recipes: [&"recipe_tier3_net"]

**Likely root cause:** the only net targeting the input's source tier requires drops from monsters in that same tier. Tap-grinding does NOT bypass this in the live game — `CatchingSystem.pick_spawn` filters by `net.targets_tiers` for both auto-catch AND tap spawns ([catching_view.gd:154](../../game/scenes/catching/catching_view.gd:154)). The wall is real. Fix paths: (1) overlap net target ranges so e.g. `tier3_net` includes tier 4, (2) cross-tier item drops (lower-tier monsters occasionally drop the next-tier ingredient), (3) a shop or trade-in mechanic that converts lower-tier drops into higher-tier ones.
