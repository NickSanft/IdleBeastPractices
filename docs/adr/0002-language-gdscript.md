# 0002 — Language: GDScript (with C# escape hatch)

## Status
Accepted — 2026-04-30

## Context
Godot supports GDScript and C#. C# is faster for tight loops and has IDE tooling parity with mainstream languages; GDScript is more concise, has no compile step, integrates more tightly with the editor, and avoids the mono build complexity for content authors.

## Decision
Use **GDScript** for all game code. C# is allowed only if a profiling pass identifies a hot loop where GDScript is the bottleneck — and only inside `game/systems/` for that one subsystem, documented in a follow-up ADR.

## Consequences
- **+** No compile step; saves a few seconds per iteration.
- **+** All systems live in one language; no GDScript ↔ C# marshalling.
- **+** Static-typed GDScript catches type errors at parse time.
- **+** Editor integration (autocomplete, refactor) is best-in-class for GDScript.
- **−** GDScript is slower than C# for compute-heavy loops; the BigNumber and BattleSystem are the most likely candidates if perf becomes an issue. We profile before assuming.
- **−** Tooling outside Godot (linters, formatters) is sparser than for C#; we accept that and rely on the editor.
