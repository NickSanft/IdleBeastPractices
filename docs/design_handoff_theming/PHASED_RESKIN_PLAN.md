# Phased re-skin plan — Dusk Pixel-RPG theming

Companion to `README.md`. Lays out how to take the live game from its current parchment-and-brass aesthetic to the deep-amethyst Dusk look the handoff specifies, **in increments small enough that each one is independently verifiable on a real device**.

The Amethyst Theme resource (`assets/themes/dusk/amethyst.tres`) ships in **v0.15.0** ahead of any scene changes. Then six numbered phases re-skin the existing scenes, each with its own ship + Maestro pass + visual-regression snapshot. No phase touches gameplay logic; every change is presentation-only.

---

## Visual regression strategy (applies to every phase)

Existing test infrastructure carries over: GUT for unit / contract tests, Maestro for emulator smoke. New for Phase 14:

### 1. Themed-snapshot tests (GUT-level, run on every CI)

Already shipped in v0.15.0:

- `test_dusk_theme.gd` pins palette token values, the seven type variations the builder emits (`DisplayHeading` / `DisplaySmall` / `UiTiny` / `UiCaption` / `BodyText` / `BodyIntro` / `BodyTextRich` / `PixelButtonGold`), zero-corner-radius invariant on every StyleBoxFlat, and a **drift detector** — the committed `amethyst.tres` is compared against a freshly-built one each test run, so a maintainer who edits `palette_dusk.gd` without re-running `tools/build_dusk_themes.gd` fails by name.

Each subsequent phase adds variation-coverage tests: when phase 14b re-skins the Catch screen, a test instantiates the Catch view, walks each labeled element, and asserts the right `theme_type_variation` is set (`DisplayHeading` for the title, `UiTiny` for currency labels, etc.). That catches "developer added a Label and forgot to set theme_type_variation" regressions.

### 2. Render-snapshot tests (per-phase, headless PNG diff)

Extend the existing `_run_screenshot_mode` (`game/scenes/main.gd:115`) so each re-skin phase records a deterministic PNG of the touched view at known game-state and orientation, **and** asserts pixel-level equivalence against a committed reference PNG.

Plan:

1. Add a CLI flag `--screenshots=phase14b` (etc.) so each phase has its own output directory.
2. Reference PNGs live under `tests/snapshots/phase14<sub>/`. First run is committed; subsequent runs diff against the committed reference.
3. Allow a small per-pixel tolerance (≤2 LSB on RGB) to absorb font-rasterisation jitter across Godot patch versions; major drift fails the test.
4. CI runs the snapshot job after the GUT job. Failures point at the offending PNG with the diff visualised side-by-side.

The handoff screenshots in `docs/design_handoff_theming/screenshots/` are the **target** images; the per-phase snapshots are *current state* — they converge on the targets as phases land. A separate "handoff comparison" Markdown doc (one per phase) embeds both side by side so reviewers can eyeball alignment.

### 3. Maestro flows (already shipped)

The seven existing Maestro YAMLs already exercise the catching / battle / nav / settings / save flows on a Pixel 6 emulator. They use **selectors by visible text + tooltip_text** (Phase 13g added the latter), so they survive re-skins as long as the text doesn't change. Each phase adds at most one new Maestro flow if a new visible element is introduced (e.g., the Peniber intro in Phase 14e).

### 4. Manual handoff sign-off

After each phase ships green, the handoff PNGs in `docs/design_handoff_theming/screenshots/` are checked side-by-side with the live build. Discrepancies become tickets for the next phase.

---

## Phase 14a — Theme resource only (this release, v0.15.0)

**No scene changes.** Lands the theme machinery so future phases can `Window.theme = load("…/amethyst.tres")` and the styling cascades.

### Ships

- `assets/fonts/dusk/` — three vendored OFL TTFs (Press Start 2P / Silkscreen / VT323) + their OFL.txt licenses
- `assets/themes/dusk/palette_dusk.gd` — `PaletteDusk` static class, three palettes (Amethyst / Twilight / Ember) returning matching keysets
- `assets/themes/dusk/dusk_theme_builder.gd` — `DuskThemeBuilder.build(palette, fonts) -> Theme`, parameterised so the same builder produces all three palettes
- `tools/build_dusk_themes.gd` — one-shot runner that builds + saves the three .tres files. Re-run when palette or builder changes
- `assets/themes/dusk/amethyst.tres` (default), `twilight.tres`, `ember.tres` — committed outputs
- `game/tests/test_dusk_theme.gd` — palette + builder + .tres-drift coverage

### Tests

- 17 cases covering: 17-token Amethyst palette match, Twilight + Ember overrides, palette inheritance for un-specified tokens, `by_id` fallback, builder output shape (Button/CheckBox/OptionButton ×4 states, Panel + PanelContainer panels, 8 type variations), zero corner radius invariant, three .tres files load cleanly, **drift detector** (committed vs freshly-built)

### Acceptance

- Full GUT suite green
- Themes load via `load("res://assets/themes/dusk/amethyst.tres")` without warnings
- No live scenes touched yet — current parchment look unchanged on screen

### Tag: `v0.15.0`

---

## Phase 14b — Apply Amethyst theme to the root + sweep Settings / Ledger / Bestiary card details (cosmetic only)

**Goal:** make the entire app render in Dusk colors with one root-theme assignment, then audit the few inline `add_theme_color_override` calls that leak the old parchment palette through.

### Approach

1. `main.gd._apply_mobile_default_theme` keeps its job (font sizes, Phase 13d tap-target padding) but **stops creating a fresh Theme**. Instead, load `assets/themes/dusk/amethyst.tres` and override the same font_size + content_margin values onto it (or, cleaner, move those overrides into `DuskThemeBuilder` itself and delete the per-tab parchment theme).
2. `palette_colors.gd` (the existing parchment palette referenced from ~14 view files) gets a compatibility layer: each color name now returns the Dusk equivalent. e.g., `_PALETTE.PARCHMENT` → `PaletteDusk.amethyst()["card"]`. View code keeps working but renders Dusk; in 14d–14f those references migrate to the type-variation system and the compat layer goes away.
3. Sweep the 17 inline `add_theme_color_override` call sites — most are passing a parchment color to a label that should now use a theme variation.
4. **No structural / layout changes** — currency_bar still has 3 chips, bottom nav still has 5 buttons, etc. Pure repaint.

### Visual regression deliverables

- New `tests/snapshots/phase14b/` reference set (10 PNGs — one per primary tab + Settings + Bestiary + Battle idle + Catching empty)
- Compare against handoff PNGs `01-catch-mid-amethyst.png`, `08-battle-stub.png`, `09-inventory-stub.png`, `10-upgrades-stub.png`, `11-more-stub.png`
- New GUT case: `test_root_theme_is_dusk_amethyst.gd` — instantiates main, asserts `get_tree().root.theme.resource_path == "res://assets/themes/dusk/amethyst.tres"`

### Risk + mitigation

- **Some inline color overrides are gameplay-meaningful** (e.g., the wipe-save button uses `BLOOD_RUBY` to signal "destructive"). Keep those — map to `PaletteDusk.amethyst()["danger"]` so the semantic survives the palette change.

### Tag: `v0.15.1`

---

## Phase 14c — Catch screen chrome (HUD + Tier ribbon + auto-net)

**Goal:** replace the current `currency_bar` with the three "currency pill" cards from styles.css, swap the existing "next goal chip" for the Tier ribbon, and add the auto-net widget per the handoff.

### Touched files

- `game/scenes/ui/currency_bar.gd` + `currency_chip.gd` — repaint as three pixel-cards with 22×22 colored glyph squares, 7-px UPPERCASE label above, 11-px value below. Use `theme_type_variation = "DisplaySmall"` for the glyph, `"UiTiny"` for the label, default Silkscreen for the value.
- `game/scenes/ui/next_goal_chip.gd` → rename to `tier_ribbon.gd`. Add the `T2` badge + species progress + 8-px teal→magenta gradient bar + right-aligned %.
- New `game/scenes/ui/auto_net_widget.gd` — pulsing teal dot, 6-px progress bar (3-s loop), level + cooldown text. Show iff at least one auto-net is owned.
- `game/scenes/catching/catching_view.gd` — drop the old `_build_drops_2x_button` placement maths in favour of the auto-net widget anchor (`top: 92px right: 14px` per styles.css).

### Animations

The README's animation table per element. Phase 14c covers:
- Auto-net `net-fill` (3-s loop, 0%→100% bar fill)
- Auto-net dot `pulse-dot` (1.4-s opacity 0.6↔1)
- Tier ribbon progress (teal→magenta gradient — texture or shader)
- Currency pill press feedback (existing Phase 13f haptic gradient already covers this)

### Visual regression deliverables

- Updated `tests/snapshots/phase14c/` set, primary target = handoff `01-catch-mid-amethyst.png`
- Gradient bar: pixel-tolerance set higher (≤8 LSB on the gradient strip alone) since shader output varies per-driver
- `test_currency_bar_uses_dusk_variations.gd` — three chips' labels each use `UiTiny`, values use default UI, glyphs use `DisplaySmall`

### Tag: `v0.15.2`

---

## Phase 14d — Map background + scanline overlay + monster card chrome

**Goal:** swap the current parchment / paper-grain catching background for the dusk repeating-band map per styles.css `.map`, add the scanline overlay, and put pixel-card frames around the existing monster sprites.

### Touched files

- `game/scenes/catching/catching_background.gd` — repeating horizontal-band background (16 px stripes alternating `bg` / `bg_2`), faint scanline overlay (`linear-gradient(transparent 50%, rgba(0,0,0,0.10) 50%)` × 4 px tall, multiply blend, opacity 0.35). Plus radial dusk glows. The existing parallax horizon-glow code can be repurposed — same shader idea, new colors.
- `game/scenes/catching/monster_instance.gd` — add the 92-px-wide pixel-card chrome around the existing 32×32 sprite (which keeps using the project's pixel art — README is explicit that real monster sprites stay). Card has the small-cap `WISPLET · T2` label below the sprite, 8-px Silkscreen, white text on a 1-px-bordered black-tinted card.
- 4–5 vignette props per tier (`game/data/vignettes/tier_<n>.tres`) — small ASCII labels at fixed % positions, 50% opacity. Data is in `data.js → MAP_VIGNETTES` — port to `.tres` Resources.

### Pixel sharpness

Project Settings → Rendering → Textures → Default Texture Filter is already `0` (Nearest) per `project.godot:58` — no change needed. Verify by checking `_build_amethyst().resource_local_to_scene` style stays nearest-neighbor.

### Visual regression deliverables

- `tests/snapshots/phase14d/` for early / mid / late tier (matching handoff `02`, `01`, `03`)
- Multi-tier coverage so the vignette swap works at every tier

### Tag: `v0.15.3`

---

## Phase 14e — Peniber dialog ribbon + intro overlay (replace narrator_overlay)

**Goal:** swap the current sepia-toned narrator scroll for the dusk pixel-card with gold "PENIBER" name pin, 28×28 wizard portrait, VT323 typewriter body. Also build the first-launch intro overlay per the handoff (4 beats from `data.js → PENIBER_INTRO`).

### Touched files

- `game/scenes/ui/narrator_overlay.gd` → rebuild as `peniber_ribbon.gd` per `.peniber` styles.css. Anchor bottom, full width minus 14-px gutter, `12 + tab_bar_height` from bottom. Uses `theme_type_variation = "BodyText"` (VT323 18) + `"DisplaySmall"` for the gold name. Typewriter is a tween on a `RichTextLabel`'s `visible_characters` property.
- New `game/scenes/ui/peniber_intro_overlay.gd` — dim backdrop, title with flicker animation, wizard sprite (use a real pixel sprite if you have one; otherwise the prototype's geometric stand-in is acceptable for v0.15.4 with a polish pass later), dialog bubble with page-dot indicators.
- `game/scenes/ui/peniber_ribbon.gd` subscribes to existing EventBus events — `monster_caught`, `tier_completed`, `prestige_triggered`, etc. — and shows the matching `PENIBER_BARKS` line. The existing `peniber-voice.md` doc is the source of truth for the bark inventory; the handoff's `data.js` lines are *additional* options to consider.
- `TutorialState` already tracks intro-shown; reuse it to gate the intro overlay.

### Animations

- `peniber-in` 280 ms slide-up + fade
- Typewriter at 18 ms/char (gameplay) / 22 ms/char (intro)
- Caret blink 600 ms, square gold block 6×14
- Intro title flicker 4-s loop (90% / 92% drop / 94% / 100%)
- Wizard float 3.4-s ±6 px
- Hat sparkle 2-s loop

### Visual regression deliverables

- `tests/snapshots/phase14e/` for ribbon (idle / typing / dismissed) + intro overlay (each of 4 beats)
- Match handoff `12-peniber-intro.png`

### Tag: `v0.15.4`

---

## Phase 14f — Bottom nav + alt-palette switcher in Settings

**Goal:** swap the existing 5-button bottom nav for the styles.css `.tabbar` (bg-deep base, 2-px border-top, gold-pressed-state for the active tab). Add a "Theme" picker in Settings that swaps between the three Dusk palettes at runtime.

### Touched files

- `game/scenes/main.gd._build_nav_buttons` — repaint with the per-state styleboxes (active = gold top inset bar, gold glyph, gold label, lifted card_2 bg). Use `theme_type_variation` for the active-state distinction rather than per-button color overrides — keeps the palette swap in 14f cheap.
- `Settings.theme_id: String` — new field, default `"amethyst"`. Setter routes through to `Window.set_theme(load("res://assets/themes/dusk/%s.tres" % theme_id))`. Persisted via the existing settings.cfg.
- `game/scenes/ui/settings_view.gd` — new "Theme" section above the existing Audio section: 3 toggle-Buttons in an HBox (Amethyst / Twilight / Ember), each tinted to its primary card color so the picker is itself self-illustrating.

### Visual regression deliverables

- `tests/snapshots/phase14f/` covers active-tab state for each of 5 tabs × 3 palettes = 15 PNGs (or sample 3 — Catch on Amethyst, Battle on Twilight, Inventory on Ember)
- Match handoff `06-theme-twilight.png` and `07-theme-ember.png`
- New GUT case: `test_settings_theme_picker_persists` — sets theme_id, reloads Settings, asserts persisted

### Tag: `v0.15.5`

---

## Phase 14g — Polish pass (RPG-window L-bracket corners, animation curves, audio sting timing)

**Goal:** the deferred details that needed the rest of the system in place first.

### Items

- **Gold L-bracket card corners** — every `pixel-card` (HUD pills, auto-net, Peniber ribbon, etc.) gets the 6×2-px gold brackets at all four corners. styles.css uses `::before` pseudo-elements with eight `linear-gradient` lines; in Godot this is a `StyleBoxTexture` with a 9-slice atlas drawn-in or a small overlay Control. Pick one — atlas is cheaper at runtime, overlay is data-driven and can pull color from the active palette.
- **Float-gain numbers** — replace the existing `floating_number.gd` with the styles.css `.float-gain` look (Silkscreen 11 px, gold for +N G, teal for +1 ItemName, 1.1-s ease-out + scale 0.7→1.1→1).
- **Catch animation** swap — current implementation uses parchment-style fade; new is 360 ms scale 1→1.2→0.1 + 8°→-20° rotation + opacity → 0 (CSS keyframes already in styles.css).
- **Toast** — replace tier-completion toast with the gold-bordered `.toast` (240 ms slide + 1.6 s hold + 240 ms slide-out). Existing celebration_overlay handles the major events; toast is for less-loud beats.
- **Audio sting re-timing** — already covered by Phase 13f's haptic gradient, but pair the haptic with an audio sting on shiny / tier / prestige if not already.

### Visual regression deliverables

- `tests/snapshots/phase14g/` covers static states only; the animation polish needs frame-stepped capture which is overkill for one phase. A single "before vs after" PNG of the catch screen with the L-corners visible suffices.

### Tag: `v0.15.6`

---

## Out of scope (separate efforts after Phase 14)

- **Real wizard sprite** for Peniber portrait + intro — the prototype's geometric stand-in works as v0.15.x placeholder. A pixel-art sprite is its own commission.
- **Sprite art for monsters at the Dusk palette saturation** — README says keep existing sprites. If they end up looking off against the new dark backgrounds, that's a separate art pass.
- **Localisation** — Settings Phase 13g hid the dead Language picker; the Dusk theme uses the same fonts so re-enabling it is independent of theming.

---

## Per-phase ship loop (for reference)

Same pattern as Phase 12–13:

1. Implement on `main` directly (Maestro is the device-level signal).
2. Run `tools/build_dusk_themes.gd` if any palette token / builder constant changed.
3. Run the full GUT suite headlessly. Fix any failures before commit.
4. Run the new render-snapshot job for the affected phase. Update reference PNGs only if the new output is genuinely correct vs the handoff target.
5. Commit + push + tag `v0.15.<n>` + `phase-14<sub>-complete`.
6. Watch CI: Build / Release / Maestro / Pages should all turn green within 15 minutes.
7. After CI lands green, eyeball the live build against the handoff PNGs side-by-side. Discrepancies become 14g-followup or the next phase.
