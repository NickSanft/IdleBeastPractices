# CLAUDE.md

Durable, high-signal facts for working in this repo. Long-form detail lives in
[docs/PROJECT_NOTES.md](docs/PROJECT_NOTES.md) (architecture + systems) and
[docs/DEV_NOTES.md](docs/DEV_NOTES.md) (build/test/CI + hard-won gotchas).
Version-by-version history is in [CHANGELOG.md](CHANGELOG.md).

## What this is

An idle monster-catching game for **Android** (primary), Windows, and Web.
**Godot 4.6 (mono build, GDScript only — no C#)** — **CI pins 4.6.3** (minimum
for Google Play's target-API-36 deadline; see DEV_NOTES "Target API 36"), local
editor is 4.6.1 mono (fine for tests; don't ship a local Android export — it
would target SDK 35). Save format is
versioned JSON with a migration chain. Tests: **GUT** (headless unit) + **Maestro**
(Android-emulator UI flows).

## Build & test

Local Godot lives at
`C:/Users/nicho/Desktop/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64_console.exe`
(use the `_console.exe` variant so stdout is captured).

```sh
# Import once after adding/renaming resources, then run the full suite (this is
# exactly what CI's Build job runs):
<godot> --headless --path . --import
<godot> --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://game/tests/ -ginclude_subdirs -gexit
```

Exit-time `ObjectDB instances leaked` / `resources still in use` / RID-leak lines
are **benign headless noise** — judge pass/fail by GUT's `Passing/Failing Tests`
totals, not the exit code alone (a stray line can force a non-zero exit even when
all tests pass). If a run hangs for minutes, check for an **orphaned headless
Godot process holding the import lock** and kill it (`Get-Process Godot*`).

## Ship workflow (followed for every feature)

1. **Scout** the affected code first (don't assume from memory).
2. **Implement** one focused feature.
3. **Test headlessly** with GUT — aim for **two clean full-suite runs** (order-stability matters; shared autoload/`GameState`/disk-save state leaks between test files).
4. **Adversarial review** — fan out multi-agent reviewers by dimension, then skeptically verify each finding before acting. Apply confirmed findings; document (don't silently drop) the ones you deliberately keep.
5. **CHANGELOG** — add an entry under `## [Unreleased]` (Keep-a-Changelog style; the honest voice includes deferred work + deliberate non-fixes).
6. **Commit** `vX.Y.Z: <summary>` on the working branch (which tracks `origin/main`), **push to main** (fast-forward), then **tag `vX.Y.Z`** and push the tag.
7. **Watch CI** green: Build (GUT + export), Maestro (emulator), Pages, Release.

**Versioning is automated in CI** from the git tag + commit count — do **not**
hand-edit `export_presets.cfg` version fields. Pre-1.0 the **minor version ==
phase number**. Git tags are lightweight.

## Architecture conventions (the load-bearing ones)

- **Autoloads** are the source of truth (17 of them; see PROJECT_NOTES). Stateful orchestration lives in autoloads; **pure logic lives in `game/systems/*` static classes** (`OfflineProgressSystem`, `DailyLoginSystem`, `DailyQuestsSystem`, `CatchingSystem`, `SaveConflictResolver`, …) so it's deterministically unit-testable with injected inputs.
- **`EventBus`** is a stateless global signal bus. Signal names are **past-tense verbs** (`monster_caught`, `quest_completed`), each `@warning_ignore("unused_signal")`.
- **Coalesce signal-driven work**: set a `_dirty` flag in the handler, drain it once per frame in `_process` (`QuestLog`, `DailyQuests`, `Achievements`, and main's `_theme_dirty` / `_safe_area_dirty` / `_orientation_dirty`). A hold-to-tap burst fires many signals per frame — never do expensive work per-signal.
- **Money is `BigNumber`** (`{m: mantissa, e: exponent}` dict); Rancher Points (RP, the prestige currency) is a plain `int`.
- **Adding a persistent save field** is a checklist — miss a step and you get silent data loss or a farm exploit: (1) declare on `GameState`; (2) `to_dict`; (3) `from_dict` with a **safe default** (old saves must load); (4) `_reset_to_defaults`; (5) if it must survive prestige, snapshot+restore in `perform_prestige`'s keep-list; (6) if it's a monotonic/one-time-reward field, add a MAX/union merge in `SaveConflictResolver` (last-write-wins would drop it and re-grant). Additive-with-safe-default fields **don't need a schema version bump** (precedent: `tiers_rp_awarded`, the daily-login/quest fields).
- **Test seams**: `TimeManager._test_now_override` (fix the clock; always reset in `after_each`), stub backends that record calls (`StubLocalNotificationBackend.scheduled`, `AudioManager` sfx counters, `HapticManager.vibrate_count`). Pure systems take `now`/`tz_bias` as params so tests never touch the wall clock.
- **`.uid` files** (Godot 4.4+) for scripts are **tracked in git** — commit them alongside new `.gd`/`.tscn` files.
- **Window-subtype dialogs** (`AcceptDialog`/`ConfirmationDialog`/`PopupPanel`) do **not** inherit the parent `Control`'s theme — assign a theme explicitly. Sequencing two modals: defer the second by a frame so the first releases its exclusive-window slot.

## Android / Godot gotchas (one-liners → details in DEV_NOTES)

- Silent "configuration errors" on Android export → check `rendering/textures/vram_compression/import_etc2_astc=true` **first**.
- `window/handheld/orientation` is an **integer enum, not a string** (`1`=portrait, `6`=sensor). This project uses `6` + orientation-aware layout (`DeviceLayout` / `_apply_orientation_layout`).
- Scripted gradle/AAB builds must write `android/.build_version` after unzipping `android_source.zip`, else "no version info exists".
- Godot forces `resizeableActivity=true`, breaking orientation control on large screens → a `process*Manifest` gradle `doLast` hook (in all three CI workflows) rewrites it to `false`; the `src/release/` overlay is a no-op here.
- Looped music `AudioStreamWAV` can finish in 0 frames after a fresh import → `duplicate()` the stream and set `loop_begin`/`loop_end` explicitly.
- Keep files under ~5 MB in plain git; blanket-LFS + multi-job CI drains the 1 GB/month LFS budget fast (already encoded in `.gitattributes`).

## Conventions

- End commit messages with the `Co-Authored-By: Claude …` trailer.
- Prefer the dedicated file/search tools over shell `grep`/`cat`/`find`.
- The grumpy in-world narrator (Peniber) has a voice guide: [docs/peniber-voice.md](docs/peniber-voice.md).
