# IdleBeastPractices — Detailed Implementation Plan

This document expands [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) into a handoff-ready, phase-by-phase build sheet. Where the parent plan says "define analogously" or "compute X", this document gives the actual schema, formula, file list, and test list. The parent plan remains authoritative on scope and pillars; this plan is authoritative on **how**.

Sequencing rule: phases execute in order, each one closes per the per-phase ship loop in §2 before the next begins.

---

## 1. Decisions confirmed (this session, 2026-04-30)

| Decision | Value |
|---|---|
| Godot version | **4.6.1-stable mono** (pinned in `project.godot` and CI; mono build runs GDScript fine — no C# in this project) |
| Repo init | `git init` locally; **public** GitHub remote `IdleBeastPractices` created via `gh repo create` (account `NickSanft`) |
| Phase 0 local export verification | Windows + Web + Android debug APK, all on this Win11 box |
| Planning depth | All six phases expanded up front (this document) |

**Local toolchain status (verified 2026-04-30):**

| Component | Status |
|---|---|
| Godot 4.6.1-stable mono | ✓ at `C:/Users/nicho/Desktop/Godot_v4.6.1-stable_mono_win64/` |
| Export templates `4.6.1.stable.mono` | ✓ |
| JDK | Corretto 25 + 26 installed; **plan: try JDK 25 first**, install JDK 17 only if Godot's Gradle wrapper fails |
| Android SDK | ✓ at `C:/Users/nicho/AppData/Local/Android/Sdk` — build-tools 34/35/36/36.1, platforms 34/35/36 |
| Android NDK | ✓ `30.0.14904198` (newer than the r23c historically referenced in Godot docs; verify at first Android export — Godot 4.6 generally supports modern NDKs) |
| AVDs | ✓ `Medium_Phone`, `Medium_Phone_2`, `Medium_Tablet` |
| `ANDROID_HOME` env var | Unset; will be configured in Godot Editor Settings → Export → Android instead of as a system var |
| `gh` CLI | ✓ authenticated as `NickSanft` |

---

## 2. Per-phase ship loop (meta-process)

Adapted from the `feedback_phase_workflow` memory. Every phase ends with this loop run cleanly:

1. **Implement** the phase scope, no scope creep.
2. **Tests** — GUT unit tests for everything in `game/systems/`, plus scene smoke tests (instantiate, assert no `_ready()` errors). Skip e2e where unit coverage is exhaustive; document the skip in the phase's CHANGELOG entry.
3. **Pre-push checklist — all green before push:**
   - `godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://game/tests/` exits 0
   - `godot --headless --path . --check-only` (parse-check) exits 0
   - All three exports succeed locally (Windows EXE, Web HTML5, Android debug APK)
   - No errors in Godot's debugger panel when running `main.tscn`
4. **Commit** with HEREDOC, multi-line message, ending with the `Co-Authored-By` line.
5. **Push** to `main`.
6. **Watch CI in the background** via `gh run watch <id> --exit-status` plus `ScheduleWakeup` so the conversation stays unblocked.
7. **Tag annotated `phase-N-complete`** ONLY after CI is green. Never tag before CI confirms.
8. **CHANGELOG.md entry** per phase: Added · Why it matters · Architecture · UX details · Tests · Pre-push checklist results.
9. **Roll into the next phase** without prompting.

---

## 3. Resource schemas not specified in the parent plan

These are marked "define analogously" in [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) §4.3. They land in Phase 0 as schema-only (with a single example `.tres` per type as a smoke test).

### 3.1 `NetResource` — `game/resources/net_resource.gd`

```gdscript
class_name NetResource extends Resource
@export var id: StringName
@export var display_name: String
@export var sprite: Texture2D
@export var description: String
@export var tier_required: int = 1                 # Min tier to unlock purchase
@export var cost: Dictionary                       # BigNumber dict {"m": .., "e": ..}
@export var catches_per_second: float = 0.5        # Base auto-catch rate
@export var catch_speed_multiplier: float = 1.0    # Multiplies tap-catch progress
@export var spawn_max: int = 3                     # Concurrent monsters allowed on screen
@export var targets_tiers: Array[int] = [1]        # Which tiers this net hunts
@export var sfx_catch: AudioStream                 # Optional override; nil falls back to default
```

### 3.2 `ItemResource` — `game/resources/item_resource.gd`

```gdscript
class_name ItemResource extends Resource
enum Category { DROP, MATERIAL, CONSUMABLE }

@export var id: StringName
@export var display_name: String
@export var sprite: Texture2D
@export var description: String
@export var category: Category = Category.DROP
@export var stack_max: int = 9_999_999             # Hard cap before BigNumber-backing kicks in (post-1.0)
@export var sell_value: Dictionary                 # BigNumber dict, gold per unit
@export var flavor_text: String                    # Bestiary / tooltip
```

### 3.3 `UpgradeResource` — `game/resources/upgrade_resource.gd`

```gdscript
class_name UpgradeResource extends Resource
enum Currency { GOLD, RANCHER_POINTS }

@export var id: StringName
@export var display_name: String
@export var sprite: Texture2D
@export var description: String
@export var effect_id: StringName                  # Hook name in UpgradeEffectsSystem
@export var magnitude: float = 1.0                 # Effect-defined; e.g. multiplier delta
@export var cost: Dictionary                       # BigNumber dict
@export var cost_currency: Currency = Currency.GOLD
@export var cost_growth: float = 1.5               # Multiplied per level for repeatable upgrades
@export var max_level: int = 1                     # 1 = one-shot purchase
@export var prereq_ids: Array[StringName] = []
@export var tier_required: int = 1
@export var persists_through_prestige: bool = false
```

### 3.4 `CraftingRecipeResource` — `game/resources/crafting_recipe_resource.gd`

```gdscript
class_name CraftingRecipeResource extends Resource

@export var id: StringName
@export var display_name: String
@export var sprite: Texture2D
@export var description: String
@export var inputs: Array[Dictionary] = []         # [{"item_id": StringName, "amount": int}, ...]
@export var output_item: ItemResource              # Mutually exclusive with output_net
@export var output_net: NetResource
@export var output_amount: int = 1
@export var gold_cost: Dictionary                  # BigNumber dict; can be zero
@export var prereq_recipe_ids: Array[StringName] = []
@export var tier_required: int = 1
@export var duration_seconds: float = 0.0          # 0 = instant; >0 reserved for queued crafts post-1.0
```

### 3.5 `DialogueLineResource` — `game/resources/dialogue_line_resource.gd`

```gdscript
class_name DialogueLineResource extends Resource

@export var id: StringName
@export var trigger_id: StringName                 # See §8 of parent plan
@export var text: String
@export var mood: StringName = &"smug"             # smug | exasperated | begrudging | reverent | weary
@export var weight: float = 1.0
@export var max_uses: int = 0                      # 0 = unlimited
@export var min_total_catches: int = 0
@export var min_prestige_count: int = 0
@export var conditions: Dictionary = {}            # Free-form for future extension
```

---

## 4. BigNumber — concrete algorithm

Mantissa/exponent representation. Invariants:
- `mantissa == 0.0` AND `exponent == 0` represents zero.
- For nonzero values: `1.0 <= abs(mantissa) < 10.0`.
- `exponent` is an `int` (Godot int is 64-bit signed; ample range).

Normalization (`_normalize()`) runs after every mutation:
- If `mantissa == 0.0`, force `exponent = 0` and return.
- While `abs(mantissa) >= 10.0`: divide mantissa by 10, increment exponent.
- While `abs(mantissa) < 1.0`: multiply mantissa by 10, decrement exponent.

Operations:
- **add(b)**: align by raising the smaller exponent to match the larger (cap shift at 16; beyond that, the smaller term is negligible at float precision and is dropped). Sum mantissas after shift, normalize.
- **subtract(b)**: same, with sign handling. Underflow to zero when mantissa cancels.
- **multiply(b)**: `m1*m2`, `e1+e2`, normalize.
- **multiply_float(f)**: `m*f`, exponent unchanged, normalize.
- **divide(b)**: division by zero returns zero AND emits a `push_error` (caught by tests). Otherwise `m1/m2`, `e1-e2`, normalize.
- **pow_int(n)**: integer exponentiation by repeated squaring. Negative `n` divides one by the result.
- **compare(b)**: zero handling first, then exponent compare, then mantissa compare. Sign-aware.

Suffix table (used by `format()`):

```
e<3   → no suffix, 2 decimals
e3    → "K"
e6    → "M"
e9    → "B"
e12   → "T"
e15   → "Qa"
e18   → "Qi"
e21   → "Sx"
e24   → "Sp"
e27   → "Oc"
e30   → "No"
e33   → "Dc"
e36+  → letter pairs: aa, ab, ac, ..., az, ba, bb, ... (each step = ×1000)
```

Letter-pair generation: `e36` = "aa", `e39` = "ab", ..., `e36 + (26*i + j) * 3` = letter[i] letter[j]. Wraps cleanly past `zz`.

**Phase 0 tests (`test_big_number.gd`)** — at least:
1. `from_float`/`to_dict`/`from_dict` round-trip preserves value within float epsilon.
2. `add` with mixed exponents: `1e3 + 1e0 == 1001`.
3. `add` with massive exponent gap returns the larger unchanged.
4. `multiply` overflow: `1e100 * 1e100` → exponent ≈ 200, mantissa normalized.
5. `subtract` to zero: `5 - 5` returns canonical zero (m=0, e=0).
6. `compare` covers six branches (a<b, a>b, a==b for both signs, zero on either side).
7. `divide_by_zero` returns zero and pushes an error.
8. `pow_int(0)` returns one; `pow_int(-2)` returns reciprocal squared.
9. `format()` matches expected strings for `999`, `1000`, `1.23e6`, `1.23e36` (= "1.23aa"), `1.23e39` (= "1.23ab").

---

## 5. System algorithms — concrete

### 5.1 `CatchingSystem`

```
spawn_schedule(state) -> Array[MonsterResource]
  - Active tiers = [1 .. state.current_max_tier]
  - For the active net's targets_tiers ∩ active_tiers, weighted-pick up to (active_net.spawn_max - currently_on_screen) monsters.
  - Weight = MonsterResource.spawn_weight × (1.0 / tier) so lower tiers hum more often by default; balanced per-tier in §6.

resolve_tap(state, monster_instance) -> CatchOutcome
  - tap_progress += 1.0 × upgrade_multiplier("tap_speed")
  - If tap_progress >= base_catch_difficulty, monster is caught; emit `monster_caught` (source="tap")
  - Drops: random integer in [drop_amount_min, drop_amount_max] × upgrade_multiplier("drop_amount")
  - Gold: monster.tier-keyed base × upgrade_multiplier("gold_mult"); BigNumber.
  - Shiny roll: rng.randf() < shiny_rate × upgrade_multiplier("shiny_rate")

resolve_auto(state, dt) -> Array[CatchOutcome]
  - per_second = active_net.catches_per_second × upgrade_multiplier("auto_speed")
  - Accumulate fractional progress; while progress >= 1, pop a catch from the spawn pool.
```

### 5.2 `OfflineProgressSystem`

```
compute(state, elapsed_seconds) -> Dictionary
  - elapsed = clamp(elapsed_seconds, 0, 3600 × upgrade_multiplier("offline_cap"))
  - per_second = active_net.catches_per_second × all_relevant_multipliers
  - expected_catches = per_second × elapsed
  - Per spawnable species, distribute expected_catches by spawn_weight.
  - Per species:
      * normal_catches = round(expected_per_species × (1 - shiny_rate_eff))
      * Shiny count uses a normal approximation to Poisson:
          λ = expected_per_species × shiny_rate_eff
          shiny_catches = max(0, round(λ + sqrt(λ) × rng.randfn()))   # randfn = standard-normal sample
      * items_gained += normal_catches × avg(drop_min, drop_max)
      * gold_gained += normal_catches × per-tier-gold-base BigNumber
  - Return {seconds, catches_by_species, items_gained, gold_gained, shinies_caught}

Anti-cheat: TimeManager records last_save_unix. On resume:
  - now < last_save_unix         → elapsed = 0, log warning, set 'clock_warning' flag in state
  - 0 ≤ delta ≤ 3600 × cap_mult  → credit normally
  - delta > cap                  → credit cap, store leftover in 'untracked_idle_seconds' (display only, never refunded)
```

### 5.3 `BattleSystem`

Deterministic, seeded RNG (`RandomNumberGenerator` with explicit `seed`). Turn-based, fixed tick rate.

```
simulate(seed, player_team, enemy_team) -> BattleLog

State per combatant: {hp, atk, def, ability_id, ability_cooldown, status_effects[]}
Tick = 0.25 seconds of in-game time. Battle caps at 600 ticks (= 2.5 minutes); draw if cap hit.

Per tick:
  1. Status effect ticking (DOTs apply, cooldowns decrement).
  2. Each living combatant in initiative order (player first, then enemy; within team, by index):
     - If ability ready, fire ability via the AbilityRegistry hook (see below).
     - Else basic attack: damage = max(1, attacker.atk - target.def), with rng.randf() ∈ [0.85, 1.15] variance.
     - target.hp -= damage. Emit a frame {tick, actor, target, action, damage, hp_remaining, status_changes}.
  3. KO check: if a side has zero living combatants, end battle with the other side winning.

AbilityRegistry: a static dictionary {StringName -> Callable(caster, allies, enemies, log) -> void}. Phase 2 ships with 3 starter abilities ('strike', 'shield', 'heal') so the framework is exercised; per-pet abilities are added as content in Phase 5.

Reward computation (winning side): rancher_points = floor(sum(enemy.tier) × upgrade_multiplier("rp_mult")).
```

`BattleLog` is `Array[Dictionary]`. UI subscribes to `battle_tick` and renders each frame at a configurable speed (default 4 ticks/sec visible). Leaving the screen does NOT advance the simulation — it's already simulated; the UI is replay only.

### 5.4 `UpgradeEffectsSystem`

```
get_multiplier(effect_id: StringName) -> float
  - Aggregates over all purchased upgrades whose effect_id matches.
  - Composition rule per effect_id:
      additive_effects = ["tap_speed", "auto_speed", "shiny_rate"]   # multiplier = 1.0 + sum(magnitudes × levels)
      multiplicative_effects = ["gold_mult", "drop_amount", "rp_mult", "offline_cap"]   # multiplier = product(1 + magnitude)^level
  - Final value clamped to [1.0, 1e9] to prevent BigNumber-formula explosions.

invalidate() -> void
  - Called on `upgrade_purchased` and `prestige_triggered`. Clears a cached multiplier dictionary.
```

---

## 6. Tier 1–3 content seed

Sprite sheets in `assets/sprites/`: `wisplet.png`, `centiphantom.png`. Tier 3 placeholder uses a tinted recolor of the wisplet sheet until art lands.

| Tier | Species | id | Drop item | Drop range | Gold base | Catch difficulty | Shiny rate |
|---|---|---|---|---|---|---|---|
| 1 | Green Wisplet | `green_wisplet` | `wisplet_ectoplasm` | 1–2 | 1 | 1.0 | 0.05 |
| 1 | Red Wisplet | `red_wisplet` | `wisplet_ectoplasm` | 1–3 | 2 | 1.2 | 0.05 |
| 1 | Blue Wisplet | `blue_wisplet` | `wisplet_ectoplasm` | 1–2 | 3 | 1.5 | 0.05 |
| 2 | Dust Centiphantom | `dust_centiphantom` | `centiphantom_jelly` | 1–2 | 12 | 4.0 | 0.04 |
| 2 | Dawn Centiphantom | `dawn_centiphantom` | `centiphantom_jelly` | 2–3 | 18 | 5.0 | 0.04 |
| 2 | Dusk Centiphantom | `dusk_centiphantom` | `centiphantom_jelly` | 2–4 | 24 | 6.0 | 0.04 |
| 3 | Bramble Hush | `bramble_hush` | `hush_pollen` | 1–2 | 80 | 12.0 | 0.03 |
| 3 | Hollow Hush | `hollow_hush` | `hush_pollen` | 1–3 | 110 | 14.0 | 0.03 |
| 3 | Glowmoth Hush | `glowmoth_hush` | `hush_pollen` | 1–3 | 150 | 17.0 | 0.03 |

Tier-completion gate: capture all three species at least once **AND** capture ≥25 of any species in the tier.

Net seed:
- `basic_net` — cost `100 gold`, `catches_per_second = 0.5`, `spawn_max = 3`, targets `[1]`.
- `tier2_net` (Phase 4 craftable) — cost `5000 gold + 50 wisplet_ectoplasm`, `catches_per_second = 0.8`, targets `[1,2]`.
- `tier3_net` (Phase 4 craftable) — cost `50_000 gold + 200 centiphantom_jelly`, `catches_per_second = 1.2`, targets `[2,3]`.

Phase 5 bulk-authors tiers 4–20 with placeholder sprites (recolors) and a continuation of the curve `gold_base = round(prev_gold_base × 6.5)`, `catch_difficulty = round(prev × 2.8, 1)`.

---

## 7. Phase 0 — Foundation (file-by-file task plan)

Total: ~28 files. Estimated 1 commit-cycle, possibly two if Android tooling needs install time.

### 7.1 Task ordering

1. **Repo scaffolding**
   - `git init`
   - `.gitignore` (Godot defaults: `.godot/`, `.import/`, `*.translation`, `export.cfg`, `export_credentials.cfg`, plus `/exports/`, `*.keystore`, `/.godot-cache/`)
   - `.gitattributes` (LFS for `*.png`, `*.jpg`, `*.wav`, `*.ogg`, `*.mp3`, `*.tres`-binary cases)
   - `README.md` — single section, Godot 4.5 stable line, build instructions
   - `CHANGELOG.md` — `## [Unreleased]` placeholder with Phase 0 entry stub

2. **Godot project skeleton**
   - `project.godot` — name `IdleBeastPractices`, run/main_scene `res://game/scenes/main.tscn`, autoloads stub-registered in load order, **Godot 4.5 features bit set**
   - `icon.svg` — placeholder (Godot's default copied in)
   - `addons/gut/` — vendor [GUT v9](https://github.com/bitwes/Gut) (last 4.x-compatible release as of cutoff)

3. **Resource schemas (Phase 0 gets all of them; instances added as later phases need)**
   - `game/resources/monster_resource.gd`
   - `game/resources/pet_resource.gd`
   - `game/resources/net_resource.gd`
   - `game/resources/item_resource.gd`
   - `game/resources/upgrade_resource.gd`
   - `game/resources/crafting_recipe_resource.gd`
   - `game/resources/dialogue_line_resource.gd`

4. **BigNumber and tests** (do this *first* among logic; everything currency depends on it)
   - `game/systems/big_number.gd` — full implementation per §4
   - `game/tests/test_big_number.gd` — 9+ assertions per §4
   - Run GUT, confirm green.

5. **Save framework**
   - `game/systems/save_backend.gd` — abstract base (per parent §5.3)
   - `game/systems/local_file_backend.gd` — atomic write to `user://save.json` via `.tmp` + rename
   - `game/systems/save_migrations.gd` — registry: `[{from_version: 0, fn: Callable}]` initially empty, plus a no-op v0→v1 used by the test fixture
   - `game/autoloads/save_manager.gd` — `load_save()`, `save(state)`, applies migration chain, validates `version <= CURRENT_VERSION`, atomic write
   - `game/tests/test_save_migration.gd` — fixture v0 dict → migrated → asserts shape matches v1 expectation

6. **Autoloads with full EventBus catalog**
   - `game/autoloads/event_bus.gd` — every signal from parent §4.2, no logic
   - `game/autoloads/settings.gd` — preferences scaffolding (audio_master_db, sfx_db, music_db, reduce_motion, font_scale)
   - `game/autoloads/time_manager.gd` — `now_unix()`, `last_save_unix`, anti-cheat warning flag, offline-elapsed calc
   - `game/autoloads/game_state.gd` — Dictionary-of-truth: currencies, inventory, monsters_caught, etc. Mirrors the §5.1 save schema 1:1. `to_dict()` / `from_dict()` for save round-trip.
   - `game/autoloads/audio_manager.gd` — stub that subscribes to relevant `EventBus` signals; logs to console for now
   - `game/autoloads/narrator.gd` — stub: subscribes to triggers, picks a placeholder `"[Peniber says nothing yet]"` line, emits `narrator_line_chosen`

   Register all of these in `project.godot` `[autoload]` block in this exact order:
   `Settings → EventBus → SaveManager → TimeManager → GameState → AudioManager → Narrator`

7. **Main scene**
   - `game/scenes/main.tscn` — Control root with a CenterContainer + Label "Critterancher (placeholder)"
   - `game/scenes/main.gd` — calls `SaveManager.load_save()` on `_ready()`, hooks `WM_CLOSE_REQUEST` to call `SaveManager.save(GameState.to_dict())`

8. **Integration smoke test**
   - `game/tests/test_save_round_trip.gd` — populate GameState fixture, save, clear, load, assert equality

9. **CI/CD**
   - `.github/workflows/build.yml` — jobs: `test`, `build-windows`, `build-web`, `build-android-debug`. Pinned `barichello/godot-ci:4.6.1` Docker image. Artifact upload per job.
   - `.github/workflows/release.yml` — on `v*` tag: same jobs + `build-android-release` (signed AAB from secrets), `gh release create` with all artifacts attached.
   - `export_presets.cfg` — three presets (Windows Desktop, Web, Android), no secrets in the file (those come from CI env).

10. **ADRs (MADR format)**
    - `docs/adr/0001-engine-godot.md` — engine choice
    - `docs/adr/0002-language-gdscript.md`
    - `docs/adr/0003-content-as-resources.md`
    - `docs/adr/0004-save-format-versioned-json.md`
    - `docs/adr/0005-bignumber-mantissa-exponent.md`
    - `docs/adr/0006-deterministic-battle-sim.md`
    - `docs/adr/0007-android-first-then-windows-web.md`

11. **Local export verification**
    - Windows EXE → run, confirm placeholder visible, close cleanly.
    - Web export → `godot --export-debug Web exports/web/index.html`, serve via Python `http.server`, open in browser.
    - Android debug APK → `godot --export-debug Android exports/android/debug.apk`, `adb install -r exports/android/debug.apk`, launch, confirm placeholder.

12. **Phase 0 ship loop:** GUT green, all three exports succeed, commit, push, watch CI, tag `phase-0-complete` on green.

### 7.2 Phase 0 acceptance (must all be true)

- [ ] `godot --headless ... gut_cmdln.gd` → exits 0 in CI
- [ ] BigNumber 9+ tests pass
- [ ] Save migration test passes (fake v0 → migrated → v1 shape)
- [ ] Save round-trip test passes (populated state → disk → loaded → equal)
- [ ] Windows export runs locally, shows placeholder
- [ ] Web export runs locally in a browser
- [ ] Android debug APK installs and launches on AVD or device
- [ ] All seven ADRs exist and are committed
- [ ] `CHANGELOG.md` Phase 0 entry filled in
- [ ] CI green on `main`, tag `phase-0-complete` pushed

---

## 8. Phase 1 — MVP catch loop (file-level plan)

### 8.1 Files

**Scenes**
- `game/scenes/main.tscn` (upgraded) — three-tab layout: Catch · Inventory · Shop. `TabContainer`-based; tab visibility gated on `current_max_tier`/`gold` to keep it minimal at start.
- `game/scenes/catching/catching_view.tscn` (+ `.gd`) — root `Control`, contains a `MonsterSpawner` (script-only Node), `MonsterInstance` children, currency bar overlay.
- `game/scenes/catching/monster_instance.tscn` (+ `.gd`) — `Sprite2D` + `Area2D`, simple wander state machine, `pressed` signal on tap.
- `game/scenes/ui/inventory_panel.tscn` — scrollable list of `ItemRow`s (icon, name, count).
- `game/scenes/ui/currency_bar.tscn` — gold (BigNumber-formatted) + RP placeholder (hidden until Phase 2).
- `game/scenes/ui/net_shop.tscn` — list of nets; "Buy" button gated on cost.
- `game/scenes/ui/welcome_back_dialog.tscn` — modal showing `OfflineProgressSystem` summary; "Claim" button.

**Systems**
- `game/systems/catching_system.gd` — per §5.1
- `game/systems/offline_progress_system.gd` — per §5.2

**Content**
- 9 `MonsterResource` `.tres` (3 per tier 1–3) per §6 table.
- 3 `ItemResource` `.tres` (`wisplet_ectoplasm`, `centiphantom_jelly`, `hush_pollen`).
- 1 `NetResource` `.tres` (`basic_net`).

**Tests**
- `game/tests/test_catching_system.gd` — spawn weighting, tap resolution, drop ranges, shiny RNG seeded.
- `game/tests/test_offline_progress.gd` — cap enforcement, distribution by spawn weight, anti-cheat zero-credit on past clock.

### 8.2 Phase 1 acceptance

- [ ] Tap → catch → SFX + inventory increment + gold awarded; verifiable in 30 seconds of play
- [ ] Buying `basic_net` enables auto-catch at the configured rate
- [ ] Closing the game and returning >1 minute later shows the welcome-back dialog with non-zero rewards
- [ ] All three tiers reachable in a 20-minute play session (manual verification, recorded in CHANGELOG)
- [ ] Coverage threshold set in CI (proposed: ≥75% on `game/systems/`)

---

## 9. Phase 2 — Pets & battles

### 9.1 Files

**Scenes**
- `game/scenes/battle/battle_view.tscn` (+ `.gd`) — fixed-camera arena, sprite slots for 3v3, frame replay loop, "speed up" button (1×/2×/4×).
- `game/scenes/battle/team_select.tscn` (+ `.gd`) — drag-from-roster onto 3 player slots.
- `game/scenes/ui/upgrade_tree.tscn` — flat list for now (visual tree deferred to Phase 5 polish).

**Systems**
- `game/systems/battle_system.gd` — per §5.3
- `game/systems/upgrade_effects_system.gd` — per §5.4
- `game/systems/ability_registry.gd` — three abilities: `strike` (1.5× damage, 4-tick cooldown), `shield` (+50% def for 8 ticks, 12-tick cooldown), `heal` (+25% max hp on lowest ally, 16-tick cooldown).

**Content**
- 3 `PetResource` `.tres` (one per tier-1 species; ability_id = `strike`).
- 5 `UpgradeResource` `.tres`: `catch_speed_1` (`tap_speed`, +20%), `gold_mult_1` (×1.25), `drop_amount_1` (×1.5), `shiny_rate_1` (+25%), `offline_cap_1` (×2 → 2 hours).

**Tests**
- `game/tests/test_battle_system.gd` — same-seed determinism (byte-equal log), different-seed divergence, instant KO, 600-tick draw, ability cooldowns respected.
- `game/tests/test_upgrade_effects.gd` — additive vs multiplicative composition, clamp upper bound, invalidation on prestige.

### 9.2 Phase 2 acceptance

- [ ] Completing tier 1 emits `pet_acquired`; pet shows in roster
- [ ] Battle plays a deterministic log; same seed twice = identical replay
- [ ] Battle wins emit `rancher_points_earned`; RP visible in currency bar
- [ ] Upgrade purchase persists across save/load
- [ ] Determinism test runs in CI

---

## 10. Phase 3 — Prestige

### 10.1 Files

**Scenes**
- `game/scenes/prestige/prestige_view.tscn` (+ `.gd`) — preview pane (current tier, projected RP), confirm button, second confirm modal ("Reset everything except upgrades?").

**Systems**
- `game/systems/prestige_system.gd` — `compute_rp_gain(state) -> int = floor(sqrt(total_gold_earned_this_run / 1e6))`, `perform_reset(state) -> state'` that zeroes currencies/inventory/current_max_tier/tiers_completed/current_battle but preserves upgrades-flagged-`persists_through_prestige`, pets_owned, pet_variants_owned, monsters_caught, ledger.prestige_count++, ledger totals.

**Content**
- 4 `UpgradeResource` `.tres` flagged `persists_through_prestige=true`, costed in RP: `prestige_gold_mult` (×1.5/level, max 10), `prestige_starting_net` (begin run with `basic_net`, max 1), `prestige_offline_cap` (+1 hour/level, max 5), `prestige_rp_mult` (×1.25/level, max 5).

**Tests**
- `game/tests/test_prestige_system.gd` — RP formula, preserved fields untouched, reset fields zeroed, `prestige_count` increments, idempotent if invoked twice via guard.

### 10.2 Phase 3 acceptance

- [ ] Preview shows projected RP correctly
- [ ] Reset preserves upgrades, pets, bestiary, prestige_count, ledger; zeroes the rest
- [ ] RP from prestige is additive to RP from battles in the bar
- [ ] Save round-trip test extended to cover prestige fields

---

## 11. Phase 4 — Bestiary, shinies, crafting

### 11.1 Files

**Scenes**
- `game/scenes/bestiary/bestiary_view.tscn` — grid of species cards: normal/shiny/variant slots, count, flavor text, "??? Not yet caught" for unknowns.
- `game/scenes/crafting/crafting_view.tscn` — recipe list, requirement check, craft button, output preview.

**Systems**
- `game/systems/crafting_system.gd` — `can_craft(state, recipe) -> bool`, `craft(state, recipe) -> state'` (consume inputs, produce outputs, emit `item_crafted`).
- Update `CatchingSystem` to write shiny flag to `monsters_caught[id].shiny`.
- Update tier-completion flow to roll variant on pet award (independent rate; emit `pet_acquired(..., is_variant=true)`).

**Content**
- 5 `CraftingRecipeResource` `.tres`:
  - `recipe_tier2_net` → outputs `tier2_net`
  - `recipe_tier3_net` → outputs `tier3_net`
  - `recipe_tier4_net` (placeholder, gated to tier 4) → outputs a future net
  - `recipe_pet_collar` → outputs `pet_collar` item granting +10% atk in battle
  - `recipe_shiny_lure` → outputs `shiny_lure` consumable, +50% shiny rate for 60s

**Tests**
- `game/tests/test_crafting_system.gd` — input check, prereq gate, tier gate, output produced, gold cost deducted (BigNumber), error path on insufficient inputs.

### 11.2 Phase 4 acceptance

- [ ] Bestiary populates as species are caught; shiny + variant slots fill independently
- [ ] Shiny rate ≈ 5% on tier 1 (statistical check in CI: 10000 simulated catches, 95% CI overlaps 5%)
- [ ] Pet variant rolls fire on tier completion at the configured rate
- [ ] Crafting consumes inputs, produces outputs, persists across save

---

## 12. Phase 5 — Peniber & polish

### 12.1 Files

**Autoloads**
- `game/autoloads/narrator.gd` (full impl): subscribes to all triggers in parent §8 table, filter-by-conditions, weighted-random with sliding-window-of-5 anti-clustering, emits `narrator_line_chosen`. Persists `narrator_state.lines_seen` and `last_line_unix` to save.

**Scenes**
- `game/scenes/ui/narrator_overlay.tscn` — Peniber portrait + text bubble + tap-to-dismiss; idle-fades after 8 seconds.
- `game/scenes/ledger/ledger_view.tscn` — Peniber-editorialized labels for every stat in `state.ledger`.

**Content**
- `game/data/dialogue/*.tres` — ≥150 lines per parent §8 distribution. Voice guide drives all writing.
- 17 tiers of monsters/pets/nets seeded with placeholder sprites (recolors) and the curve in §6.

**Polish**
- Catch particles (`CPUParticles2D` burst on tap-catch).
- Screen shake on tier-up (Camera2D offset noise, 0.3s).
- Floating gold-gain numbers (`Label` tween, fades over 1s).
- SFX: tap, catch, shiny catch, tier-up, pet acquired, prestige, battle hit, battle win.
- Difficulty curve QA pass — log a fresh-start playthrough to tier 5, confirm it pacing-feels right (in CHANGELOG).

**Docs**
- `docs/peniber-voice.md` — voice guide: vocabulary list, sample lines per mood, "do/don't" examples, full title rule.

**Tests**
- `game/tests/test_narrator.gd` — trigger filtering, max_uses respected, sliding window prevents repeats, condition gating works.

### 12.2 Phase 5 acceptance

- [ ] Peniber comments on first species catch, 100/1000/10000 milestones, first shiny, tier completion, prestige, idle, offline return
- [ ] Ledger tab shows all stats with editorialized labels
- [ ] All 20 tiers reachable end-to-end (manual playthrough log in CHANGELOG); no runtime errors
- [ ] Polish pass visible in a 60-second screen capture

---

## 13. Phase 6 — Android & ads

### 13.1 Files

- `addons/admob/` — Poing Studios AdMob plugin, vendor specific version (pin in README)
- `game/autoloads/ads_manager.gd` — interface (`show_rewarded(reward_id, on_completed: Callable)`) + AdMob impl. Stub backend in editor.
- `.github/workflows/release.yml` — extended for signed AAB build via `ANDROID_KEYSTORE_BASE64` etc.
- `docs/android-emulator.md` — AVD setup, `adb install`, keystore generation (`keytool -genkey ...`), Play Console internal track upload steps.

### 13.2 Ad placements (strict)

Rewarded video, all optional, no gameplay gated:
- Welcome-back dialog: "Watch ad for 2× offline catches"
- Battle screen: "Watch ad for instant finish"
- Catch view: "Watch ad for 2× drops, next 10 catches"

**Test ad unit IDs** in dev builds (Google's documented test IDs); production IDs via `ADMOB_APP_ID` / `ADMOB_REWARDED_UNIT_ID` GitHub Secrets only.

### 13.3 Phase 6 acceptance

- [ ] Tag push triggers `release.yml` and produces a signed AAB
- [ ] Rewarded video plays on a real Android device, grants its reward exactly once per view
- [ ] Play Store internal track upload documented in `docs/android-emulator.md`
- [ ] No gameplay locked behind any ad

---

## 14. CI/CD workflow shapes (concrete)

### 14.1 `.github/workflows/build.yml`

```yaml
name: Build
on:
  push:
    branches: [main]
  pull_request:
jobs:
  test:
    runs-on: ubuntu-latest
    container: barichello/godot-ci:4.6.1
    steps:
      - uses: actions/checkout@v4
        with: { lfs: true }
      - run: godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://game/tests/ -gexit
  build-windows:
    needs: test
    runs-on: ubuntu-latest
    container: barichello/godot-ci:4.6.1
    steps:
      - uses: actions/checkout@v4
        with: { lfs: true }
      - run: |
          mkdir -p exports/windows
          godot --headless --export-debug "Windows Desktop" exports/windows/game.exe
      - uses: actions/upload-artifact@v4
        with: { name: windows-build, path: exports/windows }
  build-web:
    needs: test
    runs-on: ubuntu-latest
    container: barichello/godot-ci:4.6.1
    steps:
      - uses: actions/checkout@v4
        with: { lfs: true }
      - run: |
          mkdir -p exports/web
          godot --headless --export-debug "Web" exports/web/index.html
      - uses: actions/upload-artifact@v4
        with: { name: web-build, path: exports/web }
  build-android-debug:
    needs: test
    runs-on: ubuntu-latest
    container: barichello/godot-ci:4.6.1
    steps:
      - uses: actions/checkout@v4
        with: { lfs: true }
      - run: |
          mkdir -p exports/android
          godot --headless --export-debug "Android" exports/android/game-debug.apk
      - uses: actions/upload-artifact@v4
        with: { name: android-debug, path: exports/android }
```

### 14.2 `.github/workflows/release.yml`

Triggered on `v*` tag push. Same four jobs as `build.yml`, plus:

```yaml
  build-android-release:
    needs: test
    runs-on: ubuntu-latest
    container: barichello/godot-ci:4.6.1
    env:
      ANDROID_KEYSTORE_BASE64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
      ANDROID_KEYSTORE_PASSWORD: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
      ANDROID_KEY_ALIAS: ${{ secrets.ANDROID_KEY_ALIAS }}
      ANDROID_KEY_PASSWORD: ${{ secrets.ANDROID_KEY_PASSWORD }}
    steps:
      - uses: actions/checkout@v4
        with: { lfs: true }
      - name: Decode keystore
        run: echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > release.keystore
      - run: |
          mkdir -p exports/android
          godot --headless --export-release "Android" exports/android/game-release.aab
      - uses: actions/upload-artifact@v4
        with: { name: android-release, path: exports/android }
  release:
    needs: [build-windows, build-web, build-android-debug, build-android-release]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
      - run: gh release create ${{ github.ref_name }} ./*-build/* ./android-*/*
        env: { GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }} }
```

---

## 15. Testing strategy (cross-phase)

| Layer | Tool | Phase introduced | Notes |
|---|---|---|---|
| Unit (systems) | GUT | Phase 0 | ≥80% on `game/systems/`; 75% threshold enforced from end of Phase 1 |
| Save migrations | GUT | Phase 0 | Fixture-based; one fixture per historical version |
| Battle determinism | GUT | Phase 2 | Byte-equal `BattleLog` for same seed |
| Scene smoke | GUT | Phase 1 | Instantiate every `.tscn`, assert no `_ready()` errors |
| Statistical | GUT | Phase 4 | Shiny-rate confidence intervals; runs longer (parallel CI job optional) |
| Manual playthrough | Human | Phase 1, 5 | Logged in CHANGELOG; unblocks tag |

---

## 16. Risks layered onto the parent plan's §12

| Risk | New mitigation in this plan |
|---|---|
| Android tooling install consumes a full session before any code lands | Phase 0 starts with a "toolchain check" task; if any of JDK 17 / SDK / NDK / templates is missing, that's a sub-phase 0a we close before BigNumber |
| Resource churn on schema changes pre-1.0 | All `.tres` files reviewed during Phase 5 freeze; save format v1 locked at Phase 1 ship; later schema edits require a v2 migration even if internal-only |
| BigNumber float-precision drift in long sessions | All currency math goes through BigNumber; floats banned in `game/systems/` for currency-typed values (lint/grep check in CI: `grep -r "var gold.*: float" game/systems/` must return zero) |
| Battle log grows large in memory for long fights | 600-tick cap (= 2.5 min real time) per battle hard-stops; battles longer than that resolve as draws |
| Peniber lines drift in voice as 150 are written | All Phase 5 lines authored in one sitting against `docs/peniber-voice.md`; spot-check 10% during Phase 5 review |

---

## 17. Out of scope (additive to parent §13)

- **Telemetry / analytics** — not built in any phase; player privacy default.
- **In-app purchases** — explicitly out (parent plan).
- **Debug menu / cheats** — Phase 5 may add a behind-flag dev console for manual playthrough QA, but it's not user-facing.
- **Save export/import UI** — file lives at `user://save.json`, advanced users can copy it; no in-game UI for it pre-1.0.

---

## 18. First commands when execution begins

When approved, Phase 0 starts here:

1. Toolchain verified (§1) — Godot 4.6.1-stable-mono, NDK 30, JDK 25 (will fall back to 17 if Gradle fails), AVDs ready.
2. `git init` + write `.gitignore` / `.gitattributes` / `README.md` / `CHANGELOG.md`.
3. Create `project.godot` with autoloads + Godot 4.6.1 features bit.
4. Vendor GUT into `addons/gut/`.
5. Implement BigNumber + tests; run GUT green.
6. Implement save framework + migration test + round-trip test.
7. Wire all autoloads with the full EventBus signal catalog.
8. Write all seven Resource schema scripts.
9. Build placeholder `main.tscn`.
10. Write GitHub Actions workflows.
11. Write seven ADRs.
12. Run all three local exports; verify each manually.
13. Per-phase ship loop steps 4–8: commit, create remote with `gh repo create NickSanft/IdleBeastPractices --public`, push, watch CI, tag `phase-0-complete`.

Phase 1 begins immediately after `phase-0-complete` is tagged green.
