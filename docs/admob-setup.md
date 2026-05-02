# AdMob setup

This project ships rewarded video ads via the Poing Studios
[godot-admob-plugin](https://github.com/poingstudios/godot-admob-plugin)
(MIT-licensed, vendored at `addons/admob/`). The plugin's GDScript API
exposes `MobileAds`, `RewardedAdLoader`, `RewardedAd`, etc., and is wrapped
by [`AdMobAdsBackend`](../game/systems/admob_ads_backend.gd) which speaks
the project's [`AdsBackend`](../game/systems/ads_backend.gd) signal
contract.

## How backend selection works

[`AdsManager._ready`](../game/autoloads/ads_manager.gd):

```gdscript
if AdMobAdsBackend.is_plugin_loaded():
    backend = AdMobAdsBackend.new()
else:
    backend = StubAdsBackend.new()
```

`AdMobAdsBackend.is_plugin_loaded()` returns `true` only when
`Engine.has_singleton("PoingGodotAdMob")` — which happens only on Android
device builds where the plugin's `.aar` is packaged into the AAB. On the
editor, Windows, and Web exports, the stub backend (a confirmation-dialog
simulator) is used instead.

This means: **dev builds work on every platform without any AdMob account**.

## Test ad IDs (default in source)

Both the AdMob app ID and the rewarded ad unit ID default to Google's
[documented test IDs](https://developers.google.com/admob/android/test-ads),
which always serve test ads regardless of network conditions:

| Use | Test ID |
|---|---|
| App ID (`addons/admob/android/config.gd:APPLICATION_ID`) | `ca-app-pub-3940256099942544~3347511713` |
| Rewarded unit (`AdMobAdsBackend._TEST_REWARDED_UNIT`) | `ca-app-pub-3940256099942544/5224354917` |

Test ads display a "Test Ad" banner overlay so it's obvious you're not
showing real inventory. **Never serve real ad inventory in dev** — Google
suspends accounts that click their own ads.

## Switching to production ads

1. Sign in at [admob.google.com](https://admob.google.com/) and create:
   - **An app** (Android, package `com.divora.beast`) — note the App ID, format `ca-app-pub-XXXX~YYYY`.
   - **A rewarded ad unit** under that app — note the Ad Unit ID, format `ca-app-pub-XXXX/ZZZZ`.
2. Add two GitHub repository secrets:
   - `ADMOB_APP_ID` — the App ID (`ca-app-pub-XXXX~YYYY`).
   - `ADMOB_REWARDED_UNIT_ID` — the Ad Unit ID (`ca-app-pub-XXXX/ZZZZ`).
3. Push a release tag (`v0.7.x` etc). The release workflow's "Inject AdMob
   secrets" step patches both into the source before export — production
   AABs ship with your real IDs while the committed source still has the
   test IDs (so dev builds keep working).

If either secret is unset when a release runs, CI emits a `::warning::`
and the AAB ships with the test IDs.

## Verifying after a release

After the AAB lands on Play Console internal track and you install on a
device:

1. Trigger any rewarded ad placement (welcome-back 2× claim, battle skip,
   catching 2× drops).
2. The ad surface should show **"Test Ad"** in the corner if you haven't
   set the secrets, or a real test ad from your AdMob account if you have
   (AdMob serves test ads against your account until you've set up
   payment + crossed Google's review threshold; this is normal).
3. After the reward grants, the corresponding game state should update
   (gold doubled, battle finished, drops counter incremented).

## Common issues

- **"PoingGodotAdMob not found"** in the runtime log — the plugin's `.aar`
  isn't being packaged into the AAB. Verify the plugin is enabled in
  `project.godot`'s `[editor_plugins]` section and that
  `addons/admob/android/bin/ads/libs/poing-godot-admob-ads-release.aar`
  exists in the repo.
- **Ad never loads** on a real device — check that
  `addons/admob/android/config.gd:APPLICATION_ID` is set (test or
  production), the device has internet, and the app is installed via
  Play Store / internal-track install, not directly via `adb install`
  (AdMob may rate-limit unknown installs).
- **App crashes on first ad load** — likely an outdated Google Play
  Services version on the device. Update the AdMob plugin via the
  Poing Studios releases (`poing-godot-admob-android-vX.Y.Z.zip`) if a
  newer compatible Godot 4.6 build is available.
