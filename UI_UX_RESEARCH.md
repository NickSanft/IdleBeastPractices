# UI/UX research — post-Phase 12 audit

Research notes + phased proposal for the next round of UI/UX work. Written after a full audit of `project.godot`, `main_theme.tres`, every primary view scene, the accessibility hooks added through Phase 11–12, and the export config. Drafted 2026-05-09.

The two issues you flagged — **text doesn't scale for phones** and **landscape mode unsupported** — are real, but they're surface symptoms of two larger structural gaps. Both belong in a coherent Phase 13 rather than as one-off fixes, because each gap touches every screen.

---

## Executive summary

| Theme | Severity | Effort | Phase |
|---|---|---|---|
| **Font scale doesn't reach 71 hard-coded overrides** | High — your "doesn't scale" complaint | M (one-day pass) | 13a |
| **No DPI / safe-area awareness** | High — text size varies by device, status bar overlaps content | M | 13b |
| **Portrait-locked; no landscape layout** | Medium — your second complaint; no foldable/tablet usable layout | L (every screen) | 13c |
| **Touch-target audit gaps** | Medium — pills, chips, some Buttons under Material 48 dp | S | 13d |
| **Tablet horizontal space underused** | Medium — only 2 of 8 views breakpoint by width | M | 13e |
| **Microinteraction timing** | Low — animation curves, haptic gradient | S | 13f |
| **Accessibility v3 (screen reader, contrast)** | Low — but legally important if shipping wider | M | 13g |

Prioritized as listed: 13a + 13b together knock out the immediate complaints and unlock device variability cleanly; 13c is the bigger lift and benefits from the foundation 13a/b lays.

---

## 1. Font sizing — current state

**Setup:**
- `main_theme.tres` defines `default_font_size = 16` plus per-control sizes (Button 16, Label 16, Heading 26, Subhead 18, ProgressBar 13, …).
- `Settings.font_scale` (range `0.85 – 1.5`, persisted) was added in Phase 11b. `main.gd._apply_mobile_default_theme()` rebuilds a `Theme` and sets `Button/Label/RichTextLabel font_size` to `int(round(N * font_scale))`. Subscribed to `accessibility_settings_changed` for live re-application.

**Problem:** **71 places in the codebase use `add_theme_font_size_override("font_size", N)` with a hard-coded number.** Those bypass both the theme and the scale. `main.gd:272` admits this explicitly:

> *"Inline font_size overrides on individual labels are NOT scaled — that's a documented limitation; theme-level scaling reaches the bulk of default-styled labels and the bottom-nav, which is the most important text."*

That documented limitation is now your bug report. Worst offenders:
- `bestiary_card` — 5 hard-coded sizes per card × 60 cards = 300 hard-coded labels.
- `battle_view` — 5 hard-coded sizes for status, log, roster.
- `celebration_overlay`, `quest_strip`, `next_goal_chip`, `currency_chip`, `floating_number`, `coachmark`, `inventory_card`, `welcome_back_dialog`, `peniber_overlay`.

**Compounding gap:** there's no DPI awareness. A `font_size = 16` design value renders at:
- 16 px on a 1080×1920 phone (typical scaling)
- ~12 px on a 1440×3200 phone → small
- ~32 px on a 720×1280 phone → too big
The viewport stretch (`canvas_items` + `keep_width`) handles the geometry, but the user's perception of "small text" on dense displays is real.

**Phase 13a proposal — `UiScale` helper + sweep:**

1. Add a static helper `UiScale.size(base_px: int) -> int` that returns `int(round(base_px * Settings.font_scale * dpi_bucket))` where `dpi_bucket ∈ {0.85, 1.0, 1.15, 1.30}` is computed once at startup from `DisplayServer.screen_get_dpi()` (or `OS.get_screen_dpi()`).
2. Sweep all 71 call sites: `add_theme_font_size_override("font_size", 16)` → `add_theme_font_size_override("font_size", UiScale.size(16))`.
3. Subscribe on the long-lived ones (cards that persist across refreshes) to `Settings.accessibility_settings_changed` so they re-apply on slider change. Most call sites build during `_refresh()` so they pick up the new value automatically.
4. Test: a `test_ui_scale.gd` that snapshots `UiScale.size(16)` at scale 1.0, 0.85, 1.5 and asserts the expected px values; a regression test that grep-asserts no remaining literal `font_size`, M call site (run via a CI script).

**Estimated effort:** 1 day. Mostly mechanical sweep; the helper is ~20 lines.

---

## 2. Display / safe-area / DPI — current state

**Setup (`project.godot`):**
```
window/size/viewport_width = 720
window/size/viewport_height = 1280
window/stretch/mode = "canvas_items"
window/stretch/aspect = "keep_width"
window/handheld/orientation = 1   ; portrait
```

**No code in the project currently calls `DisplayServer.window_get_safe_area()`, `screen_get_dpi()`, or `content_scale_factor`.** That's fine on a stock 9:16 phone but creates three concrete problems:

1. **Status-bar / notch / gesture-bar overlap.** The catching view's currency_bar sits at offset_top=0 — it'll be partially obscured by the status bar on most devices. The drops_2x button anchors to bottom-right with `offset_bottom = -20`, which may be inside the gesture-bar zone on Android 10+ devices using gesture nav.
2. **Density mismatch.** A 720-design `Button` with 14 px content_margin is 48 dp at 1080×1920 (1.5× scale) but only ~36 dp at 720×1280 native and ~64 dp at 1440×3200. Your hand-tested touch sizes were calibrated on one density.
3. **Foldable open state.** Per your saved memory entry on `feedback_godot_android_resizeable_activity.md`, Godot's Android export forces `resizeableActivity=true`, which means foldable users can land in a 1768×2208 landscape layout that the project's portrait-only design treats as letterboxed-portrait.

**Phase 13b proposal — `Viewport` autoload + safe-area margins:**

1. New `Viewport` autoload (or static helper on `Settings`) that exposes:
   - `safe_area: Rect2` — recomputed on `DisplayServer.notify_event` for safe-area changes.
   - `dpi_bucket: float` — the same constant `UiScale.size` consumes.
   - `is_landscape: bool` (used by 13c).
   - `is_tablet: bool` — `min(width, height) > 600 dp` cutoff.
2. Top-level `MarginContainer` in `main.gd._build_ui()` whose margins bind to `Viewport.safe_area`. Currency bar shifts down past the status bar; bottom nav shifts up past gesture bar.
3. Settings UI gains a "Reset UI scale to device default" button that calls `Settings.set_font_scale(Viewport.dpi_bucket / 1.0)` so users on dense screens get a sensible starting point.
4. Test: stub `DisplayServer.window_get_safe_area` via a test seam (helper that the autoload reads from), assert MarginContainer margins update.

**Estimated effort:** 1 day. The autoload is small; rewiring the root layout to pass safe-area through is the biggest piece.

---

## 3. Landscape mode — what's actually blocking

**Hard blockers:**
1. `project.godot:46` — `window/handheld/orientation=1` locks portrait. Easy flip to `7` (`SENSOR_LANDSCAPE`-style; integer enum per your saved memory).
2. AndroidManifest — Godot's gradle export forces `resizeableActivity=true`, but explicit `android:screenOrientation` on the activity overrides device sensor. Per your memory entry the gradle `process*Manifest.*` doLast hook is the existing pattern — extend it to remove the orientation lock for landscape support, not just to re-enforce portrait.

**Layout blockers (each view needs a landscape branch):**
| View | Current portrait pattern | Landscape consideration |
|---|---|---|
| `main.gd` root | Vertical stack: currency_bar / TabContainer / quest_strip / bottom_nav | Bottom nav becomes left-side rail (~80 dp wide); quest strip moves to right side; currency_bar stays top |
| `catching_view` | Spawn area is full viewport minus 80px top + 200px bottom | Spawn area becomes wider; chip + button positions need to anchor to the screen, not the spawn root |
| `battle_view` | Vertical: roster on top, status, action log, battle map | Side-by-side: roster left, battle map right; action log slides over |
| `bestiary_view` | 1/2/4-col grid based on width breakpoints (already responsive!) | Already adapts — need only safe-area padding |
| `inventory_panel` | 3/4/5-col grid (already responsive!) | Already adapts |
| `crafting_view`, `net_shop`, `upgrade_tree` | Single VBox of cards | Two-column card layout (master-detail or 2-col grid) |
| `prestige_view` | Single column of stat blocks + button | Stats on left, button + confirm dialog on right |
| `ledger_view` | Single column rows + 4-col achievement grid | Stat rows can sit beside achievement grid |
| `settings_view` | Single ScrollContainer of sections | Two-column section grid |
| `narrator_overlay` | Bottom-anchored speech bubble | Side-anchored speech bubble |
| `welcome_back_dialog` | Centered modal | Same — modals are orientation-agnostic |

**Plus:**
- `catching_view._spawn_bounds` uses fixed-pixel margins (20 left, 80 top, 200 bottom) — needs `is_landscape ? landscape_bounds : portrait_bounds` logic.
- `next_goal_chip` and `drops_2x_button` are anchored top-right and bottom-right with fixed pixel offsets (-200, -220). Those clamp to the right edge in landscape and look fine, but on tablets they leave big horizontal gaps.
- Hold-to-tap input in landscape — finger-tracking bounds need to recompute.

**Phase 13c proposal — staged landscape:**

1. **13c.1 — unlock orientation, gracefully degrade.** Set `orientation=7` (sensor) + manifest hook. Every view inherits the existing portrait layout but via a top-level `MarginContainer` that re-anchors based on `Viewport.is_landscape`. Result: landscape *works* but looks like a stretched portrait. Ship this first to stop crashing the orientation lock and let foldable users use the app at all.
2. **13c.2 — primary screens get landscape layouts.** Catching, Battle, and the bottom nav. These are the hot paths. Two-pane layouts where it makes sense.
3. **13c.3 — secondary screens.** Crafting, Shop, Upgrades, Prestige, Ledger, Settings.
4. **13c.4 — tablet column polish.** Bestiary + Inventory already breakpoint to 4–5 columns; sweep the rest.

Each stage ships as its own minor version (v0.14.0, v0.14.1, …). Tests: take a screenshot from `_run_screenshot_mode` at 1280×720 (landscape phone) and 1768×2208 (foldable open) for each shipped view; visual regression check against the committed PNG.

**Estimated effort:** 13c.1 is 1 day. Each subsequent stage is ~2 days per view group.

---

## 4. Touch-target audit

**Setup:** `main.gd:288` documents Material's 48 dp floor and applies it to themed Buttons via styling. `Input.vibrate_handheld(20)` is wired globally to button presses (Phase 11b haptics).

**Gaps found while auditing:**
- **Bestiary card pills** (`◇ ✦ ✧ ⬢` slot indicators) are `Label`s, not Buttons, but they advertise tap-ability via tooltip_text. The tooltip is dead on touch — the label has no `_gui_input`. Either wire taps or remove the tooltip.
- **Currency chip** in the header uses a custom panel with `mouse_filter = STOP`, so taps register, but its visible size is ~110 px wide × ~40 px tall — slightly under 48 dp on 720-design. With Phase 13a/b the size will grow with `font_scale`, but the 40-px-tall chassis should bump to 48.
- **Drops 2x button** uses `_drops_2x_button.offset_top = -64` so its 44-dp tall — close to the floor but under Material's recommendation.
- **Quest strip rows** (12g) are tappable but non-Button; verify their hit zone.

**Phase 13d proposal — touch-target sweep:**

1. Static helper `UiScale.tap_target() -> int` returning `max(48, base_dp * dpi_bucket)`.
2. One-pass review of every interactive Control: Buttons, Panels with `_gui_input`, Labels with `tooltip_text`. Anything claiming tappability gets `custom_minimum_size.y >= UiScale.tap_target()`.
3. Add `test_touch_targets.gd` that walks the scene tree of every primary view, finds tap-receivers, and asserts minimum size.

**Estimated effort:** half a day.

---

## 5. Information architecture rough edges

**Findings while auditing:**

- **Welcome-back dialog (F47/F48 from earlier)** — already iterated. Fine.
- **Settings view "Language" section** is a placeholder with one entry that prints to console on selection. Either hide it until i18n ships or label it more clearly as "Coming soon" — the current "Additional languages will arrive" subtext plus a working dropdown reads as a bug.
- **More menu** — 6 items behind a single "More" button. Current Phase-9 nav split has the feel right, but research says 4–5 primary destinations is the upper bound for thumb-zone bottom nav. With Achievements (12f) + Quests (12g) added since the nav was designed, "More" now has 6 entries. Consider promoting Crafting or Prestige to primary, demoting Settings to a header-icon.
- **Quest strip** (12g) sits *above* the bottom nav. That's the right thumb-zone spot, but it's a heavy band of always-on UI that crowds the catching screen on phones. Consider making it collapsible — a compact 1-row indicator that expands to the 3-row strip on tap.
- **Tutorial coachmarks** (12c) — solid first-launch flow, but no in-game "help" surface for returning players who forgot a mechanic. A `?` icon in Settings opening a "How does X work?" cheatsheet would close the loop.
- **Currency bar** — gold + RP only. Items / pets owned shown as raw counts on relevant tabs but never as headline. Mild gap.

These are 13g material — not pressing, but each is a small "I noticed this didn't quite work" that compounds.

---

## 6. Microinteraction polish

Lower priority than the structural items above, but listed for completeness:

- **Tap feedback animation** — `monster_instance.play_tap_feedback()` is a brief scale-pulse. Solid. The miss-tap ripple is good. The catch animation is fine. No real complaints here.
- **Animation curves** — most tweens use `TRANS_CUBIC + EASE_OUT`. Consistent. Reduce-motion (Phase 11b) skips them, also good.
- **Haptic gradient** — currently 20 ms for buttons, 40 ms for monster taps, no feedback for catches. A 60-ms sting on shiny catches would land well.
- **Audio sting timing** — uses the audio bus correctly; not aware of a complaint.

Phase 13f could batch these into a small one-day microinteraction polish if the bigger phases land first.

---

## 7. Accessibility v3 (forward-looking)

What's already in place (Phases 11b + 12b):
- `font_scale` 0.85–1.5
- `reduce_motion`
- `haptics_enabled`
- `colorblind_mode` (redundant shapes on bestiary slot pills + shiny floats)
- `hold_to_tap_enabled` + `hold_tap_rate_hz`

What's missing if you ever want WCAG-AA-ish coverage:
- **Screen-reader labels.** Godot 4 supports `tooltip_text` and `accessibility_name` (via `set_meta` or third-party plugins). Currency bar shows "1.2 K gold" visually but exposes nothing to TalkBack.
- **Contrast pass.** SEPIA_MID and SEPIA_DARK on PARCHMENT pass at body sizes; some 12px footnotes don't.
- **Keyboard nav** for desktop / web builds. Bottom nav buttons are focusable; tab order in side panels is ad-hoc.
- **Per-tab toggle for narrator pop-ups.** Some users find them noisy; a per-overlay opt-out matches the `reduce_motion` philosophy.

Phase 13g material. Lift after the foundational scale/safe-area work.

---

## 8. Suggested phasing

| Phase | Subject | Effort | Ships as |
|---|---|---|---|
| **13a** | UiScale helper + 71 hard-coded font_size sweep | 1d | v0.14.0 |
| **13b** | Viewport autoload, safe-area margins, DPI bucket | 1d | v0.14.1 |
| **13c.1** | Unlock orientation, all views inherit portrait-shaped layout | 1d | v0.14.2 |
| **13c.2** | Catching + Battle + nav landscape layouts | 2d | v0.14.3 |
| **13c.3** | Secondary screens landscape layouts | 3d | v0.14.4 |
| **13c.4** | Tablet column polish across the remaining views | 1d | v0.14.5 |
| **13d** | Touch-target sweep + regression test | 0.5d | v0.14.6 |
| **13e** | (folded into 13c.4) | — | — |
| **13f** | Microinteraction polish (haptic gradient, sting timing) | 0.5d | v0.14.7 |
| **13g** | IA cleanup + screen-reader pass | 1d | v0.14.8 |

Total ~10 days of focused work for a complete UI/UX modernization pass. **My recommendation: ship 13a + 13b first as a 2-day "make text + layout actually scale" release, see how it lands, then schedule landscape (13c) as a separate effort once you've felt the foundation in your hands.**

---

## 9. What I'd start tomorrow

If you want me to roll into one of these, my pick is **13a → 13b** in a single push:
- Both are mostly mechanical sweeps, low risk.
- They directly address the "text doesn't scale" complaint.
- They unlock 13c by giving every view a way to reason about safe-area + DPI.
- The combined CHANGELOG entry is concrete and self-contained.

Landscape (13c) I'd save for a focused effort because each view needs design judgment, not just code, and shipping a half-finished landscape mode would leave half the views looking awkward.

Tell me which phase to start, or which to skip — happy to dig in further on any single area before committing to a phase plan.
