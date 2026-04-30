# 0003 — Content as `.tres` Resources

## Status
Accepted — 2026-04-30

## Context
We will ship 20 tiers of monsters, pets, nets, items, upgrades, recipes, and ~150 dialogue lines. Each is a piece of authorable content with named fields. Two main options:
1. Hardcoded constants / enums in code.
2. Engine-native `.tres` resource files with typed schemas.

## Decision
Every monster, pet, net, item, upgrade, crafting recipe, and dialogue line is a **`.tres` Resource file** backed by a typed `Resource` subclass in `game/resources/`. New content is added by creating a `.tres` in the editor — never by editing code.

## Consequences
- **+** Content scales linearly without code edits; non-engineers can author.
- **+** The Godot editor renders an inspector for each resource type, surfacing typed fields with validation.
- **+** Schemas live in code (`*.gd` files extending `Resource`); evolving the schema is a single-file change with editor migration.
- **+** Tests can assert content invariants (every monster has a non-null sprite, every recipe has at least one input) by walking the `.tres` directory.
- **−** Schema changes mid-development require updating every `.tres` in the field; mitigated by keeping content thin during Phase 0.
- **−** Loading hundreds of resources at startup is slow if naive; we cache via lazy directory scans (deferred until perf demands it).
