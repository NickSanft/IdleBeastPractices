# 0001 — Engine: Godot 4.6.1-stable (mono)

## Status
Accepted — 2026-04-30

## Context
We need a 2D-capable game engine that exports to Android, Windows, and Web from one codebase, with a permissive license, an active community, a usable scene/UI editor, and ergonomic scripting. Candidates considered: Godot, Unity, Unreal, Defold.

## Decision
Use **Godot 4.6.1-stable, mono build**, pinned in `project.godot` and CI. Even though no C# is planned, the mono build runs GDScript projects identically and leaves the door open for a single perf-critical subsystem in C# if a profiling pass later demands it (per ADR 0002).

## Consequences
- **+** MIT-licensed; no royalties or seat costs.
- **+** Built-in 2D toolchain, scene system, and Control nodes cover all Phase-0–5 UI needs without third-party libs.
- **+** Single codebase exports cleanly to Android, Windows, and Web.
- **+** GDScript is fast to author and the static-typed dialect catches most bugs at parse time.
- **−** Smaller asset-store ecosystem than Unity (we vendor everything we need).
- **−** Mono build is ~100 MB larger than the standard editor; trivial overhead.
- **−** Web export uses Godot's WASM runtime; large initial download (mitigated by hosting and HTTP caching).
