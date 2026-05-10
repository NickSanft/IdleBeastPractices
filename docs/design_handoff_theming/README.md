# Handoff: IdleBeastPractices — Dusk Pixel-RPG Theming

## Overview
Visual theming + UI/UX direction for the existing **IdleBeastPractices** Godot 4.6 idle monster-catching game (https://github.com/NickSanft/IdleBeastPractices). The current game logic stays as-is; this package is about **how it should look and feel**: a "dusk pixel-RPG" aesthetic with deep amethyst + teal + warm gold, pixel display fonts, and an old-school RPG window vocabulary.

Primary target: **Android portrait**. Secondary: PC + browser at the same aspect or letterboxed.

## About the Design Files
The files in `reference_files/` are **HTML/React design references** built to communicate look + behavior. They are NOT meant to be copied into Godot directly. The task is to **recreate the visual system in Godot** using its theme system (`Theme` resources, `StyleBoxFlat` / `StyleBoxTexture`, custom fonts, custom controls) so the live game matches what the prototype shows.

If you want to run the prototype to see it move, open `reference_files/IdleBeastPractices.html` in any modern browser.

## Fidelity
**High-fidelity for theming.** Colors, typography, spacing, animations, and chrome are all final-pass and should be matched closely.

The **layout direction** (HUD placement, monster spawn cards, Peniber dialog ribbon, tab bar) is also high-fidelity but the prototype offers three HUD variants (Top bar / Floating / Side rail) — see Tweaks. Pick one per the in-game decision; the default is **Top bar**.

Monster sprites in the prototype are **labeled placeholder boxes** (`SLIME · BOG`, `WISPLET · T2`, etc.) — the real Godot game already has pixel sprites; keep using those. The prototype is showing where they go and the chrome around them.

---

## Design Tokens

### Color · Default theme "Amethyst"
| Token | Hex | Use |
|---|---|---|
| `bg-deep` | `#0c0820` | Phone screen base, behind everything |
| `bg` | `#15102e` | Map base color (band A) |
| `bg-2` | `#1d1640` | Map base color (band B), tile alternate |
| `card` | `#251b52` | Panels, currency pills, dialog box |
| `card-2` | `#2f2364` | Card hover / inner highlight |
| `border` | `#4a3a8a` | Card borders, all framed UI |
| `border-soft` | `#3a2d6f` | Inner divider, faded border |
| `ink` | `#ece4ff` | Primary text |
| `ink-dim` | `#b6a8de` | Secondary text |
| `ink-mute` | `#8576b6` | Tertiary / disabled text |
| `gold` | `#f5c46b` | Accent — currency, active tab, CTA, Peniber name |
| `gold-dark` | `#b8862e` | Gold border / shadow |
| `teal` | `#5fd3c2` | Accent — Rancher Points, HP bars, auto-net |
| `teal-dark` | `#2e8a82` | Teal border / shadow |
| `magenta` | `#d96fb8` | Accent — Shinies, T2 species hue |
| `rose` | `#ef6f8a` | Accent — alerts, T3 species hue |
| `danger` | `#ff6b6b` | Errors only |

### Color · Alt theme "Twilight Teal" (sub option)
`bg-deep #061518`, `bg #0a2024`, `bg-2 #0f2c32`, `card #143a40`, `border #2e7a82`, `ink #e0f7f4`, `gold #f0b95a`, `magenta #ff89a8`. Same teal.

### Color · Alt theme "Embered Plum" (sub option)
`bg-deep #1a0814`, `bg #2a1020`, `bg-2 #381a2c`, `card #4a2238`, `border #8a3f6a`, `ink #ffe8f4`, `gold #ffb84d`, `magenta #ff7090`.

> Implement all three as Godot `Theme` resources so the player (or the game's settings menu) can switch palettes.

### Typography
| Role | Font | Use |
|---|---|---|
| Display (titles, glyphs, currency labels) | **Press Start 2P** | Headline title, currency glyphs (`G` `R` `★`), tier badge `T1`/`T2`/`T3`, big section headers |
| UI (labels, buttons, captions) | **Silkscreen** (400) | Tab labels, button text, monster label boxes, HUD labels |
| Body (Peniber dialog, longform) | **VT323** | All Peniber speech, descriptions, supporting copy |

Sizes (anchor: 412×892 design viewport):
- Display title: **18px**, letter-spacing `0.05em`, gold, 2px black drop-shadow + soft 24px gold glow
- Section header (Stub screens): **12px** gold
- Tab label: **9px** uppercase, letter-spacing `0.05em`
- Currency value: **11px** ink, letter-spacing `0.04em`
- Currency lbl (`GOLD`/`RANCHER`/`SHINIES`): **7px** ink-mute uppercase
- Monster label box: **8px** uppercase
- Peniber name: **10px** display gold
- Peniber body: **17–19px** VT323 ink
- Vignette/scenery labels: **7px** ink-dim

Free fonts — load from Google Fonts (`Press Start 2P`, `Silkscreen`, `VT323`) or vendor the OFL `.ttf` files into `assets/fonts/` and import as `FontFile` resources in Godot.

### Spacing
- Phone safe gutter: **14px**
- HUD height (top bar): **56px**
- Tab bar height: **64px**
- Card inner padding: **10–14px**
- Vertical rhythm between rows: **8px**
- Pixel grid base (where it matters for sprite alignment): **8px tile**

### Borders & shadow
- All cards: **2px solid `border`**, plus **inset 2px `rgba(0,0,0,0.35)`**, plus **0 4px 0 `rgba(0,0,0,0.4)`** drop shadow (no blur — it's an offset block, classic chunky pixel-UI)
- Buttons: **2px border**, **0 3px 0 #00000080** drop, lift on press by translating Y +2px
- Cards have **gold L-shaped corner notches** (6×2px brackets at each corner) — this is the "RPG window" detail. In Godot use a 9-slice `StyleBoxTexture` with corners drawn in.
- No `border-radius` anywhere except the phone bezel itself. **Square corners** are part of the aesthetic.

### Image rendering
- Use **nearest-neighbor scaling** everywhere (`image-rendering: pixelated` in CSS — in Godot, set `Project Settings → Rendering → Textures → Default Texture Filter = Nearest`).

---

## Screens / Views

### 1. Catch screen (`src/screens/Catch`)
**Purpose:** primary play loop — monsters spawn on a tile-mapped backdrop, player taps to catch.

**Layout (top → bottom):**
1. **Status bar** (28px) — system overlay; in real Godot you'd just use the OS status bar + a 28px safe area padding.
2. **HUD** (56px, 3 currency pills): Gold | Rancher (RP) | Shinies. Each pill: 22×22 colored glyph square (`G` gold, `R` teal, `★` magenta) + 7px label above + 11px value. Equal flex.
3. **Tier ribbon** (~36px): badge `T2` + tier name (`Whisper Glade`) in ink with `b` highlighted gold, "/SPECIES" suffix in ink, 8px progress bar (teal→magenta gradient with teal glow), `%` value right-aligned.
4. **Map** (flex 1): repeating horizontal-band background (16px stripes alternating bg/bg-2), faint scanline overlay (4px tall, multiply blend, opacity 0.35), radial dusk glows behind. 4–5 vignette props ("BOG · LANTERN", "STONE · MOSS") at fixed positions, 50% opacity, decorative only.
5. **Auto-net widget** (top-right of map, 84px wide card): shown only when owned. Pulsing teal dot + "AUTO·NET" header, 6px progress bar that loops every 3s, level + cooldown in 7px text.
6. **Peniber ribbon** (above tab bar, dismissible card): 28×28 wizard portrait (purple body + gold-bordered face + triangle hat), "PENIBER" name in 10px display gold, timestamp in 8px mute, body line typewritten in VT323 17px, blinking gold caret while typing.
7. **Tab bar** (64px): 5 tabs — Catch / Battle / Inv / Upgrade / More. Active tab gets gold top inset bar, gold glyph, gold label, lifted card-2 background.

**Interactions:**
- Monsters spawn at one of 5 fixed positions (`{x,y}` % coords), bob ±4px every 2.6s.
- Tap monster → 360ms catch animation: scale 1→1.2 then 1→0.1, slight rotation, fade. Two float-up texts spawn at the monster's position: `+N G` (gold) and `+1 ItemName` (teal). 1.1s float-up + fade.
- Top of map flashes a gold-bordered toast `CAUGHT · MONSTER LABEL` for 1.9s.
- Peniber ribbon updates to a "caught" bark and re-runs the typewriter.
- Every ~11s with 40% chance, an idle bark replaces the line.
- Tapping the ribbon (or the X) dismisses it; a new bark re-opens it.

### 2. Peniber Intro overlay (`src/screens/Intro`)
**Purpose:** first-launch tutorial; can be replayed.

**Layout:**
- Full-screen dim (rgba(7,5,15,0.92)) with subtle teal radial glow behind Peniber.
- Title group near top: `IDLE BEAST PRACTICES` in 18px Press Start 2P gold with the flicker animation (90% opacity 100%, 92% 60%, 94% 100% — fires every 4s); subtitle "A WIZARD'S RELUCTANT TUTORIAL" in 9px Silkscreen ink-dim, letter-spacing `0.2em`.
- "SKIP ›" link top-right (9px Silkscreen ink-mute → ink on hover).
- **Wizard sprite** centered: floats up/down 6px every 3.4s. Built from layered divs in the prototype — in Godot, use a real pixel sprite; the relative geometry is hat-cone (60×50 triangle, dark purple) + face square (32×32 skin) + black eye dots (4×4 each) + beard triangle (clipped 36×30) + robe trapezoid. Hat tip has a gold sparkle that pulses (scale 1↔0.7, opacity 1↔0.4) every 2s.
- **Dialog bubble**: card with a gold "PENIBER" pin tab on top-left edge (style like a tab sticker). 19px VT323 body with typewriter (22ms per char), blinking caret. Page dot indicators bottom-left (6×6 squares, off=mute, on=gold w/ glow). "FAST ›" / "NEXT ›" / "BEGIN" pixel button bottom-right.
- 4 beats total — see `src/data.js → PENIBER_INTRO`. Tap anywhere on the overlay (outside bubble) to advance / fast-forward.

### 3. Battle stub
**Purpose:** auto-battle arena where pets fight for RP.

When `pets === 0`: empty state — `⚔` glyph + "Complete a tier to earn a pet companion. Then pets battle while you nap." in VT323 18px ink-mute, max-width 260px.

Otherwise: list of pet rows (label + level + role chip + RP/sec) and one "SLOT · LOCKED" placeholder row tied to next tier.

### 4. Inventory stub
List rows of crafting items (`SLIME SLIME × 1240`, `CRACKLE JELLY × 482`, `PIXIE DUST × 24`, etc.). Each row: 36×36 colored thumb (uses the monster's hue), name in 11px Silkscreen, "CRAFT · TRADE · CONSUME" subline in 9px mute, quantity right-aligned in display gold.

### 5. Upgrades stub
"RANCHER UPGRADES" header + a one-line wizard sub ("Permanent. Survive prestige…"). Rows: thumb + name + effect description + cost button (gold pixel button, e.g. `12 RP`).

### 6. More stub
Linked rows for Bestiary / Achievements / Prestige / Settings / Codex. Each row: thumb + name + state line + chevron `›`.

---

## Interactions & Behavior

### Animations (durations + easings)
| Animation | Duration | Easing | Notes |
|---|---|---|---|
| Monster bob | 2.6s loop | ease-in-out | translateY ±4px |
| Monster catch | 360ms | ease-in | scale 1→1.2→0.1 + 8°→-20° + opacity → 0 |
| Float gain | 1.1s | ease-out | translateY 0 → -56px, scale 0.7→1.1→1, opacity 0→1→0 |
| Peniber ribbon enter | 280ms | ease-out | translateY 8px → 0, fade in |
| Toast | 240ms in / 240ms out (after 1.6s hold) | ease-out / ease-in | slide-down + fade |
| Auto-net fill | 3.0s loop | linear | 0% → 100% width |
| Auto-net dot pulse | 1.4s loop | linear | opacity 0.6 ↔ 1 |
| Title flicker | 4s loop | step-keyed | brief drops at 92% mark |
| Wizard float | 3.4s loop | ease-in-out | translateY ±6px |
| Hat sparkle | 2s loop | ease-in-out | scale + opacity |
| Tab press | 60ms | linear | Y +2px depress |
| Caret blink | 600ms | steps(2) | hard on/off |

### Typewriter
~18ms per char during gameplay barks, ~22ms per char during intro. Tapping the bubble during typing = jump to full line; second tap = next page.

### State preservation
- Active tab and current bark in memory only — fine.
- Intro shown flag should persist across launches (Godot `ConfigFile` or save state).

---

## State Management
The prototype reads from a single store keyed by `tier` (`early` / `mid` / `late`). In the real game, derive these values live:

```
progress = {
  tierId, gold, rp, shinies,
  species: { caught, total },
  autoNet: { owned, level },
  pets,
}
```

`tier = TIERS.find(t => t.id === progress.tierId)` then everything in the HUD reads from those two.

---

## Assets
None packaged — everything is CSS/SVG-style primitives drawn from the design tokens. Bring your existing pixel sprites for monsters and Peniber. Free fonts (Press Start 2P, Silkscreen, VT323) are SIL OFL — bundle the .ttf in `assets/fonts/` and register in Godot.

---

## Screenshots
See `screenshots/INDEX.md` for the full list. Twelve PNGs covering: every tab (catch/battle/inventory/upgrades/more), three tier states (early/mid/late), three HUD layouts, three palettes, and the Peniber intro overlay.

## Files
- `reference_files/IdleBeastPractices.html` — entry point
- `reference_files/styles.css` — **the source of truth for the visual system**. CSS variables (top of file) → port to Godot Theme `colors`. Component blocks (`.pixel-card`, `.tabbar`, `.peniber`, etc.) describe each piece in detail.
- `reference_files/components.jsx` — React components for each piece of UI. Use as a structural reference.
- `reference_files/app.jsx` — main composition + Tweaks wiring.
- `reference_files/data.js` — tier defs, Peniber lines, vignette positions, monster drops.

---

## Implementation tips for Godot 4.6

1. **Build the Theme resource first.** Put the Amethyst palette in `assets/themes/amethyst.tres`. Style every `Control` (Button, Panel, ProgressBar, Label) with `StyleBoxFlat` (no rounded corners, 2px border, content margin = 8/10) and the inset shadow as a second StyleBoxFlat behind it, or a 9-slice texture if you want the L-bracket corners.
2. **Custom font setup.** Load the three TTFs as FontFile resources, then assign per-Label-variation in the theme: `display`, `ui`, `body`. Use `Label` `theme_type_variation` to swap.
3. **Pixel sharpness.** Set `Project Settings → Rendering → Textures → Default Texture Filter = Nearest`. Confirm the map background uses point sampling.
4. **HUD.** Three `PanelContainer`s in an `HBoxContainer` with `size_flags_horizontal = EXPAND_FILL` and 6px separation.
5. **Monster spawn cards.** A `Node2D` spawner that instantiates a `Control` scene with the labeled name tag; tween in/out is straight `create_tween().tween_property()` on `scale` + `modulate.a`.
6. **Peniber ribbon.** `PanelContainer` anchored to bottom, full width minus 14px gutter, sitting `12 + tab_bar_height` from bottom. RichTextLabel with `bbcode_enabled = true` to get the gold caret as a separate inline element animated via `Tween`.
7. **Theme switching.** Three `Theme` resources, swap at runtime via `Window.set_theme()` from a Settings menu. The prototype calls these "Amethyst / Twilight / Ember".

If anything is ambiguous, defer to `styles.css` — that file has the exact pixel/color values for every detail.
