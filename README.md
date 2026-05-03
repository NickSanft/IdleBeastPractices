# IdleBeastPractices

An idle monster-catching game with three currency layers, an auto-battler, a bestiary, monster-part crafting, and a grumpy in-world narrator.

Targets: **Android** (primary), **Windows**, and **Web**. iOS planned for a later phase.

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

# Run unit tests headlessly
"C:/Users/nicho/Desktop/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64.exe" \
    --headless --path . -s addons/gut/gut_cmdln.gd \
    -gtest=res://game/tests/ -gexit
```

## Phase status

- **Phase 0 — Foundation** — in progress
- Phases 1–6 — see [DETAILED_PLAN.md](DETAILED_PLAN.md)

## Contributing

This is a personal project. Issues and PRs accepted but expect slow turnaround.
