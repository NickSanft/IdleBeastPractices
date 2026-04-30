# 0005 — BigNumber as mantissa + exponent

## Status
Accepted — 2026-04-30

## Context
An idle game accumulates currency well past `2^63`. Plain `int` overflows; plain `float` (IEEE 754 double) loses integer precision past `2^53` and exhibits compounding rounding errors over long sessions. Idle-game canon (Cookie Clicker, Antimatter Dimensions) uses a mantissa/exponent representation in base 10.

## Decision
Implement `BigNumber` as a `RefCounted` GDScript class with `var mantissa: float` (normalized to `1.0 <= |m| < 10.0` or zero) and `var exponent: int`. All currency math goes through this class. Float currency in `game/systems/` is banned (lint check planned for Phase 1+).

## Consequences
- **+** Effectively unbounded value range (exponent is a 64-bit int; we'll never reach `e+9.2 × 10^18`).
- **+** Display formatting is trivial: group exponent by 3, look up suffix.
- **+** Serializes cleanly to JSON as `{"m": float, "e": int}`.
- **−** Mantissa retains float precision (~15 decimal digits); fine for game display, not for financial math.
- **−** Add/subtract with very different exponents loses the smaller term. Capped at a 16-shift threshold; below that, the smaller term is below float epsilon anyway.
- **−** Slower than a native int for small values. Negligible at game-scale operation counts.
