# 0006 — Deterministic, seeded battle simulation

## Status
Accepted — 2026-04-30

## Context
Pet auto-battles (Phase 2) need to feel responsive on screen but also resolve correctly when the player isn't watching. If we tick the simulation in real-time tied to the UI, leaving the screen mid-battle creates two failure modes: the battle pauses (boring) or runs at uneven rates depending on framerate (incorrect outcomes). We also want save/replay parity for debugging.

## Decision
`BattleSystem.simulate(seed, player_team, enemy_team) -> BattleLog` is **pure and deterministic**: same inputs → byte-identical output. The full battle is computed up front from a seed, producing an `Array[Dictionary]` of frames. The UI is a replay layer that walks frames at a configurable speed; it can speed up, pause, or skip without changing the outcome.

## Consequences
- **+** Same seed produces same outcome — we test for byte-equality in CI (Phase 2).
- **+** Leaving the screen mid-battle is safe; the result is already determined.
- **+** Bug reports can include `seed` + `team` and reproduce the exact battle.
- **+** Speed-up button is free.
- **−** Compute happens up-front rather than amortized over animation. Capped at 600 ticks (= 2.5 min) per battle so the cost is bounded.
- **−** Memory cost: BattleLog can be a few thousand frames per battle. Bounded; freed when battle ends.
- **−** All RNG must flow through the seeded `RandomNumberGenerator`. Calls to `randi()` / `randf()` outside that RNG are bugs that break determinism; reviewed in PRs.
