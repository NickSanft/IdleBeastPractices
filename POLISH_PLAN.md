# IdleBeastPractices — Polish Plan (Phase 10)

This document scopes the visual polish pass that follows Phase 9. It mirrors the structure and per-phase ship loop of [DETAILED_PLAN.md](DETAILED_PLAN.md) §2 (implement → tests → pre-push checklist → tag → CHANGELOG → next phase). Sub-phase letters follow the project's existing convention (`phase-5a`, `phase-6a`, etc.).

**Background.** Audit of the current UI layer found:

- Zero `ColorRect` / `StyleBoxFlat` use across any `.tscn` — the game ships on Godot's default dark-gray theme.
- No theme resource checked in.
- Inline `add_theme_*_override` calls scattered across ~15 scripts (~80 occurrences).
- Asset bank is minimal: 2 sprite sheets (wisplet, centiphantom), 1 SFX (`tap.wav`), 1 music track, no fonts, no icons.

This plan covers items #1–#7 from the polish suggestions discussion. Items #8–#10 (sprite commission, audio bank, Peniber portrait variants) remain out of scope and are flagged as known limitations.

---

## Phase 10a — Theme & font foundation

**Items addressed: #1, #2**

**Goal.** Replace Godot's default dark-gray theme with an intentional Peniber-flavored aesthetic (parchment / sepia / aged-brass palette) applied at the `main.tscn` root, with one display font for headings and one body font.

**Scope guard.** This phase is cosmetic-only: StyleBoxes, colors, and base font. Inline `font_size` and color overrides in scripts are **kept** as semantic emphasis on top of the theme — auditing/removing them is deferred to a future sub-phase if needed. This prevents an 80-line cleanup from creating layout regressions inside what should be a foundation phase.

**Files**

- `game/resources/main_theme.tres` — Theme resource:
  - `Button/normal`, `Button/hover`, `Button/pressed`, `Button/disabled`: StyleBoxFlat with parchment fill, brass border, 6px corner radius.
  - `PanelContainer/panel`: StyleBoxFlat (slightly darker parchment, 4px corner).
  - `ProgressBar/background`, `ProgressBar/fill`: themed StyleBoxes.
  - `Label/default_color`: sepia ink.
  - Default font + font size set at the theme level.
- `game/resources/palette_colors.gd` — `class_name PaletteColors extends RefCounted` with named constants (`SEPIA_DARK`, `PARCHMENT`, `BRASS_ACCENT`, `BLOOD_RUBY`, `INK_BLACK`). Future scenes reference these instead of hardcoding hex.
- `assets/fonts/peniber_display.ttf` — Victorian display face (Cinzel or UnifrakturCook, OFL-licensed).
- `assets/fonts/peniber_body.ttf` — Readable serif body (EB Garamond, OFL-licensed).
- `assets/fonts/README.md` — attribution and replacement instructions.
- `game/scenes/main.tscn` — set `theme = preload("res://game/resources/main_theme.tres")` at root.

**Tests**

- `game/tests/test_theme.gd` — load `main_theme.tres`, assert key StyleBoxes resolve, font is non-null, font size is in sane range.
- Re-use existing scene smoke tests (instantiate every top-level scene, assert no `_ready()` errors).

**Acceptance**

- [ ] Every screen renders with the new theme; no residual default-gray Godot panels.
- [ ] Fonts load on Web export (no remote fetch, no CSP issues).
- [ ] All existing GUT tests still pass.
- [ ] Pre-push checklist green (parse, GUT, three exports).

**Tag.** `phase-10a-complete`. Bump CHANGELOG to **v0.10.0**.

---

## Phase 10b — Catching screen visuals & tap juice

**Items addressed: #3, #5**

**Goal.** Make the most-used screen feel alive: depth via parallax background, satisfying feedback on every tap.

**Files**

- `game/scenes/catching/catching_background.tscn` — `ParallaxBackground` with three layers (sky gradient, silhouette horizon, ground tile). Sky gradient color shifts subtly per `current_max_tier`.
- `game/scenes/catching/catching_view.tscn` — wrap existing content in a `CanvasLayer` over the background.
- `game/scenes/ui/catch_flash.gd` — `ShaderMaterial` for white-out flash on the catch sprite; fades over 0.15s.
- `game/scenes/catching/monster_instance.gd` — scale-punch tween on tap (1.0 → 1.25 → 1.0 over 0.12s) BEFORE catch resolves.
- `game/autoloads/audio_manager.gd` — register additional SFX hooks (catch, shiny, miss-tap). Actual audio files remain a Phase 5 leftover; AudioManager just exposes the entry points.
- `game/scenes/catching/catching_view.gd` — emit `Input.vibrate_handheld(40)` on Android catches.

**Tests**

- `game/tests/test_catch_flash.gd` — instantiating the shader material doesn't error; flash fades to alpha 0 within 0.2s.
- Smoke: 30 simulated catches don't leak nodes.

**Acceptance**

- [ ] Catching view has visible background + ground; sky color matches `current_max_tier`.
- [ ] Every catch shows scale punch + white flash + existing particles + existing floating gold number.
- [ ] Mistapping shows a transient ripple at tap location.
- [ ] No frame-rate regression (catching view < 4ms/frame on Pixel 4-class emulator).

**Tag.** `phase-10b-complete`. Bump to **v0.10.1**.

---

## Phase 10c — Currency bar redesign

**Item addressed: #4**

**Goal.** [currency_bar.tscn](game/scenes/ui/currency_bar.tscn) currently has zero visual weight. Make currencies feel like resources.

**Files**

- `game/scenes/ui/currency_chip.tscn` + `.gd` — reusable component: rounded StyleBoxFlat, icon + monospace digit Label + ProgressBar for next-milestone hint.
- `game/scenes/ui/currency_bar.tscn` — replace empty PanelContainer with HBox of three `currency_chip` instances.
- `game/scenes/ui/currency_bar.gd` — driving-number tween (Tween, ease-out cubic, 0.4s) instead of jumping.
- `assets/sprites/icons/coin.png`, `rancher_point.png`, `prestige.png` — generated in Phase 10a's prep step (placeholder; easily replaceable).

**Tests**

- `game/tests/test_currency_chip.gd` — driving a value change tweens through intermediate states.
- `game/tests/test_currency_bar.gd` — no leaks on connect/disconnect across re-instantiations.

**Acceptance**

- [ ] Three chips visible, themed, with icon + count + monospace digits.
- [ ] Number changes tween smoothly.
- [ ] Long-tap on a chip shows a tooltip with the BigNumber breakdown.

**Tag.** `phase-10c-complete`. Bump to **v0.10.2**.

---

## Phase 10d — Bestiary card frames

**Item addressed: #6**

**Goal.** [bestiary_view.tscn](game/scenes/bestiary/bestiary_view.tscn) is a list. Make it a Pokédex.

**Files**

- `game/scenes/bestiary/bestiary_card.tscn` + `.gd` — reusable component:
  - 4 slots: silhouette (uncaught), normal, shiny, variant.
  - Slot states: locked / seen / captured / perfected (gold border).
  - StyleBoxFlat parchment fill, brass border.
- `game/scenes/bestiary/bestiary_view.gd` — replace list rendering with `GridContainer` (2 columns on phone / 4 on tablet).
- `game/scenes/bestiary/bestiary_card_detail.tscn` — modal: full sprite, flavor text, drop info, catch counter, Peniber's first-catch line.

**Tests**

- `game/tests/test_bestiary_card.gd` — slot state transitions correctly given GameState fixtures.

**Acceptance**

- [ ] Bestiary tab shows a grid of cards, one per species across all 20 tiers.
- [ ] Tier headers visually distinct (color band: 1–5 brass, 6–10 silver, 11–15 gold, 16–20 obsidian).
- [ ] Tapping a card opens detail modal; closing returns to scroll position.
- [ ] Silhouettes for uncaught species use a `ShaderMaterial` (sample alpha → output black).

**Tag.** `phase-10d-complete`. Bump to **v0.10.3**.

---

## Phase 10e — Battle map

**Item addressed: #7**

**Goal.** Replace the bars-and-numbers battle UI with a side-scrolling visual playback. Pets walk in from the left, monsters from the right, they meet at an engagement point, fight using the existing deterministic [BattleLog](game/systems/battle_system.gd), advance to the next encounter, repeat.

Largest of the five phases — split into two milestones.

### 10e.1 — Battle map foundation

**Files**

- `game/scenes/battle/battle_map.tscn` + `.gd` — root `Node2D` (or `SubViewport` embedded in the existing PanelContainer):
  - `ParallaxBackground` matching catching view's tier-coloring.
  - Tiled ground texture, scrolls to suggest forward motion.
  - `Camera2D` centered on engagement point, slight follow-shake on hits.
- `game/scenes/battle/combatant.tscn` + `.gd` — sprite controller wrapping `AnimatedSprite2D` (or `Sprite2D` + tween-bob if no anim frames yet).
  - States: `WALK`, `IDLE_AT_ENGAGEMENT`, `ATTACK_LUNGE`, `HURT_FLASH`, `DEFEATED_FADE`.
  - Reads visual state from BattleLog frames; does NOT compute combat. Replay only.
- `game/scenes/battle/battle_view.gd` — refactor:
  - Keep state machine (`IDLE` / `BATTLING` / `POST`).
  - Replace `_player_bars`/`_enemy_bars` with `_player_combatants` / `_enemy_combatants`.
  - HP bars become small floating overlays above each combatant.
  - Speed selector and Skip-ad button stay on HUD layer.
- `game/systems/battle_system.gd` — **no algorithm changes**. Existing BattleLog suffices. May add cosmetic frame metadata (`attack_kind: "melee" | "ranged"`) — optional.

**Tests**

- `game/tests/test_battle_view.gd` — same seed → identical sequence of combatant state transitions.
- `game/tests/test_combatant.gd` — state machine transitions on synthetic frames; defeated combatant fades and stops responding.

**Acceptance**

- [ ] "Fight" → pets slide in from off-screen left, monsters from right.
- [ ] Sprites converge at engagement point, exchange lunges synced to BattleLog tick frames.
- [ ] HP bars float above combatants; defeated combatants fade out.
- [ ] Same seed → identical visual sequence (determinism preserved).
- [ ] Speed selector (1×/2×/4×) controls replay rate without breaking determinism.

**Tag.** `phase-10e1-complete`. Bump to **v0.10.4**.

### 10e.2 — Multi-encounter stages

**Files**

- `game/resources/battle_stage_resource.gd` — `id`, `display_name`, `tier`, `encounters: Array[Encounter]` where `Encounter` has `monster_ids` and optional `narrator_line_id`.
- `game/data/battle_stages/*.tres` — one stage per tier band (5 stages for 20 tiers initially).
- `game/systems/battle_system.gd` — extend `simulate(seed, player_team, encounters: Array[Array[MonsterState]]) -> StageLog` where `StageLog.encounters[i]: BattleLog`. Pet HP carries between encounters; team wipe = stage failure.
- `game/scenes/battle/battle_map.gd` — between encounters, scroll camera + ground texture, fade next monster set in.
- `game/scenes/battle/team_select.tscn` + `.gd` — pick which 3 pets to send into the stage.

**Tests**

- `game/tests/test_battle_stage.gd` — same seed → same `StageLog`; HP carry-over correct; team wipe on encounter 2 leaves encounter 3 unsimulated.
- `game/tests/test_battle_system.gd` — existing single-encounter calls still pass.

**Acceptance**

- [ ] "Fight" opens stage selection (per-tier).
- [ ] Pets walk between encounters; camera scrolls; idle pets bob.
- [ ] Stage rewards (RP + drops) emit at stage end with a "Stage cleared" Peniber line.
- [ ] Stage failure restores roster (no permadeath); player back to IDLE.
- [ ] Bestiary "battles fought" stat ticks per encounter, not per stage.

**Tag.** `phase-10e2-complete`. Bump to **v0.10.5**.

---

## Cross-cutting

**Asset gap warning.** Phases 10b/10d/10e all assume placeholder recolors are acceptable (consistent with Phase 5). Without commissioned art the battle map will show 6 wisplet-shaped sprites in different colors fighting each other. That's serviceable but not polished. Real asset commission is out of scope here.

**Determinism guard.** Phase 10e changes the visual layer only. A property-based test in `test_battle_stage.gd` should compare `StageLog` outputs across N seeds before/after the refactor to confirm no regression in the live battle math.

**Headless sim compatibility.** [tests/sim/sim_runner.gd](tests/sim/sim_runner.gd) fast-forwards using `OfflineProgressSystem` and doesn't exercise battle visuals — Phase 10e is sim-neutral.

---

## Out of scope

- Item #8 (commissioned sprite art for tiers 2–20).
- Item #9 (full SFX bank: 8 named SFX from Phase 5 plan).
- Item #10 (Peniber portrait expression variants).

These can be authored independently and dropped into the existing infrastructure once 10a–10e land.
