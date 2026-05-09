# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Pre-1.0, the **minor version equals the phase number**.

## [Unreleased]

### v0.14.1 — Phase 13c.1: Landscape baseline (orientation unlocked)

**Why**

Phase 13a + 13b laid the foundation; this is the smallest possible step toward landscape support: **unlock orientation, let every existing view inherit a graceful "stretched portrait" landscape layout**. The user can rotate their device, the app rotates with it, and nothing crashes. Per-screen polish (proper landscape layouts) is Phase 13c.2+, where each primary view picks up a custom landscape branch.

**The change**

- [`project.godot`](project.godot): `window/handheld/orientation` flipped from `1` (portrait) to `6` (`SCREEN_SENSOR` — auto-rotate based on device sensor; excludes reverse-portrait by default, which is what idle games want). Per the saved Galaxy Z Fold7 fix the integer enum is required; string `"sensor"` silently falls back.
- The Phase-13b machinery already in place handles the rotation transparently:
  - `DeviceLayout.is_landscape` flips on every viewport `size_changed` and emits `layout_changed`.
  - `main.gd._safe_margin` reapplies safe-area insets for the new aspect.
  - `catching_view._on_resized` already recomputed spawn bounds from `viewport.size`, so the wandering monsters spawn in the rotated rectangle without code changes.
  - `bestiary_view` and `inventory_panel` already had width breakpoints; landscape gets the wider column count for free.

**Note on Android manifest hooks**

The three workflow YAMLs (build, release, maestro-emulator) currently patch `android:resizeableActivity="true"` → `"false"` to defeat the foldable orientation-lock bug. With orientation now unlocked, that workaround is no longer load-bearing — Android sensor rotation works regardless of `resizeableActivity`. The hooks are left in place because they still prevent multi-window / freeform on devices that support it, which is fine for an idle game where windowed shrinkage would crowd the catching screen. If you ever want multi-window support, drop the patcher; orientation is independent.

**Tests — 5 new, 403/403 passing**

- [`test_landscape_baseline.gd`](game/tests/test_landscape_baseline.gd):
  - `test_orientation_flip_emits_layout_changed` — `_test_set_orientation(true)` fires the signal.
  - `test_is_landscape_field_updates` — public field flips with the setter.
  - `test_main_gd_root_layout_handles_landscape_safe_area` — boots main.gd with a 1280×720 landscape safe area + 60-px notch inset; asserts the root MarginContainer's `margin_left` reflects the inset.
  - `test_main_gd_layout_survives_orientation_flip` — boots in portrait, then forces landscape via `_test_set_orientation` + a wider safe area; asserts no crash and `_safe_margin` is still valid.
  - `test_catching_view_spawn_bounds_reflow_to_landscape` — instantiates the catching view and asserts `_spawn_bounds` is non-empty after the resize event runs.

**Pre-push checklist**

- Full GUT suite: **403/403 pass**, 53 scripts (+5 from this phase, +40 since v0.13.4)
- Headless project loads cleanly (no SCRIPT ERROR / autoload failure)
- DeviceLayout.is_landscape signal contract preserved across the orientation change

**Phase 13c roadmap**

- 13c.1 (this release): orientation unlocked, layout pipeline survives
- 13c.2: catching + battle + bottom-nav landscape layouts (left-side rail nav, side-by-side battle UI)
- 13c.3: secondary screens (crafting, shop, upgrades, prestige, ledger, settings)
- 13c.4: tablet column polish across the remaining views

### v0.14.0 — Phase 13a + 13b: Responsive font scale + device-aware layout

**Why**

Two structural gaps the user surfaced after the perf work landed:
1. **Text didn't scale.** The Phase-11b `Settings.font_scale` slider only reached the Theme-level `Button` / `Label` / `RichTextLabel` defaults — but **71 places in the codebase used hard-coded `add_theme_font_size_override("font_size", 16)`** that bypassed it entirely. `main.gd:272` even documented the limitation explicitly.
2. **No DPI / safe-area awareness.** A `font_size = 16` design value rendered at noticeably different physical sizes on a 720×1280 vs 1440×3200 phone. The currency bar slid under the device status bar, and the bottom nav drifted into the gesture-bar zone on Android 10+.

This release lays the foundation that Phase 13c (landscape, also requested) builds on.

**Phase 13b — `DeviceLayout` autoload**

- New [`game/autoloads/device_layout.gd`](game/autoloads/device_layout.gd) — single source of truth for:
  - **`safe_area: Rect2`** — usable rect minus status bar / gesture bar / notch, derived from `DisplayServer.screen_get_usable_rect(0)` and translated into viewport coords through the `canvas_items` stretch ratio.
  - **`dpi_bucket: float`** — one of `{0.85, 1.0, 1.15, 1.30}` chosen from `DisplayServer.screen_get_dpi(0)` via Android-style cutoffs (mdpi / hdpi / xhdpi / xxhdpi).
  - **`is_landscape`** + **`is_tablet`** — booleans for Phase 13c view-layout branches.
  - **`layout_changed`** signal — fires on every viewport `size_changed` (orientation flip, foldable open, split-screen resize) so subscribed views can re-anchor without polling.
  - **Test seams** — `_test_set_safe_area`, `_test_set_dpi_bucket`, `_test_set_orientation`, `_test_set_tablet` let tests stage any device profile without a real DisplayServer.
- **Root safe-area `MarginContainer`** in [`main.gd._build_ui()`](game/scenes/main.gd) wraps the entire UI tree. Margins update on every `layout_changed`. On desktop / web where the safe area equals the viewport the wrapper costs nothing.

**Phase 13a — `UiScale` helper + sweep**

- New [`game/systems/ui_scale.gd`](game/systems/ui_scale.gd) — static helper exposing:
  - **`UiScale.size(base_px) -> int`** — returns `base_px * Settings.font_scale * DeviceLayout.dpi_bucket`, rounded. Reads both globals via the autoload tree so unit tests don't need to monkey-patch globals.
  - **`UiScale.tap_target() -> int`** — Material 48 dp floor scaled by dpi_bucket (lands here ahead of the Phase 13d touch-target sweep that will route every tappable Control through it).
- **Sweep**: 70 of the 71 hard-coded `add_theme_font_size_override("font_size", N)` call sites across 23 view files now route through `UiScale.size(N)`. The 71st was already replaced by an earlier edit. The accessibility slider now reaches every label in the codebase.
- **Live re-application**: long-lived cards (e.g., `bestiary_card`) that build labels in `_build_layout` now subscribe to `Settings.accessibility_settings_changed` + `DeviceLayout.layout_changed` and reapply the font_size override without a refresh. Most other call sites are already inside `_refresh()` paths and pick up new sizes automatically.

**Tests — 14 new, 398/398 passing**

- [`test_ui_scale.gd`](game/tests/test_ui_scale.gd) (11 cases): unit-scale identity; `font_scale` multiplier; `dpi_bucket` multiplier; compound scaling; zero/negative clamping; dpi-cutoff lookup; boundary values (140 / 200); `layout_changed` signal contract on each test setter.
- [`test_ui_scale.gd::test_no_hardcoded_font_size_overrides_remain`](game/tests/test_ui_scale.gd) — **lint test** that walks `res://game/scenes` + `res://game/autoloads`, regex-matches `add_theme_font_size_override("font_size", N)` literals, and fails with file:line if any sneak back in. A future maintainer who forgets `UiScale.size(N)` fails on this named test rather than at user-tap time.
- [`test_safe_area_margin.gd`](game/tests/test_safe_area_margin.gd) (3 cases): main.gd's root `MarginContainer` zeroes margins when safe area equals viewport; updates margins when safe area shrinks (status bar + gesture bar test profile); maps horizontal insets correctly (landscape notch profile).

**Pre-push checklist**

- Full GUT suite: **398/398 pass**, 52 scripts, ~3500 asserts (+14 from this phase, +35 since v0.13.4)
- No `add_theme_font_size_override` literals remain anywhere in `game/scenes` or `game/autoloads`
- DeviceLayout autoload registered after QuestLog (project.godot autoload order)
- main.gd root layout still parses + boots from `_run_screenshot_mode`

### v0.13.6 — Tap-path freeze: hidden-tab rebuilders

**Why**

v0.13.5 fixed the autoload evaluator fan-out, but the user reported the ~1-second freeze persisted. Profiling traced it to a much heavier offender: **six different view scenes were full-rebuilding their entire DOM on every per-tap signal, even while hidden behind another tab.**

The worst offender was `bestiary_view`: every `monster_caught` (one per caught tap) called `_refresh_cards()`, which iterates 60 cards. Each card's `refresh()` then queue-freed its 4 pill `Label`s and re-built fresh ones, plus allocated a new `AtlasTexture`. That's **240 Label allocations + 240 destroys + 60 AtlasTexture allocations per tap, while the bestiary tab wasn't even visible.** Compounding listeners across `crafting_view`, `inventory_panel`, `net_shop`, `upgrade_tree`, and `prestige_view` — each running its own full rebuild on `currency_changed` / `item_gained` (both fire per catch) — multiplied the cost.

`ledger_view` already had the right pattern (`if visible: _refresh()`); the others were missing it.

**Fix — visibility-gated rebuilders**

Every signal-driven rebuilder now uses the same gate:

```gdscript
func _on_signal(...) -> void:
    if visible:
        _refresh()
    else:
        _dirty = true   # defer until visibility_changed
```

When the player switches to the previously-hidden tab, `visibility_changed → visible=true` drains the dirty flag with **exactly one** refresh — not one per suppressed signal. Six views updated:

- [`bestiary_view`](game/scenes/bestiary/bestiary_view.gd) — was the heaviest. `monster_caught`, `first_catch_of_species`, `first_shiny_caught`, `pet_acquired` all now gated.
- [`crafting_view`](game/scenes/crafting/crafting_view.gd) — `currency_changed`, `item_gained`, `item_spent`, `item_crafted`, `tier_unlocked`, `tier_completed` all gated.
- [`inventory_panel`](game/scenes/ui/inventory_panel.gd) — `item_gained`, `item_spent` gated.
- [`net_shop`](game/scenes/ui/net_shop.gd) — `currency_changed` gated.
- [`upgrade_tree`](game/scenes/ui/upgrade_tree.gd) — `currency_changed`, `upgrade_purchased` gated.
- [`prestige_view`](game/scenes/prestige/prestige_view.gd) — `currency_changed`, `tier_completed`, `tier_unlocked`, `upgrade_purchased`, `prestige_triggered` gated.

**Bonus fix — bestiary_card no longer rebuilds pills in `refresh()`**

The 4 pill Labels are built once in `_build_layout` and just have their fill state updated by `refresh()` via a new `_update_pill(label, glyph, filled, color)` helper. The `AtlasTexture` is also constructed once in `_build_layout` and retargeted on refresh. Eliminates the per-card allocations even when the bestiary IS visible, so foreground refreshes are cheap too.

**Tests — `test_hidden_tab_refresh_budget.gd` (13 cases, +13)**

- For each of the six views: a `_hidden_skips_refresh_*` test fires 20 same-signal emits while the view is hidden and asserts `refresh_count == 0` plus `is_dirty() == true`. A future maintainer who adds a new rebuilder and forgets the gate sees a specific named test fail, not a generic budget violation.
- For each of the six views: a `_drains_on_show` test stages dirty signals while hidden, then sets `visible = true` and asserts `refresh_count == 1` (one drain pass, not N).
- `_visible_still_refreshes_per_signal` for bestiary — guards against over-correcting and accidentally suppressing the foreground refresh.
- All views expose `refresh_count: int` + `is_dirty() -> bool` as the public test surface; the dirty flag itself is private.

**Pre-push checklist**

- Full GUT suite: **384/384 pass**, 50 scripts, 3413 asserts (+13 from this fix, +21 total since v0.13.4)
- New hidden-tab suite: 13/13 pass

### v0.13.5 — Tap-path performance regression fix

**Why**

A user-reported Android perf regression in this batch (12a–12h): tapping enemies on the catching screen had become noticeably slower. Profiling traced it to a fan-out problem introduced when 12f (achievements) and 12g (quests) both subscribed to the same set of progress signals. A single caught tap fires three signals — `monster_tapped`, `currency_changed` (from `add_gold`), `monster_caught` — and each evaluator was re-running the full content-registry walk per signal:

| Per caught tap | Before | After |
|---|---|---|
| `Achievements.evaluate_all` calls | **2** | **1 / frame** |
| `QuestLog.evaluate_progress` calls | **3** | **1 / frame** |
| Allocations of `Array[AchievementResource]` | **2** | **0** |
| Allocations of `Array[QuestResource]` | **3** | **0** |

12b's hold-to-tap (up to 8 Hz) plus offline-progress auto-catches multiplied that further — visible in frame timings on Android.

**Fix — per-frame coalescing + allocation-free hot path**

- **[`Achievements`](game/autoloads/achievements.gd) and [`QuestLog`](game/autoloads/quest_log.gd)** now use a dirty-flag pattern: each subscribed signal calls `_mark_dirty()` (a single bool write), and `_process` drains the flag with one evaluator call per frame. Any number of cascaded same-frame signals collapse to a single evaluator pass. Public `is_dirty()` + `eval_count` exposed for tests.
- **`ContentRegistry.achievement_index()` and `quest_index()`** — return the cached `Dictionary` reference instead of allocating a fresh `Array[…Resource]` each call. The evaluators now iterate the dict's keys directly. `achievements()` / `quests()` array variants stay around for non-hot-path callers (Ledger grid, etc.).
- **QuestLog `_pick_for_slot` was O(N²)** — the inner `_is_eligible_ladder_position` scanned all quests for every quest under consideration. Replaced with a one-time predecessor map built before the eligibility loop. Now O(N). Only fires on quest completion (not per tap), but the cleanup matches the broader allocation budget theme.

**Tests — `test_tap_path_perf.gd` (8 cases, +8)**

The new suite codifies the budget so this regression class can't return:

- `test_burst_of_signals_in_one_frame_yields_one_achievement_eval` / `_quest_eval` — emit 10 signals back-to-back, assert evaluator runs **0** times before `_process` drains, **1** time after.
- `test_caught_tap_simulation_stays_under_budget` — fire the exact 3-signal cascade a caught tap produces; assert each autoload evaluates once, not 2× / 3×.
- `test_eight_taps_in_one_frame_yields_one_eval` — hold-to-tap worst case (8 caught taps × 3 signals each = 24 signals) collapses to 1 eval.
- `test_signals_across_frames_eval_per_frame` — one signal per frame × 5 frames yields 5 evals (proves coalescing is per-frame, not "ever").
- `test_idle_frame_does_not_eval` — 60 idle frames cost zero evaluator runs (no per-frame cost when nothing is happening).
- `test_achievement_index_returns_same_dict_every_call` / `_quest_index_…` — index getters return the live cached reference, not a copy. A copy-per-call would re-introduce the allocation pressure even with coalescing in place.

**Pre-push checklist**

- Full GUT suite: **371/371 pass**, 49 scripts, 3395 asserts
- New perf suite: 8/8 pass

### v0.13.4 — Phase 12h: Difficulty curve overhaul

**Why**

The headless sim runner from v0.9.4 stalled at tier 4: `tier3_net` only targeted tiers [2,3], so the player could never catch a tier-4 monster to drop the `wraith_cinder` needed to craft `wraith_net`. Classic chicken-and-egg. The mid-tier nets (tier3, wraith, hedgewright, gleamwarp, refrain, vigil) all had the same off-by-one structural gap — each net's `targets_tiers` ended exactly at the tier whose drops the *next* net's recipe required, locking the player out of progression.

**Fix — overlap net target ranges by one tier**

Each middle net now extends one tier into the next bracket so the next recipe's input drops are reachable without crafting the net you need them for first. Higher CPS still drives the player to upgrade — the overlap just unblocks the chain.

| Net | Old `targets_tiers` | New `targets_tiers` | Unlocks input for |
|---|---|---|---|
| `tier3_net` | `[2, 3]` | `[2, 3, 4]` | `wraith_net` (needs tier-4 `wraith_cinder`) |
| `wraith_net` | `[4, 5, 6]` | `[4, 5, 6, 7]` | `hedgewright_net` (needs tier-7 `glimmer_husk`) |
| `hedgewright_net` | `[4, 5, 6, 7, 8, 9]` | `[4, 5, 6, 7, 8, 9, 10]` | `gleamwarp_net` (needs tier-10 `drift_crystal`) |
| `gleamwarp_net` | `[7, 8, 9, 10, 11, 12]` | `[7, 8, 9, 10, 11, 12, 13]` | `refrain_net` (needs tier-13 `refrain_echo`) |
| `refrain_net` | `[10, 11, 12, 13, 14, 15]` | `[10, 11, 12, 13, 14, 15, 16]` | `vigil_net` (needs tier-16 `refract_splinter`) |
| `vigil_net` | `[13, 14, 15, 16, 17, 18]` | `[13, 14, 15, 16, 17, 18, 19]` | `nadir_net` (needs tier-19 `hollow_cinder`) |

`basic_net`, `tier2_net`, and `nadir_net` are unchanged — `basic_net` is the seed (player is handed it), `tier2_net` already targets `[1, 2]` (its own input is tier 1), and `nadir_net` is the terminal net.

**Sim runner improvements**

- **`MAX_DESIGNED_TIER = 20`** + new `endgame_reached` event. Once `current_max_tier > 20` the runner exits cleanly with `endgame_reached` instead of false-positive STALLED. The post-cap "stall" was always just the player having nothing left to catch and the prestige threshold growing past their gold rate — not a balance issue.
- New `> ENDGAME REACHED` blockquote at the top of the report when the run cleared tier 20.
- Methodology note documenting that the **tier-2 wall flag is a known false positive** — tier 2 takes ~50 minutes (grind 50 wisplet_ectoplasm + craft `tier2_net`), which is the natural bootstrap pace; the median-relative flag fires because tiers 3-7 chain through in seconds with accumulated resources. Real walls show as multiple consecutive tiers flagged or as an outright stall.

**Sim sweep results (seed=42, 14-day horizon)**

- **Endgame reached at t=5.4h** (was: stalled at tier 4 with no progression after 31h)
- 11 prestige cycles in the first run before hitting the cap
- All 8 nets in the chain crafted: `basic → tier2 → tier3 → wraith → hedgewright` shown in the timeline by t=1.13h; later nets craft after subsequent prestige climbs
- Multi-seed sanity (seed=99): also hits endgame at t=5.4h, confirming the fix isn't seed-specific

**Tests**

- Full GUT suite: **363/363 pass**, 48 scripts, 3377 asserts, 19.28s
- No new tests authored — the change is data-only (+ a small sim runner ergonomic improvement). The sim itself is the regression test for difficulty-curve health.

**Pre-push checklist**

- Project loads cleanly (60-frame headless run): no SCRIPT ERROR / autoload failures
- Full GUT suite green
- Sim sweep with `seed=42` and `seed=99` both reach endgame; CSV + report committed

### v0.13.3 — Phase 12g: Quest system

**Why**

Achievements (12f) give long-running meta-goals to chip away at across many sessions, but they don't tell the player *what to do next minute*. The quest strip fills that gap with three concurrent goals — SHORT (next minute), MEDIUM (this session), LONG (this prestige cycle). Pecorella's GDC framing: surface "what's next" without overwhelming.

**Added — Quest schema + content**

- **[`QuestResource`](game/resources/quest_resource.gd)** — minimal schema mirroring `AchievementResource` with two extensions: `quest_tier { SHORT, MEDIUM, LONG }` (which slot the strip shows it in) and `repeatable: bool` + `next_quest_id` for ladder chains. `Source` enum picks up `RUN_GOLD_EARNED` so quests can read `total_gold_earned_this_run` directly.
- **30 starter quests** generated by [`scripts/generate_quests.sh`](scripts/generate_quests.sh) (idempotent — re-running overwrites cleanly):
  - **SHORT (10)**: catching ladder (`short_catch_25 → 100 → 500`), tap ladder (`short_tap_100 → 500`), one-shot misc (`short_first_shiny`, `short_recipe_any`, `short_pet_one`), run-gold ladder (`short_gold_1k → 10k`).
  - **MEDIUM (12)**: tier reaches, roster size, nets owned, recipes crafted, run shinies, lifetime catch/tap, run-gold milestones, battle unlock.
  - **LONG (8)**: prestige cycles (1/5/25), tier highlands (10/15/20), menagerie (10 pets), master crafter (8 recipes).
- **`ContentRegistry.quests()` + `quest(id)`** — registry indexes `game/data/quests/`.

**Added — QuestLog autoload**

- **[`QuestLog`](game/autoloads/quest_log.gd)** subscribes to the same fan of EventBus signals as `Achievements` plus `currency_changed` (so RUN_GOLD_EARNED quests update). Re-evaluates every slot on each event; emits `quest_progress_changed(slot, current, target)` only when the value actually moved (prevents UI spam).
- On completion: marks the id in `quests_completed` (de-dupe set), applies RP / gold / item rewards via the existing GameState helpers, emits `quest_completed`, then advances along `next_quest_id` for repeatables OR refills the slot from the eligible pool.
- Picker is deterministic (alphabetical-by-id of eligible matches): same tier as the slot, not currently active in another slot, not already completed, not a ladder tail until the head completes.
- New EventBus signals: `quest_completed(id)`, `quest_activated(slot, id)`, `quest_progress_changed(slot, current, target)`.

**GameState + save migration v4 → v5**

- **`active_quests: Dictionary`** — `{slot_int: quest_id_str}`. Persisted with stringified slot keys for JSON safety; normalized back to int keys on load via `_normalize_active_quests`. Resets on prestige (QuestLog repopulates from the picker).
- **`quests_completed: Dictionary`** — id-set of completed non-repeatables. Persists across prestige (the picker needs it to avoid re-issuing one-shots).
- New `_migrate_v4_to_v5` in [`save_migrations.gd`](game/systems/save_migrations.gd). `SaveManager.CURRENT_VERSION` bumped to 5.

**QuestStrip UI**

- **[`QuestStrip`](game/scenes/ui/quest_strip.gd)** — three-row PanelContainer pinned between the tab content and bottom nav in `main.gd._build_ui`. Each row: tier-tinted name, progress bar, current/target text. Empty slots collapse to "Short: ..." rather than disappearing — the fixed row count prevents content from jumping when a quest completes. Visible from every primary tab since it's part of the main vbox, not a per-tab child.
- Subscribes to `quest_activated`, `quest_completed`, `quest_progress_changed`, `game_loaded`. Painted lazily via `call_deferred("_refresh_all")` so QuestLog has a tick to fill slots first.

**Celebration spectrum**

- Quest completions go to **toast only** (SHORT cycles every minute or two; full celebration would over-celebrate the loop). LONG-tier completions get a longer-dwelling toast (4s vs 2.5s) since they're prestige-cycle milestones.

**Bug caught during dev**

- **Stack overflow** when a quest with `rp_reward > 0` completed: `add_rancher_points` emits `currency_changed`, which re-entered `evaluate_progress`, which re-fired `_on_completed` because the slot still pointed at the completed quest. Fix: clear the slot + mark `quests_completed` *before* applying rewards in `QuestLog._on_completed`.

**Tests (363 passing, +15)**

- [`test_quest_log.gd`](game/tests/test_quest_log.gd) — 15 cases covering: initial fill of all three slots; tier-matching; ladder advancement (`short_catch_25 → short_catch_100`); non-repeatable completion clears + refills with a different quest; RP reward; `quest_completed` signal contract; picker skips already-completed and ladder-tail quests until heads done; `slot_state` reports baseline-aware progress; save round-trip; v4→v5 migration seeds + preserves; prestige preserves `quests_completed`.

**Pre-push checklist**

- Project loads cleanly (60-frame headless run): no SCRIPT ERROR / autoload failures
- Full GUT suite: 363/363 pass, 48 scripts, 3377 asserts, 19.88s
- Class cache regenerated to register `QuestResource` globally

### v0.13.2 — Phase 12f: Achievements

**Why**

Long-running idle games need persistent meta-goals that survive prestige resets — checkboxes the player can chip away at across many sessions. Phase 12f introduces achievements: 20 starter goals spanning catching, tapping, prestige, pets, nets, crafting, and tier progression, with bronze/silver/gold tiers. Unlocks pay out in Rancher Points, so they double as a soft RP injection that smooths the ramp without being printer-money.

**Added — Achievement schema + content**

- **[`AchievementResource`](game/resources/achievement_resource.gd)** — minimal schema with `Tier { BRONZE, SILVER, GOLD }` and `Source { LEDGER_FIELD, PRESTIGE_COUNT, PETS_OWNED_COUNT, NETS_OWNED_COUNT, RECIPES_CRAFTED_COUNT, CURRENT_MAX_TIER }`. Picking a source means writing one branch in `Achievements._evaluate_trigger`.
- **20 starter achievements** generated by [`scripts/generate_achievements.sh`](scripts/generate_achievements.sh) (idempotent — re-running overwrites cleanly): catching milestones (`catch_100/1000/10000`, `shiny_1/25`), tap milestones (`tap_500/5000/50000`), prestige cycles (`prestige_1/5/25`), roster size (`pet_1/3/10`), nets owned (`net_2/5`), recipes crafted (`recipe_1/5`), and tier reached (`tier_5/10`). RP rewards scale 5/25/100 by tier.
- **`ContentRegistry.achievements()` + `achievement(id)`** — registry now indexes `game/data/achievements/`.

**Added — Achievements autoload**

- **[`Achievements`](game/autoloads/achievements.gd)** subscribes to a fan of EventBus signals (`monster_caught`, `monster_tapped`, `pet_acquired`, `recipe_unlocked`, `item_crafted`, `tier_completed`, `tier_unlocked`, `prestige_triggered`, `game_loaded`) and re-evaluates every still-locked achievement on each event. Cheap (a handful of int comparisons per signal) so wiring it to fast events is fine — no batching needed.
- On unlock: records the id in `GameState.achievements_unlocked`, applies RP / gold rewards via the existing `add_rancher_points` / `add_gold` paths, and emits `EventBus.achievement_unlocked`.
- `Achievements.progress_summary()` returns `{unlocked, total}` for the Ledger header.
- New `EventBus.achievement_unlocked(achievement_id: String)` signal.

**GameState + save migration v3 → v4**

- **`achievements_unlocked: Dictionary`** — `id_str → true`. Persisted; consulted before re-firing any unlock. Carried through `perform_prestige` (achievements are meta-progression, not run-progression).
- New `_migrate_v3_to_v4` in [`save_migrations.gd`](game/systems/save_migrations.gd) seeds an empty dict on existing v3 saves. `SaveManager.CURRENT_VERSION` bumped to 4.

**Celebration + ledger UI**

- **Celebration spectrum**: BRONZE / SILVER unlocks → toast (subtle, doesn't interrupt the loop, includes the RP reward in the toast body); GOLD unlocks → full celebration overlay with the achievement sprite. `main.gd._on_achievement_unlocked` routes by tier.
- **Ledger view** gains an "Achievements (N / total)" section beneath the existing stat rows: 4-column grid, tier-tinted name (bronze/silver/gold), description below, locked entries shown as dimmed `?????` silhouettes. Refreshes on `EventBus.achievement_unlocked`.

**Tests (348 passing, +13)**

- [`test_achievements.gd`](game/tests/test_achievements.gd) — 13 cases covering: every Source enum branch unlocks at threshold and not below; idempotent (`evaluate_all` twice fires once); RP reward applied; save round-trip preserves unlocks; v3→v4 migration seeds empty dict and preserves prior entries; `perform_prestige` keeps unlocks. Tests bypass the EventBus hookup and call `evaluate_all` directly so they're deterministic regardless of connection ordering.

**Pre-push checklist**

- `--check-only` (project loads cleanly via `--headless --path . --check-only`): pass
- Full GUT suite: 348/348 pass, 47 scripts, 3337 asserts, 18.9s
- Class cache regenerated to register `AchievementResource` globally

### v0.13.1 — Phase 12e: Pet equipment + prestige polish

**Why**

Phase 12d gave pets abilities; 12e gives them gear. Equipment provides a meta-progression layer between tier completions: craft a Brass Collar, your tank pet hits a little harder; craft a Seer's Circlet, your healer cycles abilities a tick faster. Combined with abilities, the wisplet trio becomes a small composition puzzle. Prestige polish lifts the most-celebrated event in the game out of "default Godot screen" territory.

**Added — Equipment system**

- **[`EquipmentResource`](game/resources/equipment_resource.gd)** — schema with `Slot { HEAD, BODY, TRINKET }`, `tier`, additive stat modifiers (`attack_add`, `defense_add`, `hp_add`), and an `ability_cooldown_reduction` capped at -2 ticks across all slots.
- **6 starter items** in [`game/data/equipment/`](game/data/equipment/): Copper Circlet / Brass Collar / Agitator Charm (tier 1, one per slot) and Seer's Circlet / Silver Collar / Rending Fang (tier 2). Stat ratios chosen so each item carves a distinct role.
- **`ContentRegistry.equipment(id)` + `equipment_items()`** — registry indexes the new content dir alongside monsters / pets / nets / etc.
- **3 equipment recipes** ([`recipe_brass_collar.tres`](game/data/recipes/recipe_brass_collar.tres), [`recipe_agitator_charm.tres`](game/data/recipes/recipe_agitator_charm.tres), [`recipe_copper_circlet.tres`](game/data/recipes/recipe_copper_circlet.tres)) producing the tier-1 items. New `output_equipment` field on `CraftingRecipeResource`; `CraftingSystem.can_craft` accepts it as a valid output type.

**GameState extensions**

- **`pet_equipment: Dictionary`** — `pet_id_str → {head: id, body: id, trinket: id}`. Persisted via the v3 save schema.
- **`owned_equipment: Array[String]`** — fallback stash when a freshly-crafted item has nowhere to go (e.g., all matching slots full). Future picker UI re-equips from here.
- **`best_rp_at_prestige: int`** — frozen at the highest RP gain across runs. Used by the prestige view's "vs your best" comparison.
- **`_grant_equipment(item)`** — auto-equip on craft: walks `pets_owned` in order, slots into the first pet with an empty matching slot, falls back to `owned_equipment` if all are full.
- **`equipment_in_slot(pet_id, slot_key)`** + **`equipment_stats_for(pet_id)`** — read helpers used by `BattleSystem` and future UI.

**BattleSystem integration**

- `_make_combatant_from_pet` now applies equipment stat modifiers when building the combatant dict. The pet's base stats remain on `PetResource`; the runtime values combine base + summed equipment bonuses. `ability_cooldown_reduction` reduces the start-of-battle cooldown but is capped so a fully-decked pet can't drop every ability to 0-tick spam.

**Save migration v2 → v3**

- New migration in [`save_migrations.gd`](game/systems/save_migrations.gd) seeds `pet_equipment = {}`, `owned_equipment = []`, `best_rp_at_prestige = 0`. Existing v2 saves load cleanly with empty equipment scaffolds.
- `CURRENT_VERSION` bumped to 3.

**Prestige preserves equipment**

- `perform_prestige()` snapshots `pet_equipment`, `owned_equipment`, and updates `best_rp_at_prestige` to `max(current, this_run_rp_gain)` before resetting other state. Pets persist through prestige so their gear should too.

**Prestige view polish**

- Themed brass-tinted "Projected: +N RP" header (was `Color(1.0, 0.86, 0.4)` modulate; now uses `_PALETTE.BRASS_ACCENT` via theme color override).
- New "vs your best" sub-line under the projected RP. Three states: "First prestige run", "New record! Previous best: N RP", "Your best run: N RP".
- Confirm button ruby-tinted (`BLOOD_RUBY` font color override) to mirror the wipe-save destructive pattern.
- Confirmation dialog explicitly assigned `theme = main_theme.tres` per the v0.10.4 popup-theme fix.

**Tests (335 passing, +10)**

- [`test_equipment.gd`](game/tests/test_equipment.gd):
  - Equipment loads via ContentRegistry.
  - Auto-equip places first crafted item on first eligible pet; second goes to next pet.
  - Falls back to `owned_equipment` when all matching slots are full.
  - BattleSystem combatant dict reflects base + equipment stats; no equipment → base stats only.
  - `equipment_stats_for` returns correct totals across multiple slots.
  - Save migration v2 → v3 adds the three new fields with safe defaults.
  - Prestige preserves equipped items.
  - Prestige updates `best_rp_at_prestige` only when current run beats it.
  - Recipe with `output_equipment` validates via `can_craft` and crafts end-to-end.
- Full GUT suite: **335/335 passing, 3318 asserts.**

**Pre-push checklist**

- `--check-only` exits 0.
- Full GUT suite green.
- Three exports left to CI.

**Notes / what's deferred**

- Explicit equipment picker UI (the `team_select.tscn` from DEPTH_PLAN's 12e acceptance) is **not** in 12e. Auto-equip-on-craft means players don't need a picker to *use* the system, but unequipping or reassigning gear requires one. Deferred.
- Roster-row stat preview ("+5 ATK · +20 HP from equipment") on the Battle screen — also deferred. The combat math already applies; this is just surfacing it in UI.
- 15-item full equipment grid (3 slots × 5 tiers) from DEPTH_PLAN — currently 6 items. The remaining 9 land as content authoring.
- Animated RP forecast ring chart on the prestige view — a static label is shipped; the radial chart is purely cosmetic.

### v0.13.0 — Phase 12d: Pet abilities

**Why**

`PetResource.ability_id` had been wired since Phase 2, `BattleSystem._act` already queried `AbilityRegistry.get_ability(id)`, and the BattleLog supported ability frames — but only three abilities (`strike`, `shield`, `heal`) shipped. Battle was effectively "highest-ATK wins" because every pet defaulted to plain attacks. Phase 12d adds five new ability templates plus the status-effect plumbing they need (bleed DOT, taunt-aware targeting), turning team selection into a genuine choice.

**Added — 5 new abilities in [`AbilityRegistry`](game/systems/ability_registry.gd)**

- **`taunt`** — applies `taunted` status to caster for 5 ticks. Enemy basic attacks (and `_pick_lowest_hp`-driven ability targeting) preferentially route to taunted enemies via the new `pick_target_with_taunt` helper. 10-tick cooldown.
- **`rend`** — applies `bleed` status (5 dmg / tick × 4 ticks) to lowest-HP enemy. `BattleSystem._tick_statuses` now applies the bleed damage before decrementing duration. 8-tick cooldown.
- **`smite`** — 2.5× damage on the **highest-HP** enemy. Inverts `strike`'s target selection so the role is "focus-fire on the tankiest enemy" rather than "finish the squishy one." Uses new `_pick_highest_hp` picker. 12-tick cooldown.
- **`cleanse`** — strips `bleed` from all allies (positive statuses like `def_buff` and `taunted` survive). Counter to enemy DOT teams. 14-tick cooldown.
- **`burst`** — 0.6× damage AOE to all living enemies. Multi-target alternative to strike. 10-tick cooldown.

**BattleSystem extensions**

- `_tick_statuses` applies per-tick effects (currently `bleed`) before decrementing `ticks_remaining`. Existing passive statuses (`def_buff`, `taunted`) read elsewhere are unchanged.
- `_act`'s basic-attack target selection routes through `AbilityRegistry.pick_target_with_taunt(enemies)` instead of the local `_pick_lowest_hp(team)`. Taunt now actually redirects targeting end-to-end.

**Pet ability assignments**

- `green_wisplet_pet`: `strike` → **`heal`** (defensive support).
- `red_wisplet_pet`: `strike` → **`smite`** (focus-fire damage).
- `blue_wisplet_pet`: **`shield`** (kept — already a tank role).

The wisplet roster now plays as a tank/damage/healer trio: send all three into a Wisplet Hollows stage and the team shape feels intentional. Previously they all played identically.

**Tests (~324 passing, +10)**

- [`test_abilities.gd`](game/tests/test_abilities.gd) — coverage per ability:
  - taunt applies status, redirects targeting (taunted enemy picked over lower-HP non-taunted), falls back to lowest-HP without taunt.
  - rend applies bleed; 4 ticks of bleed deal exactly `5 × 4 = 20` damage; bleed expires after duration.
  - smite picks highest-HP enemy; damage uses 2.5× multiplier (bound-checked under variance).
  - cleanse strips bleed from allies; def_buff and other positive statuses survive.
  - burst hits all living enemies; skips already-dead.
  - Determinism: same RNG seed produces byte-identical damage rolls for smite + burst.
- Existing `test_battle_system.gd`, `test_battle_stage.gd`, `test_battle_view.gd` still pass — the new behavior layers on top of the existing simulator without breaking determinism contracts.

**Pre-push checklist**

- `--check-only` exits 0.
- Full GUT suite green.
- Three exports left to CI.

**Notes**

- Combatant visuals for the new abilities currently fall back to the standard attack-lunge animation. Distinguishable visuals (aura flash for buffs, ground glyph for AOE, beam for heal targeting) are listed in DEPTH_PLAN's 12d acceptance and remain a follow-up — the gameplay-side work is what makes the ability variety meaningful; visuals are polish.
- Tier 2+ pets don't yet have `.tres` files, so the new abilities are accessible only via the wisplet trio for now. Future tier-2-pet content can pull from the new pool.

### v0.12.2 — Phase 12c: FTUE / Tutorial coachmarks

**Why**

The Phase 10 audit's #3 cluster: new players had to deduce the loop. There was zero scripted onboarding (`Grep tutorial|onboarding|coachmark` returned nothing). Per Pecorella's GDC framing, idle games shouldn't *teach* — they should *unlock* mechanics in sequence and surface the next mechanic when its trigger condition fires.

Phase 12c lays the FTUE foundation: 4 contextually-fired coachmarks, persistent state so they don't replay, and a Replay-tutorial button in Settings.

**Added**

- **`TutorialState` autoload** ([`game/autoloads/tutorial_state.gd`](game/autoloads/tutorial_state.gd)) — tracks which steps have been completed. Persists to `user://tutorial.cfg`. API: `should_show(step_id)`, `mark_seen(step_id)`, `reset()`, `has_any_progress()`. Six step ids defined; four are wired in this iteration (`tap_first_monster`, `buy_first_net`, `enter_battle`, `craft_first_recipe`); `equip_net` and `complete_first_tier` remain in the registry as future hooks.
- **[`game/scenes/ui/coachmark.tscn`](game/scenes/ui/coachmark.tscn) + [`.gd`](game/scenes/ui/coachmark.gd)** — focused tooltip overlay:
  - `CanvasLayer` at layer 75 (below celebration_overlay 80, above narrator).
  - Dim backdrop (40 % opacity) + pulsing brass-tinted arrow + themed text bubble.
  - Anchors to a target Control's global rect; auto-flips arrow direction so the bubble sits above the target when target is in the bottom 60 % of the screen, below otherwise.
  - Re-anchors each frame (`_process` calls `_reposition`) so the coachmark tracks targets that move (e.g., wandering monsters in future hooks).
  - Tap anywhere dismisses, marks the step seen, fires `dismissed(step_id)`.
  - Pulse animation skipped under `Settings.reduce_motion`.
- **Tutorial director in [`main.gd`](game/scenes/main.gd) (`_install_tutorial_director`)** — subscribes to EventBus signals so coachmarks fire when their trigger conditions hit:
  - `tap_first_monster` → first launch with zero catches → targets the Catch nav button.
  - `buy_first_net` → reach 100 gold + no nets owned → targets More button (Shop is inside More).
  - `enter_battle` → first `pet_acquired` signal → targets Battle nav button.
  - `craft_first_recipe` → first `tier_unlocked(2)` with no recipes crafted → targets More button (Crafting is inside More).
- **Replay-tutorial button in Settings** — visible only when `TutorialState.has_any_progress()`. Calls `Main.replay_tutorial()` which resets state and re-fires the first-launch check.

**Tests (314 passing, +10)**

- [`test_tutorial_state.gd`](game/tests/test_tutorial_state.gd) (6): should_show defaults true, mark_seen flips it, idempotent on duplicate marks, reset clears, has_any_progress, settings.cfg round-trip.
- [`test_coachmark.gd`](game/tests/test_coachmark.gd) (4): starts hidden, show_for makes visible + sets hint, dismiss marks step seen, tap on backdrop dismisses.
- Full GUT suite: **314/314 passing, 3255 asserts.**

**Pre-push checklist**

- `--check-only` exits 0.
- Full GUT suite green.
- Three exports left to CI.

**Notes**

- `equip_net` and `complete_first_tier` step ids are in `TutorialState.ALL_STEPS` but no trigger fires them yet. They're available for future iteration if playtesting flags those moments as needing explicit coachmarks. The current four cover the highest-leverage onboarding moments (Catch tab → Net unlock → Battle tab → Crafting tab), which trace the natural progression path through the first 10–20 minutes of play.

### v0.12.1 — Phase 12b: Accessibility v2 (hold-to-tap + color-blind redundancy)

**Why**

Game Accessibility Guidelines flags hold-to-tap as the highest-leverage accessibility add for clicker games — it serves players with RSI, motor sensitivities, and players whose phones can't keep up with rapid taps. Color-blind mode similarly addresses a population the existing UI hadn't considered: bestiary slot pills (and the shiny floating-number cue) leaned on color discrimination for filled-vs-unfilled state.

**Added — Hold-to-tap (item 11)**

- **`Settings.hold_to_tap_enabled: bool`** (default false), **`hold_tap_rate_hz: float`** (default 8 Hz, clamped 4–16). New setters `set_hold_to_tap_enabled()` + `set_hold_tap_rate_hz()` emit `accessibility_settings_changed` and persist to the `[accessibility]` section of `settings.cfg`.
- **[`catching_view.gd`](game/scenes/catching/catching_view.gd) `_handle_hold_to_tap`** — accumulator-based repeat-tap loop in `_process`. Press starts hold mode, drag updates the tracked finger position (so dragging across multiple monsters resolves them in turn), release ends it. Decoupled from input-event frequency so the rate stays steady at the configured Hz.
- Refactored `_gui_input` into `_resolve_tap_at(local_pos)` so the hold loop and the press handler share one resolve path.

**Added — Color-blind redundancy (item 12)**

- **`Settings.colorblind_mode: bool`** (default false). Same persistence + signal pattern as the other accessibility flags.
- **[`bestiary_card.gd `_pill`](game/scenes/bestiary/bestiary_card.gd)** — appends `✓` for filled / `·` for unfilled when `colorblind_mode` is on. Filled-vs-unfilled state now reads through shape regardless of whether the player can distinguish the modulate color from the dim outline.
- The shiny floating-number cue already uses shape redundancy (`✨` prefix + larger font), so no extra change there.

**Added — Settings UI**

- Three new controls in the Accessibility section: "Hold to auto-tap" toggle, "Hold tap rate" slider (4–16 Hz), and "Color-blind mode" toggle with a one-line blurb explaining what it does.

**Tests (304 passing, +8)**

- [`test_hold_to_tap.gd`](game/tests/test_hold_to_tap.gd) (4): rate clamps below 0 and above 99, enabled-setter emits signal, idempotent on unchanged value, round-trips through `settings.cfg`.
- [`test_colorblind_mode.gd`](game/tests/test_colorblind_mode.gd) (4): setter emits signal, no shape suffix when off, ✓/· suffixes appear when on, round-trips through `settings.cfg`.
- The behavioral catching_view test for hold-to-tap was scoped down to setter contracts after instantiating catching_view in tests caused state-leak warnings ("lambda capture freed") in unrelated tests further along in the alphabetical order. The integration is straightforward `_process` logic — its real validation happens via Maestro emulator flows.
- Full GUT suite: **304/304 passing, 3230 asserts.**

**Pre-push checklist**

- `--check-only` exits 0.
- Full GUT suite green.
- Three exports left to CI.

### v0.12.0 — Phase 12a: Quality-of-life bundle

**Why**

Phase 11 closed the celebration / accessibility / production-hygiene gaps; Phase 12a tackles the per-screen friction the audit flagged. Bulk crafting (single-craft was tedious), inventory icons (the "most default-Godot-feeling" screen left after Phase 10), net comparison (no signal whether an upgrade was worth the gold), Settings expansion (master volume slider was persisted but never exposed). Item 17 from the suggestion list — long-press menus — landed in inventory only; broader long-press wiring deferred to a follow-up so 12a stays scoped.

**Added — Inventory cards (item 15)**

- **[`ItemResource.rarity: Rarity`](game/resources/item_resource.gd)** — new `@export` enum with COMMON / UNCOMMON / RARE / EPIC. Defaults to COMMON so existing items render unchanged; per-item overrides land later as content is authored.
- **[`game/scenes/ui/inventory_card.tscn`](game/scenes/ui/inventory_card.tscn) + [`.gd`](game/scenes/ui/inventory_card.gd)** — themed PanelContainer with icon (or "?" fallback), name, count, and a per-card StyleBoxFlat override for the rarity-tinted border (brass / sage / dusk / ruby).
- **Rewritten [`inventory_panel.gd`](game/scenes/ui/inventory_panel.gd)** — `GridContainer` of cards instead of flat VBox of Labels. Column count adapts to viewport: 3 / 4 / 5 across [<480, 480–999, ≥1000] px. Items sort by rarity descending then by display name, so rare drops surface at the top of the list. Empty state preserved.

**Added — Bulk crafting (item 4)**

- **[`crafting_view.gd `_on_craft_n_pressed`](game/scenes/crafting/crafting_view.gd)** — wraps `try_craft` in a count-bounded loop; stops early on first failure; one `_refresh` at the end so the UI doesn't flicker through intermediate states.
- **`_max_craftable(recipe)`** — computes the cap for the "Max" button from the per-input material floor and the gold floor (via BigNumber.divide → float). Conservative: returns 0 if both are 0.
- Recipe cards now render three buttons (`Craft` / `x5` / `Max`) instead of a single Craft. Auto-craft scheduler (the optional `auto_craft_enabled` toggle from the plan) deferred — bulk buttons solve the most-painful friction without that complexity.

**Added — Inventory long-press → "Sell all" (item 17, partial)**

- Inline long-press in `inventory_card.gd`: holds for ≥ 0.5 s emit `card_long_pressed(item_id)`. Polls in `_process` so the long-press fires mid-hold without the user lifting first.
- `inventory_panel.gd` builds a themed PopupPanel with a "Sell all" button on long-press. Sells the entire stack at the item's `sell_value × count`, applies via `GameState.add_gold`. Future hooks for "Use as ingredient" / "Pin to top" left as TODO comments.
- Long-press wiring on **recipes / pets / bestiary** deferred — the inventory case is the highest-traffic; the others can land in 12a-followup.

**Added — Net comparison (item 16)**

- **[`net_shop.gd `_format_stat_delta`](game/scenes/ui/net_shop.gd)** — for unowned, comparable nets, renders a BBCode delta line like `vs Basic Net: +1 spawn_max · +0.30 catches/s · targets tier 2` with sage-green positives and ruby-tinted negatives. Hidden when no net is equipped or when the candidate IS the equipped net (no point comparing to itself).

**Added — Settings expansion (item 18)**

- **Master volume slider** — `Settings.audio_master_db` had been persisted in `settings.cfg` since Phase 0 but had no setter or UI. New `set_master_db()` + slider, and [`AudioManager._apply_volumes`](game/autoloads/audio_manager.gd) now writes the value through to `AudioServer`'s Master bus on every `audio_settings_changed` signal.
- **Language picker** — placeholder `OptionButton` with one entry ("English"). Note explains additional languages will arrive with the localization phase. Structural placeholder so the UI rotation is in place.
- **Replay tutorial button** — deferred to 12c (the FTUE / tutorial phase). Adding it now would require stubbing TutorialState which is out of scope here.

**Tests (296 passing, +14)**

- [`test_inventory_card.gd`](game/tests/test_inventory_card.gd) (5 tests): bind displays name + count, "?" glyph fallback when no sprite, rarity colors differ across tiers, short-press emits `card_tapped`, long-press emits `card_long_pressed`.
- [`test_bulk_crafting.gd`](game/tests/test_bulk_crafting.gd) (5 tests): Craft 5 consumes 5× materials, stops early on material exhaustion, `_max_craftable` caps at material floor, caps at gold floor, returns 0 when materials are 0.
- [`test_net_comparison.gd`](game/tests/test_net_comparison.gd) (4 tests): no delta when no equipped net, no delta when target is owned, no delta vs self, delta surfaces for unowned upgrade.
- Full GUT suite: **296/296 passing, 3216 asserts.**

**Pre-push checklist**

- `--check-only` exits 0.
- Full GUT suite green.
- Three exports left to CI.

**Out of scope / deferred from 12a**

- Auto-craft scheduler (optional toggle gated behind first prestige).
- Long-press menus on pets / recipes / bestiary cards.
- Replay-tutorial button (waits on 12c).

### v0.11.4 — Phase 11e: Short-session affordance + welcome-back robustness

**Why**

Three audit findings combined: F42 (battle speed resets to 1× every entry), F47 (welcome-back 2× ad missed the rolled-up `shinies_caught` counter), F48 (force-quit at the welcome-back dialog loses offline progress entirely).

**Added**

- **`Settings.battle_speed_index: int` (persisted)** + `set_battle_speed_index(value)` setter. Loaded from `settings.cfg` `[gameplay] battle_speed_index`. Defaults 0 (1× speed) so existing players see no change.

**Wired**

- **[`battle_view.gd `_ready`](game/scenes/battle/battle_view.gd)** — initializes `_speed_index` from `Settings.battle_speed_index`, clamped to the valid range. The 4× setting now sticks across sessions.
- **[`battle_view.gd `_cycle_speed`](game/scenes/battle/battle_view.gd)** — calls `Settings.set_battle_speed_index(_speed_index)` on every tap so the persisted value tracks the live one immediately.

**Fixed (welcome-back)**

- **F48 (force-quit at dialog loses progress)** — [main.gd `_apply_offline_progress`](game/scenes/main.gd) now applies the offline rewards via `_on_welcome_back_claimed(summary)` IMMEDIATELY before showing the dialog. The dialog becomes a confirmation/summary; the rewards land in GameState and persist via the next save tick regardless of whether the player taps Claim or force-quits. The "Claim" button's confirm handler is now a no-op (rewards already credited).
- **F47 (2× ad missed shinies_caught counter)** — [welcome_back_dialog.gd `_on_rewarded_completed`](game/scenes/ui/welcome_back_dialog.gd) used to build a "doubled summary" by walking nested fields, but missed the top-level `shinies_caught` rollup. Removing the doubling logic entirely (since rewards are now pre-applied at compute time) made this a non-bug. The 2× path now emits the ORIGINAL summary so the claim handler applies it AGAIN, yielding 2× total — simpler than the manual-doubling approach and forecloses similar "missed a field" bugs.

**Tests (282 passing, +5)**

- [`game/tests/test_persistent_battle_speed.gd`](game/tests/test_persistent_battle_speed.gd) — 5 tests:
  - `set_battle_speed_index` clamps below 0 and above 2.
  - Setter is idempotent at the current value.
  - `battle_view._ready` initializes `_speed_index` from `Settings.battle_speed_index`.
  - `_cycle_speed` writes through `Settings.set_battle_speed_index` on every tick (covers the wrap from 2 → 0).
  - `battle_speed_index` round-trips through `settings.cfg`.
- Full GUT suite: **282/282 passing, 3194 asserts.**

**Pre-push checklist**

- `--check-only` exits 0.
- Full GUT suite green.
- Three exports left to CI.

**Notes / what's left**

- The audit's "Claim All" idea (one-button absorbs offline + daily + queued progress) is **not** implemented here; with offline already pre-applied at launch, the welcome-back dialog effectively IS claim-all. A daily-login bonus is a separate design item — deferred until the broader retention loop gets attention.
- Audit F65/F66 (spawn bounds overlap with currency bar / nav) not addressed in 11e — small layout fixes pending broader playtest feedback.

### v0.11.3 — Phase 11d: Progression visibility

**Why**

The audit's #3 cluster: new players had to deduce the loop. Tier-up arrived as a surprise (no "23/25 caught" indicator). The Battle tab's "no pets" empty state had no path forward. The Crafting tab pre-tier-1 was a literal empty void with no hint of when something would unlock. Per Pecorella's GDC Europe talk, idle games should layer goal horizons; the catching screen had none.

**Added**

- **[`game/scenes/ui/next_goal_chip.tscn`](game/scenes/ui/next_goal_chip.tscn) + [`.gd`](game/scenes/ui/next_goal_chip.gd)** — compact tier-progress indicator. Themed PanelContainer + Label + ProgressBar. Two display modes:
  - "Tier N: K species left to find" while any tier-N species is unseen.
  - "Tier N: K / 25 catches" once every species is at least seen — surfaces the actual catch count toward the unlock.
  - Subscribes to `EventBus.monster_caught`, `tier_completed`, `game_loaded`. Disconnects in `_exit_tree` so the chip is signal-leak-clean across instantiations.
  - Reads the same threshold the awarding code uses (`_TIER_DEBUG_THRESHOLD` vs `_TIER_COMPLETE_CATCH_THRESHOLD`) gated by `Settings.debug_fast_pets`, so the chip and the actual unlock condition stay in sync.
- **Mounted on the catching view** at top-right (anchor 1,0,1,0; offsets -200/12/-12/56). Sits just below the currency_bar in the natural eye-scan path.

**Empty-state hints**

- **Battle tab without pets** ([battle_view.gd `_render_idle`](game/scenes/battle/battle_view.gd)) now surfaces a "Go to Catch" button below the "Complete a tier..." message. Players never get stuck on an empty Battle screen.
- **Crafting tab without unlocked recipes** ([crafting_view.gd `_refresh`](game/scenes/crafting/crafting_view.gd)) shows a centered "Nothing crafted here yet" card with the next-tier-required teaser ("Recipes start unlocking at tier N. Catch monsters to advance.") and a "Go to Catch" button.

**Cross-screen navigation**

- **`EventBus.tab_switch_requested(tab_name)`** — new signal so any screen can request a primary-tab switch without coupling to main.gd. Main subscribes and routes to the existing `_navigate_to_tab`.

**Tests (277 passing, +4)**

- [`game/tests/test_next_goal_chip.gd`](game/tests/test_next_goal_chip.gd) — 4 tests:
  - Fresh state shows "species left to find" message.
  - After catching one of every tier-1 species, switches to "X / 25 catches" mode.
  - Progress bar tracks `max_count / threshold` (15/25 ≈ 0.6).
  - Bar clamps at 1.0 even when `max_count` exceeds threshold.
- Full GUT suite: **277/277 passing, 3185 asserts.**

**Pre-push checklist**

- `--check-only` exits 0.
- Full GUT suite green.
- Three exports left to CI.

**Notes / future work**

- POLISH_PLAN finding F15 (prestige progress meter on Catch/Battle tabs) is **not** addressed here. The catch screen now shows "what's next at this tier"; surfacing prestige progress requires more design (where does it live? how do we keep it from cluttering the catching view further?). Deferred.
- The next_goal_chip UI is single-line; multi-line goal horizons (Pecorella's seconds/minutes/hours/days framing) are a richer future project.

### v0.11.2 — Phase 11c: Production hygiene

**Why**

The Phase 10 audit flagged three diagnostic overlays + two debug keyboard shortcuts as production-leaks: shipping with the touch-debug overlay paints **green outlines around every Button** in release builds (a visible "this is in development" tell), the save-indicator flashes "Saved <HH:MM:SS>" every save tick (no end-user value), and F3 silently wipes the save with no confirmation if a Bluetooth keyboard happens to send the keystroke.

These were left in production through Phase 10 because the Android input + save-lifecycle bugs they debugged were still being investigated. Those are resolved now.

**Fixed**

- **[`main.gd` `_build_ui`](game/scenes/main.gd)** — `_AD_DIAGNOSTIC_OVERLAY`, `_SAVE_INDICATOR_OVERLAY`, `_TOUCH_DEBUG_OVERLAY` instantiation now gated behind `OS.is_debug_build()`. Release builds get a clean UI.
- **[`main.gd` `_unhandled_input`](game/scenes/main.gd)** — F2 (debug_fast_pets toggle) and F3 (full save reset) gated behind `OS.is_debug_build()` at the top of the handler. The number-key shortcut block immediately below was already gated; this just covers the two function keys that weren't.

**Tests (273 passing, no count change)**

- Pure plumbing change — existing test suite catches structural regressions and stays green.
- Full GUT suite: 273/273 passing, 3181 asserts.

**Pre-push checklist**

- `--check-only` exits 0.
- Full GUT suite green.
- Three exports left to CI.

**Notes**

- Emoji-glyph nav icons (POLISH_PLAN finding F62) are still in place — replacing them with shipped PNG icons requires authoring 11 nav-bar glyphs, deferred until the broader sprite-asset pass.

### v0.11.1 — Phase 11b: Accessibility section (reduce motion + haptics + font scale)

**Why**

The audit found `Settings.reduce_motion` and `Settings.font_scale` were declared in the autoload and persisted to `settings.cfg`, but **no code in the project ever read them**. The infrastructure existed; the wiring didn't. Phase 11b lights it up — adds an Accessibility section to the Settings UI, plumbs the flags through the highest-traffic animation sites and the haptic hooks, and ensures live changes apply without a scene reload.

**Added**

- **`Settings.set_reduce_motion(bool)` / `set_font_scale(float)` / `set_haptics_enabled(bool)`** — typed setters in [`game/autoloads/settings.gd`](game/autoloads/settings.gd) that clamp, dedupe, persist, and emit `accessibility_settings_changed` for live UI re-application.
- **`Settings.haptics_enabled: bool`** — new persisted flag (default true) covering the global button-haptic hook + the per-tap haptic in catching_view.
- **`Settings.FONT_SCALE_MIN/MAX` (0.85 / 1.5)** — clamp range chosen so all themed Labels stay readable without overflowing their containers (notably the 110-px currency_chip panel) at the upper end.
- **Accessibility section in [`settings_view.gd`](game/scenes/ui/settings_view.gd)** — checkbox toggles for "Reduce motion" + "Haptic feedback", and an HSlider for "Text size" (85 % – 150 %, live percentage readout).

**Wired**

`reduce_motion` now gates animation at:
- [catching_view.gd `_shake_spawn_root`](game/scenes/catching/catching_view.gd) — tier-up + first-shiny screen jitter.
- [monster_instance.gd `_play_tap_bump`](game/scenes/catching/monster_instance.gd) — the highest-frequency animation in the game (every tap).
- [floating_number.gd `_ready`](game/scenes/ui/floating_number.gd) — number drift; alpha fade still plays so the gain registers.
- [catching_background.gd `_process`](game/scenes/catching/catching_background.gd) — ambient parallax scroll (the "nothing's wrong but my eyes are tracking motion" effect motion-sensitive players ask to disable).
- [combatant.gd `_step_idle_bob`, `play_attack_lunge`, `_play_defeated_fade`](game/scenes/battle/combatant.gd) — battle screen bob, attack-lunge translation (state machine still flips through ATTACK_LUNGE so the contract holds), defeated-fade rotation (alpha fade still plays so defeat reads).
- [celebration_overlay](game/scenes/ui/celebration_overlay.gd) and [toast](game/scenes/ui/toast.gd) — defensive hooks added in 11a now actually consult the live `Settings.reduce_motion`.

`haptics_enabled` now gates:
- [main.gd `_on_any_button_pressed`](game/scenes/main.gd) — global Button haptic.
- [catching_view.gd `_on_monster_tapped`](game/scenes/catching/catching_view.gd) — per-tap catch haptic.

`font_scale` is applied to the mobile-default theme's `Button` / `Label` / `RichTextLabel` font sizes when the theme is built. `accessibility_settings_changed` triggers a `_apply_mobile_default_theme` re-call, so a slider drag reflects on every theme-styled Label without leaving the Settings screen.

**Documented limitation**

Inline `add_theme_font_size_override` calls on individual labels (battle_view status label, prestige heading, narrator_overlay, etc.) are NOT scaled by `font_scale` — they bypass the theme. Theme-level scaling reaches the bulk of default-styled labels (catching roster, currency chip values, bestiary cards, button text on the bottom nav, all the inventory / crafting / shop list rows), which is the most important text. Selectively scaling per-label overrides would touch ~80 sites; deferred to a follow-up if vision-impaired playtesting flags specific overrides as problems.

**Tests (273 passing, +8)**

- [`game/tests/test_accessibility_settings.gd`](game/tests/test_accessibility_settings.gd) — 8 tests:
  - `set_reduce_motion` emits `accessibility_settings_changed`.
  - Setter is idempotent — setting to current value does not fire signal.
  - `set_font_scale` clamps below FONT_SCALE_MIN and above FONT_SCALE_MAX.
  - `set_haptics_enabled` round-trips through `settings.cfg`.
  - `floating_number` skips drift when `reduce_motion` is on.
  - `floating_number` drifts normally when `reduce_motion` is off (regression — protects against the gate getting stuck on).
  - `combatant` idle bob is static when `reduce_motion` is on.
  - `combatant` attack lunge returns immediately when `reduce_motion` is on.
- Test isolation: `before_each` in `test_catching_background.gd` and `test_combatant.gd`, plus `after_each` in `test_accessibility_settings.gd`, reset Settings state. Without these, the new `reduce_motion` gates leak state across test files in unpredictable order — caught and fixed mid-iteration.
- Full GUT suite: **273/273 passing, 3181 asserts, 0 warnings.**

**Pre-push checklist**

- `--check-only` exits 0.
- Full GUT suite green.
- Three exports left to CI.

### v0.11.0 — Phase 11a: Celebration tier (state-change feedback hierarchy)

**Why**

Two parallel research/audit passes (industry research on Android idle-game UX + a 70-finding audit of the live codebase) converged on the same #1 issue: state-change feedback was at v0.5-prototype level despite Phase 10 polish. Tier completions, first pets, first shinies, stage clears, and even **prestige** — the largest progression event in the game — fired with no celebration. Per Wayline's juice essays and Yarahmadi's casual-game UX writeup, feedback intensity should be roughly logarithmic in event rarity. The current game inverted that.

Phase 11a builds the missing T2/T4 layer of the feedback spectrum.

**Added**

- **[`game/scenes/ui/celebration_overlay.tscn`](game/scenes/ui/celebration_overlay.tscn) + [`.gd`](game/scenes/ui/celebration_overlay.gd)** — full-screen Tier-4 celebration modal:
  - `CanvasLayer` at layer=80 (above narrator overlay).
  - Centered themed `PanelContainer` card with title + optional sprite + body + "Tap anywhere to dismiss" hint.
  - Fade-in + scale-up tween (0.92 → 1.0, cubic-ease-out, 0.25 s).
  - 0.25 s **input lock** at start so a player tapping rapidly doesn't dismiss the overlay before noticing it appeared.
  - Both backdrop and card accept tap-to-dismiss — no hunting for the right pixel.
  - `dismissed` signal fires after fade-out completes (consumers like the bestiary modal pattern can chain on it).
  - `Settings.reduce_motion` consulted defensively — when wired in 11b, motion-reduced users get instant show/hide.

- **[`game/scenes/ui/toast.tscn`](game/scenes/ui/toast.tscn) + [`.gd`](game/scenes/ui/toast.gd)** — slide-down Tier-2 toast queue:
  - Top-anchored banner that slides in from above the viewport, holds, slides back out.
  - Internal queue: rapid `show_toast` calls play one-after-another instead of clipping each other.
  - `queue_size()` exposed for tests.
  - 0.5 s minimum duration floor so a `show_toast(text, 0)` still has a visible window.
  - `Settings.reduce_motion` consulted defensively as above.

- **EventBus dispatch in [`main.gd`](game/scenes/main.gd) (`_install_celebrations`)** — the tier-spectrum routing:
  - **Tier 4 (overlay):** `tier_completed`, `first_shiny_caught`, `prestige_triggered`, `battle_ended` (won).
  - **Tier 2 (toast):** `pet_acquired`, `recipe_unlocked`.
  - Tier-1 events (currency_changed, item_gained, monster_caught) intentionally not surfaced here — they're already covered by per-screen feedback (floating numbers, particles, audio stings); over-celebrating the loop fatigues the player.
  - `tier_completed` overlay body lists the actual pet names earned (via `CatchingSystem.pets_to_award_for_tier`).
  - `first_shiny_caught` overlay shows the species sprite alongside the title.
  - `prestige_triggered` overlay reports both RP gained and prestige cycle number.

**Tests (265 passing, +14)**

- [`game/tests/test_celebration_overlay.gd`](game/tests/test_celebration_overlay.gd) (8): starts hidden, becomes visible on `show_celebration`, sprite rect toggles correctly with/without sprite, dismiss + fade-out hides the overlay, subsequent `show_celebration` replaces the previous, **input lock blocks immediate dismissal** (regression for the rapid-tap dismiss case), `dismissed` signal fires.
- [`game/tests/test_toast.gd`](game/tests/test_toast.gd) (6): show_toast marks showing, label reflects text, queue grows when multiple toasts fire, auto-dismisses after duration, queued toast runs after first finishes, duration is floored to a 0.5 s minimum.
- Full GUT suite: **265/265 passing, 3170 asserts.**

**Pre-push checklist**

- `--check-only` exits 0.
- Full GUT suite green.
- Three exports left to CI.

**Notes**

- The actual tier-4 events still need their original handlers to fire properly (catching_view._award_tier_completion, battle_view._finish_stage, prestige_view._on_prestige_confirmed, etc.) — Phase 11a only ADDS celebration on top of those existing emit sites. No regressions to underlying gameplay.
- Future polish: Phase 11b wires `Settings.reduce_motion` into the overlay's tween paths and exposes the toggle in the Settings tab.

### v0.10.8 — Phase 10e.2: Multi-encounter battle stages

**Why**

Phase 10e.1 shipped the side-scrolling battle map but the underlying flow was still "one battle = one encounter". Phase 10e.2 turns each Fight into a stage: a 1-N sequence of encounters the player team must clear in succession. Pet HP carries between encounters; team wipe ends the stage early. Stage rewards (RP) sum across encounters and credit once on stage completion.

**Added**

- **[`game/resources/encounter_resource.gd`](game/resources/encounter_resource.gd)** — `EncounterResource` schema. Each encounter is `monster_ids: Array[StringName]` (up to 3 monsters spawning simultaneously) plus an optional `narrator_line_id` for a Peniber line on encounter start.
- **[`game/resources/battle_stage_resource.gd`](game/resources/battle_stage_resource.gd)** — `BattleStageResource` schema: `id`, `display_name`, `tier`, `encounters: Array[EncounterResource]`, `narrator_stage_clear_id`, `bonus_rp_on_clear`. The view picks a stage via `ContentRegistry.default_stage_for_tier(player_tier)` — highest-tier stage the player has unlocked.
- **Two seed stages** in [`game/data/battle_stages/`](game/data/battle_stages/):
  - `wisplet_hollows.tres` (tier 1): 1 wisplet → 2 wisplets → 3 wisplets, ramping difficulty within a single stage.
  - `centiphantom_drifts.tres` (tier 2): same shape with the centiphantom roster.
- **[`ContentRegistry.battle_stages()`](game/systems/content_registry.gd) + `battle_stage(id)` + `default_stage_for_tier(tier)`** — registry now indexes `game/data/battle_stages/*.tres` alongside monsters/items/etc.

**BattleSystem refactor**

- New static `BattleSystem.simulate_stage(seed, pets, stage, rp_mult) -> StageLog`. Drives an internal `_simulate_encounter` per encounter, threading the player team's HP through so survivors retain damage between waves. Single shared RNG carries state across encounters so a tweak to encounter 1 deterministically shifts encounter 2's variance.
- `BattleSystem.simulate(...)` (single-encounter API) is preserved unchanged — refactored to call `_simulate_encounter` internally. Existing test_battle_system suite still passes 8/8.
- StageLog shape: `{stage_id, seed, winner, last_encounter_index, encounters: Array[BattleLog], rewards: {rancher_points}}`. Frame-level data is one BattleLog per encounter; UI replays them in sequence.

**BattleView state machine**

- Added `BETWEEN_ENCOUNTERS` state. Flow: `IDLE → BATTLING (encounter 0) → BETWEEN_ENCOUNTERS (0.7s pause + enemy fade-out) → BATTLING (encounter 1) → … → POST`.
- IDLE now surfaces stage info: stage name, tier, encounter count.
- `_begin_encounter(index)` spawns fresh enemy combatants for the encounter (player team persists across encounters so HP carries visually). Optional Peniber line via the encounter's `narrator_line_id`.
- `_finish_encounter_replay` decides "next encounter" vs "stage end" based on the just-finished encounter's winner. Team wipe in encounter N skips encounters N+1..end.
- `_finish_stage` credits the stage's summed RP once (not per-encounter), fires the `narrator_stage_clear_id` line on victory, emits `EventBus.battle_ended`.
- `_fast_forward_replay` extended to walk through ALL remaining encounters in one pass when the rewarded-video skip lands.

**Visual transition between encounters**

- Old enemy combatants fade out via tween before queue_free (`modulate:a → 0` over 0.2s). The despawn tween is tracked in a `_despawn_tweens` array so `_teardown_battle_map` can kill it before freeing the combatant out from under the tween's callback (avoids Godot's "lambda capture was freed" warning during scene transitions).

**Tests (252 passing, +7)**

- [`game/tests/test_battle_stage.gd`](game/tests/test_battle_stage.gd) (7 tests):
  - Same seed → identical StageLog (per-encounter frame counts match).
  - Different seeds can diverge in at least one encounter's frame count.
  - Player win emits summed RP (`rewards.rancher_points > 0`).
  - Team wipe terminates the stage early; `last_encounter_index < stage.encounters.size()`.
  - Team wipe emits no rewards.
  - Existing `simulate()` single-encounter contract unchanged (regression check).
  - StageLog echoes the source stage's id for telemetry.
- [`game/tests/test_battle_view.gd`](game/tests/test_battle_view.gd) updated:
  - `_start_battle` → `_start_stage` (renamed to reflect stage semantics).
  - The first-encounter spawn assertion accepts 1–3 enemies (was hardcoded 3 under the old single-encounter view).
  - Determinism test uses `_setup_battle_map_with_player_team()` + `_spawn_enemy_team()` mirroring the new live flow.
- Full GUT suite: **252/252 passing, ~3142 asserts, 0 failures.**

**Pre-push checklist**

- `--check-only` exits 0.
- Full GUT suite green.
- Three exports left to CI.

**Known limitations**

- Stage selection UI is implicit (`default_stage_for_tier` auto-picks). Explicit stage picker + team_select left for follow-up polish.
- Visual between-encounter motion is a fade; the camera-scroll / ground-scroll polish from POLISH_PLAN's 10e.2 description is deferred. The 0.7-second pause + enemy fade reads as "next wave coming" without needing parallax scrolling. If the camera scroll is wanted, it's a small additive tween in battle_map.

### v0.10.7 — Variant RNG bug fix + GDScript warning sweep

**Why**

User reported the long-standing "getting one pet unlocks all variants" bug was still present after the v0.10.6 fresh-save flow. Their save showed `pet_variants_owned == pets_owned == [all three wisplets]` after a single tier-1 completion — statistically impossible at `variant_rate=0.02` if the rolls were independent (P ≈ 8 × 10⁻⁶).

**Root cause**

[catching_view.gd:357–362](game/scenes/catching/catching_view.gd) created a fresh `RandomNumberGenerator` inside the per-pet awarding loop:

```gdscript
for pet in CatchingSystem.pets_to_award_for_tier(...):
    var rng_local := RandomNumberGenerator.new()
    rng_local.randomize()           # ← time-based seed
    is_variant = rng_local.randf() < pet.variant_rate
    ...
```

When the three loop iterations all execute within the same microsecond (no I/O between them, three pets per tier), `randomize()`'s time-based seed is identical for every iteration, every `randf()` returns the same value, and the pets roll variant/not-variant in lockstep. Symptom: `variant_rate=0.02` produces "all three variants" exactly 2 % of the time and "no variants" the remaining 98 %, instead of independent 0.02 chances per pet.

**Fix**

Replaced the per-iteration RNG with the catching view's existing `_rng` member (randomized once in `_ready`). Three sequential `_rng.randf()` calls produce three independent draws.

**Tests (244 passing, +3)**

- [`game/tests/test_variant_rolls.gd`](game/tests/test_variant_rolls.gd) — 3 tests:
  - With `Settings.debug_fast_pets=true`, all three wisplet variants land in `pet_variants_owned` (sanity baseline).
  - Same `_rng.seed` reproduces the same `pet_variants_owned` outcome — proves rolls go through `_rng`, which the buggy version's fresh randomized RNGs would have ignored.
  - Sweeping 50 seeds produces ≥ 2 distinct outcomes — confirms the seed actually drives variation, ruling out a regression where the loop ignores `_rng` again.

**GDScript warning sweep**

While diagnosing, the user shared the editor's startup warnings. Cleaned up all eight:

- **[`game/systems/ads_backend.gd`](game/systems/ads_backend.gd)** — `@warning_ignore("unused_signal")` on `completed`/`failed`. They're abstract-interface signals emitted by concrete subclasses.
- **[`game/systems/cloud_sync_backend.gd`](game/systems/cloud_sync_backend.gd)** — renamed unused param `state` → `_state` in the abstract `upload()`. Concrete subclasses keep `state` (the abstract default just errors).
- **[`game/scenes/catching/catching_background.gd`](game/scenes/catching/catching_background.gd)**, **[`battle_map.gd`](game/scenes/battle/battle_map.gd)**, **[`bestiary_card.gd`](game/scenes/bestiary/bestiary_card.gd)** — `@warning_ignore("integer_division")` on the three tier-band `(tier - 1) / 5` lookups. Integer division is the desired behavior (tiers 1-5 → band 0, etc.); the warning was just flagging the truncation.
- **[`bestiary_card.gd`](game/scenes/bestiary/bestiary_card.gd)** — removed unused `pet_owned` local. The card UI only needs `variant_owned` (Variant pill); base-pet ownership state isn't surfaced on the card.
- **[`game/scenes/main.gd`](game/scenes/main.gd)** — renamed local `theme` → `mobile_theme` in `_apply_mobile_default_theme()` to avoid shadowing `Control.theme` (Main extends Control, so the property is in scope).
- **[`game/scenes/main.gd`](game/scenes/main.gd)** — renamed for-iterator `name` → `nav_name` in `_set_active_nav()` to avoid shadowing `Node.name`.

Editor startup is now warning-clean.

**Pre-push checklist**

- `--check-only` exits 0.
- Full GUT suite: **244/244 passing, ~3113 asserts, 0 warnings, 0 failures.**
- Three exports left to CI.

### v0.10.6 — Wipe-save feature + pet acquisition diagnosis

**Why**

User report: "I can't get pets anymore — might be a save migration." Inspecting the live `save.json` showed `tiers_completed=[1]`, `current_max_tier=2`, no tier-2 monster catches, and `recipes_crafted=[]`. **Not a migration bug** — the player is stuck behind the v0.9.4-flagged tier-2 net craft gate: `basic_net.targets_tiers=[1]` so tier-2 monsters can't spawn (auto-catch *or* tap), and tier-2 monster catches are required to advance toward the next pet award. The unstick is to craft `recipe_tier2_net` (50 wisplet ectoplasm + 5 K gold), which the player already has materials for.

While here, the user also asked for a wipe-save feature with confirmation — useful both for testing fresh-start flows and as an emergency reset for any future save wedge.

**Added**

- **[`SaveBackend.clear()`](game/systems/save_backend.gd)** — abstract method on the storage backend interface. Phase-7 `CloudBackend` will need to wipe its remote object too.
- **[`LocalFileBackend.clear()`](game/systems/local_file_backend.gd)** — deletes `user://save.json` AND the `.tmp` from any interrupted prior write (so a re-save's atomic rename can't surface the leftover stale data). Idempotent: returns true if the save is gone after the call, regardless of whether anything was deleted.
- **[`SaveManager.clear_save()`](game/autoloads/save_manager.gd)** — coordinated wipe:
  1. `backend.clear()` — wipe disk.
  2. `GameState.from_dict({})` — reset in-memory to first-launch defaults.
  3. `SaveManager.save(GameState.to_dict())` — persist the cleared defaults so a hard quit before the next save tick can't restore the prior data via OS swap.
  4. Emit `EventBus.game_loaded` so subscribers (currency_bar, bestiary view, narrator state) refresh.
- **Reset Progress section in [`settings_view.gd`](game/scenes/ui/settings_view.gd)** — a destructive button under Cloud Save with a `BLOOD_RUBY`-tinted label, blurb, and a `ConfirmationDialog` ("Wipe save data? This will permanently erase all progress…"). The dialog gets `theme = main_theme.tres` explicitly per the v0.10.4 fix so its label + buttons paint with parchment/brass instead of the dark-gray root theme.

**Tests (241 passing, +6)**

- [`game/tests/test_save_clear.gd`](game/tests/test_save_clear.gd) (6 tests):
  - `LocalFileBackend.clear()` removes the save file.
  - `clear()` is idempotent (succeeds when there's nothing to clear).
  - `SaveManager.clear_save()` resets currencies / prestige_count / pets_owned / tiers_completed.
  - `clear_save()` persists the cleared state to disk so a hard quit doesn't restore the prior data.
  - `clear_save()` emits `EventBus.game_loaded` synchronously.
  - `clear_save()` works when there's no save on disk yet.
- Full GUT suite: **241/241 passing, 3106 asserts, 0 failures.**

**Notes**

- The pet-acquisition gate is a known limitation flagged in v0.9.4's headless simulation. Players who progress past tier 1 *must* craft the tier-2 net before they can grind toward the tier-2 pet awards. Surface UI for the gate (e.g. an empty-spawn-pool hint on the catching view) is out of scope here; future polish.

**Pre-push checklist**

- `--check-only` exits 0.
- Full GUT suite green.
- Three exports left to CI.

### v0.10.5 — Phase 10e.1: Battle map foundation

**Why**

[battle_view.gd](game/scenes/battle/battle_view.gd) shipped in Phase 2 as a stack of `ProgressBar` HP bars driven by replay frames — the math worked, but the screen didn't *feel* like a battle. Phase 10e.1 keeps the deterministic `BattleSystem` simulator unchanged and replaces the visual layer with a side-scrolling stage: pets walk in from the left, monsters from the right, exchange attack lunges synced to BattleLog frames, and fade on KO. Same seed → same visual sequence.

**Added**

- **[`game/scenes/battle/combatant.tscn`](game/scenes/battle/combatant.tscn) + [`.gd`](game/scenes/battle/combatant.gd)** — sprite controller with explicit state machine:
  - `WALK_IN` → slides at 240 px/s from off-screen toward `engagement_pos`.
  - `IDLE_AT_ENGAGEMENT` → trig bob at 1.4 Hz, 2 px amplitude. Distinct from `DEFEATED_FADE`, which is static.
  - `ATTACK_LUNGE` → tween toward target (28 px reach, 0.08 s out / 0.12 s back), then auto-returns to idle.
  - `HURT_FLASH` → HDR-style modulate flash on `apply_damage`, fades back to the per-monster tint.
  - `DEFEATED_FADE` → alpha-fade + topple rotation toward the opposing team (45 % seconds). Absorbing state — subsequent `apply_damage` / `play_attack_lunge` calls are silently ignored.
  - HP bar is a `ProgressBar` child positioned 52 px above the sprite, color-coded by team (sage green for player, blood ruby for enemy). Hidden on defeat.

- **[`game/scenes/battle/battle_map.tscn`](game/scenes/battle/battle_map.tscn) + [`.gd`](game/scenes/battle/battle_map.gd)** — Node2D root hosting the stage:
  - `ColorRect` sky with the same `mix(top, bottom, UV.y)` gradient shader as [catching_background](game/scenes/catching/catching_background.gd), so battle and catch screens read as the same world. Tier-band palette: 1–5 dawn, 6–10 cave, 11–15 dusk, 16–20 abyss.
  - Distant `Polygon2D` ridge silhouette for depth.
  - `Polygon2D` ground band + brass highlight strip at y=460.
  - `Camera2D` centered on the 720×520 viewport.
  - `Combatants` Node2D layer that battle_view spawns combatants under.
  - Public `engagement_pos(team, index)` / `start_pos(team, index)` / `facing_for_team(team)` helpers so battle_view doesn't need to know layout magic numbers.

- **Rewritten [`battle_view.gd`](game/scenes/battle/battle_view.gd)** — keeps the IDLE / BATTLING / POST state machine + speed selector + skip-ad button + reward plumbing. Replaces the HP bar stack with a `SubViewportContainer` → `SubViewport` → `BattleMap` subtree:
  - `_setup_battle_map` builds the SubViewport on `_start_battle`, spawns one combatant per team summary entry into `battle_map.combatants_layer()`, drives sky color from `current_max_tier`.
  - `_apply_replay_frame` interprets each frame as `actor.play_attack_lunge(target.position)` + `target.apply_damage(hp_remaining)`. Action log line preserved.
  - `_render_idle` tears down the SubViewport so the IDLE roster shows the original text-list preview without leaking nodes.
  - `_summarize_pets` falls back through `pet.source_monster_id → ContentRegistry.monster(...).sprite` when a pet has no sprite of its own — important because the current Phase 5 content seed only has wisplet/centiphantom art.

**Determinism preserved**

- `BattleSystem.simulate` is unchanged; the same BattleLog still drops out for the same seed + teams.
- The visual layer interprets each frame as a one-shot lunge + damage, with no time-dependent state of its own that affects subsequent frames. Two replays of the same log produce the same defeat sequence — covered by `test_two_replays_of_same_log_produce_identical_defeat_sequence`.

**Tests (235 passing, +14)**

- [`game/tests/test_combatant.gd`](game/tests/test_combatant.gd) (7 tests):
  - Initial state is `WALK_IN`; position is still off-screen at frame 1 (defends against the combatant teleporting straight to engagement).
  - Walks to engagement within 1.4 s; transitions to `IDLE_AT_ENGAGEMENT`.
  - `play_attack_lunge` flips state to `ATTACK_LUNGE`, returns to idle after the tween.
  - `apply_damage(60)` updates `hp` field and `_hp_bar.value`.
  - `apply_damage(0)` marks defeated and transitions to `DEFEATED_FADE`.
  - Defeated combatant ignores subsequent `apply_damage` and `play_attack_lunge`.
  - Facing -1 negates `_sprite.scale.x` so enemies render mirrored.

- [`game/tests/test_battle_view.gd`](game/tests/test_battle_view.gd) (7 tests):
  - Fight button disabled when no pets owned; enabled with a pet.
  - `_start_battle` spawns one combatant per team summary entry, instantiates `_battle_map`.
  - Player team faces +1, enemy team faces -1.
  - **Determinism contract:** two BattleViews fed identical BattleLog frames produce the same combatant defeat sequence (target ids in frame order, deduped).
  - `_fast_forward_replay` transitions to POST.
  - `_render_idle` tears down `_battle_map` and clears combatant arrays.

- Full GUT suite: **235/235 passing, ~3088 asserts, 0 failures.**

**Pre-push checklist**

- `--check-only` exits 0.
- Full GUT suite green.
- Three exports left to CI.

**Known limitations / scope guard**

- 10e.1 is the foundation. Phase 10e.2 (multi-encounter stages, team selection, stage rewards) is a separate milestone — combatant + battle_map already support multiple sequential calls but the view still treats one battle = one encounter.
- Sprite art is still the Phase 5 placeholder set (wisplet / centiphantom recolors). Tier-3+ pets fall through to their source-monster sprite, which means several of the late-tier "pets" visually look like the wisplet line. This is intentional per the polish-plan asset-gap warning; commissioned art is out of scope.

### v0.10.4 — Theme fixes for popups + RichTextLabel default color

**Why**

Two visual issues surfaced after Phase 10a–10d shipped, both rooted in the same gap:

1. **More menu showed teal-green button outlines** that didn't match the rest of the parchment/brass UI.
2. **Peniber's dialog bubble was unreadable** — pale text on the parchment background with the new bubble fill.

**Root cause**

- `PopupPanel`, `AcceptDialog`, and other `Popup`-family nodes are `Window` subtypes in Godot 4. **Window subtrees do not inherit theme from their parent Control's theme cascade.** They read from `get_tree().root.theme`, which `_apply_mobile_default_theme()` overrides at startup with a v0.8.3 dark-gray mobile theme. So popups have always lived in their own visual world; before Phase 10a the rest of the UI matched that world, so it didn't show. After Phase 10a the rest of the UI is parchment, and the popup mismatch became visible.
- `Label/colors/font_color` does NOT cascade to `RichTextLabel`. RichTextLabel reads `RichTextLabel/colors/default_color`, which my Phase 10a theme didn't set — so RichTextLabels were rendering Godot's default white text. The narrator overlay's bubble has a parchment fill, so white-on-parchment was nearly invisible.

**Fixed**

- **[`game/resources/main_theme.tres`](game/resources/main_theme.tres)** — added `RichTextLabel/colors/default_color = INK_BLACK` and `RichTextLabel/font_sizes/normal_font_size = 16`. Five RichTextLabel uses (narrator_overlay, prestige_view summary, crafting_view recipes, welcome_back_dialog body, plus the Phase 10d card detail) now render with sepia text on parchment.
- **[`game/scenes/main.gd`](game/scenes/main.gd)** `_build_more_popup` — assign `theme = main_theme.tres` to the More popup at construction time so its buttons paint with the parchment/brass styleboxes instead of inheriting the dark-gray root theme.
- **[`game/scenes/bestiary/bestiary_card_detail.gd`](game/scenes/bestiary/bestiary_card_detail.gd)** `_ready` — same treatment for the Phase 10d bestiary detail modal.
- **[`game/scenes/ui/welcome_back_dialog.gd`](game/scenes/ui/welcome_back_dialog.gd)** `_ready` — same for the welcome-back AcceptDialog. This was already broken before 10a (white-on-dark instead of white-on-parchment), but now visually consistent with the rest of the UI.

**Tests (221 passing, no count change)**

- Pure stylistic plumbing change; existing test suite catches structural regressions and stays green.
- Full GUT suite: 221/221 passing, 3060 asserts.

**Pre-push checklist**

- `--check-only` exits 0.
- Full GUT suite green.
- Three exports left to CI.

### v0.10.3 — Phase 10d: Bestiary cards

**Why**

[bestiary_view.tscn](game/scenes/bestiary/bestiary_view.tscn) shipped in Phase 4 as a `VBoxContainer` of inline panels — readable but not browseable. Phase 10d converts it into a Pokédex-style grid of `bestiary_card` instances with a four-state slot machine (LOCKED → SEEN → CAPTURED → PERFECTED), tier-banded ribbons, ShaderMaterial silhouettes for unseen species, and a tappable detail modal.

**Added**

- **[`game/scenes/bestiary/bestiary_card.tscn`](game/scenes/bestiary/bestiary_card.tscn) + [`.gd`](game/scenes/bestiary/bestiary_card.gd)** — reusable card component:
  - Themed `PanelContainer` (clip_contents=true) with a 6 px tier-band ribbon at top: tiers 1–5 brass, 6–10 silver, 11–15 gold, 16–20 obsidian.
  - Sprite cell that flips between a normal-tinted `TextureRect` (seen) and a silhouette `ShaderMaterial` over the same texture (locked). Shader samples the source alpha and outputs near-black RGB, so silhouettes work on top of the existing recolor placeholders without per-species art.
  - Name / count / four pill row (Seen ◇ · Normal ✦ · Shiny ✧ · Variant ⬢) summarising completion at a glance.
  - **Perfected state** (all four slots filled) overrides the panel's `StyleBoxFlat` per-card to paint a brass border — change is local, doesn't leak back to the theme.
  - Public `slot_state()` returning the LOCKED/SEEN/CAPTURED/PERFECTED enum so tests can inspect the state machine without scraping label text.
  - `_gui_input` emits a `card_tapped(monster_id)` signal on left-click or touch.

- **[`game/scenes/bestiary/bestiary_card_detail.tscn`](game/scenes/bestiary/bestiary_card_detail.tscn) + [`.gd`](game/scenes/bestiary/bestiary_card_detail.gd)** — `PopupPanel` that opens on card tap:
  - Big sprite at 4× display scale (or silhouette for locked species).
  - Name + tier header.
  - Flavor text (autowrapped).
  - Stats block: catches, shinies, drop info, pet status (locked / owned / variant).
  - Best-effort hook for Peniber's first-catch quote — no-ops cleanly when the Narrator doesn't expose `first_catch_line_for(monster_id)`. Future Narrator API can light it up without changing the modal.
  - Close button + tap-outside-to-dismiss via `exclusive = true`.

- **Rewritten [bestiary_view.gd](game/scenes/bestiary/bestiary_view.gd)** — `GridContainer` of cards instead of `VBoxContainer` of inline panels:
  - Column count adapts to viewport width: 1 col under 480 px, 2 cols 480–900, 4 cols above 900. The bestiary view's `resized` signal re-applies on rotation / window resize.
  - One card per registered monster, sorted by tier then id (matching the prior view's order).
  - Catch-related EventBus signals call `card.refresh()` in place; only `game_loaded` triggers a full rebuild (the registry might have shifted).
  - Single shared `bestiary_card_detail` instance kept as a child; `popup_centered` opens it for the tapped card. Closing it preserves the underlying scroll position because PopupPanel is a sibling, not a router.

**Backwards-compat**

- `_list` is still the cards-container member name (now `GridContainer` instead of `VBoxContainer`); the existing test suite reads it by that name. Tests updated for the new layout (pairwise `Rect2.intersects` overlap check; silhouette ShaderMaterial check replacing the prior "?" Label assertion).

**Tests (221 passing, +9)**

- [`game/tests/test_bestiary_card.gd`](game/tests/test_bestiary_card.gd) (8 tests):
  - LOCKED state when monster is unseen.
  - CAPTURED on first catch (verifying the state machine doesn't loop through SEEN as an intermediate).
  - PERFECTED after normal + shiny + variant pet are all owned.
  - Locked card paints a `ShaderMaterial` silhouette on the sprite.
  - Seen card clears the silhouette material.
  - Tier-band ribbon colors differ between bands (skipped gracefully if the content seed has no tier-6+ monsters).
  - Perfected card overrides the panel `StyleBoxFlat`; locked card does not.
  - `card_tapped` signal fires with the right monster id on click — using an Array capture because GDScript 4 lambdas capture outer locals by value.

- [`game/tests/test_bestiary_view.gd`](game/tests/test_bestiary_view.gd) updated:
  - Replaced "expect a `?` placeholder Label" with "expect at least one TextureRect carrying a ShaderMaterial silhouette".
  - Replaced the y-position non-overlap invariant with a pairwise `Rect2.intersects` check that's correct for any layout (the GridContainer breaks the old single-column assumption).
  - All other assertions (card count, name swap, count display, clip_contents) preserved.

- Full GUT suite: **221/221 passing, 3060 asserts, 0 failures.** Assert count jumped because the new pairwise non-overlap test does ~1770 pairs across the full registry.

**Pre-push checklist**

- `--check-only` exits 0.
- Full GUT suite green.
- Three exports left to CI.

### v0.10.2 — Phase 10c: Currency bar redesign

**Why**

[currency_bar.tscn](game/scenes/ui/currency_bar.tscn) shipped in Phase 1 as two color-tinted Labels in an HBox. After Phase 10a's theme pass it was the most prominent piece of vestigial UI on the screen — a thin strip with no weight. Phase 10c replaces it with three themed chips that surface gold / rancher points / prestige as legible cards, and adds tweened number changes so a currency gain feels like an event rather than a repaint.

**Added**

- **[`game/scenes/ui/currency_chip.tscn`](game/scenes/ui/currency_chip.tscn) + [`.gd`](game/scenes/ui/currency_chip.gd)** — reusable single-currency display:
  - Themed `PanelContainer` (parchment fill, brass border via the Phase 10a theme).
  - 4 px brass accent stripe along the left edge — keys each chip to its currency without fighting the theme.
  - 32 px icon + value Label + an optional next-milestone `ProgressBar`.
  - Two value flavors: `set_int_value(value, animate=true, duration=0.4)` and `set_big_value(value, animate=true, duration=0.4)`. Both tween via Cubic-EaseOut; BigNumbers are interpolated through `from + (to - from) * t` using BigNumber.subtract / multiply_float / add.
  - First-paint guards: BigNumber chip with no prior value snaps instead of tweening from null. Bar asks for `animate=false` on its initial `_refresh_all` so a saved game's gold doesn't run a 0 → loaded jackpot at startup.
  - `set_progress_fraction(-1)` hides the bar; range `[0..1]` clamps and reveals.
- **Rewritten [currency_bar.gd](game/scenes/ui/currency_bar.gd)** — composes three chips:
  - **Gold** — always visible. Brass accent. ProgressBar tracks progress through the current decade (`(mantissa - 1.0) / 9.0`). Tooltip shows `mantissa × 10^exponent  (formatted)`.
  - **Rancher Points** — hidden until `current_rancher_points() > 0` for the first time, then sticky.
  - **Prestige** — hidden until `prestige_count > 0`, then sticky.
  - `_exit_tree` disconnects from `EventBus.currency_changed`, `prestige_triggered`, and `game_loaded` so re-instantiating the bar (test suites, scene swaps) doesn't accumulate ghost connections.
- **Long-press / hover tooltips** — chips set `tooltip_text` so Godot's auto-tooltip fires on mouse hover and on Android touch-and-hold. Gold tooltip exposes the underlying BigNumber breakdown (`1.234 × 10^5  (123.4K)`); RP and Prestige tooltips give plain-English context.

**Tests (212 passing, +15)**

- [`game/tests/test_currency_chip.gd`](game/tests/test_currency_chip.gd) (7 tests):
  - Snap behaviour with `animate=false`.
  - Mid-tween sample for int values; final-value landing after the tween window.
  - First-paint snap for BigNumber values.
  - Final-value landing after BigNumber tween.
  - Progress bar visibility toggling on negative / clamped fractions.
  - `configure()` re-applies label prefix on a live chip.
- [`game/tests/test_currency_bar.gd`](game/tests/test_currency_bar.gd) (8 tests):
  - All three chips present.
  - Gold chip always visible.
  - RP / Prestige chips hidden at zero, surface after the relevant EventBus signal.
  - Progress bar tracks gold's mantissa-within-decade.
  - **Signal-leak regression test:** instantiate-and-destroy the bar three times; the `EventBus.currency_changed` connection count must return to its initial value, catching the easy-to-introduce bug where a re-mounted bar accumulates ghost handlers.
- Full GUT suite: **212/212 passing, 1328 asserts, 0 failures.**

**Pre-push checklist**

- `--check-only` exits 0.
- Full GUT suite green.
- Three exports left to CI.

### v0.10.1 — Phase 10b: Catching screen visuals & tap juice

**Why**

The most-used screen in the game (Catching) was a flat default-gray Control with monsters wandering on top. After 10a's theme pass the rest of the UI looks intentional, which made the catch screen's lack of background especially visible. Phase 10b gives it depth (parallax background) and amplifies the existing tap feedback (white-flash on catch, miss-tap ripple, Android haptic).

**Added**

- **[`game/scenes/catching/catching_background.tscn`](game/scenes/catching/catching_background.tscn) + [`.gd`](game/scenes/catching/catching_background.gd)** — `ParallaxBackground` (CanvasLayer at `layer = -2`) with three layers:
  - Sky: full-coverage `ColorRect` driven by a procedural ShaderMaterial (`mix(top_color, bottom_color, UV.y)`). Two color uniforms switch by tier band:
    - Tiers 1–5: dawn (parchment-pink → vellum)
    - Tiers 6–10: cave (dim sepia → deep brown)
    - Tiers 11–15: dusk (purple-brass → parchment)
    - Tiers 16–20: abyss (near-black → deep ruby)
  - Mid silhouette: jagged-ridge `Polygon2D` at `motion_scale=0.3` with `motion_mirroring=1500px` for seamless tiling.
  - Near ground: rolling-hill `Polygon2D` at `motion_scale=0.7`.
  - Slow ambient horizontal scroll (`6 px/s`) so the world feels alive even when no monsters are on screen.
  - Listens to [EventBus.tier_unlocked](game/autoloads/event_bus.gd) to repaint the sky.
- **White-flash on catch.** [monster_instance.gd](game/scenes/catching/monster_instance.gd) `play_catch_and_despawn` now runs a brief HDR-style modulate flash (Color(2.4, 2.4, 2.4) over 0.05s) BEFORE the existing scale + alpha despawn tween. Stacks on the catch particles already there.
- **Miss-tap ripple + soft SFX.** [catching_view.gd](game/scenes/catching/catching_view.gd) `_gui_input` now spawns a 14-particle parchment ripple at the tap location and calls `AudioManager.play_miss_tap_sfx()` when a tap registers but doesn't hit a monster. Confirms the tap was received without granting reward.
- **Android haptic.** Catching view `_on_monster_tapped` calls `Input.vibrate_handheld(40)` gated on `OS.has_feature("mobile")` so desktop builds skip the call entirely.
- **AudioManager miss-tap player.** [audio_manager.gd](game/autoloads/audio_manager.gd) — new `_miss_tap_player` (same source WAV, `volume_db = sfx_db - 8.0`, pitch 1.3) and `play_miss_tap_sfx()`. Self-throttling: re-entrant calls during an active play() are no-ops so rapid mistapping doesn't machine-gun.

**Architecture notes**

- Catching view's existing scale-punch on tap (`monster_instance._play_tap_bump`, 1.18× over 0.06+0.10s) was kept — it already shipped in Phase 5. Phase 10b is purely additive on top.
- Background owns its scroll loop in `_process` rather than depending on a Camera2D — there is no camera in the catch view, and `motion_mirroring` handles the visual wrap as `scroll_offset.x` advances monotonically.
- Tier palette is stored as constant arrays of (top, bottom) Colors indexed by `(current_max_tier - 1) / 5`. Adding a tier band is one constant edit each.

**Tests (197 passing, +7)**

- [`game/tests/test_catching_background.gd`](game/tests/test_catching_background.gd) (4 tests): scene structure (3 ParallaxLayers, layer=-2), Sky has ShaderMaterial, tier-palette swap mutates shader uniforms, ambient scroll advances `scroll_offset.x` within 0.4s.
- [`game/tests/test_catch_flash.gd`](game/tests/test_catch_flash.gd) (3 tests): modulate brightens past tint at some point during the flash window (frame-polled to dodge headless tween-timing flakiness — see [v0.8.2](#v082-sprite-animation-polish-save-robustness) precedent), instance `queue_free`s within 0.4s of catch, 10 successive catches don't leak nodes.
- Full GUT suite: **197/197 passing, 1304 asserts, 0 failures.**

**Pre-push checklist**

- `--check-only` exits 0.
- Full GUT suite green.
- Three exports left to CI.

### v0.10.0 — Phase 10a: Theme & font foundation

**Why**

Audit of the UI layer found zero `ColorRect` / `StyleBoxFlat` use across any `.tscn`, no theme resource checked in, and the game shipping on Godot's default dark-gray theme. Phase 10a is the foundation for the rest of the polish pass ([POLISH_PLAN.md](POLISH_PLAN.md) covers items #1–#7): a Theme + fonts at the root scene that every subsequent phase builds on.

**Added**

- **[`game/resources/main_theme.tres`](game/resources/main_theme.tres)** — new Theme resource applied at [main.tscn](game/scenes/main.tscn) root. Parchment palette with brass accents:
  - StyleBoxFlat for `Button` (normal / hover / pressed / disabled / focus), `PanelContainer/panel`, `PopupPanel/panel`, `LineEdit` (normal / focus), and `ProgressBar` (background / fill).
  - Default font + sepia text color set at theme level so unstyled Labels pick them up automatically.
  - `Heading` and `Subhead` theme-type entries that route to the display face — scenes opt in via `theme_type_variation = "Heading"` or by reading `get_font("font", "Heading")` directly.
- **[`game/resources/palette_colors.gd`](game/resources/palette_colors.gd)** — `class_name PaletteColors` with named Color constants (`PARCHMENT`, `SEPIA_DARK`, `BRASS_ACCENT`, `BLOOD_RUBY`, etc.). For the cases where scenes need a Color literal that doesn't go through Theme.
- **[`assets/fonts/peniber_body.ttf`](assets/fonts/peniber_body.ttf)** — EB Garamond variable font, OFL-licensed.
- **[`assets/fonts/peniber_display.ttf`](assets/fonts/peniber_display.ttf)** — Cinzel variable font, OFL-licensed. Used for headings and Peniber's overlay.
- OFL license texts (`EBGaramond-OFL.txt`, `Cinzel-OFL.txt`) and an [`assets/fonts/README.md`](assets/fonts/README.md) explaining replacement.
- **Background ColorRect** in [main.tscn](game/scenes/main.tscn) — a vellum-toned base layer behind all panels so the engine clear-color never shows through. `mouse_filter = MOUSE_FILTER_IGNORE` so it doesn't eat input.
- **Currency icon placeholders** at [`assets/sprites/icons/`](assets/sprites/icons/) (`coin.png`, `rancher_point.png`, `prestige.png`) — 64×64 PNGs generated by [`scripts/generate_placeholder_icons.py`](scripts/generate_placeholder_icons.py). Brass/blue/ruby discs with G/R/P glyphs. Re-running the script overwrites in place; replacing with final art is a same-filename, same-size swap. Used by Phase 10c.

**Scope guard (intentional)**

Phase 10a is cosmetic-only: StyleBoxes, colors, base font. The ~80 inline `add_theme_*_override` calls scattered across ~15 scripts are **kept** as semantic emphasis on top of the theme. Removing them risks layout regressions inside what should be a pure foundation phase; deferred to a follow-up sub-phase if needed. Result: existing layouts visually upgrade automatically wherever they hit theme defaults, while bespoke font sizes (e.g. catching view's currency labels) continue to look identical.

**Tests (190 passing, +9 from theme suite)**

- New [`game/tests/test_theme.gd`](game/tests/test_theme.gd) (9 tests):
  - Theme resource loads cleanly.
  - Default font + size is set and within sane bounds.
  - All four `Button` state styleboxes resolve as `StyleBoxFlat`.
  - `PanelContainer/panel` and `ProgressBar` background/fill resolve.
  - `Heading` variation defines a display font, larger size than body, and differs from `default_font`.
  - `Subhead` variation defines a font + size, smaller than `Heading`.
  - [`main.tscn`](game/scenes/main.tscn) root has the theme assigned via `resource_path` match.
  - `PaletteColors` constants are typed `Color`.

**Pre-push checklist**

- `--check-only` exits 0.
- Full GUT suite: 190 passing / 0 failing / 1280 asserts.
- Three exports not run locally (CI will; this iteration didn't change export-path code).

### v0.9.4 — Difficulty curve QA via headless simulation

**Why**

Manual playtesting can't surface a 3-day stall on tier 13 — by the time you hit it you've forgotten what the sprint from tier 6→9 felt like. v0.9.4 adds a deterministic, headless Godot simulator that fast-forwards a model player through tier 1-20 over a configurable real-time horizon, reusing the live game's `OfflineProgressSystem` / `CatchingSystem` / `UpgradeEffectsSystem` / `PrestigeSystem` so the sim can't drift from the live balance numbers in `game/data/`.

**Added**

- **[`tests/sim/sim_runner.tscn`](tests/sim/sim_runner.tscn) + [`sim_runner.gd`](tests/sim/sim_runner.gd)**. Standalone headless scene; run with `godot --headless --path . res://tests/sim/sim_runner.tscn -- --seed=N --hours=N --tick=N`. Outputs:
  - [`tests/sim/output/difficulty_curve.csv`](tests/sim/output/difficulty_curve.csv) — every milestone event (first-catch, tier-complete, net-crafted, upgrade-purchased, prestige) with timestamp, gold, RP, total catches, max tier, prestige count, active net.
  - [`tests/sim/output/difficulty_curve.md`](tests/sim/output/difficulty_curve.md) — human-readable report: tier-completion timeline with wall/sprint flags, prestige timeline, net-acquisition timeline, methodology, stall diagnosis (when triggered).
- **[`tests/sim/README.md`](tests/sim/README.md)** documents the AI policy, limitations, and how to use the sim for regression diffs after balance edits.
- **Stall detection.** If 24 sim-hours pass with no progression event, the sim terminates early and emits a structured diagnosis explaining the next net the AI tried to craft, what's missing, and what tier each input drops from.

**AI policy**

Greedy each tick: equip best owned net for `current_max_tier`; craft next net up the chain when gold + items + prereqs all clear; buy cheapest affordable upgrade. Prestige is *patient* — only when `current_max_tier ≥ 8 AND projected_rp ≥ max(20, 2× current_rp)`. The patient gate avoids a local minimum where a fully-greedy AI cycles tier 1-4 forever (each prestige resets nets, the threshold is met immediately again, RP never compounds). `prestige_starting_net` is skipped because the sim re-equips `basic_net` post-prestige regardless.

**Findings (seed 42, 14-day horizon)**

- **Tier 3 → tier 4 is a hard wall.** The first sim run **stalls at t=31.8h** with the player permanently stuck. Diagnosis from [the report](tests/sim/output/difficulty_curve.md): `recipe_wraith_net` requires 50 `wraith_cinder` (tier-4-only drop) but `wraith_net` is the **only** net that targets tier 4. Circular dependency: the only net for tier T requires drops from tier T monsters, but tier T monsters only spawn when a net targets tier T. Tap-grinding does NOT bypass this — `CatchingSystem.pick_spawn` filters by `net.targets_tiers` for both auto-catch and tap spawns ([catching_view.gd:154](game/scenes/catching/catching_view.gd:154)).
- **Auto-catch speed has no upgrade.** All the `catch_speed_1` purchases the AI logs feed `tap_speed`, not `auto_speed`. Auto-catch rate is a function of `net.catches_per_second` only — which means there's no in-tier way to speed up idle play. Possibly intentional, but worth confirming.
- **Tier 1 → 2 → 3 is well-paced.** Tier 1 completes in ~3 minutes (3 wisplet species, 25 catches each), tier 2 at 5.2h (after crafting tier2_net), tier 3 at 7.7h (after crafting tier3_net). Smooth ramp; no walls or sprints in the early curve.

The fix for the tier-3→4 wall is a separate balance task — the headline path is overlapping `tier3_net.targets_tiers` to include tier 4, or adding cross-tier drops. The simulator is committed so future balance edits can be regression-checked by diffing the output report.

**Limitations**

- **Auto-catch only.** Tap-grinding isn't modeled. Doesn't matter for tiers past ~3 (where catch difficulty makes tap progress negligible) but the player is handed `basic_net` for free at sim start to skip the bootstrap.
- **No battles.** Battle RP is a separate income stream the sim under-reports.
- **Player AI is one fixed policy.** A real human's prestige intuition varies; the patient-gate heuristic is a baseline, not the only valid policy.

**Tests (181 passing, no count change)**

The sim is invoked manually for QA, not in CI. GUT suites are unaffected.

### v0.9.3 — Debug number-key shortcut + restored Maestro coverage

**Why**

Phase 9's Maestro flow inventory regressed when v0.9.0 moved Settings (and
five other destinations) into the More sheet. Coordinate taps inside a
Godot popup are calibration-fragile across emulator resolutions, and
`swipe` on the TabContainer's tab bar doesn't reliably scroll in the
emulator (see the v0.8.x flow that timed out and got removed). Without a
deterministic way to land on trailing tabs, the v0.8.3-class
"Settings clipped off bottom" bug class lost its regression net.

**Added**

- **Number-key debug shortcuts in [`main.gd`](game/scenes/main.gd) `_unhandled_input`**. Keys `1`–`9` and `0` jump the TabContainer to indices 0–9 directly: `1`→Catch, `2`→Battle, `3`→Inventory, `4`→Bestiary, `5`→Crafting, `6`→Ledger, `7`→Shop, `8`→Upgrades, `9`→Prestige, `0`→Settings. Gated by `OS.is_debug_build()` so production-exported APKs ignore them; editor and debug-exported builds (the kind the Maestro CI flow installs) honor them.

- **[`tests/maestro/06_more_sheet.yaml`](tests/maestro/06_more_sheet.yaml)**. Taps the More button (rightmost in the v0.9.0 bottom nav, ~`90%, 95%`), screenshots the open popup, taps the first secondary destination (Shop) at `50%, 80%`, screenshots the resulting view. Catches: More popup handler unwired, popup renders empty, secondary-destination tap doesn't switch tabs.

- **[`tests/maestro/07_settings_scrollable.yaml`](tests/maestro/07_settings_scrollable.yaml)**. Uses `pressKey: 0` (the new debug shortcut) to land on Settings without coordinate-tap dependencies, then `scroll`s and screenshots before/after. Catches the v0.8.3-class regression where Settings' VBoxContainer wasn't wrapped in a ScrollContainer and the Cloud Save section clipped off shorter screens.

**Documentation**

- [`tests/maestro/README.md`](tests/maestro/README.md): two new flow rows in the inventory table, plus a "Debug number-key shortcut" section with the full key→tab mapping so future flow authors know the pattern is available.

**Tests (181 passing, no count change)**

GUT suites unaffected; the changes are runtime-only behavior gated on debug builds.

### v0.9.2 — Dialogue corpus expansion 71 → 150 lines

**Added**

Phase 5c follow-up. Brings the Peniber dialogue corpus from 71 to **150 lines**, hitting the parent plan's §8 target. Voice held to the Victorian-under-secretary register documented in [`docs/peniber-voice.md`](docs/peniber-voice.md): verbose, condescending, archaic, begrudging, secretly invested.

Distribution of the 76 new lines:

| Category | New | After | Notes |
|---|---|---|---|
| Tier 4–20 first-catch | +20 | 29 / 60 species | Tier 4 lead species (`dross_wraith`, `agate_golem`, `ripple_surge`, …, `aether_nadir`) get a one-shot line each; three tiers get a second species line where the lead drew an especially strong response (`scoria_wraith`, `geode_golem`, `eon_nadir`). |
| `on_battle_loss` pool | +8 | 13 | More variety on the trigger that fires most after a real losing streak. |
| `on_battle_win` pool | +5 | 8 | |
| `on_idle_too_long` pool | +8 | 13 | Idle-nag is the second-most-fired pool after a long session. |
| `on_ledger_opened` pool | +5 | 10 | |
| `on_offline_return_short` pool | +4 | 7 | |
| `on_offline_return_long` pool | +4 | 7 | |
| `on_pet_acquired` pool | +5 | 8 | |
| `on_prestige` pool | +5 | 8 | |
| `on_shiny` pool | +4 | 8 | |
| Late-game milestones | +2 | 6 | New: `on_milestone_100000`, `on_milestone_1000000`. |
| Prestige milestones | +3 | 3 | New: `on_5_prestiges`, `on_10_prestiges`, `on_25_prestiges`. |
| Per-recipe first-craft | +3 | 4 | New: `on_first_craft_recipe_tier2_net`, `..._pet_collar`, `..._shiny_lure`. |

**Generator**

Lines added via [`scripts/generate_dialogue_v092.sh`](scripts/generate_dialogue_v092.sh) — idempotent bash wrapper around a `write_line` shell function that templates the same `[gd_resource]` shape Phase 5a used. Re-running the script overwrites cleanly so iterations on text don't require manual file editing.

**Tests (181 passing, no count change)**

- `test_narrator.test_recent_window_suppresses_repeats_for_pool` already counts pool sizes dynamically, so the wider pools (e.g. `on_battle_loss` going from 5 → 13) flow through without test changes.
- The new triggers (`on_milestone_100000`, `on_5_prestiges`, etc.) need code-side wiring in `Narrator.maybe_speak()` callsites before they actually fire — that's a follow-up item, not a v0.9.2 ask. The lines are now in the corpus and will start playing as soon as the corresponding events emit.

### v0.9.1 — Nav polish: button icons + custom More sheet

**Added**
- **Emoji icons on every nav destination.** Bottom-nav primary buttons now read `🐾 Catch`, `⚔ Battle`, `📦 Inventory`, `⬆ Upgrades`, `☰ More`. Secondary destinations in the More sheet get matching glyphs (`🛒 Shop`, `🛠 Crafting`, `📖 Bestiary`, `✨ Prestige`, `📊 Ledger`, `⚙ Settings`). Emoji rather than vector/raster icons because they need zero asset-pipeline work and render reliably across Android system fonts. The icon mapping lives in [`main.gd`](game/scenes/main.gd) `_NAV_ICONS` and is shared between the bottom nav and the More popup so they stay in sync.

**Changed**
- **Custom More sheet replaces system PopupMenu.** The v0.9.0 default `PopupMenu` used Godot's small-text styling — a visual mismatch with the 18 sp / 64 dp Material-style bottom nav. v0.9.1 builds a `PopupPanel` with a margin-padded `VBoxContainer` of `Button`s, each 64 dp tall and styled identically to the bottom-nav primaries (left-aligned, the same icon + text pattern). The popup positions itself as a bottom sheet — anchored just above the More button, full-width minus a small lateral inset. Built lazily on first open and cached for subsequent opens.

**Tests (181 passing, no change)**
- `test_more_button_exists_alongside_primaries` updated to assert the label *contains* "More" rather than equaling it exactly (label now reads `☰  More` with the icon prepended).

### Phase 9 — Bottom navigation restructure (v0.9.0)

**Why**

The original 10-tab top bar fought basic mobile-game ergonomics. Material 3
recommends 3–5 primary destinations in a bottom nav (thumb zone) with the
rest in a "More" sheet — and that's the pattern most successful idle/clicker
games (Egg Inc, Almost a Hero, etc.) actually ship. The Galaxy Z Fold7
foldable testing further reinforced the case: the top tab bar was both
hard to reach with one thumb and hard to scroll horizontally. v0.8.8
fixed the actual tap-blocker bug; v0.9.0 puts the navigation where Android
players' thumbs already live.

**Changed**

- **Bottom navigation bar.** Built in [main.gd](game/scenes/main.gd)'s new
  `_build_bottom_nav(root_vbox)`. Five buttons, each `64 dp` tall (above
  Material's 48 dp accessibility floor), `SIZE_EXPAND_FILL` horizontally
  so the row evenly spans the device width. Buttons stay visible on every
  screen, anchored at the bottom of the root VBoxContainer below the
  TabContainer's content area.
- **Primary destinations** (left → right): **Catch**, **Battle**,
  **Inventory**, **Upgrades**, **More**. Catch is the default selection
  on first launch. The first four use `toggle_mode = true`; the active
  one shows the v0.8.3 mobile theme's pressed stylebox so the player
  always knows where they are at a glance.
- **More sheet.** Tapping More opens a `PopupMenu` listing the six
  secondary destinations: **Shop**, **Crafting**, **Bestiary**,
  **Prestige**, **Ledger**, **Settings** (frequency-ordered). Selecting
  any item navigates the TabContainer's `current_tab` to it and dismisses
  the popup. While a secondary destination is active, no primary button
  is highlighted — visual cue that the player has stepped outside the
  primary loop.
- **TabContainer's tab bar hidden** (`tabs.tabs_visible = false`). The
  TabContainer still owns content visibility / per-tab scenes — the bottom
  nav just drives `current_tab`. Means every existing tab scene wires up
  unchanged.
- **`SaveIndicatorOverlay` re-anchored** to sit ~8 px above the new nav
  bar (`offset_top = -96, offset_bottom = -72`) so the "Saved HH:MM:SS"
  toast doesn't overlap the nav buttons.

**Removed**

- `_apply_mobile_tab_theme(tabs)` — was styling the (now-hidden)
  TabContainer tab bar. Dead code.

**Tests (181 passing, +7)**

[`test_bottom_nav.gd`](game/tests/test_bottom_nav.gd):
- Tab bar is hidden.
- Each `_PRIMARY_NAV` destination has a corresponding bottom-nav Button.
- The More button exists and reads `"More"`.
- `_navigate_to_tab(name)` switches the TabContainer's `current_tab` to
  the right index for every primary destination.
- Only the active primary button is `button_pressed = true`; the others
  are unpressed.
- Navigating to a SECONDARY destination unpresses every primary button.
- `_PRIMARY_NAV + _SECONDARY_NAV` covers every TabContainer tab —
  catches anyone adding a new tab and forgetting to wire it into the nav.

**Backlog for v0.9.x**

- Icons next to each nav button label (currently text-only).
- Polish for the More popup: a custom `PopupPanel` with bigger touch
  targets instead of the system `PopupMenu` (which uses Godot's default
  small-text styling).
- Animated transition when switching tabs (currently instant via
  TabContainer.current_tab).

### v0.8.8 — Actual root cause: overlays' child Controls were eating taps

**Investigation**

User reported the buttons-hard-to-press symptom **also reproduces in the Godot
editor** — meaning v0.8.5 / v0.8.7's stretch/aspect changes were chasing an
Android-specific input bug that wasn't actually the issue. The real root
cause was in our own GDScript overlay code, present on every platform.

**Root cause**

Each of the four overlay scenes (`AdDiagnosticOverlay`, `SaveIndicatorOverlay`,
`TouchDebugOverlay`, `NarratorOverlay`) sets `mouse_filter = MOUSE_FILTER_IGNORE`
on its **wrapper** `Control`. But every child Control inside (the
`PanelContainer` bubble, `MarginContainer`, `Label`, `RichTextLabel`,
`VBoxContainer`) defaults to `MOUSE_FILTER_STOP`. Each child silently consumes
taps that fall in its own rect, **even when the wrapper is fully transparent**.

The visible consequence:
- `AdDiagnosticOverlay` is anchored top-wide (y=64–116). Its inner Label/Margins
  blocked taps on the **tab bar** in that strip — the user's "tap on Inventory
  doesn't register" report. ([screenshot reference from v0.8.6 thread.](https://github.com/NickSanft/IdleBeastPractices))
- `SaveIndicatorOverlay` is anchored bottom-right with `offset_left = -180`.
  Its Label blocked taps on `CatchingView`'s **drops-2× ad button**.
- `NarratorOverlay`'s bubble was set `STOP` permanently in `_ready`, so the
  invisible (alpha=0) bubble at the bottom of the screen blocked taps on
  `BattleView`'s **Skip-ad row** and `CatchingView`'s drops-2× button — even
  when no narrator line was showing.
- `TouchDebugOverlay`'s info label blocked a small upper-left strip.

**Fixed**

- All four overlays now set `mouse_filter = MOUSE_FILTER_IGNORE` explicitly on
  every child `Control` (`PanelContainer`, `MarginContainer`, `VBoxContainer`,
  `Label`, `RichTextLabel`).
- `NarratorOverlay`'s bubble is gated by visibility: starts `IGNORE`, flips
  to `STOP` inside `_show()` so a tap dismisses an active bubble, flips
  back to `IGNORE` once `_hide()`'s fade-out tween completes.

**Regression test (174 passing, +5)**

- `test_overlay_mouse_filter.gd`: instantiates each overlay, walks every
  Control descendant via the scene tree, asserts `mouse_filter` is `IGNORE`.
  Catches anyone (me) re-introducing the same bug class on a future overlay.
- The `narrator_overlay_active` variant verifies the bubble flips to `STOP`
  while a narrator line is visible (so the dismiss-tap path still works).

**Why we didn't catch this earlier**

- Headless GUT runs of the scenes succeeded — they don't fire input.
- The 4 added overlays were all introduced *after* the catch loop's main UI,
  spread across v0.7.1 (ad diagnostic), v0.8.2 (save indicator), v0.8.5
  (touch debug). Each by itself was a small patch; the cumulative effect of
  4 invisible-to-visual but hit-test-active strips overlapping the gameplay
  UI wasn't obvious from any single review.
- The Galaxy Z Fold7 testing accidentally led down the canvas_items input
  rabbit hole, with v0.8.5's `aspect="keep"` introducing a *separate* bug
  (the letterbox offset) that masked the real issue.

### v0.8.7 — Letterbox-induced input offset fixed (aspect: keep → keep_width)

**Root cause confirmed via the v0.8.6 diagnostic overlay**

User's Fold7 screenshot reported: `viewport=720x1280  window=1080x2520  scale=1.50`. With those values:
- Width scale: `1080 / 720 = 1.50`
- Height scale: `2520 / 1280 = 1.97`
- `aspect="keep"` picks the smaller scale (1.50), so the viewport renders at `720*1.50 = 1080` × `1280*1.50 = 1920` — leaving **600 px of vertical letterbox** (300 top + 300 bottom).

The user's screenshot showed the black letterbox bars clearly, and confirmed Godot's touch transform was NOT subtracting the 300 px top-letterbox offset from incoming touches. So a tap at the visible top of "Inventory" (device y ≈ 420 — i.e. just below the 300 px black bar) got recorded at viewport y ≈ 280 (well below the actual tab bar). To register on the tab bar at viewport y ≈ 80, the user had to physically tap at device y ≈ 120 — *inside the black letterbox*. The phrase from the report: "Works is even farther up and finally works."

This is godotengine/godot#118153 manifested concretely on the Fold7's 9:21 inner display.

**Fix**

- **`display/window/stretch/aspect="keep_width"`** in [project.godot](project.godot). Width still matches design (720), but height extends to fill the device aspect — `720 × 1680` effective viewport on the Fold7 — eliminating the letterbox entirely. No letterbox → no offset math → touch coordinates match the visible UI directly.
- Existing layouts: top-anchored UI (currency bar, tab bar) stays exactly where it was. Bottom-anchored elements (the catching view's `Watch ad: 2× drops × 10` button, the `Skip (ad)` row in BattleView) move to the new viewport bottom, which is what we want on a taller device — they're now in the natural thumb zone instead of squeezed into the middle of a letterboxed view.
- Tests still 169/169 green.

**What you should see on the Fold7 once v0.8.7 reaches Play Store**

1. No black bars at top or bottom — the game fills the inner display.
2. Tap targets register exactly where you physically tap. The crosshair from `TouchDebugOverlay` should land directly on the green outline of the Button you tapped.
3. The bottom-of-screen UI (drops-2x button, skip ad, etc.) sits at the natural bottom of the screen, not floating mid-screen.

### v0.8.6 — TouchDebugOverlay actually shows now, plus button hit-rect outlines

**Fixed**
- **`TouchDebugOverlay` was invisible on Android** — v0.8.5's overlay subscribed via `_unhandled_input(event)`, which only fires AFTER `_gui_input` handlers have consumed the event. Every tap that landed on a Button (or anything with a `_gui_input`) was eaten before the overlay saw it, leaving the overlay silent on real device tests. v0.8.6 switches to `_input(event)`, which fires BEFORE GUI dispatching, so the overlay records every touch.

**Added**
- **Button hit-rect outlines** — overlay now walks the scene tree every frame and draws each visible Button's `get_global_rect()` as a faint green rectangle. The crosshair (red, fired on tap) lands at the touch position; the green outline shows where Godot considers the Button tappable. Direct visual evidence of any hit-test/visual mismatch: a tap inside the green outline that doesn't trigger the button is the mismatch.
- **Viewport/window/scale info label** at the top-left of the overlay: `viewport=720x1280  window=2160x1856  scale=3.00` (or whatever the actual values are on your device). Lets us read off the active stretch behavior from a screenshot.
- **Crosshair lifetime extended** from 0.8 s → 1.5 s so it's visible long enough to take a screenshot during testing.

**What this gets us**
A v0.8.6 build on the Fold7 should let you screenshot a tap and have, in the same frame:
1. The visible Button surface (rendered)
2. Godot's hit-test rect for that Button (green outline)
3. The actual touch position Godot saw (red crosshair)
4. The viewport/window scale (top-left text)

If the green outline is smaller than the visible button, that's the v0.8.5 stylebox-extending-past-rect bug (we'll know what direction). If the crosshair lands outside the button you tapped on, that's the canvas_items input transform bug (#118153) and the offset tells us the exact compensation needed.

### v0.8.5 — Targeted Android input fixes (named-bug mitigations + diagnostics)

**Investigation note**
The v0.8.3 → v0.8.4 padding adjustments didn't actually move the needle on the user's "buttons hard to press" report. A research pass turned up two **named Godot 4 bugs** that are far more likely to be the root cause:
- [godotengine/godot#118153](https://github.com/godotengine/godot/issues/118153) — `canvas_items` stretch mode on Android can render UI at the right place but fail to map touch coordinates back to the same point.
- [godotengine/godot#91987](https://github.com/godotengine/godot/issues/91987) — `TabContainer` with `MOUSE_FILTER_STOP` can dispatch tab clicks in two different coordinate systems.

**Fixed**
- **`display/window/stretch/aspect="keep"`** in [project.godot](project.godot). Previously unset → Godot's default `"ignore"` non-uniformly stretched the 720×1280 viewport to whatever device aspect, which is the path that triggers #118153. With `"keep"`, the viewport letterboxes on the Fold7's inner display but every coordinate transform uses the same uniform scale factor.
- **`TabContainer.mouse_filter = MOUSE_FILTER_PASS`** applied in `_apply_mobile_tab_theme`. Per #91987's documented workaround, this lets the child `TabBar` handle input cleanly without the parent re-emitting a duplicate event in mismatched coords.
- **48 dp tap targets restored**. v0.8.4 dialed Button stylebox `content_margin_*` down to `8/12` thinking the padding was the bug. With the real bugs identified, restored to `14/18` (text height ~22 px + 14 + 14 = ~50 px ≈ 48 dp at our viewport scale, matching Material's accessibility floor). Tab styleboxes similarly restored to `14/18`.

**Added**
- **Haptic feedback on every Button press** — [main.gd](game/scenes/main.gd) walks the tree on startup and again on `SceneTree.node_added`, connecting `Input.vibrate_handheld(20)` to every Button's `pressed` signal. 20 ms is Android's recommended `EFFECT_CLICK` duration. No-op on desktop.
- **`TouchDebugOverlay`** ([game/scenes/ui/touch_debug_overlay.gd](game/scenes/ui/touch_debug_overlay.gd)) — paints a fading red crosshair + outer ring at every touch / click position for ~0.8 s. Diagnostic for confirming the input-coordinate-mapping bug is actually fixed: if a tap lands on a button visually but the crosshair appears off-button, we have direct evidence of #118153 still affecting the build. Will be gated behind a debug flag in a follow-up release.

**Tests**: 169/169 still green.

**What's queued for v0.9.0**
A bigger UI restructure based on the same research: 10-tab top bar replaced by a 5-button bottom navigation in the thumb zone + a "More" sheet for the secondary destinations (Bestiary, Crafting, Ledger, Shop, Upgrades). The current pattern fights basic mobile-game ergonomics; this is a Phase-level revamp, not a release-cycle tweak.

### v0.8.4 — Hit-test mismatch fix (relaxed v0.8.3 stylebox padding)

**Fixed**
- **Buttons in v0.8.3 had a clickable area that didn't match the visible button** — user reported on the Fold7 that taps only registered "near the top" of buttons. Root cause: the v0.8.3 mobile-theme stylebox padding (14 px vertical / 18 px horizontal `content_margin_*`) was forcing the rendered stylebox larger than the parent container could allocate on certain views (settings sliders' embedded buttons, corner-anchored Buttons in CatchingView/BattleView, the cloud-save toggle). Godot's Button still hit-tests against the control's actual rect, but the stylebox had drawn past the bottom — so the visible "button surface" extended beyond the clickable region. Reduced to 8/12 (top/bottom and left/right) — still a noticeable size bump over Godot's ~4/8 default but no longer fights with constrained parent heights. Tab bar similarly relaxed from 14/18 to 10/14.

### v0.8.3 — Mobile UX polish (bigger tap targets, tab bar, scrollable Settings)

**Changed**
- **Project-wide mobile theme** — `main.gd._apply_mobile_default_theme()` builds a `Theme` at startup and assigns it to `get_tree().root.theme` so every `Control` inherits mobile-friendly defaults:
  - `Button` styleboxes now have 14 px vertical / 18 px horizontal content margins → ~48 dp min hit-box per Material's tap-target recommendation. Rounded corners (6 px) keep the bigger surface reading as a button.
  - `Button` and `Label` / `RichTextLabel` font sizes bumped to 18 / 16 / 16 px respectively.
  - `HSlider` grabber gets a 24 px circular grabber via stylebox padding so the volume sliders are draggable with a thumb without stylus precision.
  - Per-control `add_theme_*_override` calls already in the codebase still take precedence; the project-wide theme just raises the floor everywhere else.
- **Bigger tab bar** — `_apply_mobile_tab_theme(tabs)` overrides the four tab styleboxes (`tab_selected`, `tab_unselected`, `tab_hovered`, `tab_focus`) with 14 px vertical and 18 px horizontal padding. Selected tab gets a 2 px top border + brighter background tint so the current tab is unambiguous on a small screen. Font size bumped to 18 px. The 10-tab strip auto-overflows now that each tab has a real min-size; Godot's TabBar shows left/right arrows for horizontal scrolling.
- **Settings tab scrolls** — wrapped the existing `VBoxContainer` in a `ScrollContainer` (vertical-only) so the cloud-save section, volume sliders, and the spacer no longer clip off the bottom on shorter phones once the bigger v0.8.3 tap targets land.

**Why now**
User reported on Galaxy Z Fold7 (Android 16) that buttons were too small to reliably hit and scrolling through the tab menu was difficult. The 48-dp / Material guideline is the floor for finger-friendly UI; anything smaller is a tap-target failure on phones, especially foldables where the inner display is larger but pixel density is even higher.

### v0.8.2 — Sprite animation polish + save robustness

**Added (animation polish — Catch screen)**
- **Walk-cycle animation** on `monster_instance` ([game/scenes/catching/monster_instance.gd](game/scenes/catching/monster_instance.gd)). The monster spritesheets (`assets/sprites/wisplet.png`, `centiphantom.png`) are 256×32 — 8 frames of 32×32 — but only frame 0 was rendered. v0.8.2 cycles through all 8 frames at 8 fps during the WANDER state, holds frame 0 during PAUSE.
- **Idle bob** during PAUSE — a subtle 2-px sine-wave Y offset at 1.6 Hz so paused monsters look like they're breathing rather than frozen. Bob residual is zeroed when transitioning back to WANDER so the next walk cycle starts at sprite-y=0.
- **Smoothed direction flip** — replaced the instant `flip_h = true/false` swap with a 0.18 s `scale.x` tween through 0, so a wisplet changing direction reads as a quick turnaround animation instead of a snap. The direction-flip tween, the existing tap-bump squash, and the catch-despawn scale-up all share a single `_scale_tween` member with `kill()` on each new tween so they don't fight for the same property.
- **`_facing` member** (+1 / -1) tracks the current facing as a sign on `scale.x`, so the tap-bump tween multiplies through facing and a left-facing monster stays left-facing through the bump.

**Tests (169 passing, +4)**
- `test_monster_instance_animation.gd`:
  - Walk-cycle frame advances past frame 0 within 0.2 s of WANDER.
  - PAUSE state holds the configured pause frame (frame 0).
  - `_set_facing(-1)` flips the synchronous `_facing` member and creates a live scale-x tween.
  - Redundant `_set_facing(same)` is a no-op (doesn't allocate a new tween).

**Fixed (save robustness)**
- **Save persistence still failing on Android** despite the v0.7.5 `NOTIFICATION_APPLICATION_PAUSED` handler — user reported on a Galaxy Z Fold7 (Android 16) that close+reopen still drops progress. Three changes:
  - Periodic save cadence dropped from 30 s → **10 s**. Cheap (single small JSON write) but narrows worst-case progress loss by 3×.
  - `_notification` now also catches `NOTIFICATION_APPLICATION_FOCUS_OUT` and `NOTIFICATION_WM_WINDOW_FOCUS_OUT`. Some Android versions / OEMs dispatch one but not the other when the activity backgrounds; saving on all three is idempotent and harmless.
  - **`SaveIndicatorOverlay`** ([game/scenes/ui/save_indicator_overlay.gd](game/scenes/ui/save_indicator_overlay.gd)) — bottom-right toast that flashes `Saved HH:MM:SS` for ~1.5 s every time `EventBus.game_saved` fires. Diagnostic for this cycle: lets the user visually confirm whether the periodic Timer + lifecycle hooks actually fire on their device. Once persistence is verified reliable across cold-launch cycles, the overlay can be gated behind a debug flag or removed.

### Phase 7b — Real Google Play Games Services cloud sync

**Added**
- **Vendored godot-play-game-services v3.2.0** at [`addons/GodotPlayGameServices/`](addons/GodotPlayGameServices/) (MIT-licensed, ~345 KB plain git, no LFS — saved bandwidth memory respected). Pulled from `godot-sdk-integrations/godot-play-game-services` GitHub releases. Vendored as-is (no pruning) since the editor dock and assets weigh <40 KB combined.
- **[`PlayGamesCloudBackend`](game/systems/play_games_cloud_backend.gd)** — concrete `CloudSyncBackend` impl. Wraps the plugin's `PlayGamesSignInClient` (sign-in lifecycle) and `PlayGamesSnapshotsClient` (Saved Games / Snapshots API). Save format: `GameState.to_dict()` → `JSON.stringify` → `to_utf8_buffer()` → passed as `PackedByteArray` to `save_game()`. Download reverses this; the plugin's `PlayGamesSnapshot.content` is the raw bytes. Plugin's auto-startup auth check is silent (only signals when the user *was* signed in, so signed-out cold starts don't show a fake error); explicit `sign_in()` calls surface success/failure normally.
- **[`CloudSyncManager`](game/autoloads/cloud_sync_manager.gd)** autoload — orchestrates the sign-in → download → merge → upload-after-save flow:
  - Picks `PlayGamesCloudBackend` on Android with the PGS plugin loaded; otherwise `backend = null` (editor / desktop / web stay disabled).
  - On first successful sign-in: pulls the cloud snapshot, runs `SaveConflictResolver.resolve(local, remote)` from Phase 7a, applies the merged dict to `GameState`, writes back to local.
  - Subscribes to `EventBus.game_saved`: each save schedules a debounced (5 s) cloud upload, so rapid back-to-back saves coalesce into one push.
  - Status field + `status_changed(status)` signal: `disabled` / `signed_out` / `downloading` / `uploading` / `idle` / `error`. The Settings tab subscribes for live UI updates.
- **Settings tab — Cloud Save section** ([game/scenes/ui/settings_view.gd](game/scenes/ui/settings_view.gd)) — status label + "Sign in to Google Play Games" / "Sign out" button. Shows "Cloud sync is only available on Android with the Play Games Services plugin" + disabled button on platforms where the backend is null. Updates live as `CloudSyncManager.status_changed` fires.
- **CI manifest wiring** ([.github/workflows/release.yml](.github/workflows/release.yml)) — new "Write Play Games Services games_strings.xml" step before the AdMob secret injection. Extracts the App ID from `PGS_OAUTH_CLIENT_ID` (first numeric segment, e.g. `933809256647-xxx.apps.googleusercontent.com` → `933809256647`), validates it's all digits, writes `android/build/src/main/res/values/games_strings.xml` with `<string name="game_services_project_id">$APP_ID</string>`. The plugin's `EditorExportPlugin._get_android_manifest_application_element_contents()` injects `<meta-data android:name="com.google.android.gms.games.APP_ID" android:value="@string/game_services_project_id"/>` into the manifest at export time, AGP resolves the string resource, and the resulting AAB has the right App ID. `build.yml` writes a stub value (`0`) since debug builds don't ship cloud sync — but AAPT still needs the resource to exist for the meta-data reference to compile.
- **`PGS_OAUTH_CLIENT_ID` GitHub secret** — set to the OAuth 2.0 client ID from the Google Play Console PGS configuration.

**Tests (165 passing, +6)**
- `test_cloud_sync_manager.gd`:
  - Disabled when no PGS plugin (default state in headless tests).
  - Sign-in → download → merge → idle status transition.
  - Upload-after-save no-op when not signed in.
  - `status_changed` signal fires on transitions.
  - Sign-out resets the initial-sync-done flag.
  - Idempotent sign-in (second call no-ops if already signed in).

**Notes**
- The plugin auto-attempts auth at every cold start. If the user previously signed in on this device, the cloud sync runs invisibly within a few hundred ms of launch; otherwise the Settings tab shows the sign-in prompt.
- Conflict resolution: when the plugin reports two divergent snapshots that it can't auto-merge, `_on_conflict_emitted` surfaces it as a download/upload failure and skips the sync. Local progress is never overwritten. A future Phase 7c could expose dual-snapshot resolution UI; for now we trust the plugin's auto-merge for the common case.
- Sign-out is local-only — Google Play Games doesn't expose programmatic sign-out from a third-party app. The "Sign out" button just flips `CloudSyncManager`'s flag so uploads stop; to fully revoke, the user does it from the Play Games app's settings.
- **Dev-track caveat**: Cloud sync only works on internal-track installs for users you've added to the PGS Testers list in Play Console (until the underlying app + PGS configuration pass Google review). Test users see green sign-in immediately; non-testers get an OAuth 404 from Google's auth flow.

### Phase 7a — Cloud sync scaffolding (resolver + abstract backend)

**Added**
- **`SaveConflictResolver`** ([game/systems/save_conflict_resolver.gd](game/systems/save_conflict_resolver.gd)) — pure static `resolve(local, remote) -> Dictionary` function that merges two save dicts (e.g. local + cloud) using these rules per field:
  - **Monotonic accumulating** (preserve from BOTH saves so divergent offline play never loses progress): `pets_owned`, `pet_variants_owned`, `recipes_crafted`, `nets_owned` UNION; `monsters_caught` per-species per-{normal,shiny} MAX; `ledger` per-counter MAX (with `first_launch_unix` taking the earliest non-zero value); `narrator_state.lines_seen` per-line MAX; `prestige_count`, `current_max_tier` MAX.
  - **Last-write-wins** (the save with the higher `last_saved_unix` represents "where the player is now"): `currencies`, `inventory`, `active_net`, `current_battle`, `upgrades_purchased`, `tiers_completed`, `session_id`, `total_gold_earned_this_run`.
  - **Schema**: `version` MAX, `last_saved_unix` MAX. Tied timestamps prefer the remote save so two pristine devices converge on the same fixpoint regardless of which one runs the resolver.
- **`CloudSyncBackend`** ([game/systems/cloud_sync_backend.gd](game/systems/cloud_sync_backend.gd)) — abstract `RefCounted` defining the sign-in / upload / download contract. Signals: `sign_in_complete(success, error)`, `sign_out_complete()`, `upload_complete(success, error)`, `download_complete(data, success, error)`. Mirrors the `AdsBackend` pattern from Phase 6: Phase 7b will swap the stub for a real `PlayGamesCloudBackend` wrapping the Saved Games API on Android, callers stay backend-agnostic.
- **`StubCloudSyncBackend`** ([game/systems/stub_cloud_sync_backend.gd](game/systems/stub_cloud_sync_backend.gd)) — in-memory only. `sign_in()` succeeds immediately; `upload(state)` records the dict; `download()` returns the last upload (or `{}` if no upload ever happened, simulating a fresh device pulling cloud state). All callbacks deferred via `call_deferred` so the orchestrator's signal-handler invariants match a real async backend.

**Tests (159 passing, +24)**
- `test_save_conflict_resolver.gd` (16 tests) — every merge rule covered: empty-input handling, last-write-wins on non-monotonic fields, pet/recipe/net union, bestiary per-species MAX, ledger per-counter MAX with `first_launch_unix=MIN` and zero-handling, `current_max_tier` / `prestige_count` / `version` MAX, narrator `lines_seen` per-line MAX, `last_saved_unix` tiebreak determinism, input-mutation safety.
- `test_stub_cloud_sync_backend.gd` (8 tests) — sign-in flips state and emits, sign-out clears, upload-while-signed-out fails cleanly, upload→download round-trip preserves payload, first-time download returns empty dict, upload doesn't mutate caller's state.

**What's NOT in this phase**
- No real cloud provider — the stub doesn't talk to a network. Phase 7b will vendor a Play Games Services Godot plugin and wire `PlayGamesCloudBackend`.
- `SaveManager` is unchanged. The resolver and backend exist as standalone primitives ready for the orchestration layer Phase 7b will add (sync-on-login, upload-after-save, download-and-resolve at startup).
- No UI yet (no "Sign in to Google Play Games" button). Coming in 7b alongside the real backend.

### v0.7.5 — Android save lifecycle + debug-toggle default off

**Fixed**
- **Save not persisting on Android** — `main.gd`'s only save trigger was `Window.close_requested`, which fires when the user clicks the X on desktop but never fires on Android (home button, app switcher, swipe-to-dismiss, screen-off, force-stop all bypass it). Result: progress was lost every time the app was backgrounded. Two changes:
  - Hook `NOTIFICATION_APPLICATION_PAUSED` in [main.gd](game/scenes/main.gd)'s `_notification()`. This is dispatched via SceneTree to every node when the Android activity is paused (covers home, app switcher, screen-off, incoming call) — the last reliable hook before Android may kill the process.
  - Add a 30-second periodic save Timer as a safety net for hard kills (low-memory OOM, force-stop, system update) that don't fire any lifecycle notification. Cheap (single small JSON write) and idempotent.
- **All three pet variants unlocked simultaneously on tier completion** — `Settings.debug_fast_pets` defaulted to `true` in [game/autoloads/settings.gd](game/autoloads/settings.gd), which (1) dropped the per-tier catch threshold from 25 to 2 and (2) forced every variant roll to succeed (`roll_ceiling = 1.0`). Production builds shouldn't ship in dev-toggle mode. Defaulted to `false`; F2 still toggles it on for hand-testing.

### v0.7.4 — Force test ad units while AdMob account is "in review"

**Changed**
- Added `[admob] use_test_ad_units=true` to [project.godot](project.godot). When this flag is true, [`AdMobAdsBackend._resolve_ad_unit_id()`](game/systems/admob_ads_backend.gd) short-circuits the configured `admob/rewarded_unit_id` value and returns Google's documented test rewarded unit (`ca-app-pub-3940256099942544/5224354917`). Used during the AdMob account review window where real units fail with `load_failed: Publisher Data not found` (AdMob serving error code 9). Flip the flag to `false` (or delete the line — defaults to false) once Google approves the account and real ads start serving.
- The `ADMOB_APP_ID` injection still happens — Google's test ad units serve regardless of which app ID is in the manifest meta-data, so we keep the user's real app ID. Production wiring is fully exercised; only the rewarded unit is overridden.

**Tests (135 passing, +1)**
- `test_admob_backend_use_test_ad_units_flag_overrides_configured_value`: confirms the flag short-circuits before the configured-value check; existing `test_admob_backend_resolves_test_unit_when_setting_empty` updated to explicitly disable the flag (otherwise it'd short-circuit before reaching the empty-fallback branch).

### v0.7.3 — Un-LFS the AdMob AAR files (124 KB total)

**Fixed**
- v0.7.2's release build failed at `git checkout` because four AdMob bridge AARs (`poing-godot-admob-{ads,core}-{debug,release}.aar`, 4–58 KB each, ~124 KB total) had been routed through Git LFS via `*.aar filter=lfs` in `.gitattributes`. Multi-job CI fanout × LFS bandwidth = 1 GB/month free quota exhausted in one push, blocking checkout: `batch response: This repository exceeded its LFS budget`.
- Removed the `*.aar` LFS rule. Re-added the AARs as plain git blobs (LFS pointers → real binaries). `.so` and `.dll` LFS rules stay (those genuinely can be large); `.aar` joins `.png`/`.wav`/`.ttf` etc. in plain git per the saved bandwidth-budget memory.

### v0.7.2 — Commit AdMob AARs the plugin's `.gitignore` had excluded

**Fixed**
- The Poing Studios plugin ships with `addons/admob/android/.gitignore` containing `/bin`, which silently excluded the four bridge AARs and the `poing_godot_admob_ads.gd` Android export plugin from being committed in v0.7.0/v0.7.1 — the local files existed (extracted from `poing-godot-admob-android-v4.6.1.zip`) but git skipped them. v0.7.0 happened to slip through because the plugin's editor-side download service auto-fetches missing AARs at export time (`AdMob Android plugin not found. Installing...` in CI logs). v0.7.1 surfaced the gap with `AAPT: error: 'res://addons/admob/android/bin/ads/poing_godot_admob_ads.gd doesn't exists' is incompatible with attribute enabled (attr) boolean` (the plugin's `_get_android_manifest_application_element_contents()` deliberately emits broken XML when a configured library's .gd is missing).
- Removed `addons/admob/android/.gitignore`. Tracked the four AARs (then mistakenly via LFS — see v0.7.3 for the correction) and the export plugin script.

### v0.7.1 — Ad lifecycle diagnostic overlay

**Added**
- **`AdsManager.requested(reward_id: String)`** signal — fires synchronously inside `show_rewarded()` before the request goes to the backend. Lets diagnostic UI distinguish "tap registered, ad load in flight" from "tap never reached AdsManager".
- **`AdDiagnosticOverlay`** ([game/scenes/ui/ad_diagnostic_overlay.gd](game/scenes/ui/ad_diagnostic_overlay.gd) + `.tscn`) — top-of-screen banner that shows ad lifecycle events:
  - blue `[ad] requested: <id> …` on tap
  - green `[ad] <id> — reward granted` on success
  - red `[ad] <id> — failed: <reason>` on failure (e.g. `load_failed:no fill`, `not_initialized`, `user_canceled`)
  
  Holds for 6 s, then fades. Mouse-filter `IGNORE` so background taps still reach the gameplay underneath. Wired into [main.gd](game/scenes/main.gd) at the same level as `NarratorOverlay`.

**Why ship this:** A real AdMob ad attempt on the foldable failed silently in v0.7.0. The skip button just re-enabled itself with no UI feedback because `AdMobAdsBackend` emits `failed(reason)` but no caller surfaced the reason. With the overlay, the actual error string from the AdMob SDK (or "not_initialized" if the SDK init callback hasn't fired yet) is visible in-game without needing `adb logcat`. Once we've stabilized the production ad flow, this overlay can be gated behind a debug flag or removed.

**Tests (134 passing, +1)**
- `test_show_rewarded_emits_requested_signal`: confirms `AdsManager.requested` fires when `show_rewarded(id)` is called, with the matching reward ID.

### Phase 6b — Real AdMob integration (replaces stub on Android)

**Added**
- **Vendored Poing Studios godot-admob-plugin v4.3.1** at [`addons/admob/`](addons/admob/) (MIT-licensed, ~560 KB plain git, no LFS). Pruned to runtime-only — sample assets/fonts/music/csharp/sample-scenes dropped. The plugin's GDScript API surface (`MobileAds`, `RewardedAdLoader`, `RewardedAd`, `OnUserEarnedRewardListener`, `FullScreenContentCallback`, etc.) is `class_name`-registered so it's accessible without preloads.
- **Android `.aar` libraries** at [`addons/admob/android/bin/ads/libs/`](addons/admob/android/bin/ads/libs/) — `poing-godot-admob-ads-{debug,release}.aar` and `poing-godot-admob-core-{debug,release}.aar` (from `poing-godot-admob-android-v4.6.1.zip` matching Godot 4.6.1). The plugin's `EditorExportPlugin._get_android_libraries()` injects these into the AAB at export time.
- **[`AdMobAdsBackend`](game/systems/admob_ads_backend.gd)** — concrete `AdsBackend` impl wrapping the plugin's API. Lifecycle: `show_rewarded` → `RewardedAdLoader.new().load(unit_id, AdRequest, callback)` → `_on_ad_loaded` shows the ad → `_on_user_earned_reward` records the grant flag → `_on_ad_dismissed` emits `completed`/`failed` and destroys the ad. Reward signals are emitted on dismiss (not earn) so UI transitions happen on a clean screen, not over the ad surface.
- **[`AdsManager._ready`](game/autoloads/ads_manager.gd) backend selection** — picks `AdMobAdsBackend` when `Engine.has_singleton("PoingGodotAdMob")` is true (Android device with the plugin loaded), `StubAdsBackend` everywhere else (editor, Windows, Web, headless CI). Means dev/CI builds keep exercising the rewarded-video plumbing end-to-end without any AdMob account.
- **`admob/rewarded_unit_id` project setting** in `project.godot`. Defaults to `""` — `AdMobAdsBackend._resolve_ad_unit_id()` falls back to Google's documented test rewarded unit `ca-app-pub-3940256099942544/5224354917` when empty. Production override is patched in by CI.
- **Release-time secret injection** in [`.github/workflows/release.yml`](.github/workflows/release.yml). Two GitHub secrets:
  - `ADMOB_APP_ID` → `sed`-patched into `addons/admob/android/config.gd`'s `APPLICATION_ID` constant. The plugin's `_get_android_manifest_application_element_contents()` injects this as a `<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" .../>` tag inside `<application>`.
  - `ADMOB_REWARDED_UNIT_ID` → `sed`-patched into `project.godot`'s `[admob] rewarded_unit_id` value, read by `AdMobAdsBackend` at runtime.
  
  If either secret is unset, CI emits a `::warning::` and the AAB ships with Google's test IDs (which still display real test ads on a real device — useful for verifying plumbing before cutting over to production).
- **[`docs/admob-setup.md`](docs/admob-setup.md)** — backend-selection mechanics, test-ID defaults, AdMob console setup, secret-wiring instructions, troubleshooting.

**Tests (133 passing, +2)**
- `test_ads_manager.gd`:
  - Renamed `test_stub_backend_is_default` → `test_stub_backend_when_admob_plugin_absent`. Asserts `AdMobAdsBackend.is_plugin_loaded()` returns false in headless tests, and that `AdsManager` falls back to `StubAdsBackend` accordingly.
  - `test_admob_backend_fail_softs_without_plugin`: instantiating `AdMobAdsBackend` without the plugin singleton doesn't crash; `is_available` returns false; `show_rewarded` emits `failed("no_plugin")` instead of touching the uninitialized `RewardedAdLoader`.
  - `test_admob_backend_resolves_test_unit_when_setting_empty`: `_resolve_ad_unit_id()` returns the test unit when `admob/rewarded_unit_id` is empty, and the configured value when set.

**Notes**
- The plugin runs as a `@tool` `EditorPlugin` and registers its export plugins via `_enter_tree`. It's enabled in `project.godot`'s new `[editor_plugins]` section. Headless `--export-release` still loads the plugin (Godot's headless editor still fires `EditorPlugin._enter_tree`), so the `.aar` libraries get packaged.
- The Poing Studios plugin is **not** distributed via Maven Central despite earlier research — it's GitHub Releases only, with platform-specific zips per Godot version. Vendoring directly is the cleanest integration; the AAR files are <100 KB each so plain git is fine (no LFS bandwidth concerns per the saved feedback memory).

### Fixed (v0.6.8)
- **Android orientation lock not honored on foldables / large-screen devices** — even after the v0.6.7 int-enum fix shipped `android:screenOrientation="1"` (portrait), the Galaxy Z Fold7 (Android 16) still rendered the game rotated 90° on the inner display. Root cause: Godot 4.6's Android exporter hardcodes `android:resizeableActivity="true"` on the GodotApp activity, and on Android 12+ large screens (sw600dp+) the OS *ignores* `screenOrientation` when an activity is resizeable. The first attempted fix — a `src/release/AndroidManifest.xml` overlay with `tools:replace="android:resizeableActivity"` — was ignored by AGP (Godot's gradle wiring may skip non-main source dirs at merge time). The shipped fix appends a gradle hook to `android/build/build.gradle` from CI: `afterEvaluate { tasks.matching { it.name ==~ /process.*Manifest.*/ }.doLast { ... } }` rewrites the merged manifest's `resizeableActivity="true"` to `"false"` after Godot's regeneration and AGP's manifest merger run, but before the AAB packager reads it. Verified post-fix via `bundletool dump manifest`: AAB now shows `resizeableActivity="false"` and `screenOrientation="1"`.
- **`StubAdsBackend` exception when claiming offline 2× reward** — clicking "Claim 2× (watch ad)" inside `WelcomeBackDialog` triggered `Attempting to make child window exclusive, but the parent window already has another exclusive child` because `WelcomeBackDialog` (an `AcceptDialog`) was already exclusive of `/root` and the stub's `ConfirmationDialog` defaults to exclusive too. Set `_dialog.exclusive = false` on the stub dialog so it can layer on top of an existing modal without conflict; input still routes to the topmost popup.

### Phase 6a — Rewarded-video scaffolding (stub backend)

**Added**
- **`AdsManager` autoload** ([game/autoloads/ads_manager.gd](game/autoloads/ads_manager.gd)) — single entry point for the three rewarded-video placements. Holds a swappable `backend: AdsBackend`; Phase 6a ships `StubAdsBackend` which pops a confirmation dialog standing in for a real ad. Emits `rewarded_completed(reward_id, granted)` on grant and `rewarded_failed(reward_id, reason)` on cancel/error. Stable reward IDs:
  - `REWARD_OFFLINE_2X` (`"offline_2x"`) — double offline-progress reward on welcome-back.
  - `REWARD_BATTLE_INSTANT_FINISH` (`"battle_instant_finish"`) — fast-forward to the end of the current battle replay.
  - `REWARD_DROPS_2X_NEXT_10` (`"drops_2x_next_10"`) — double item drops on the next 10 catches (`DROPS_2X_CATCH_COUNT`).
- **`AdsBackend` abstract** ([game/systems/ads_backend.gd](game/systems/ads_backend.gd)) and **`StubAdsBackend`** ([game/systems/stub_ads_backend.gd](game/systems/stub_ads_backend.gd)). Phase 6b will land an `AdMobBackend` wrapping the Poing Studios plugin; everything calling `AdsManager.show_rewarded(reward_id)` stays untouched.
- **Three rewarded-video placements wired:**
  - `WelcomeBackDialog` — adds a `Claim 2× (watch ad)` button alongside the standard `Claim`. On grant, doubles `gold_gained`, every entry in `items_gained`, and every `catches_by_species` entry's `normal`/`shiny` count, then emits the doubled summary.
  - `BattleView` — adds a `Skip (ad)` button that becomes visible on battle start. On grant, fast-forwards through every remaining replay frame and transitions straight to POST. On cancel, the battle continues at the current speed.
  - `CatchingView` — bottom-right `Watch ad: 2× drops × 10` button. On grant, sets `GameState.transient_drops_2x_remaining = 10`; while > 0 the next item-drop in `_apply_catch_rewards` doubles in size and decrements the counter. Button label updates live (`2× drops: N left`) and disables when ads aren't available.
- **`EventBus.rewarded_video_completed(reward_id, granted)`** — fired by every grant site, reserved for future telemetry / tutorial hooks.
- **`GameState.transient_drops_2x_remaining: int`** — transient (not persisted) counter, reset by `_reset_to_defaults`.

**Tests (131 passing, +6)**
- `test_ads_manager.gd`:
  - Reward ID constants are stable strings (`offline_2x`, `battle_instant_finish`, `drops_2x_next_10`); `DROPS_2X_CATCH_COUNT == 10`.
  - `is_available()` delegates to the backend.
  - `show_rewarded(id)` routes the request to the backend.
  - Backend `completed`/`failed` signals forward through to `AdsManager.rewarded_completed`/`rewarded_failed` 1:1.
  - Calling `show_rewarded` with a null backend fail-softs to `rewarded_failed(id, "no_backend")` rather than crashing.
  - Production default backend is `StubAdsBackend` (Phase 6b will swap this).

**Notes**
- No real network calls or ad SDK integration in this phase. The stub's confirmation dialog is the only user-visible UI; it ships with the production build until Phase 6b lands the AdMob plugin.

### Fixed
- **Android portrait orientation** — `project.godot` had `window/handheld/orientation="portrait"` (string), but Godot 4.x stores this as an integer enum. The string parsed as `0` (landscape default), so the AAB shipped with `android:screenOrientation="0"`, which displayed the game rotated 90° on portrait-locked devices. Changed to `window/handheld/orientation=1`. Also dropped the now-dead `sed`-patch in CI workflows: Godot regenerates the AndroidManifest.xml from project settings during export, overwriting any pre-export edits to `android/build/src/main/AndroidManifest.xml`. Verified post-fix: `bundletool dump manifest` shows `android:screenOrientation="1"`.

### Phase 5c — Tier 4–20 content + dialogue corpus expansion

**Added**
- **51 new monster `.tres` files** — three species per tier across tiers 4–20, generated by `scripts/generate_tier_content.py`. Each species follows the §6 curve: `gold_base × 6.5` per tier (chained from tier-3 mid 110), `catch_difficulty × 2.8` per tier; per-species variants mirror the tier-1 spread (1.0 / 0.85 / 0.70 weight; 1.0 / 1.2 / 1.5 difficulty mult). Sprites alternate between `wisplet.png` and `centiphantom.png`; tints sweep HSV-style from pink-orange (T4) through cyan (T12) to deep purple (T20).
- **17 new `ItemResource` `.tres`** — one drop item per tier (`wraith_cinder`, `golem_pebble`, `surge_brine`, `glimmer_husk`, `hedge_thorn`, `gleam_filing`, `drift_crystal`, `scour_cinder`, `muddler_glyph`, `refrain_echo`, `knot_strand`, `vigil_tallow`, `refract_splinter`, `palimpsest_leaf`, `whisper_sigil`, `hollow_cinder`, `nadir_pollen`). Each has a Peniber-flavored description and a sell_value scaled to the tier curve.
- **6 new `NetResource` `.tres`** — `wraith_net` (T4 unlock), `hedgewright_net` (T7), `gleamwarp_net` (T10), `refrain_net` (T13), `vigil_net` (T16), `nadir_net` (T19). Each covers a 6-tier hunting band with progressively higher `catches_per_second` (1.6 → 5.6) and `spawn_max` (5 → 10).
- **6 new crafting recipes** chaining through the prereq tree (`recipe_tier3_net` → `recipe_wraith_net` → `recipe_hedgewright_net` → ... → `recipe_nadir_net`). Each consumes 50–425 of the matching tier's drop item plus a tier-scaled gold cost.
- **17 `on_tier_complete_4..20` dialogue lines** — Peniber's tier-by-tier observations, themed to the tier's species.
- **12 pool dialogue variants** — additional `on_shiny`, `on_idle_too_long`, `on_battle_loss`, `on_battle_win`, `on_offline_return_short/long`, `on_pet_acquired`, `on_prestige`, `on_ledger_opened` lines so the rotation doesn't repeat as quickly.
- **`scripts/generate_tier_content.py`** — one-shot, idempotent content generator. Re-running overwrites; tier curve and theme tables are easy to extend if Phase 6+ adds tiers 21+.

**Dialogue corpus total: 71 lines** (up from 42 in Phase 5a), about half-way to the parent plan's 150-line target.

**Tests (124 passing)**
- `test_narrator.test_recent_window_suppresses_repeats_for_pool` updated to dynamically count the `on_battle_loss` pool size rather than hardcoding 3 — pool has 5 entries now.
- All other tests still green.

**Pre-push checklist (Phase 5c)**
- ✓ GUT 124/124 passing
- ✓ Project boots clean headlessly with `--quit-after 60`
- ✓ CI green on `main` (run [25255692384](https://github.com/NickSanft/IdleBeastPractices/actions/runs/25255692384))
- ✓ Tag `phase-5c-complete` pushed

**Difficulty curve QA** is deferred to a follow-up: the curve is mathematically continuous (`× 6.5` gold, `× 2.8` difficulty), but a manual playthrough log to tier 5+ should confirm pacing-feels-right before tagging. Captured here as the pending checklist item; Phase 6 can consume the QA notes.

### Phase 5b — Visual & audio polish

**Added**
- `FloatingNumber` scene (`game/scenes/ui/floating_number.tscn`): a self-freeing `Label` that drifts up 56 px and fades over 1 s on every successful catch. Color-tinted gold (`#ffdd66`) for normal catches, larger and brighter for shinies (`+5 g` becomes `✨ +5 g`). Spawned from `catching_view._spawn_floating_gold` with x-jitter so stacked catches don't perfectly overlap.
- Screen shake on `tier_completed` (intensity 8 px / 0.45 s) and `first_shiny_caught` (4 px / 0.25 s). `catching_view._shake_spawn_root` tweens the `_spawn_root` Node2D's position with a falloff envelope, so the wandering monsters jitter without disturbing the Control-based UI layout.
- Audio variety in `AudioManager`: dedicated `_shiny_player` (`pitch_scale = 1.6`, +4 dB) and `_tier_up_player` (`pitch_scale = 0.7`, +6 dB). Same `tap.wav` source — pitch differentiates the moments without shipping new audio. Subscribes to `monster_caught` (with `is_shiny=true`) and `tier_completed` to fire automatically. Volumes track `Settings.sfx_db` on slider drag.

**Tests (124 passing, +3)**
- `test_floating_number.gd`: instantiates and configures, shiny variant prepends sparkle and bumps font size, drift tween starts on `_ready` without error.

**Pre-push checklist (Phase 5b)**
- ✓ GUT 124/124 passing
- ✓ Project boots clean headlessly with `--quit-after 60`
- ✓ CI green on `main` (run [25235523153](https://github.com/NickSanft/IdleBeastPractices/actions/runs/25235523153))
- ✓ Tag `phase-5b-complete` pushed

### Phase 5a — Peniber + Ledger

**Added**
- `Narrator` autoload full implementation: trigger map, weighted-random selection, sliding-window-of-5 anti-clustering, `min_total_catches` / `min_prestige_count` / `max_uses` filters, `narrator_state.lines_seen` persistence (survives prestige), idle detection (5-min trigger, 90 s cooldown).
- 42 `DialogueLineResource` `.tres` covering the trigger taxonomy from parent plan §8: `on_first_launch` (full Peniber title), `on_first_catch_ever`, `on_first_catch_<species>` × 9, `on_milestone_10/100/1000/10000`, `on_first_shiny` + 3 pool, `on_first_pet_acquired` + 2 pool, `on_first_battle_win` + 2 pool, `on_battle_loss` × 3, `on_tier_complete_1/2/3`, `on_first_prestige` + 2 pool, `on_idle_too_long` × 3, `on_offline_return_short/long` × 2 each, `on_first_craft`, `on_ledger_opened` × 3.
- `NarratorOverlay` scene at the main scene's top level (above the TabContainer): floating bottom-of-screen text bubble that fades in on `narrator_line_chosen`, holds for 8 s or until tapped, then fades out. `mouse_filter = IGNORE` on the wrapper so background taps still reach the catching view; only the bubble itself catches the dismiss tap. Mood-tinted bubble (`smug` / `begrudging` / `reverent` / `weary` / `exasperated`).
- `LedgerView` scene + Ledger tab: 15 stat rows with Peniber-editorialized labels ("Specimens captured (in their entirety)", "Iridescent oddities encountered", "Quotes Peniber has indulged you with", etc.). Live refresh on `monster_caught` / `first_shiny` / `prestige_triggered` / `item_crafted` / `game_loaded` / `game_saved`. Fires `on_ledger_opened` on visibility change.
- `docs/peniber-voice.md`: tone levers, mood field semantics, trigger taxonomy table, selection rules, and the "Victorian under-secretary" smell test for new lines. Phase 5b backlog noted.
- `ContentRegistry` extended to index dialogue lines.

**Tests (121 passing, +8)**
- `test_narrator.gd`:
  - `on_first_launch` fires once; second call returns null (max_uses).
  - Unknown trigger returns null.
  - Pool trigger picks distinct lines via the recent-window.
  - All 3 pool entries exhausted ⇒ next call returns null until `reset_recent_window()`.
  - `lines_seen` persists across `to_dict` / `from_dict` round-trip; max_uses re-applies.
  - Per-species and milestone trigger lookups all resolve.
  - Speaking increments `ledger.peniber_quotes_seen`.

**Pre-push checklist (Phase 5a)**
- ✓ GUT 121/121 passing
- ✓ Project boots clean headlessly with `--quit-after 60`
- ✓ Local Windows export builds
- ✓ CI green on `main` (run [25234365350](https://github.com/NickSanft/IdleBeastPractices/actions/runs/25234365350))
- ✓ Tag `phase-5a-complete` pushed

### Phase 4 — Bestiary, shinies, crafting

**Added**
- `CraftingSystem` (`game/systems/crafting_system.gd`): pure validation. `can_craft(recipe, inventory, gold, current_max_tier, recipes_crafted)` returns `{can: bool, reason: String}` with explicit reasons (`tier_locked`, `missing_prereq`, `insufficient_input`, `insufficient_gold`, `no_output`). `compute_deltas(recipe)` extracts inputs, gold cost, and output id/amount as a side-effect-free dict.
- `GameState.try_craft(recipe)` applies the deltas: deducts gold, removes inputs (erasing the inventory key on zero), adds the output to inventory or to `nets_owned`, marks the recipe id in `recipes_crafted`, emits `item_spent` / `item_gained` / `item_crafted` / `recipe_unlocked`.
- `GameState.recipes_crafted: Array[String]` — additive across prestiges (kept by `perform_prestige`); enables prereq chains (Tier 2 net unlocks Tier 3, etc.).
- 2 new `NetResource` `.tres` (`tier2_net`, `tier3_net`) and 2 new `ItemResource` `.tres` (`pet_collar`, `shiny_lure`; effects wired in Phase 5+).
- 5 `CraftingRecipeResource` `.tres`: `recipe_tier2_net`, `recipe_tier3_net` (gated on tier-2 recipe), `recipe_tier4_net` (placeholder until tier-4 content lands), `recipe_pet_collar`, `recipe_shiny_lure`.
- `CraftingView` scene as a Crafting tab. Cards show name, description, per-input availability with red/green color coding, gold cost, status string, Craft button. Hides recipes whose `tier_required > current_max_tier + 1` so future content stays out of sight.
- `BestiaryView` scene as a Bestiary tab. Per-species card: sprite (region-clipped), name + tier (or `??? — Tier X` until first catch), three slots — Caught / Shiny / Variant — and flavor text once seen. Live refresh via `monster_caught` / `first_catch_of_species` / `first_shiny_caught` / `pet_acquired`.
- `ContentRegistry` extended to index recipes alongside monsters/items/nets/pets/upgrades.

**Tests (99 passing, +12)**
- `test_crafting_system.gd` (new file): can_craft happy path; insufficient input / tier lock / missing prereq / passes once prereq is in `recipes_crafted` / insufficient gold / no_output. compute_deltas extracts inputs + gold + output id. Integration: `GameState.try_craft` consumes inputs, produces outputs, records recipe; rejects on short inputs without mutating state; recipes_crafted survives prestige.
- `test_catching_system.gd` extended with a 10000-trial Bernoulli check: `shiny_rate=0.05` produces 457–543 shinies (95% CI). Catches drift in the shiny RNG path.

**Pre-push checklist (Phase 4)**
- ✓ GUT 99/99 passing
- ✓ Project boots clean headlessly with `--quit-after 60`
- ✓ Local Windows export builds
- ✓ CI green on `main` (run [25217297549](https://github.com/NickSanft/IdleBeastPractices/actions/runs/25217297549))
- ✓ Tag `phase-4-complete` pushed

### Phase 3 — Prestige + audio

**Added**
- `PrestigeSystem` (`game/systems/prestige_system.gd`): pure helpers. `compute_rp_gain(gold_earned_dict, rp_mult)` returns `floor(sqrt(earned / 1e6) × rp_mult)` (1M gold → 1 RP; 4M → 2; 100M → 10; 10B → 100). `filter_persistent_upgrades` returns the entries from `upgrades_purchased` whose `UpgradeResource.persists_through_prestige=true` survive a reset.
- `GameState.perform_prestige()`: snapshots persisted state (pets, bestiary, ledger totals, persistent upgrades, RP balance, first_launch_unix), wipes the rest via `_reset_to_defaults`, then re-applies. Adds RP additively to the balance, increments `prestige_count` on root + ledger, emits `currency_changed` + `rancher_points_earned` + `prestige_triggered`. Honours the Headstart upgrade by re-equipping `basic_net` post-reset.
- `GameState.total_gold_earned_this_run`: BigNumber-dict counter that accumulates on every `add_gold` call and resets on prestige; PrestigeSystem reads it.
- `GameState.projected_rp_gain()`: convenience for the UI.
- 4 prestige `UpgradeResource` `.tres`, all RP-cost and `persists_through_prestige=true`:
  - `prestige_gold_mult` — Rancher's Knack: ×1.5/level (effect_id `gold_mult`), max 10.
  - `prestige_starting_net` — Headstart: equips Basic Net at run start, max 1.
  - `prestige_offline_cap` — Long Watches: +50% offline cap per level (multiplicative), max 5.
  - `prestige_rp_mult` — Reputation: +25% RP per level (effect_id `rp_mult`), max 5.
- `PrestigeView` scene as a new tab: shows projected RP, current run summary, what persists vs what wipes, double-confirm dialog.
- `AudioManager` autoload: looping music player streams `assets/music/Divora - New Beginnings - DND 4 - 05 Bring The Guitar, It's Going Down.wav`; SFX pool of 4 `AudioStreamPlayer`s plays `assets/sounds/tap.wav` on every monster tap. Volumes read from `Settings.music_db` / `Settings.sfx_db`.
- `EventBus.monster_tapped(monster_id, instance_id)` signal emitted from `catching_view._on_monster_tapped`. AudioManager subscribes; future analytics or VFX can hook the same signal without modifying the catch view.

**Save format**
- Bumped `CURRENT_VERSION` 1 → 2.
- New v1 → v2 migration in `save_migrations.gd`: seeds `total_gold_earned_this_run` from the existing `currencies.gold` value so existing saves can prestige without grinding from zero.
- Existing v0 → v1 → v2 chain still works.

**Tests (87 passing, +15)**
- `test_prestige_system.gd` (new file):
  - `compute_rp_gain`: zero below 1M threshold, 1 RP at 1M, sqrt-shaped scaling at 4M / 100M / 10B, multiplier applied, zero on zero gold.
  - `filter_persistent_upgrades`: keeps only `persists_through_prestige=true`, ignores unknown ids, returns empty when none qualify.
  - `GameState.perform_prestige` integration: zeros gold + inventory + tier; preserves pets + bestiary; increments `prestige_count` on root + ledger; awards RP additively; resets even when below RP threshold.
  - v1 → v2 migration: seeds `total_gold_earned_this_run` from gold; v0 → v2 chain handles full path with default 0.
- All Phase 0 / 1 / 2 tests still green.

**Pre-push checklist (Phase 3)**
- ✓ GUT 87/87 passing
- ✓ Project boots clean headlessly with `--quit-after 60`
- ✓ Local Windows export builds (PCK grew from 1.5 MB → 7.7 MB with audio bundled)
- ✓ CI green on `main` (run [25200622348](https://github.com/NickSanft/IdleBeastPractices/actions/runs/25200622348))
- ✓ Tag `phase-3-complete` pushed

**Follow-ups landed during the test cycle**
- Music WAV silently played zero frames despite reporting `playing=true`. Cause: the cached `AudioStreamWAV.load(...)` returned an instance with a degenerate `loop_end` (treats LOOP_FORWARD as a 0-length loop → "finishes" instantly). Fix: `duplicate(true)` the stream and set `loop_begin = 0`, `loop_end = total_frames - 1` explicitly on the duplicate.
- `AudioManager` defers `play()` via `call_deferred` so the AudioServer is alive before the call. Belt-and-suspenders 0.5s diagnostic timer retries play() if `pos` is still zero. `finished` signal handler logs unexpected stream end.
- Volume sliders in a new Settings tab. Range -40 → 0 dB, "Muted" label at floor; persists to `user://settings.cfg` and re-applies live via `audio_settings_changed` signal.
- Warning sweep: `@warning_ignore("unused_signal")` per signal in `EventBus`; `@warning_ignore("integer_division")` on the two intentional integer divisions in `BigNumber.format()`; renamed shadowing local `size` → `viewport_size` in `catching_view.gd` and `name` → `item_name` in `welcome_back_dialog.gd`.

### Phase 2 — Pets and battles

**Added**
- `BattleSystem` (`game/systems/battle_system.gd`): deterministic seeded auto-battle simulation. Returns a `BattleLog` dictionary `{seed, winner, ticks, frames, rewards}`. 600-tick cap, basic-attack damage = `max(1, atk - effective_def) × variance(0.85, 1.15)`, ability hooks via `AbilityRegistry`. RP reward = `floor(sum(enemy.tier) × rp_mult)` on player win.
- `AbilityRegistry` (`game/systems/ability_registry.gd`): three starter abilities. `strike` (1.5× damage, 4-tick cooldown, lowest-HP enemy), `shield` (+50% def status for 8 ticks, 12-tick cooldown), `heal` (+25% max-HP on lowest-HP ally, 16-tick cooldown). Static dictionary lookup; per-pet abilities are content in Phase 5+.
- `UpgradeEffectsSystem` (`game/systems/upgrade_effects_system.gd`): aggregates owned-upgrade effects into per-`effect_id` multipliers. Additive composition for `tap_speed`/`auto_speed`/`shiny_rate`; multiplicative for `gold_mult`/`drop_amount`/`rp_mult`/`offline_cap`. Output clamped to `[1.0, 1e9]`. Includes `cost_for_next_level` helper.
- 3 `PetResource` `.tres` (one per tier-1 species; abilities `strike`/`strike`/`shield`).
- 5 `UpgradeResource` `.tres`: `catch_speed_1` (+20% tap), `gold_mult_1` (×1.25), `drop_amount_1` (×1.5), `shiny_rate_1` (+25%), `offline_cap_1` (×2 → 2 hours per level).
- `BattleView` scene (Battle tab): roster + Fight button → frame-replay UI with HP bars, action log, and 1×/2×/4× speed toggle. Replays the precomputed log deterministically; same seed → byte-identical replay.
- `UpgradeTree` scene (Upgrades tab): flat purchase list. Cards show name, description, current/max level, next-level cost, Buy button. Visual tree layout deferred to Phase 5 polish.
- `GameState` helpers: `add_pet` (+ variant flag), `owned_pets`, `get_upgrade_level`, `try_purchase_upgrade` (deducts gold or RP, increments level, emits `upgrade_purchased`), `add_rancher_points` (emits `rancher_points_earned`), `multiplier(effect_id)` convenience.
- `ContentRegistry` extended to index pets and upgrades.
- Tier completion now awards a pet for every species in the completed tier (variant rolls per `PetResource.variant_rate`).

**Why it matters**

Phase 2 closes the main game loop: tap → catch → tier up → pet → battle → RP → upgrades → faster tap/auto/gold. Upgrades wire into `CatchingSystem`/`OfflineProgressSystem` calls so the player feels them everywhere immediately. The battle layer is fully simulated up front per ADR 0006: leaving the screen mid-battle doesn't pause it, the result is already determined; the UI is replay only.

**Tests (52 passing, 0 failing)**
- `test_battle_system.gd` (8 cases): same-seed determinism (byte-identical frames + winner + ticks), different-seed divergence, player-win rewards, enemy-win no-rewards, empty-team edge cases, tick-cap bound, ability cooldown cycling.
- `test_upgrade_effects.gd` (12 cases): unknown effect, no upgrades, additive single-level + multi-level, multiplicative single + compounding, multi-upgrade composition, zero-level ignored, clamp upper bound, `cost_for_next_level` at zero / growing / max.
- All Phase 0 + 1 tests still green.

**Pre-push checklist (Phase 2)**
- ✓ GUT 72/72 passing (52 from initial Phase 2 + 20 follow-ups: tier_completion_status, pets_to_award_for_tier, GameState.add_pet variants, reconcile_pet_awards, try_purchase_upgrade, record_catch)
- ✓ Project boots clean headlessly with `--quit-after 60`
- ✓ Local Windows export builds
- ✓ CI green on `main` (run [25200097246](https://github.com/NickSanft/IdleBeastPractices/actions/runs/25200097246))
- ✓ Tag `phase-2-complete` pushed

**Follow-ups landed during the test cycle**
- `mouse_filter` fix on `CatchingView` so taps reach the catch path under a TabContainer; `_gui_input`-driven hit-testing replaces unreliable Area2D physics picking.
- `_DEBUG_LOG` console output for tap / catch / tier-complete events, `Settings.debug_fast_pets` runtime toggle (F2), and F3 reset-all-progress for testing.
- Particle bursts + scale-bump on tap, bigger burst on catch.
- Variant pet acquisition implies base ownership (`pet_variants_owned ⊆ pets_owned`).
- `GameState.reconcile_pet_awards` runs on load to heal stale saves where a tier's pet awards missed (e.g. monster `.pet` ext_resources weren't wired when the tier first completed).
- Tier-completion logic extracted to `CatchingSystem.tier_completion_status` + `pets_to_award_for_tier` pure functions.

### Phase 1 — MVP catch loop

**Added**
- `CatchingSystem` (`game/systems/catching_system.gd`): pure functions for `pick_spawn` (tier + net-targets weighted choice), `resolve_tap` (difficulty-gated catch with per-monster drops + gold + shiny roll), `resolve_auto`, and `auto_catch_count` (fractional accumulator).
- `OfflineProgressSystem` (`game/systems/offline_progress_system.gd`): per-species distribution of expected catches, normal-approximation Poisson for shiny variance, BigNumber gold accumulation, configurable cap (default 1 hour).
- `ContentRegistry` (`game/systems/content_registry.gd`): lazy-loaded index of monsters/items/nets keyed by `id`. Single source for any scene that needs the spawnable pool.
- 9 `MonsterResource` `.tres` files across tiers 1–3 with per-species spawn weight, catch difficulty, drop range, gold base, shiny rate, and color tint.
- 3 `ItemResource` `.tres` files (`wisplet_ectoplasm`, `centiphantom_jelly`, `hush_pollen`).
- 1 `NetResource` `.tres` file (`basic_net`, cost 100 gold, 0.5 catches/sec, spawn_max 3, targets tier 1).
- `MonsterInstance` scene + script: wandering pixel-sprite with click/touch input, tap_progress accumulator, and a catch-and-despawn tween.
- `CatchingView` scene: spawn loop, auto-catch loop, tap handling, and tier-completion gate (≥25 catches of any species in the active tier AND all 3 species seen → unlock next tier).
- UI components: `CurrencyBar` (BigNumber-formatted gold + RP placeholder), `InventoryPanel` (grouped item list), `NetShop` (buy/equip nets), `WelcomeBackDialog` (offline summary).
- Main scene upgraded from placeholder to a tabbed layout: Catch · Inventory · Shop, with a currency bar pinned at the top.
- `GameState` helpers: `add_gold`, `try_spend_gold`, `add_item`, `record_tap`, `record_catch`, `purchase_net`, `current_gold`, `current_rancher_points` — and EventBus signal emissions for currency / inventory / first-catch / first-shiny.
- `MonsterResource.tint` and `MonsterResource.gold_base` fields. Tint allows the 3 within-tier color variants to share one sprite sheet; gold_base centralizes per-species reward values from the §6 design table.

**Why it matters**

Phase 1 turns Phase 0's scaffolding into something playable. A first-launch player can tap monsters, accumulate gold, buy a net, watch it auto-catch, and progress through three tiers in a 20-minute session. Offline progress closes the loop for short returns. The systems layer stays pure — every catch goes through `CatchingSystem` and every offline window through `OfflineProgressSystem`, both of which are unit-tested independently of the scene tree.

**Tests (32 passing, 0 failing)**
- `test_catching_system.gd` (11 cases): tier-filter, max-tier filter, null on empty pool, tap-below-difficulty, tap-at-difficulty, drop range bounds, seeded RNG determinism, auto-catch accumulator carry, zero-dt no-op.
- `test_offline_progress.gd` (8 cases): zero-elapsed empty summary, cap enforcement, cap-multiplier extension, spawn-weight distribution sanity, BigNumber gold band, tier gate, zero-rate skip, null-net safe.
- Phase 0 tests still green (BigNumber, save migration, save round-trip).

**Pre-push checklist (Phase 1)**
- ✓ GUT 32/32 passing
- ✓ Project boots clean headlessly with `--quit-after 60` (no script errors)
- ✓ Local Windows export builds and ships
- ✓ CI green on `main` (run [25195407762](https://github.com/NickSanft/IdleBeastPractices/actions/runs/25195407762)) — tests + Windows + Web + Android all four jobs
- ✓ Tag `phase-1-complete` pushed

### Phase 0 — Foundation

**Added**
- Godot 4.6.1-stable-mono project skeleton with all autoloads registered (`Settings`, `EventBus`, `SaveManager`, `TimeManager`, `GameState`, `AudioManager`, `Narrator`).
- `EventBus` signal catalog covering catching, inventory/currency, progression, pets/battle, prestige, crafting, lifecycle, and narrator events.
- `BigNumber` mantissa/exponent class with `add`/`subtract`/`multiply`/`divide`/`pow_int`/`compare`/`format` and full GUT test coverage.
- `SaveManager` with atomic `user://save.json` writes, `LocalFileBackend`, and a migration-chain framework (no migrations needed yet, but the framework is exercised by a v0→v1 fixture test).
- Resource schemas for monsters, pets, nets, items, upgrades, crafting recipes, and dialogue lines.
- Placeholder `main.tscn` showing "Critterancher".
- GUT 9.x vendored at `addons/gut/`.
- GitHub Actions workflows: `build.yml` (test + Windows/Web/Android-debug) and `release.yml` (signed AAB on tag).
- ADRs 0001–0007 covering engine, language, content-as-resources, save format, BigNumber, deterministic battles, and platform priority.

**Why it matters**

Phase 0 establishes the abstractions every later phase depends on: BigNumber for currency, the migration chain for save evolution, the EventBus for cross-system decoupling, and the Resource layer for content-driven scaling. Nothing is gameplay yet — but the next six phases can be additive.

**Tests**
- `test_big_number.gd` — 9 cases including normalization, mixed-exponent arithmetic, divide-by-zero handling, and formatter output.
- `test_save_migration.gd` — fixture v0 save migrates to current shape without data loss.
- `test_save_round_trip.gd` — populated `GameState` survives save → clear → load equality check.

**Pre-push checklist (Phase 0 + 0a)**
- ✓ GUT exits 0 (14/14 tests pass)
- ✓ Windows export builds and launches headlessly without errors
- ✓ Web export builds (uses the standard non-mono Godot binary locally; CI uses non-mono throughout)
- ✓ Android debug APK builds locally via Godot's GUI export and on CI Linux runners. Phase 0a unblocker was `rendering/textures/vram_compression/import_etc2_astc=true` in `project.godot` — Godot's Android exporter silently rejects projects without ETC2/ASTC import enabled, since GLES doesn't support S3TC/BPTC.
- ✓ CI green on `main` (run [25192707991](https://github.com/NickSanft/IdleBeastPractices/actions/runs/25192707991))
- ✓ Tag `phase-0-complete` pushed
