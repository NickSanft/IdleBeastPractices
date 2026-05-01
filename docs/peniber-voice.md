# Peniber's Voice — Authoring Guide

Peniber is the in-world narrator. He addresses the player directly. The tone is the project's only consistent comedic register, so this guide exists to keep new dialogue lines from drifting.

## Who he is

**Peniber Perspicacious Similacrus, Agonothetes of the Sortilege Synod.**

The full name is said only once, on first launch. After that he's just *Peniber*. The Synod is a vague off-screen institution that issues incomprehensible directives, runs tedious ceremonies, and keeps Peniber on retainer for reasons it has never explained to him. Peniber has never met the player in person and is mildly affronted by the implication that he should.

## How he talks

Five tonal levers, in rough order of how often they fire:

1. **Verbose.** Two clauses where one would do; an em-dash where a comma would. He'd rather build a sentence than truncate one.
2. **Condescending.** Mild, never cruel. He underestimates the player by reflex but is nervous about being seen doing it.
3. **Archaic.** Words and constructions a Victorian under-secretary would recognize. *Manifest, Synod, agonothetes, commendation, posterity, intermission, sabbatical, drudgery, lawyers were very specific on this point.*
4. **Begrudging.** When the player does well, he lets praise slip — and immediately undermines it ("a flicker of something like respect, which I attribute to a draught").
5. **Secretly invested.** He doesn't admit he cares. He cares.

He is **not**:
- Loud. No exclamations.
- Sarcastic in a modern way. He never says "great job" to mean the opposite.
- Self-pitying. He's tired, not whining.
- Wholesome. The Synod ate his Reginald.

## Mood field

Each `DialogueLineResource` has a `mood: StringName` that the overlay uses to tint the bubble. Use one of:

- `smug` — default for catching banter and milestone gloats.
- `begrudging` — when the player does well and he's losing the war against his own pride.
- `reverent` — first-of-something, shinies, tier completions, prestige.
- `weary` — institutional fatigue. Synod-bureaucracy lines, idle nags.
- `exasperated` — battle losses, the third idle nag, late-stage failures.

The overlay's `_MOOD_TINTS` dictionary translates these to bubble colour; if you add a new mood, add a tint there too.

## Trigger taxonomy

Every line carries a `trigger_id` that maps to a place the Narrator autoload can fire. The table below lists the triggers used in Phase 5a and the planned scope for Phase 5b–post.

| Trigger | Phase 5a count | Notes |
|---|---|---|
| `on_first_launch` | 1 (max_uses=1) | Full title appears here, never again. |
| `on_first_catch_ever` | 1 (max_uses=1) | Fires once total. |
| `on_first_catch_<species_id>` | 9 (one per species, max_uses=1) | Per Tier-1/2/3 species. Add one per future species. |
| `on_milestone_10` / `_100` / `_1000` / `_10000` | 4 (max_uses=1 each) | Tied to `ledger.total_catches`. |
| `on_first_shiny` | 1 (max_uses=1) | First shiny ever. |
| `on_shiny` | 3 (pool, max_uses=0) | Subsequent shinies — weighted random over the pool. |
| `on_first_pet_acquired` | 1 (max_uses=1) | First pet awarded. |
| `on_pet_acquired` | 2 (pool) | Subsequent pet acquisitions. |
| `on_first_battle_win` | 1 (max_uses=1) | First win. |
| `on_battle_win` | 2 (pool) | Subsequent wins. |
| `on_battle_loss` | 3 (pool) | Every loss. |
| `on_tier_complete_<n>` | 3 (max_uses=1 each) | One per content tier. Add `on_tier_complete_4` etc. when tier-4+ ships. |
| `on_first_prestige` | 1 (max_uses=1) | First prestige reset. |
| `on_prestige` | 2 (pool) | Subsequent prestiges. |
| `on_idle_too_long` | 3 (pool) | Fires after 5 min of no input; cooldown 90 s between fires. |
| `on_offline_return_short` | 2 (pool) | Returns < 10 min of credited offline time. |
| `on_offline_return_long` | 2 (pool) | Returns ≥ 10 min. |
| `on_first_craft` | 1 (max_uses=1) | First successful craft. |
| `on_ledger_opened` | 3 (pool) | Fires when the Ledger tab becomes visible. |

## Selection rules

`Narrator.try_speak(trigger_id)` picks a line via:

1. Filter all loaded lines by `trigger_id`.
2. Drop lines whose `min_total_catches` / `min_prestige_count` aren't met.
3. Drop lines whose `max_uses` is reached (counted from `GameState.narrator_state.lines_seen`).
4. Drop lines whose `id` is in the recent-window (last 5 spoken). Anti-clustering.
5. Weighted-random pick by `weight`.

`weight` defaults to 1.0. Use 0.5 for "rare" pool variants and 2.0 for "common" ones. Don't go nuts.

## When in doubt

A good Peniber line passes three checks:
- **Could a Victorian under-secretary have said this?** If no, scrap.
- **Does it underestimate the player without being mean?** If it crosses into mean, soften with a complicated word.
- **Does it have a quiet beat that suggests Peniber would actually like the player to do well?** If it doesn't, you're writing an antagonist; rewrite.

## Phase 5b targets

Phase 5b will fill out the corpus toward the parent plan's ~150 lines:

- Add 1–2 more variants to each pool to thicken the rotation.
- `on_tier_complete_4` through `on_tier_complete_20` once tier content lands.
- `on_first_catch_<species>` for every new species (Phase 5b authors tiers 4–20, ~51 new species).
- More `on_idle_too_long` lines so the same nag isn't repeating.
- Conditional lines using `min_total_catches` / `min_prestige_count` so late-game players hear different variants of the same trigger.
