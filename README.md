# IdleBeastPractices

An idle monster-catching game with three currency layers, an auto-battler, a bestiary, monster-part crafting, and a grumpy in-world narrator.

Targets: **Android** (primary), **Windows**, and **Web**. iOS planned for a later phase.

## Features

**Core loop**
- Tap-to-catch plus idle **auto-catch** via purchasable nets, across monster tiers / biomes, with shinies to chase.
- A **bestiary** you fill out, with overall completion meters and a scaling tier-completion Rancher-Points bonus.

**Progression**
- A gold economy with upgrades, **monster-part crafting** + equippable pet gear, a pet **auto-battler**, and **prestige** for Rancher Points (the run-surviving meta-currency).

**Goals & retention**
- **Three-tier concurrent quests** (short / medium / long) shown in a persistent strip.
- **Daily-login streak reward** — an escalating 7-day cycle with a day-7 milestone bonus _(v0.15.14)_.
- **Resetting daily quests** — a fresh set each local day that track a per-day delta, with a complete-all bonus, in a dedicated Daily view _(v0.15.15)_.
- **Offline progress** with a welcome-back summary (and a testable local-notification seam awaiting a native plugin).

**Polish & platform**
- A grumpy in-world **narrator** (Peniber) reacting to play.
- A pixel-RPG "Dusk" theme with swappable palettes (Amethyst / Twilight / Ember).
- **Accessibility** — a font-size slider that scales the whole themed UI _(v0.15.13)_, reduce-motion, and haptics toggles.
- **Android-first** layout — portrait lock, safe-area insets, orientation-aware composition, and hardware-Back navigation; plus cloud save via Google Play Games with a conflict-merge resolver.

See [CHANGELOG.md](CHANGELOG.md) for the full version-by-version history.

## Tech stack

| Concern | Choice |
|---|---|
| Engine | **Godot 4.6.1-stable (mono)** — pinned in `project.godot`. Mono build runs the GDScript-only project; no C# is used. |
| Language | GDScript |
| UI | Godot Control nodes + custom theme |
| Testing | [GUT](https://github.com/bitwes/Gut) (unit tests, vendored in `addons/gut/`) + [Maestro](https://maestro.mobile.dev) (Android emulator UI flows in [`tests/maestro/`](tests/maestro/)) |
| Save format | Versioned JSON with a migration chain |
| CI/CD | GitHub Actions (`barichello/godot-ci:4.6.1` container) |

## Repository layout

See [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) §3 for the canonical layout and [DETAILED_PLAN.md](DETAILED_PLAN.md) for phase-by-phase build sheets.

## Local build / run

```sh
# Open in editor
"C:/Users/nicho/Desktop/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64.exe" --path .

# Run the full unit-test suite headlessly (same invocation as CI)
"C:/Users/nicho/Desktop/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64.exe" \
    --headless --path . -s addons/gut/gut_cmdln.gd \
    -gdir=res://game/tests/ -ginclude_subdirs -gexit
```

## Project status

Active development — current release **v0.15.15**. The foundational phases (0–6) are complete; ongoing work is tracked in [CHANGELOG.md](CHANGELOG.md), with the original phase-by-phase build sheets in [DETAILED_PLAN.md](DETAILED_PLAN.md).

Recent focus has been a UI/UX research-driven polish pass: accessibility font scaling _(v0.15.13)_ and the retention bundle — a daily-login streak _(v0.15.14)_ and resetting daily quests _(v0.15.15)_.

## Contributing

This is a personal project. Issues and PRs accepted but expect slow turnaround.
