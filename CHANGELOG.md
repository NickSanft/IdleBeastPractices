# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Pre-1.0, the **minor version equals the phase number**.

## [Unreleased]

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
- (pending) CI green on `main`
- (pending) Tag `phase-3-complete`

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
