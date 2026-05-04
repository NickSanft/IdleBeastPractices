# IdleBeastPractices — Phase 12 plan: depth, meta-progression, QoL, accessibility, FTUE

This document scopes the work that follows Phase 11. It mirrors the structure and per-phase ship loop of [DETAILED_PLAN.md](DETAILED_PLAN.md) §2 (implement → tests → pre-push checklist → tag → CHANGELOG → next phase). Sub-phase letters follow the project's existing convention (`phase-5a`, `phase-10a`, `phase-11a`).

**Scope.** 14 features grouped into 8 sub-phases:

| Sub-phase | Items | Focus |
|---|---|---|
| 12a | 4, 15, 16, 17, 18 | Quality of life bundle |
| 12b | 11, 12 | Accessibility v2 |
| 12c | 9 | FTUE / Tutorial |
| 12d | 1 | Pet abilities |
| 12e | 3, 13 | Pet equipment + prestige polish |
| 12f | 2 | Achievements |
| 12g | 6 | Quest system |
| 12h | 7 | Difficulty curve overhaul |

The numbering refers to the suggestion list discussed before this plan was authored:

> 1. Pet abilities + ability tree
> 2. Achievements
> 3. Pet equipment / collars
> 4. Bulk crafting + auto-craft
> 6. Quest/mission system
> 7. Difficulty curve overhaul
> 9. Tutorial / FTUE coachmarks
> 11. Hold-to-tap
> 12. Color-blind palette mode
> 13. Prestige preview improvements
> 15. Inventory icons + rarity tints
> 16. Net comparison tooltip
> 17. Long-press context menus
> 18. Settings expansion

**Ordering rationale.** QoL (12a) and Accessibility (12b) are dependency-free and reduce friction for testing everything that follows. Tutorial (12c) benefits from having bulk crafting in place to teach. Pet abilities (12d) transforms battle and unlocks the design space for equipment (12e). Achievements (12f) and quests (12g) benefit from the richer system surface that 12d–12e create. The difficulty overhaul (12h) lands last because the math shifts whenever abilities or gear change.

---

## Phase 12a — Quality of life bundle

**Items addressed: 4, 15, 16, 17, 18.**

### Goal

Cut friction across the most-used screens. Each individual change is small; the bundle ships them together because none deserve a phase of their own.

### Files

**4. Bulk crafting + auto-craft**
- [`game/scenes/crafting/crafting_view.gd`](game/scenes/crafting/crafting_view.gd) — replace single Craft button with a row of Craft 1 / Craft 5 / Craft Max buttons. Craft Max computes the cap as `min(material_floor, gold_floor)` then calls `_on_craft_pressed` in a loop with a single celebration toast at the end.
- `game/autoloads/game_state.gd` — new `auto_craft_enabled: bool` (persisted). Toggled via a checkbox per recipe.
- `game/scenes/crafting/crafting_view.gd` — auto-craft scheduler runs every 2 s in `_process`, attempts any recipe with auto_craft_enabled=true and sufficient materials. Gated behind `prestige_count >= 1` so first-prestigers get a meta-unlock moment.

**15. Inventory icons + rarity tints**
- `game/scenes/ui/inventory_panel.gd` — replace flat list with a `GridContainer` (3 cols on phone, 5 on tablet) of inventory cards.
- `game/scenes/ui/inventory_card.tscn/.gd` — new reusable card: 48×48 icon + count label + rarity-tinted border (StyleBoxFlat per rarity tier).
- `game/resources/item_resource.gd` — add `@export var rarity: int = 0` (0 common, 1 uncommon, 2 rare, 3 epic). Default 0 keeps existing items working; per-item overrides land via the existing `.tres` files.
- Placeholder icons via the existing `scripts/generate_placeholder_icons.py` pipeline — extend it with item generators (alpha disc + first-letter glyph in rarity color).

**16. Net comparison tooltip**
- `game/scenes/ui/net_shop.gd` — for each net card, when shown alongside a currently-equipped net, render a delta line: `+1 spawn_max · +0.3 catches/s · +1 tier`. Negative deltas in `BLOOD_RUBY`, positive in `SAGE_GREEN`. Only shown for nets the player can afford and meets `tier_required` for.
- Long-press a net (Phase 12a's #17) opens a side-by-side compare modal showing all stats vs equipped.

**17. Long-press context menus**
- New helper: `game/scenes/ui/long_press_detector.gd` — Control mixin that emits `long_pressed(position)` after ~500 ms hold without movement. Used on:
  - Inventory cards: `Sell all (×N)` / `Use as ingredient (recipe X)` / `Pin to top`.
  - Pet rows in Battle roster: full stats + equipped gear.
  - Recipe rows: `Craft until materials run out`.
  - Bestiary cards: already have a tap-to-detail; long-press opens "View related recipes".

**18. Settings expansion**
- `game/scenes/ui/settings_view.gd` — add:
  - **Master volume** slider (currently only Music + SFX exist; Master would multiply both per the existing AudioServer Master bus setup).
  - **Language** option button — populated with `["English"]` for now; structure is in place for future locales.
  - **Replay tutorial** button (visible after FTUE has been seen; clears the seen flag, on next launch the tutorial replays).

### Tests

- `game/tests/test_bulk_crafting.gd` — Craft 5 produces 5 outputs and consumes 5× materials. Craft Max stops when materials run out. Auto-craft fires on the 2 s tick when materials are sufficient.
- `game/tests/test_inventory_card.gd` — rarity tint applied per-tier; tier 0 falls back to default.
- `game/tests/test_long_press_detector.gd` — fires at 500 ms; cancels on movement; cancels on release before threshold.
- `game/tests/test_net_comparison.gd` — delta line correct for upgrade case, hidden for current net, hidden for unaffordable net.
- Master-volume slider + language picker covered by [`test_settings_view.gd`](game/tests/test_settings_view.gd) extension.

### Acceptance

- [ ] Crafting tab has Craft 1 / 5 / Max buttons that actually craft that many.
- [ ] Auto-craft toggle visible after first prestige; runs in the background.
- [ ] Inventory tab is a card grid with rarity borders; uncommon/rare/epic items visually distinct from common.
- [ ] Net shop shows a stat-delta line under purchasable nets.
- [ ] Long-press on inventory cards / pets / recipes / bestiary cards opens a context menu within ~500 ms.
- [ ] Settings has Master volume, Language picker, Replay-tutorial entry.

**Tag.** `phase-12a-complete`. Bump CHANGELOG to **v0.12.0**.

---

## Phase 12b — Accessibility v2

**Items addressed: 11, 12.**

### Goal

Land the two highest-leverage accessibility additions called out in [POLISH_PLAN.md](POLISH_PLAN.md) but deferred from Phase 11b: hold-to-tap (the canonical clicker accessibility add per Game Accessibility Guidelines) and color-blind palette redundancy.

### Files

**11. Hold-to-tap**
- `game/scenes/catching/catching_view.gd` — when `Settings.hold_to_tap_enabled` is true and a tap is held on a monster, fire repeat tap events at `Settings.hold_tap_rate_hz` (default 8 Hz, range 4–16). Uses a `SceneTreeTimer` per active hold.
- `game/autoloads/settings.gd` — `hold_to_tap_enabled: bool = false`, `hold_tap_rate_hz: float = 8.0`, both persisted under `[accessibility]`.
- `game/scenes/ui/settings_view.gd` — new toggle + slider in the Accessibility section.

**12. Color-blind palette mode**
- `game/scenes/bestiary/bestiary_card.gd` — slot pills currently differentiate via color + the unicode glyph (◇ / ✦ / ✧ / ⬢). Add a small icon-shape redundancy: locked = outline, seen = dot, captured = filled diamond, perfected = filled star. Shape varies regardless of color — color-blind players can still parse the state.
- Same treatment for shiny/normal differentiation in [`floating_number.gd`](game/scenes/ui/floating_number.gd) — shinies get a `✦` prefix already, but the size bump is the only other signal; add a slight border outline so silhouette differs at a glance.
- `game/autoloads/settings.gd` — `colorblind_mode: bool = false`. When on, icons fall back to higher-contrast monochrome variants.

### Tests

- `game/tests/test_hold_to_tap.gd` — hold for 1.0 s at 8 Hz produces 7-9 tap events (clamp). Release before threshold produces 0 repeats.
- `game/tests/test_colorblind_palette.gd` — `colorblind_mode = true` substitutes the alternate icons in bestiary slot pills.

### Acceptance

- [ ] Settings has Hold-to-tap toggle and rate slider; both persist.
- [ ] Holding finger on a monster auto-repeats taps at the configured rate.
- [ ] Bestiary slot pills are distinguishable without color (shape redundancy).
- [ ] All Phase 11b accessibility tests still green.

**Tag.** `phase-12b-complete`. Bump to **v0.12.1**.

---

## Phase 12c — FTUE / Tutorial

**Item addressed: 9.**

### Goal

Improve the first-30-seconds path from "I just installed this" to "I understand the loop." Per Pecorella's GDC framing, the tutorial is *unlocking* mechanics in sequence, not explaining them. The audit found there's currently zero scripted onboarding.

### Files

- `game/autoloads/tutorial_state.gd` (new) — tracks which steps have been seen. Persisted via SaveManager. Steps:
  1. `tap_first_monster` — coachmark arrow on the first wandering monster, dismisses on first tap.
  2. `buy_first_net` — fires when player has 100 gold and no net, points to Shop tab.
  3. `equip_net` — fires after first net purchase, points to the Equip button.
  4. `complete_first_tier` — fires once tier-1 catches reach 5/25, points to the next-goal-chip.
  5. `enter_battle` — fires after first pet awarded, points to Battle tab.
  6. `craft_first_recipe` — fires after first recipe unlocks (tier 2).
- `game/scenes/ui/coachmark.tscn/.gd` — pointing-arrow + tooltip-style hint overlay. Anchored to a target Control via screen-space lookup. Pulses gently to draw the eye.
- `game/scenes/main.gd` — boot the TutorialState autoload check; show the next-due coachmark when its trigger condition fires.
- Settings: "Replay tutorial" button (added in 12a) clears `TutorialState.steps_seen`.

### Tests

- `game/tests/test_tutorial_state.gd` — step gating (seen flag, advance order). Replay clears state.
- `game/tests/test_coachmark.gd` — anchors to a target Control's screen rect, dismisses on tap, fires `dismissed` signal.

### Acceptance

- [ ] First launch shows a "Tap a monster to catch it" coachmark on the first spawned monster.
- [ ] Subsequent steps fire at their gated triggers, not on a fixed timer.
- [ ] Replay tutorial works: full sequence re-fires from scratch.
- [ ] Tutorial respects `Settings.reduce_motion` (no pulsing animation when on).

**Tag.** `phase-12c-complete`. Bump to **v0.12.2**.

---

## Phase 12d — Pet abilities

**Item addressed: 1.**

### Goal

Transform battle from "highest-ATK wins" into team-comp puzzles. The framework already exists: `PetResource.ability_id` is exported, `BattleSystem._act` queries `AbilityRegistry.get_ability(id)`, and the BattleLog supports ability frames. Currently only `strike` is registered.

### Files

- `game/systems/ability_registry.gd` — extend with 6–8 new abilities, each implementing the standard signature `(tick, caster, allies, enemies, rng) -> Array[Dictionary]`:
  - **`strike`** (existing) — already shipped, kept as the baseline.
  - **`heal`** — restore 30 % of caster's max_hp to the lowest-HP ally.
  - **`shield`** — apply `def_buff` status (50 % def for 4 ticks) to lowest-HP ally.
  - **`taunt`** — apply `taunted` status to caster (forces enemies to target caster) for 5 ticks.
  - **`rend`** — bleed DOT on lowest-HP enemy: 5 dmg per tick for 4 ticks.
  - **`smite`** — heavy attack: 2.5× damage on highest-HP enemy. 6-tick cooldown.
  - **`cleanse`** — strip all negative statuses from all allies.
  - **`burst`** — AOE: 0.6× damage to all enemies.
- `game/systems/battle_system.gd` — extend `_tick_statuses` to handle new effects: `bleed`, `taunted`, plus existing `def_buff`. Update `_pick_lowest_hp` etc. to respect `taunted`.
- `game/data/pets/*.tres` — assign one ability_id per pet. Tier 1 pets keep `strike`; tier 2 pets get `heal`/`shield`/`taunt`; tier 3+ get the rarer abilities.
- `game/scenes/battle/combatant.gd` — when a frame's `action.begins_with("ability:")`, play a distinct visual: aura flash for buffs, ground-glyph for AOE, beam for heal targeting an ally.

### Tests

- `game/tests/test_abilities.gd` — one test per ability:
  - `heal` restores HP, capped at max_hp.
  - `shield` applies def_buff, expires after 4 ticks.
  - `taunt` redirects enemy targeting.
  - `rend` deals DOT each tick for 4 ticks.
  - `smite` 2.5× damage; cooldown blocks re-fire.
  - `cleanse` strips status_effects.
  - `burst` damages every living enemy.
- Determinism preserved: same seed + same teams + same ability lineup → byte-identical BattleLog (extend [`test_battle_system.gd`](game/tests/test_battle_system.gd)).

### Acceptance

- [ ] All 8 abilities exist in AbilityRegistry and can be referenced from `.tres` files.
- [ ] BattleSystem applies status_effects correctly (def_buff, bleed, taunted).
- [ ] Combatant plays a distinguishable visual per ability category.
- [ ] Existing `simulate()` test_battle_system contract still passes.
- [ ] Tier-1 wisplet roster vs. a tier-2 stage now plays out differently than the all-strike baseline.

**Tag.** `phase-12d-complete`. Bump to **v0.13.0** (minor bump for substantive new system).

---

## Phase 12e — Pet equipment + prestige polish

**Items addressed: 3, 13.**

### Goal

Add a meta-progression layer between tier completions (equipment) and dress up the largest progression event (prestige).

### Files

**3. Pet equipment / collars**
- `game/resources/equipment_resource.gd` (new) — `EquipmentResource` schema:
  - `id: StringName`, `display_name: String`, `slot: Slot` (HEAD / BODY / TRINKET enum), `tier: int`, `sprite: Texture2D`.
  - Stat modifiers: `attack_add: float`, `defense_add: float`, `hp_add: float`, `ability_cooldown_reduction: int`.
  - `recipe: CraftingRecipeResource` (the recipe that crafts this item).
- `game/data/equipment/*.tres` — 15 starter items: 3 slots × 5 tiers.
- `game/data/recipes/recipe_*.tres` — 15 new recipes; existing `recipe_pet_collar.tres` extended into the suite.
- `game/autoloads/game_state.gd` — `pet_equipment: Dictionary` mapping `pet_id` to `{HEAD: equipment_id, BODY: ..., TRINKET: ...}`. Persisted in v3 save schema; migration `_migrate_v2_to_v3` adds the empty dict.
- `game/scenes/battle/team_select.tscn/.gd` (new — referenced in POLISH_PLAN's 10e.2 acceptance but not yet built) — pet picker + equipment picker. Three slot tiles per pet; tap to open an equipment-slot modal that lists owned items for that slot.
- `game/systems/battle_system.gd` `_make_combatant_from_pet` — apply equipment additive modifiers when building the combatant dict.
- `game/scenes/crafting/crafting_view.gd` — equipment recipes show a tiny preview of the resulting stat boost (`+5 ATK · +20 HP`) so the player knows what they're crafting toward.

**13. Prestige preview improvements**
- `game/scenes/prestige/prestige_view.gd` — full polish pass:
  - Themed PanelContainer with a brass-accented "Prestige" heading and a subtitle.
  - Animated RP forecast: ring chart (Polygon2D arc) showing current vs. projected RP, animates from 0 to projected on _ready.
  - "This run vs your best" comparison: alongside the current-run RP, show `prestige_count` runs' best `rp_at_prestige` (new GameState field, persisted via the existing migration framework).
  - Pre-prestige checklist: tiers cleared this run, total catches, peak gold — gives the player a sense of accomplishment.
  - Confirm button is `BLOOD_RUBY`-tinted destructive button per the existing wipe-save pattern.

### Tests

- `game/tests/test_equipment.gd` — equipping a +5 ATK collar boosts the combatant's atk by 5 in the simulated battle. Unequipping reverses it. Saving/loading preserves the equipment dict.
- `game/tests/test_save_migration.gd` — extend with v2→v3 migration.
- `game/tests/test_prestige_view.gd` — themed panel resolves; "best run" record updates after each prestige; ring chart hits final value within tween duration.

### Acceptance

- [ ] Each pet has 3 equipment slots; equipping items modifies battle stats.
- [ ] `pet_equipment` survives save round-trip via the migration chain.
- [ ] Prestige tab has a themed UI with animated RP forecast and best-run comparison.
- [ ] Crafting recipes for equipment show preview stat deltas.

**Tag.** `phase-12e-complete`. Bump to **v0.13.1**.

---

## Phase 12f — Achievements

**Item addressed: 2.**

### Goal

Persistent meta-goals to fire celebration overlays for, separate from tier completions. The `Ledger` already tracks the right metrics; this phase adds the achievement system on top.

### Files

- `game/resources/achievement_resource.gd` (new) — schema:
  - `id: StringName`, `display_name: String`, `description: String`, `sprite: Texture2D`, `tier: int` (visual: bronze / silver / gold).
  - Trigger: `ledger_field: StringName` + `threshold: int`. Achievement unlocks when `GameState.ledger[field] >= threshold`.
  - Reward: `rp_reward: int` (Rancher Points) and/or `gold_reward: BigNumber`.
- `game/data/achievements/*.tres` — 20 starter achievements:
  - Catching: 100 / 1 K / 10 K total catches, 1 / 5 / 25 shinies, 1 / 10 species seen.
  - Battle: first win, 10 wins, first stage clear, 25 stages cleared.
  - Crafting: first craft, 10 crafts, all tier-1 nets owned.
  - Prestige: first prestige, 5 prestiges, 25 prestiges.
  - Misc: 60 minutes idle (offline), open the ledger 10 times, see 50 Peniber lines.
- `game/autoloads/achievements.gd` (new autoload) — checks all achievement triggers on EventBus signals (`monster_caught`, `tier_completed`, `prestige_triggered`, etc.), unlocks any whose threshold is now met, fires `achievement_unlocked(id)`.
- `game/scenes/main.gd` `_install_celebrations` — wire `achievement_unlocked` to the celebration_overlay (tier-3 spectrum: smaller than tier_completed but visible).
- `game/scenes/ledger/ledger_view.gd` — new "Achievements" section: 4-column grid of cards. Locked = silhouette + count of progress (e.g. `Catches: 312 / 1000`). Unlocked = full sprite + name.

### Tests

- `game/tests/test_achievements.gd` — 5 representative unlocks: catch threshold, shiny threshold, prestige threshold, ledger field, multi-trigger event ordering. Re-unlock prevented on subsequent triggers.
- `game/tests/test_ledger_view.gd` — extend with achievements grid render.

### Acceptance

- [ ] 20 achievements load via ContentRegistry (new dir).
- [ ] Achievement unlocks fire celebration_overlay with the achievement's title and sprite.
- [ ] RP/gold rewards land in GameState.
- [ ] Ledger view shows a 4-column achievement grid with locked/unlocked states.
- [ ] Re-completing the same trigger doesn't re-unlock.

**Tag.** `phase-12f-complete`. Bump to **v0.13.2**.

---

## Phase 12g — Quest system

**Item addressed: 6.**

### Goal

Three-tier concurrent goal system per Pecorella's GDC framing. Short-term (next minute), medium-term (this session), long-term (this prestige cycle). Surfaces "what's next" without overwhelming.

### Files

- `game/resources/quest_resource.gd` (new) — schema mirrors `AchievementResource` but with two key differences:
  - `quest_tier: Tier` enum — SHORT / MEDIUM / LONG. Determines which slot it occupies on the home view.
  - `repeatable: bool` — short quests cycle (catch 10 → catch 25 → catch 100); long quests usually fire once per prestige cycle.
- `game/autoloads/quest_log.gd` (new autoload) — persisted state: which quest is active in each slot, progress toward each. Fills empty slots from the available pool when the previous quest completes (or, for repeatables, advances to the next ladder rung).
- `game/scenes/ui/quest_strip.tscn/.gd` (new) — a horizontal strip of 3 mini-cards anchored above the bottom nav. Each card: icon + 1-line goal + progress bar + reward icon. Tappable for full description in a tooltip or modal.
- `game/data/quests/*.tres` — ~30 quests covering all three tiers:
  - SHORT (~10): "Catch 25 wisplets", "Tap 100 times", "Win a battle", "Craft anything", etc.
  - MEDIUM (~12): "Reach tier 3", "Collect 5 different shinies", "Earn 100 K gold this run", "Win 5 stages", etc.
  - LONG (~8): "Prestige 1 / 5 / 25 times", "Complete tier 10 / 15 / 20", "Earn 10 / 100 / 1000 RP".
- `game/scenes/main.gd` — add the quest_strip to the main scene above the bottom nav. Subscribes via QuestLog to refresh on completion.

### Tests

- `game/tests/test_quest_log.gd` — slot fill on completion, repeatable advancement, persistence round-trip.
- `game/tests/test_quest_strip.gd` — three slots render; tapping a slot opens detail; reward icon matches quest definition.

### Acceptance

- [ ] Three quest slots visible on the catching view (and bestiary, battle, etc. — anywhere with the bottom nav).
- [ ] Completing a short quest auto-fills the next one from the pool.
- [ ] Quest progress persists via the save migration.
- [ ] Quest reward (RP, gold, item) is applied via the same celebration_overlay path as achievements.

**Tag.** `phase-12g-complete`. Bump to **v0.13.3**.

---

## Phase 12h — Difficulty curve overhaul

**Item addressed: 7.**

### Goal

Re-validate and tune the 20-tier curve now that abilities (12d) and equipment (12e) are live. The headless sim runner from v0.9.4 already exists; this phase uses it.

### Files

- `tests/sim/sim_runner.gd` — extend the AI policy:
  - Equip best-available equipment per pet (greedy, matching slot).
  - Use ability-aware battle sim (already drops out via Phase 12d's BattleSystem extension).
- `tests/sim/output/difficulty_curve_v0_13.csv/.md` — fresh sweep with the new systems.
- **Tuning pass**: identify stalls and sprints. Edit per-tier:
  - `MonsterResource.spawn_weight` — drop weight for "easy" tier 1-3 species, raise for tier 4-8 to slow bonus catches.
  - `MonsterResource.base_catch_difficulty` — soften the spike from tier 3 to tier 4 (the original wall).
  - `PetResource.base_attack/defense/hp` — re-balance per-tier so abilities aren't the only viable strategy.
  - `EquipmentResource` stat boosts — keep the upper end from breaking tier 8+ enemies.
- Document expected playthrough times per tier in `docs/curve_targets.md` (new): "tier 1: 5 min, tier 5: 1 hour, tier 10: 8 hours, tier 20: 1 prestige cycle".

### Tests

- Headless sim must complete full 20-tier playthrough without stall (no early-termination on the patient-AI policy).
- `tests/sim/output/difficulty_curve_v0_13.md` includes a section confirming each tier completes within ±25 % of its target time.
- Existing `test_battle_system.gd` and `test_battle_stage.gd` regression suites stay green.

### Acceptance

- [ ] Sim sweeps 20 tiers without stalling, with ability + equipment AI policy.
- [ ] Per-tier completion times within ±25 % of `docs/curve_targets.md`.
- [ ] No tier feels like a 24-hour grind in the sim's report.
- [ ] Existing battle determinism contracts unchanged.

**Tag.** `phase-12h-complete`. Bump to **v0.13.4**.

---

## Cross-cutting

### Save migration

12d alone doesn't change the schema; `ability_id` is already persisted on PetResource. 12e adds `pet_equipment` and a per-prestige best-run tracker — both land via a v2 → v3 migration. 12f adds `achievements_unlocked: Array[String]`. 12g adds `quest_state: Dictionary`. All migrations are additive (default-empty fields), so the chain is straightforward.

### Test isolation

Phase 11b's after_each pattern in test_accessibility_settings extended to any test files that mutate Settings. New 12a/12b/12g tests should follow the same pattern: reset Settings + GameState in `before_each`, restore in `after_each` if the test mutates non-default state.

### Determinism

Pet abilities (12d) introduce new RNG draws (variance on damage, status duration, etc.). The single-RNG pattern from `simulate_stage` carries through — every ability's `Callable` receives the same shared RNG, so determinism per (seed, teams, ability lineup) is preserved.

### Asset bank

12d's ability visuals (aura flash, ground glyph, beam) can ship procedural via `Polygon2D` + tween if the broader sprite-art commission isn't done. 12e's equipment sprites use the existing placeholder-icon pipeline. 12f's achievement badges use the same. None of these phases require commissioned art to ship.

---

## Out of scope (still)

- iOS port (Phase 8 deferred)
- IAP / paid currency / shop with real money
- Multiplayer / leaderboards / friends
- Push notifications
- Daily login (#5 from the suggestion list — explicitly omitted; design-heavy retention loop)
- Audio bank (#14) — procedural pitch-shift placeholders are still in place
- Bestiary search/filter (#10 from suggestion list — explicitly omitted from this plan)
- Sprite art commission (#8 — asset work, not engineering)

---

## Definition of done (per sub-phase)

Each of 12a–12h is done when:

1. All listed files exist and are non-stubs.
2. All acceptance criteria pass.
3. All tests pass in CI on Linux + Windows + Web + Android Debug.
4. The tag `phase-12X-complete` is pushed only after CI is green.
5. CHANGELOG entry follows the existing pattern (Why · Added · Tests · Pre-push checklist).
6. The next sub-phase starts cleanly off `main`.
