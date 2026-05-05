## Phase 12g — quest evaluator, slot fill, ladder advancement,
## reward application, save round-trip.
##
## Tests bypass the EventBus signal hookup and call
## `QuestLog.evaluate_progress()` directly so they're deterministic
## regardless of connection ordering.
extends GutTest


func before_each() -> void:
	# Clean GameState slice for the trigger evaluator + quest log.
	GameState.active_quests = {0: "", 1: "", 2: ""}
	GameState.quests_completed = {}
	GameState.ledger["total_catches"] = 0
	GameState.ledger["total_taps"] = 0
	GameState.ledger["total_shinies"] = 0
	GameState.prestige_count = 0
	GameState.pets_owned = []
	GameState.nets_owned = []
	GameState.recipes_crafted = []
	GameState.current_max_tier = 1
	GameState.total_gold_earned_this_run = {"m": 0.0, "e": 0}


func after_each() -> void:
	GameState.active_quests = {0: "", 1: "", 2: ""}
	GameState.quests_completed = {}


# region — slot fill

func test_initial_fill_populates_all_three_slots() -> void:
	QuestLog._initial_fill()
	for slot in [QuestLog.SLOT_SHORT, QuestLog.SLOT_MEDIUM, QuestLog.SLOT_LONG]:
		assert_ne(
			String(GameState.active_quests.get(slot, "")), "",
			"slot %d should have a quest after initial fill" % slot)


func test_each_slot_picks_quest_of_matching_tier() -> void:
	QuestLog._initial_fill()
	for slot in [QuestLog.SLOT_SHORT, QuestLog.SLOT_MEDIUM, QuestLog.SLOT_LONG]:
		var qid: String = String(GameState.active_quests.get(slot, ""))
		assert_ne(qid, "")
		var q: QuestResource = ContentRegistry.quest(StringName(qid))
		assert_not_null(q)
		var expected: int = QuestLog._slot_to_quest_tier(slot)
		assert_eq(q.quest_tier, expected,
				"slot %d quest tier mismatch (got %d, want %d)" % [slot, q.quest_tier, expected])

# endregion


# region — completion + ladder advancement

func test_completing_short_catch_25_advances_to_catch_100() -> void:
	# Activate the head of the catch ladder explicitly.
	QuestLog._activate(QuestLog.SLOT_SHORT, "short_catch_25")
	GameState.ledger["total_catches"] = 25
	QuestLog.evaluate_progress()
	# Ladder advance: completed quest should be in quests_completed,
	# slot now holds the next rung.
	assert_true(
		GameState.quests_completed.has("short_catch_25"),
		"completed catch_25 should be marked done")
	assert_eq(
		String(GameState.active_quests.get(QuestLog.SLOT_SHORT, "")),
		"short_catch_100",
		"slot SHORT should advance to next rung short_catch_100")


func test_non_repeatable_completion_clears_slot_and_picker_fills_with_different_quest() -> void:
	# short_first_shiny is non-repeatable; pick should refill with
	# something else.
	QuestLog._activate(QuestLog.SLOT_SHORT, "short_first_shiny")
	GameState.ledger["total_shinies"] = 1
	QuestLog.evaluate_progress()
	assert_true(GameState.quests_completed.has("short_first_shiny"))
	var refilled: String = String(GameState.active_quests.get(QuestLog.SLOT_SHORT, ""))
	assert_ne(refilled, "short_first_shiny",
			"non-repeatable completion should NOT re-issue the same quest")
	assert_ne(refilled, "",
			"slot should refill rather than stay empty")


func test_completion_grants_rp_reward() -> void:
	var rp_before: int = GameState.current_rancher_points()
	QuestLog._activate(QuestLog.SLOT_SHORT, "short_first_shiny")
	GameState.ledger["total_shinies"] = 1
	QuestLog.evaluate_progress()
	# short_first_shiny rewards 5 RP.
	assert_eq(GameState.current_rancher_points() - rp_before, 5,
			"short_first_shiny should grant 5 RP on completion")


func test_completion_emits_quest_completed_signal() -> void:
	var fired: Array[String] = []
	var handler := func(id: String) -> void: fired.append(id)
	EventBus.quest_completed.connect(handler)
	QuestLog._activate(QuestLog.SLOT_SHORT, "short_first_shiny")
	GameState.ledger["total_shinies"] = 1
	QuestLog.evaluate_progress()
	EventBus.quest_completed.disconnect(handler)
	assert_eq(fired.size(), 1)
	assert_eq(fired[0], "short_first_shiny")

# endregion


# region — picker behavior

func test_picker_skips_already_completed_non_repeatable() -> void:
	GameState.quests_completed["short_first_shiny"] = true
	# Force-pick a SHORT quest; should not return the completed one.
	var picked: QuestResource = QuestLog._pick_for_slot(QuestLog.SLOT_SHORT)
	assert_not_null(picked)
	assert_ne(String(picked.id), "short_first_shiny")


func test_picker_skips_ladder_tail_until_head_complete() -> void:
	# short_catch_100 is the middle rung of the catch ladder. The
	# head (short_catch_25) is uncompleted, so the picker must NOT
	# pick short_catch_100 — it should issue the head.
	GameState.active_quests = {0: "", 1: "", 2: ""}
	var picked: QuestResource = QuestLog._pick_for_slot(QuestLog.SLOT_SHORT)
	assert_not_null(picked)
	assert_ne(String(picked.id), "short_catch_100",
			"middle rung must not be issued before the head")
	assert_ne(String(picked.id), "short_catch_500",
			"tail rung must not be issued before the head")

# endregion


# region — slot_state helper for QuestStrip

func test_slot_state_reports_progress_and_target() -> void:
	QuestLog._activate(QuestLog.SLOT_SHORT, "short_catch_25")
	GameState.ledger["total_catches"] = 10
	var s: Dictionary = QuestLog.slot_state(QuestLog.SLOT_SHORT)
	assert_eq(s.get("current"), 10)
	assert_eq(s.get("target"), 25)
	assert_almost_eq(float(s.get("progress")), 10.0 / 25.0, 0.01)


func test_slot_state_reports_baseline_for_chained_quest() -> void:
	# short_catch_100 has baseline=25; at total_catches=50 the bar
	# should show (50-25)/(100-25) = 1/3, not 50/100.
	QuestLog._activate(QuestLog.SLOT_SHORT, "short_catch_100")
	GameState.ledger["total_catches"] = 50
	var s: Dictionary = QuestLog.slot_state(QuestLog.SLOT_SHORT)
	assert_almost_eq(float(s.get("progress")), 25.0 / 75.0, 0.01)


func test_empty_slot_returns_null_quest() -> void:
	GameState.active_quests[QuestLog.SLOT_SHORT] = ""
	var s: Dictionary = QuestLog.slot_state(QuestLog.SLOT_SHORT)
	assert_null(s.get("quest"))

# endregion


# region — save round-trip + migration

func test_active_quests_round_trip_through_save() -> void:
	GameState.active_quests = {0: "short_catch_25", 1: "med_tier_3", 2: "long_prestige_1"}
	GameState.quests_completed = {"short_first_shiny": true}
	var dict: Dictionary = GameState.to_dict()
	GameState.active_quests = {0: "", 1: "", 2: ""}
	GameState.quests_completed = {}
	GameState.from_dict(dict)
	assert_eq(String(GameState.active_quests.get(0, "")), "short_catch_25")
	assert_eq(String(GameState.active_quests.get(1, "")), "med_tier_3")
	assert_eq(String(GameState.active_quests.get(2, "")), "long_prestige_1")
	assert_true(GameState.quests_completed.has("short_first_shiny"))


func test_v4_to_v5_migration_seeds_empty_quests() -> void:
	var v4: Dictionary = {"version": 4, "current_max_tier": 3}
	var migrated: Dictionary = SaveMigrations.apply_chain(v4, 5)
	assert_eq(migrated.get("version"), 5)
	assert_true(migrated.has("active_quests"))
	assert_true(migrated.has("quests_completed"))


func test_v4_to_v5_migration_preserves_existing_quest_state() -> void:
	var v4: Dictionary = {
		"version": 4,
		"active_quests": {"0": "short_catch_25", "1": "", "2": ""},
		"quests_completed": {"short_first_shiny": true},
	}
	var migrated: Dictionary = SaveMigrations.apply_chain(v4, 5)
	assert_eq(
		String((migrated["active_quests"] as Dictionary).get("0", "")),
		"short_catch_25")
	assert_true((migrated["quests_completed"] as Dictionary).has("short_first_shiny"))

# endregion


# region — prestige preserves quests_completed but resets active

func test_prestige_keeps_quests_completed() -> void:
	# perform_prestige emits currency_changed + prestige_triggered,
	# which the live QuestLog autoload subscribes to — so by the time
	# perform_prestige returns, slots have already been re-filled by
	# the picker. The meaningful invariant we test is: the de-dupe
	# set survives so non-repeatable quests aren't re-issued.
	GameState.quests_completed = {"short_first_shiny": true}
	GameState.total_gold_earned_this_run = {"m": 1.0, "e": 6}
	GameState.perform_prestige()
	assert_true(
		GameState.quests_completed.has("short_first_shiny"),
		"completed-set must persist across prestige")

# endregion
