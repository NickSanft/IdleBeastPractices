# 0007 — Platform priority: Android primary, Windows + Web in lockstep, iOS deferred

## Status
Accepted — 2026-04-30

## Context
The game targets idle-genre players who play in short bursts on phones. Mobile is the primary surface area; desktop and web are nice-to-haves that keep the audience reachable. iOS adds App Store compliance, Apple Developer enrollment, and device-specific testing that doubles the platform-validation cost.

## Decision
Phase 0–6 ships all builds for **Android** (signed AAB, Play Store release track), **Windows** (zip), and **Web** (HTML5 hosted somewhere TBD), in lockstep on every release. **iOS** is deferred to a post-1.0 phase (Phase 8 in the parent plan). Renderer is **GL Compatibility** (GLES3-equivalent) for maximum reach across older Android, low-end web, and integrated desktop GPUs.

## Consequences
- **+** Single primary target keeps gameplay tuning focused (touch input, portrait UI, short-session pacing).
- **+** Web build is essentially free given the GL Compatibility renderer.
- **+** Windows build is free given the GL Compatibility renderer and gives us a fast iteration loop in the editor.
- **+** CI exports all three on every push so we never ship a regressed platform.
- **−** No iOS player base reachable until post-1.0. Acceptable given the cost of cross-store maintenance pre-launch.
- **−** Forward+ renderer effects (volumetric fog, etc.) unavailable. None of the game's design needs them.
- **−** Touch-first input means desktop/web feel slightly weird until Phase 5 polish adds proper hover/click affordances.
