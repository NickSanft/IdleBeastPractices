## Phase 12f — persistent meta-goal definition.
##
## Achievements unlock when a tracked metric (typically a Ledger
## field, but also stand-ins like prestige_count) crosses a
## threshold. Once unlocked they don't re-fire — the [`Achievements`]
## autoload tracks `achievements_unlocked` in GameState (persisted)
## and consults it before firing.
##
## Schema is intentionally minimal: pick a source field, pick a
## threshold, optional gold/RP reward. More complex achievements
## (e.g. "catch all tier-1 species") can either compute a derived
## ledger metric upstream or land via a custom trigger in 12f-followups.
class_name AchievementResource
extends Resource

enum Tier { BRONZE, SILVER, GOLD }

## Source fields the trigger evaluator can read. Adding a new source
## means extending [`Achievements._evaluate_trigger`] to map this
## enum to a value.
enum Source {
	LEDGER_FIELD,         # GameState.ledger[field_id] >= threshold
	PRESTIGE_COUNT,       # GameState.prestige_count >= threshold
	PETS_OWNED_COUNT,     # GameState.pets_owned.size() >= threshold
	NETS_OWNED_COUNT,     # GameState.nets_owned.size() >= threshold
	RECIPES_CRAFTED_COUNT, # GameState.recipes_crafted.size() >= threshold
	CURRENT_MAX_TIER,     # GameState.current_max_tier >= threshold
}

@export var id: StringName
@export var display_name: String
@export var description: String = ""
@export var sprite: Texture2D
@export var tier: Tier = Tier.BRONZE
@export var source: Source = Source.LEDGER_FIELD
## When source is LEDGER_FIELD this is the ledger key (e.g.
## `total_catches`, `total_shinies`). For other sources, ignored.
@export var ledger_field: StringName = &""
@export var threshold: int = 1

## Optional reward applied on unlock. RP is added via
## GameState.add_rancher_points; gold via add_gold.
@export var rp_reward: int = 0
@export var gold_reward: Dictionary = {"m": 0.0, "e": 0}
