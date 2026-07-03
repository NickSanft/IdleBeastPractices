# Project Notes — architecture & systems

Long-form companion to [CLAUDE.md](../CLAUDE.md). This is the "what and why" of
the codebase; build/CI/gotcha detail is in [DEV_NOTES.md](DEV_NOTES.md); the
original phase build sheets are in
[IMPLEMENTATION_PLAN.md](../IMPLEMENTATION_PLAN.md) /
[DETAILED_PLAN.md](../DETAILED_PLAN.md).

## Shape of the codebase

- `game/autoloads/*` — singletons registered in `project.godot`; the source of truth for live state + cross-system orchestration.
- `game/systems/*` — **pure** static classes (`class_name X`). No global state; take inputs, return values. This is where the testable logic lives.
- `game/scenes/*` — the UI/scene tree (`main.tscn` is the root; per-screen views; reusable UI widgets under `game/scenes/ui/`).
- `game/resources/*` — `Resource` definitions (e.g. `QuestResource`); `game/data/*` — the authored `.tres` content instances.
- `game/tests/*` — GUT tests (one file per subsystem). `tests/maestro/*` — emulator UI flows.
- `assets/themes/dusk/*` — the runtime-built "Dusk" pixel-RPG theme + palettes.

## Autoloads (order matters — later ones may depend on earlier)

| Autoload | Role |
|---|---|
| `Settings` | User prefs: `font_scale`, `reduce_motion`, `haptics_enabled`, `theme_id`. Emits `accessibility_settings_changed` / `theme_changed`. |
| `EventBus` | Stateless global signal bus (past-tense signal names). |
| `SaveManager` | Load/save orchestration; `CURRENT_VERSION`; emits `game_loaded` / `game_saved`. Swappable `SaveBackend` (local file / cloud). |
| `TimeManager` | Authoritative unix time + offline-elapsed calc with a clock-tamper guard. Test seam: `_test_now_override`. |
| `GameState` | Live in-memory state = the save target. `to_dict`/`from_dict`/`_reset_to_defaults`/`perform_prestige`. All the currency/inventory/ledger/quest fields. |
| `AudioManager` | SFX/music playback (+ test counters). |
| `Narrator` | Peniber's in-world commentary line selection. |
| `AdsManager` | Rewarded-video orchestration; swappable `AdsBackend` (AdMob real / stub dialog). |
| `GodotPlayGameServices` | Vendored Play Games plugin (cloud save + sign-in). |
| `CloudSyncManager` | Cloud save pull/merge via `SaveConflictResolver`. |
| `TutorialState` | First-launch tutorial / coachmark gating. |
| `Achievements` | Threshold-triggered achievements (dirty-flag coalesced). |
| `QuestLog` | Three concurrent quest slots (SHORT/MEDIUM/LONG) + ladder advancement. |
| `DailyQuests` | Daily-resetting quest set (DAILY tier) tracking per-day deltas. |
| `DeviceLayout` | Safe-area + `is_landscape`/`is_tablet` for orientation-aware layout. |
| `HapticManager` | Vibration (+ `vibrate_count` test seam). |
| `LocalNotificationManager` | Local-notification seam; swappable backend (Android native skeleton / recording stub). No native plugin ships yet. |

## Save & persistence

- `GameState.to_dict()` ⇄ `from_dict()` round-trip; `from_dict` coerces types and uses `data.get(key, default)` so old saves load.
- **Migrations** (`SaveMigrations`) advance old saves version-by-version; a bump is only needed for *structural* changes, not additive fields with safe defaults.
- **Prestige** (`perform_prestige`) snapshots a keep-list (pets, bestiary, ledger, equipment, achievements, `quests_completed`, `tiers_rp_awarded`, daily-login streak, daily-quest state, RP) then `_reset_to_defaults()` then restores — each keeper is explicit (2 lines).
- **Cloud merge** (`SaveConflictResolver.resolve`, pure): newer save (by `last_saved_unix`) is the base; monotonic fields union/MAX so neither device loses progress; one-time-reward ledgers (`tiers_rp_awarded`, daily fields) MUST union/MAX or they'd re-grant. Corrupt far-future day indices are treated as reset, not a permanent lockout.

## Theme & UI

- The "Dusk" pixel-RPG theme is **built at runtime** by `DuskThemeBuilder.build(palette, fonts, scale)` (not loaded from a static `.tres`) so the accessibility font-scale slider rescales theme-variation text. Palettes: Amethyst / Twilight / Ember (`PaletteDusk`), swappable live.
- Layout is **orientation-aware**: persistent UI children are built once and re-parented into a portrait (VBox) or landscape (HBox) composition on device flips (`main._apply_orientation_layout`), so per-tab state survives rotation.
- Bottom nav: 4 primary destinations (Catch · Bestiary · Shop · Battle) + a **More** sheet for secondary screens (Inventory, Upgrades, Crafting, Prestige, Ledger, **Daily**, Settings). Android hardware **Back** is owned by a back-stack in `main._handle_go_back`.

## Feature systems

- **Catching** — tap + idle auto-catch (nets) across monster tiers/biomes; shinies; a bestiary with completion meters and a scaling tier-completion RP bonus.
- **Economy** — gold (`BigNumber`) + upgrades; Rancher Points (RP) via prestige; crafting materials + equippable pet gear; a pet auto-battler.
- **Quests** — `QuestLog`'s three concurrent slots (repeatable ladders + one-shots), plus `DailyQuests`: a fresh DAILY set each local day, tracked as a **per-day delta of a lifetime ledger counter** (`current − day-start baseline`), with progress-scaled gold per quest and a complete-all RP bonus. A "done/total" badge sits on the More button.
- **Retention** — daily-login streak reward (escalating 7-day cycle, day-7 RP milestone); offline progress with a welcome-back summary; a local-notification seam (no native plugin yet).
- **Polish** — Peniber narrator; accessibility (font scaling, reduce-motion, haptics); cloud save (Play Games) with conflict-merge; rewarded ads (AdMob, stubbed in editor/CI).

## Status & roadmap

Current release **v0.15.16**. Recent work is a UI/UX research-driven polish pass:
accessibility font scaling (v0.15.13), daily-login reward (v0.15.14), daily
quests (v0.15.15), daily-quest nav badge (v0.15.16). See [CHANGELOG.md](../CHANGELOG.md).

Known follow-ups (not started):
- **Offline cap-fill notification** — the testable seam exists (v0.15.14); what remains is a native Android notification plugin (AlarmManager/WorkManager + Android-13 `POST_NOTIFICATIONS` runtime permission) + real-device QA. This is the one retention item that can't be fully verified in CI/Maestro.
- **Cloud-merge hardening** for `quests_completed` / `achievements_unlocked` — same last-write-wins gap already fixed for `tiers_rp_awarded` and the daily fields; a small self-contained union pass.
