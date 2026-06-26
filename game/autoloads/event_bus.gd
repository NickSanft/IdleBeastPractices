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
## v0.15.14 — fired when a daily-login reward is granted at boot. `summary`
## matches DailyRewardDialog's render shape: {cycle_day, streak, gold (BigNumber),
## rp, missed}. Receivers (toast/analytics) react; the modal is shown by Main.
@warning_ignore("unused_signal") signal daily_reward_claimed(summary: Dictionary)
# endregion

# region — Narrator
@warning_ignore("unused_signal") signal narrator_line_chosen(line_id: String, text: String, mood: String)
# endregion

# region — Ads
@warning_ignore("unused_signal") signal rewarded_video_completed(reward_id: String, granted: bool)
# endregion

# region — Quests
# Phase 12g — fired by QuestLog when a quest's threshold is met. The
# QuestLog itself listens for these to fill the slot with the next
# quest (or advance along a repeatable ladder). Main routes the
# signal to celebration_overlay/toast for player feedback.
@warning_ignore("unused_signal") signal quest_completed(quest_id: String)
## Fired when a slot becomes active — either at session start (load
## from save) or when a prior quest in that slot completed and a new
## one was picked. The QuestStrip listens to refresh its row.
@warning_ignore("unused_signal") signal quest_activated(slot: int, quest_id: String)
## Fired whenever quest progress crosses a threshold the strip cares
## about (% increment). Slot is 0 (SHORT) / 1 (MEDIUM) / 2 (LONG).
@warning_ignore("unused_signal") signal quest_progress_changed(slot: int, current: int, target: int)
# endregion

# region — Daily quests (v0.15.15)
## The DailyQuests autoload manages a daily-resetting set; the DailyQuestsView
## listens to repaint. Progress is a per-day delta of a lifetime ledger counter.
@warning_ignore("unused_signal") signal daily_quest_completed(quest_id: String)
@warning_ignore("unused_signal") signal daily_quest_progress_changed(quest_id: String, current: int, target: int)
## Fired when the daily set rolls over to a new local day (fresh quests, baselines reset).
@warning_ignore("unused_signal") signal daily_quests_reset()
## Fired once when all of the day's daily quests are done and the bonus is granted.
@warning_ignore("unused_signal") signal daily_quests_all_completed(bonus_rp: int)
# endregion

# region — Achievements
# Phase 12f — fired when a previously-locked achievement crosses its
# trigger threshold. Receivers (celebration overlay, ledger view,
# Achievements autoload itself for reward grant) subscribe to react.
@warning_ignore("unused_signal") signal achievement_unlocked(achievement_id: String)
# endregion

# region — Navigation
# Phase 11d — empty-state hint buttons fire this so any screen can
# request a primary-tab switch without reaching into main.gd. Main
# subscribes and routes to _navigate_to_tab.
@warning_ignore("unused_signal") signal tab_switch_requested(tab_name: String)
# endregion
