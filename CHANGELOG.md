# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Pre-1.0, the **minor version equals the phase number**.

## [Unreleased]

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
