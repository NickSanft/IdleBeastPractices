## Global signal bus. No state. All cross-system events flow through here.
##
## Naming: past_tense_verb. Receivers connect via EventBus.<signal>.connect(...).
##
## The signals are declared here and emitted/received from many other files —
## that's the whole point of the bus pattern. GDScript's "unused_signal" check
## is per-script, so we silence it per declaration.
extends Node

# region — Catching
@warning_ignore("unused_signal") signal monster_spawned(monster_id: String, instance_id: int)
@warning_ignore("unused_signal") signal monster_tapped(monster_id: String, instance_id: int)
@warning_ignore("unused_signal") signal monster_caught(monster_id: String, instance_id: int, is_shiny: bool, source: String)
@warning_ignore("unused_signal") signal monster_despawned(monster_id: String, instance_id: int)
@warning_ignore("unused_signal") signal first_catch_of_species(monster_id: String)
@warning_ignore("unused_signal") signal first_shiny_caught(monster_id: String)
# endregion

# region — Inventory & currency
@warning_ignore("unused_signal") signal item_gained(item_id: String, amount: int)
@warning_ignore("unused_signal") signal item_spent(item_id: String, amount: int)
@warning_ignore("unused_signal") signal currency_changed(currency_id: String, new_value)
@warning_ignore("unused_signal") signal gold_milestone_reached(milestone)
# endregion

# region — Progression
@warning_ignore("unused_signal") signal tier_unlocked(tier: int)
@warning_ignore("unused_signal") signal tier_completed(tier: int)
@warning_ignore("unused_signal") signal upgrade_purchased(upgrade_id: String)
# endregion

# region — Pets & battle
@warning_ignore("unused_signal") signal pet_acquired(pet_id: String, is_variant: bool)
@warning_ignore("unused_signal") signal battle_started(battle_id: String)
@warning_ignore("unused_signal") signal battle_tick(battle_id: String, state: Dictionary)
@warning_ignore("unused_signal") signal battle_ended(battle_id: String, won: bool, rewards: Dictionary)
@warning_ignore("unused_signal") signal rancher_points_earned(amount: int, source: String)
# endregion

# region — Prestige
@warning_ignore("unused_signal") signal prestige_available(rp_on_reset: int)
@warning_ignore("unused_signal") signal prestige_triggered(rp_gained: int, prestige_count: int)
# endregion

# region — Crafting
@warning_ignore("unused_signal") signal recipe_unlocked(recipe_id: String)
@warning_ignore("unused_signal") signal item_crafted(recipe_id: String, output_item_id: String)
# endregion

# region — Lifecycle
@warning_ignore("unused_signal") signal game_loaded()
@warning_ignore("unused_signal") signal game_saved()
@warning_ignore("unused_signal") signal offline_progress_calculated(summary: Dictionary)
@warning_ignore("unused_signal") signal idle_too_long(seconds: float)
# endregion

# region — Narrator
@warning_ignore("unused_signal") signal narrator_line_chosen(line_id: String, text: String, mood: String)
# endregion

# region — Ads
@warning_ignore("unused_signal") signal rewarded_video_completed(reward_id: String, granted: bool)
# endregion
