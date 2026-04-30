# 0004 — Save format: versioned JSON with migration chain

## Status
Accepted — 2026-04-30

## Context
Saves must survive schema changes across the project's lifetime. Options considered: Godot binary `Resource` saves, custom binary, JSON, SQLite. Godot binary saves are tightly coupled to class layouts and break loudly when fields rename; SQLite is overkill; custom binary needs hand-rolled migrations anyway.

## Decision
Saves are **versioned JSON** at `user://save.json`, written atomically (write to `.tmp`, then rename). A migration chain (`game/systems/save_migrations.gd`) registers pure functions `Dictionary -> Dictionary` from version `n` to `n+1`. On load, every applicable migration runs in order.

## Consequences
- **+** Human-readable saves; easy to diff during development and to debug player reports.
- **+** Migrations are explicit, testable units; one fixture per historical version locks the contract.
- **+** Atomic writes prevent corruption from crashes mid-save.
- **+** Backend abstraction (`SaveBackend`) allows swapping in cloud sync later (Phase 7) without touching `SaveManager` callers.
- **−** Larger files than binary; negligible for a save under 1 MB.
- **−** JSON has no native int64 distinction; we store BigNumber as `{"m": float, "e": int}` rather than as a single huge number.
- **−** Forgetting to register a migration after a schema bump is silent. Mitigated by a CI check in Phase 1+ that fails if `CURRENT_VERSION` advanced without a matching migration entry.
