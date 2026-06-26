## Phase 12g — three-tier concurrent goal definition.
##
## QuestResource mirrors AchievementResource (same Source enum, same
## threshold-driven trigger model) with two extensions:
##   - `quest_tier` — SHORT / MEDIUM / LONG. Determines which slot the
##     QuestStrip occupies and roughly how big the reward should feel.
##   - `repeatable` — when true, completing this quest advances along
##     a `next_quest_id` ladder rather than removing it from the pool.
##     Short quests typically chain (catch 25 → catch 100 → catch 500);
##     long quests usually fire once per prestige cycle.
##
## QuestLog reads these fields at completion time to decide what to
## slot in next.
class_name QuestResource
extends Resource

## SHORT/MEDIUM/LONG occupy the three persistent QuestStrip slots and are
## driven by QuestLog. DAILY (v0.15.15) is a separate category: a daily-
## resetting set tracked by the DailyQuests autoload as a per-day DELTA of a
## lifetime ledger counter, surfaced in its own "Daily" view. No QuestLog slot
## maps to DAILY, so DAILY quests are automatically excluded from the strip.
enum QuestTier { SHORT, MEDIUM, LONG, DAILY }

## Same Source enum as AchievementResource, with one addition:
## RUN_GOLD_EARNED — total_gold_earned_this_run as a BigNumber (read
## via current run tracker). Lets us write "earn 100k gold this run"
## without a custom evaluator branch.
enum Source {
	LEDGER_FIELD,
	PRESTIGE_COUNT,
	PETS_OWNED_COUNT,
	NETS_OWNED_COUNT,
	RECIPES_CRAFTED_COUNT,
	CURRENT_MAX_TIER,
	RUN_GOLD_EARNED,
}

@export var id: StringName
@export var display_name: String
@export var description: String = ""
@export var sprite: Texture2D
@export var quest_tier: QuestTier = QuestTier.SHORT
@export var source: Source = Source.LEDGER_FIELD
## When source is LEDGER_FIELD this is the ledger key (e.g.
## `total_catches`). For RUN_GOLD_EARNED this is unused.
@export var ledger_field: StringName = &""
@export var threshold: int = 1
## Optional progress baseline. The displayed bar reads
## `(current - baseline) / (threshold - baseline)` so chained quests
## don't show a half-full bar at activation time. Set this to the
## value the prior rung's threshold was at, leave 0 for first-rung.
@export var baseline: int = 0
## When true, completing this quest activates `next_quest_id` rather
## than just clearing the slot. The ladder ends when `next_quest_id`
## is empty.
@export var repeatable: bool = false
@export var next_quest_id: StringName = &""

## Reward applied on completion. RP via add_rancher_points; gold via
## add_gold; item via add_item.
@export var rp_reward: int = 0
@export var gold_reward: Dictionary = {"m": 0.0, "e": 0}
@export var item_reward_id: StringName = &""
@export var item_reward_amount: int = 0
