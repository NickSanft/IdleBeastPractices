# Maestro UI tests

[Maestro](https://maestro.mobile.dev) flows that drive the Android build through
basic gameplay scenarios and tab navigation, executed against a Pixel 6 API 34
emulator in CI by [`maestro-emulator.yml`](../../.github/workflows/maestro-emulator.yml).

## Why

Godot's GUT tests are headless and never exercise touch input on a real Android
runtime. The whole class of v0.8.x bugs we just fixed —
- `aspect="keep"` letterbox + Godot input transform mismatch (#118153)
- `MOUSE_FILTER_STOP` on TabContainer dispatching duplicate events (#91987)
- `NOTIFICATION_APPLICATION_PAUSED` missing on certain Android versions
- Stub-dialog `exclusive=true` clashing with parent dialog

— would have been caught by a flow that simply *taps a tab and asserts the
content area changed*. Maestro on an emulator gives us that.

## Limitations

- **Coordinate-based taps**, not text-based. Godot renders all UI to a single
  GL canvas, so Maestro's Android accessibility tree only sees one big
  surface — `tapOn: "Battle"` doesn't work. Flows use percentage points
  (`tapOn: { point: "25%, 5%" }`) which are calibrated for the Pixel 6
  emulator's 1080×2400 portrait resolution. If the emulator profile changes,
  re-calibrate.
- **Default emulator ≠ Galaxy Z Fold7**. The Pixel 6 emulator is a 9:20
  conventional phone. Foldable-specific bugs (the kind we hit on the user's
  inner display) won't always reproduce here. Tier 3 (Firebase Test Lab on a
  Fold5/Fold6/Fold7) is the next-up if this needs covering.
- **AdMob, Play Games Services, real network**. The emulator doesn't sign in
  to a Google account, so cloud sync flows can't be exercised end-to-end.
  Stub backends used in dev builds substitute, so we still verify the
  rewarded-video lifecycle plumbing without serving real ads.

## Running locally

You'll need:
1. **Android SDK + emulator** (Android Studio is the easy way to install both).
2. **Maestro CLI**: `curl -fsSL "https://get.maestro.mobile.dev" | bash`
3. **A debug build of the app** installed on a connected device or emulator:
   ```
   adb install exports/android/IdleBeastPractices-debug.apk
   ```

Run all flows:
```
maestro test tests/maestro/
```

Run a single flow:
```
maestro test tests/maestro/01_smoke.yaml
```

Maestro Studio (GUI for recording new flows interactively):
```
maestro studio
```

## Flow inventory

| File | Purpose | Catches |
|---|---|---|
| `01_smoke.yaml` | Launch, no crash, screenshot landing page | App fails to launch / boot crash |
| `02_tab_navigation.yaml` | Tap each of the 10 tabs by coord, screenshot each | Tabs not tappable (the v0.8.x letterbox bug) |
| `03_save_persistence.yaml` | Launch, simulate gameplay, background via Home, relaunch | Save lifecycle not firing on background |
| `04_battle_skip_button.yaml` | Switch to Battle, tap Fight, verify Skip button appears | Phase 6a wiring regression |
| `05_settings_scrollable.yaml` | Switch to Settings, scroll to bottom, verify reachable | Long views getting clipped on tall screens |

Adding new flows: prefix with the next number, drop in this dir, push. The CI
workflow runs everything matching `tests/maestro/*.yaml` automatically.
