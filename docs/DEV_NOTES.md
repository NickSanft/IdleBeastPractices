# Dev Notes — build, CI, and hard-won gotchas

Long-form companion to [CLAUDE.md](../CLAUDE.md). These are debugging lessons
paid for in wasted CI cycles — each has the *symptom*, the *why*, and the *fix*.
Most are Godot 4.6 / Android-export facts that outlive any single feature.

## Build & test

- **Engine**: Godot **4.7.1-stable**, standard build (GDScript only; no C#). **Local and CI run the same version** — path in [CLAUDE.md](../CLAUDE.md); use the `_console.exe` variant so stdout is captured on Windows. The previous deliberate local/CI skew is gone, and good riddance: it cost seven CI round-trips to diagnose a layout bug that only crossed the overflow threshold on CI's font metrics (CHANGELOG v0.15.24). The **mono** build was never used by CI — it downloads the standard `Godot_v<ver>_linux.x86_64.zip` — only the old local editor was mono; `[dotnet]` in `project.godot` is vestigial.
- **Import before testing** after adding/renaming resources: `godot --headless --path . --import`. New `.gd`/`.tscn`/`.tres` get `.uid` sidecars generated here — **commit those `.uid` files**.
- **Run the suite**: `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://game/tests/ -ginclude_subdirs -gexit`.
- **Reading results**: judge by GUT's `Passing Tests` / `Failing Tests` / `All tests passed` lines. Ignore exit-time `ObjectDB instances leaked`, `resources still in use`, and RID-leak errors — they're standard headless-shutdown noise and can force a non-zero exit even on a fully-passing run.
- **Order-stability**: run the full suite **twice** before shipping. GUT runs all files in one process, and `GameState`, singleton autoloads, the on-disk save (some tests call `SaveManager.save`), and `TimeManager._test_now_override` all persist across files. A test that mutates shared state without resetting it in `after_each` causes an order-dependent flake. Reset what you touch.
- **Hang / lock**: if a headless run sits for minutes with no output, an **orphaned Godot process is holding the project import lock**. `Get-Process Godot*` (look for one with minutes of run-time and ~0 CPU), kill it, re-run. This is an environment artifact, not a code bug.

## CI (GitHub Actions)

Four workflows under `.github/workflows/`:

- **`build.yml`** — the gate: headless GUT tests + a debug Android export smoke-build. Downloads the pinned Godot release + templates from GitHub (no container) into a cached binary. The GUT step's pass/fail is judged by a **suite-integrity gate**, not the exit code: JUnit-XML `failures="0"`, runtime testcase count `>=` the static `func test_` count (GUT **silently skips** scripts that fail to parse while still printing "All tests passed" — bit us in v0.15.17), and no `Ignoring script`/`Parse error` lines in the output.
- **`maestro-emulator.yml`** — boots an Android emulator and runs the Maestro UI flows in `tests/maestro/`.
- **`release.yml`** — on a `vX.Y.Z` tag: gradle-builds the AAB, publishes the release, then calls `pages.yml` so the demo tracks the release.
- **`pages.yml`** — deploys the Pages site: Jekyll `docs/` at the root + the **playable web demo** of the latest release at `/play/` (downloaded from the release's stable `releases/latest/download/` asset — no Godot rebuild). Triggers: docs pushes, releases (via `workflow_call` — GITHUB_TOKEN-created release events can't trigger workflows), manual dispatch. The demo works on plain Pages **only because the web export is single-threaded** (`variant/thread_support=false`); enabling threads would require COOP/COEP headers Pages doesn't serve (coi-serviceworker shim territory). **One-time setup (done 2026-07-05):** the Pages source had to be flipped by hand — Settings → Pages → Source → "GitHub Actions". Neither `actions/deploy-pages` nor `configure-pages` `enablement: true` can switch an existing legacy branch-based site with the workflow's `GITHUB_TOKEN` (repo-settings change = admin); both first runs failed at `deploy-pages` until the manual flip. **Second one-time setup — the `github-pages` environment must allow `v*` tags:** the environment's "Deployment branches and tags" rule defaults to the default branch only, so the `workflow_call` from `release.yml` (which runs on a `v*` tag) is rejected at job initiation with `Tag "vX.Y.Z" is not allowed to deploy to github-pages due to environment protection rules`. The tell is a **failed job with an empty steps list**. It is *not* a permissions bug — the `pages: write` / `id-token: write` grants on `release.yml`'s `deploy-pages-demo` are already correct. Fix: Settings → Environments → `github-pages` → "Deployment branches and tags" → add tag rule `v*`. First hit on v0.15.21 (2026-08-11), the first tagged release after `pages.yml` landed; everything else in `release.yml` (AAB, zips, GitHub Release) is unaffected, and `/play` self-heals on the next docs push because it is pulled from `releases/latest/download/` rather than from the tag.

**Version is derived, not hand-edited.** `release.yml` sets the Android
`version_code` from `git rev-list --count HEAD` and the `version_name` from the
tag. Do **not** edit version fields in `export_presets.cfg` (they're placeholders
CI overwrites). Ship = commit `vX.Y.Z: …` → push to `main` → `git tag vX.Y.Z` →
push tag. Tags are lightweight.

## Android export gotchas

### 1. Silent "configuration errors" → ETC2/ASTC import
When headless/CI Android export prints `Cannot export project with preset "Android" due to configuration errors:` with **no** error string after it, check `rendering/textures/vram_compression/import_etc2_astc=true` in `project.godot` **first** — before keystore/JDK/NDK/template diagnostics. GLES (the GL-Compatibility backend on Android) can't use S3TC/BPTC, so Godot needs ETC2/ASTC texture variants; without this flag the import pipeline never produces them and the exporter's preflight refuses to proceed. The specific error is suppressed in headless mode. *(Currently set correctly in `project.godot`.)*

### 2. Scripted gradle build → `.build_version` marker
Automating an AAB/gradle build without the editor GUI: unzipping `android_source.zip` into `android/build/` is **not enough**. Godot's `Project → Install Android Build Template` also writes `android/.build_version` (the template version string, e.g. `4.7.1.stable` standard / `4.7.1.stable.mono` mono; CI writes `$GODOT_TEMPLATE_DIR`, so it follows the engine bump automatically). Without it: `ERROR: Export: Trying to build from a gradle built template, but no version info for it exists.` CI does this correctly (`release.yml`):
```bash
mkdir -p android/build
unzip -q "$TEMPLATES/${GODOT_TEMPLATE_DIR}/android_source.zip" -d android/build
echo "${GODOT_TEMPLATE_DIR}" > android/.build_version
```

### 3. Orientation is an integer enum, not a string
`display/window/handheld/orientation` in Godot 4.x is a `PROPERTY_HINT_ENUM` **int**, not a string. Writing `"portrait"` parses as `0` (landscape) and the compiled manifest gets `screenOrientation="0"`. Values: `0`=landscape, `1`=portrait, `2`=reverse_landscape, `3`=reverse_portrait, `4`=sensor_landscape, `5`=sensor_portrait, `6`=sensor. **This project uses `6` (sensor)** because it grew orientation-*aware* layout (`DeviceLayout` + `main._apply_orientation_layout` compose portrait vs. landscape), so it follows the device rather than hard-locking. Verify a build with `bundletool dump manifest --bundle=<aab>`. Don't sed-patch `android/build/src/main/AndroidManifest.xml` — Godot regenerates it from project settings at export, so the patch is dead code.

### 4. `resizeableActivity=true` breaks large-screen orientation control
Godot's exporter hardcodes `android:resizeableActivity="true"` on the GodotApp activity every export. On Android 12+ large screens (sw600dp+, foldable inner displays) the compositor ignores `screenOrientation` when the activity is resizeable. The textbook `src/release/AndroidManifest.xml` overlay with `tools:replace` is a **no-op** here — Godot's gradle wiring skips the build-type source dir at manifest merge. The fix (present in all three CI workflows) is a gradle `doLast` hook appended to `android/build/build.gradle` that rewrites the merged manifest after AGP's `process*Manifest*` tasks:
```groovy
afterEvaluate {
    tasks.matching { it.name ==~ /process.*Manifest.*/ }.all { Task t ->
        t.doLast {
            project.fileTree(dir: project.buildDir, include: '**/AndroidManifest.xml').each { File f ->
                if (f.text.contains('android:resizeableActivity="true"')) {
                    f.text = f.text.replace('android:resizeableActivity="true"', 'android:resizeableActivity="false"')
                }
            }
        }
    }
}
```

### 5. Target API 36 (Google Play deadline 2026-08-31)
Google Play requires new apps and updates to **target Android 16 (API 36) from
Aug 31, 2026** (apps targeting lower become invisible to new users on newer
devices). The project inherits its target SDK from the engine's android
template (`export_presets.cfg` leaves `gradle_build/target_sdk` blank — do
not pin it there; the engine's annual bump maintains it):

- **Godot 4.6.1** templates target SDK **35** → not compliant after the deadline.
- **Godot 4.6.3** (2026-05-20) targets SDK/compileSdk **36** *and* fixes
  API-36 predictive-back handling (GH-117653) — without that fix, targeting 36
  force-enables predictive back on Android 16 and the hardware Back gesture
  bypasses `main._handle_go_back`'s back-stack entirely. This made 4.6.3 the
  **floor**, not the pin.
- CI and the local editor now both run **4.7.1**, which clears that floor.
  Its `config.gradle` was checked against 4.6.3's before the bump and is
  **identical** on every value CI depends on — `buildTools 36.1.0`,
  `ndk 29.0.14206865`, `compileSdk/targetSdk 36`, `JavaVersion 17` — so the
  SDK packages line needed no change. Re-check it the same way on the next
  bump (read `platform/android/java/app/config.gradle` at the release tag);
  keep the engine env vars and the packages line in sync across all three
  workflows.
- Both AAB-producing workflows **assert** the built manifest via
  `bundletool dump manifest`: `targetSdkVersion >= 36` and
  `resizeableActivity="false"` (proving the gradle `doLast` patch applied) —
  a silent engine-default change or exporter reshape now fails CI instead of
  shipping.

### 6. Local Android export — JDK version
Godot's `editor_settings-4.7.tres` has `export/android/java_sdk_path`, which **overrides** shell `JAVA_HOME` for Android exports. If it points at a JDK newer than gradle supports (e.g. JDK 25 vs. gradle 8.11.x capping at JDK 21) local exports fail with `Unsupported class file major version 69` even when `JAVA_HOME` is correct. Fix the editor setting, or rely on CI (`actions/setup-java@v4` pins a known-good version).

## Audio: looped `AudioStreamWAV` finishes in 0 frames
Symptom: `AudioStreamPlayer.play()` reports `playing=true` immediately, then `playing=false` / `pos=0.00s` a half-second later, with `finished` firing unprompted. Cause: Godot 4.6's WAV importer caches an `AudioStreamWAV` with a degenerate `loop_end`; with `LOOP_FORWARD` the stream has "0 frames to play." Reproduces on long WAVs (a 175s track), not short SFX. Fix — always `duplicate()` and set the loop range explicitly:
```gdscript
var stream := (load(path) as AudioStream).duplicate(true)
if stream is AudioStreamWAV:
    var wav := stream as AudioStreamWAV
    wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
    wav.loop_begin = 0
    wav.loop_end = max(1, int(round(wav.get_length() * max(1, wav.mix_rate))) - 1)
player.stream = stream
```

## Git LFS bandwidth
GitHub's free LFS budget is **1 GB/month per repo**, and every CI job that checks out with `lfs: true` pulls every LFS object — a multi-job matrix multiplies that per push. A single 30 MB music WAV + vendored TTFs drained it in a day (symptom: `batch response: This repository exceeded its LFS budget`, checkout fails). This repo now keeps files under ~5 MB in **plain git** and reserves LFS only for genuinely large binaries — the rationale is encoded in `.gitattributes`. Convert music WAV→OGG offline (`ffmpeg -c:a libvorbis -q:a 4`), gitignore Godot's regenerable `android/build/`, and never blanket-LFS by extension (the AdMob `.aar` files are KB-sized and don't belong in LFS).

## Testing patterns
- **Pure systems** take `now`/`tz_bias`/RNG/state as parameters — tests call them with fixed inputs, no globals.
- **Test seams** for stateful autoloads: `TimeManager._test_now_override` (a fixed unix time — set a **future** value to stay ahead of on-disk `last_saved_unix` and avoid the clock-backward warning; **always reset to `-1` in `after_each`** so it doesn't leak into another file). Stub backends record calls (`StubLocalNotificationBackend.scheduled` / `.schedule_count`); `HapticManager.vibrate_count`; `AudioManager` sfx counters.
- **Main's `_process` isn't auto-pumped reliably in the headless GUT harness** — tests that rely on a dirty-flag drain call `main._process(0.0)` explicitly (see `test_buttons_on_screen`).
- **Godot auto-disconnects a freed node's signal connections**, so `add_child_autofree` on a `main` instance doesn't leak its `EventBus`/`Settings` subscriptions across tests (a clean multi-instance suite confirms it).
