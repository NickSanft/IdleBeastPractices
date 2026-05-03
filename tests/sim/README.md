# Difficulty curve simulation

Headless Godot scene that fast-forwards a simulated player through tier 1-20 to
spot difficulty walls (long stalls), unintended sprints (multiple tiers in
minutes), and prestige-curve regressions. Reuses the live game's
`OfflineProgressSystem`, `CatchingSystem`, `UpgradeEffectsSystem`, and
`PrestigeSystem` so the sim stays in lock-step with whatever balance changes
land in `game/data/`.

## Why

Manual playtesting can't surface a 3-day stall on tier 13 — by the time you
hit it you've forgotten what the sprint from tier 6→9 felt like. A
deterministic simulator lets us:

- Diff difficulty curves across balance changes (`v0.9.4` → `v0.9.5` etc.)
- Spot upgrade dead-zones (no affordable upgrade for 6+ hours of play)
- Find prestige cliffs (RP gain plateaus and player can never afford the next
  tier of nets)
- Stress new content (tier 21+, new upgrades) without 14 days of real-time
  playtesting

## Running

```bash
godot --headless --path . res://tests/sim/sim_runner.tscn
```

Or with custom parameters (note the `--` separator so Godot passes the
remaining args to the script via `OS.get_cmdline_user_args()`):

```bash
godot --headless --path . res://tests/sim/sim_runner.tscn -- \
    --seed=42 \
    --hours=336 \
    --tick=60
```

| Flag | Default | Meaning |
|---|---|---|
| `--seed=N` | `42` | RNG seed. Same seed → identical run, byte-for-byte CSV. |
| `--hours=N` | `336` | Sim horizon in real-time hours (336 = 14 days). |
| `--tick=N` | `60` | Chunk size for `OfflineProgressSystem.compute()`. Smaller = finer-grained event timestamps; larger = faster sim. |

The sim writes two files to `tests/sim/output/`:

- `difficulty_curve.csv` — every event (first-catch, tier-complete,
  net-crafted, upgrade-purchased, prestige) with timestamp, gold, RP, total
  catches, max tier, prestige count, active net.
- `difficulty_curve.md` — human-readable report: tier-completion timeline
  with wall/sprint flags, prestige timeline, net-acquisition timeline,
  methodology.

## Player AI policy

Greedy each tick:

1. **Tier advance**. Check `CatchingSystem.tier_completion_status()`; if the
   current tier is complete (all species ≥1, any species ≥25), advance
   `current_max_tier`.
2. **Net selection**. Equip the owned net with highest `catches_per_second`
   that targets `current_max_tier`. Fall back to the highest-cps net for any
   tier if none target current.
3. **Net craft**. Walk the net chain (`basic_net → tier2_net → tier3_net →
   wraith_net → hedgewright_net → gleamwarp_net → refrain_net → vigil_net →
   nadir_net`). First not-owned recipe gets attempted via `GameState.try_craft()`,
   which checks gold + items + prereqs + tier_required.
4. **Upgrade purchase**. Sort all upgrades by next-level cost (`to_float()`),
   buy cheapest affordable one. Loop until nothing affordable. RP-currency
   upgrades skipped pre-first-prestige.
5. **Prestige** (patient policy). Only when `current_max_tier >= 8` AND
   `projected_rp_gain >= max(20, 2 × current_rp)`. The patient gate avoids
   the local minimum a fully-greedy AI falls into: prestige at RP=5 → buy a
   1-RP upgrade → threshold drops back below 5 → prestige again. The greedy
   AI cycles at tier 1-4 forever, even given 14 days of sim time, because
   each prestige resets nets and the threshold heuristic is too low. Real
   players with even minimal look-ahead push for the next net before
   prestiging; the patient gate models that intuition. (See "v0.9.4
   findings" in `tests/sim/output/difficulty_curve.md` for the greedy-AI
   spiral.)
6. **`prestige_starting_net` skipped.** The sim re-equips `basic_net` at
   every prestige start regardless. In the live game this upgrade is
   load-bearing (without it, post-prestige nets_owned is empty), so a real
   player must buy it. The sim doesn't, to avoid wasting 5 RP that wouldn't
   be wasted in real play. Adjust `_try_buy_upgrades` if modeling live-game
   RP economy precisely.

## Limitations

- **Auto-catch only.** Tap-grinding is not modeled. Real players tap-grind
  tier 1-3 to bootstrap; the sim hands the player `basic_net` for free at
  start to bypass the no-gold deadlock. This costs the sim ~2 minutes of
  early-game timing fidelity but doesn't affect mid/late game (where catch
  difficulty makes tap progress irrelevant — the auto-catch dominates).
- **No battles.** Battle wins award rancher points directly. The sim
  under-reports RP accumulation because of this. If the battle path becomes
  load-bearing for prestige scaling, extend the AI to schedule battles.
- **OfflineProgressSystem cap.** Each `compute()` call enforces a 3600-second
  ceiling. The sim ticks at 60s by default — well under cap — so this never
  triggers. Setting `--tick` above 3600 would silently cap progress.
- **No item-spend modeling beyond crafting.** The sim doesn't simulate the
  player buying gleamwarp drops on the shop or feeding pets. If those become
  significant gold sinks, factor them in.
- **Greedy upgrade policy.** Real players prioritize differently (rate
  upgrades early, gold mults late, etc.). The sim's "cheapest affordable"
  heuristic is a baseline; tweaking the policy can produce a wider spread.

## Interpreting the report

- **WALL** flag: a tier-completion gap exceeded 3× the median gap. Common
  causes: net pricing jump (e.g. gleamwarp_net at 3.5×10⁸ gold), upgrade
  dead-zone, or a tier with too many high-difficulty species.
- **sprint** flag: gap below 1/3× median. Common causes: a recently-unlocked
  net targets multiple tiers (so two tiers complete in parallel), or a
  prestige boost that fast-tracked a stretch.
- **Final state line** at the top of the report: if the sim ran out of time
  before reaching tier 20, that's a soft signal the curve may be too steep
  for the target audience's session length.

## CI integration

Currently NOT run in CI — the sim takes ~30s for a 14-day run, fine to run
on demand. If we want regression coverage, add a smoke variant
(`--hours=24`) to `.github/workflows/build.yml` and snapshot-diff the CSV.

## Re-running after balance changes

1. Make balance edits in `game/data/{nets,upgrades,monsters,recipes}/*.tres`.
2. Run the sim.
3. Diff `tests/sim/output/difficulty_curve.md` against the prior commit's
   version. Walls that appear, sprints that disappear, and final-tier
   timing are the headline signals.
