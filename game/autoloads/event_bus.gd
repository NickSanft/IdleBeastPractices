## Global signal bus. No state. All cross-system events flow through here.
##
## Naming: past_tense_verb. Receivers connect via EventBus.<signal>.connect(...).
extends Node

# region — Catching
signal monster_spawned(monster_id: String, instance_id: int)
signal monster_tapped(monster_id: String, instance_id: int)
signal monster_caught(monster_id: String, instance_id: int, is_shiny: bool, source: String)
signal monster_despawned(monster_id: String, instance_id: int)
signal first_catch_of_species(monster_id: String)
signal first_shiny_caught(monster_id: String)
# endregion

# region — Inventory & currency
signal item_gained(item_id: String, amount: int)
signal item_spent(item_id: String, amount: int)
signal currency_changed(currency_id: String, new_value)
signal gold_milestone_reached(milestone)
# endregion

# region — Progression
signal tier_unlocked(tier: int)
signal tier_completed(tier: int)
signal upgrade_purchased(upgrade_id: String)
# endregion

# region — Pets & battle
signal pet_acquired(pet_id: String, is_variant: bool)
signal battle_started(battle_id: String)
signal battle_tick(battle_id: String, state: Dictionary)
signal battle_ended(battle_id: String, won: bool, rewards: Dictionary)
signal rancher_points_earned(amount: int, source: String)
# endregion

# region — Prestige
signal prestige_available(rp_on_reset: int)
signal prestige_triggered(rp_gained: int, prestige_count: int)
# endregion

# region — Crafting
signal recipe_unlocked(recipe_id: String)
signal item_crafted(recipe_id: String, output_item_id: String)
# endregion

# region — Lifecycle
signal game_loaded()
signal game_saved()
signal offline_progress_calculated(summary: Dictionary)
signal idle_too_long(seconds: float)
# endregion

# region — Narrator
signal narrator_line_chosen(line_id: String, text: String, mood: String)
# endregion
