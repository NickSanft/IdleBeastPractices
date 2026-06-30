## v0.15.15 — DailyQuests autoload + persistence + cloud-merge (retention bundle).
##
## Covers reset/init, the per-day DELTA tracking (lifetime progress excluded),
## completion + gold grant, the complete-all RP bonus (once only), day rollover,
## GameState round-trip / prestige survival / old-save defaults, and the atomic
## daily-block cloud merge.
extends GutTest

## Fixed future clock so day-boundary maths are deterministic and stay ahead of
## any on-disk last_saved_unix (no clock-backward warning).
const _FIXED_NOW := 2_000_000_000
const _MAIN_SCENE := preload("res://game/scenes/main.tscn")


func before_each() -> void:
	TimeManager._test_now_override = _FIXED_NOW
	ContentRegistry.ensure_loaded()
	GameState.from_dict({})
	# Clear the singleton autoload's transient state so tests don't leak.
	DailyQuests._last_progress.clear()
	DailyQuests._dirty = false


func after_each() -> void:
	TimeManager._test_now_override = -1


func _today() -> int:
	return DailyLoginSystem.local_day_index(TimeManager.now_unix(), TimeManager.tz_bias_minutes())


func _bump(field: String, by: int) -> void:
	GameState.ledger[field] = int(GameState.ledger.get(field, 0)) + by


# region — reset / init

func test_check_reset_initializes_daily_set() -> void:
	DailyQuests._check_reset()
	assert_eq(GameState.daily_quests_reset_day, _today())
	assert_eq(GameState.daily_quests_active.size(), DailyQuestsSystem.DAILY_COUNT)
	assert_false(GameState.daily_quest_baselines.is_empty(), "baselines snapshot at day-start")


func test_baseline_excludes_prior_lifetime_progress() -> void:
	# A veteran with 1000 lifetime catches must start the daily catch quest at 0.
	_bump("total_catches", 1000)
	DailyQuests._check_reset()
	DailyQuests.evaluate_progress()
	for qid in GameState.daily_quests_active:
		var st: Dictionary = DailyQuests.quest_state(qid)
		if String(st["quest"].ledger_field) == "total_catches":
			assert_eq(st["current"], 0, "daily progress is the delta since day-start, not lifetime")
			assert_false(st["done"])

# endregion


# region — completion + rewards

func test_completing_daily_quest_grants_gold_and_marks_done() -> void:
	DailyQuests._check_reset()
	var qid: String = String(GameState.daily_quests_active[0])
	var q: QuestResource = ContentRegistry.quest(StringName(qid))
	var gold_before: BigNumber = GameState.current_gold()
	_bump(String(q.ledger_field), int(q.threshold))
	DailyQuests.evaluate_progress()
	assert_true(GameState.daily_quests_done.has(qid), "quest marked done")
	assert_true(GameState.current_gold().gt(gold_before), "completing a daily quest grants gold")


func test_completed_quest_is_not_regranted() -> void:
	DailyQuests._check_reset()
	var qid: String = String(GameState.daily_quests_active[0])
	var q: QuestResource = ContentRegistry.quest(StringName(qid))
	_bump(String(q.ledger_field), int(q.threshold))
	DailyQuests.evaluate_progress()
	var gold_after: BigNumber = GameState.current_gold()
	# Counter keeps climbing, re-evaluate — must not pay again.
	_bump(String(q.ledger_field), 50)
	DailyQuests.evaluate_progress()
	assert_true(GameState.current_gold().eq(gold_after), "a done quest never re-grants its gold")


func test_complete_all_grants_bonus_once() -> void:
	DailyQuests._check_reset()
	var rp_before: int = GameState.current_rancher_points()
	for qid in GameState.daily_quests_active:
		var q: QuestResource = ContentRegistry.quest(StringName(qid))
		_bump(String(q.ledger_field), int(q.threshold))
	DailyQuests.evaluate_progress()
	assert_true(DailyQuests.all_complete(), "all daily quests done")
	assert_true(GameState.daily_quests_bonus_claimed)
	var rp_after: int = GameState.current_rancher_points()
	assert_gt(rp_after, rp_before, "complete-all grants the RP bonus")
	# Re-evaluate — bonus must not pay twice.
	DailyQuests.evaluate_progress()
	assert_eq(GameState.current_rancher_points(), rp_after, "complete-all bonus granted only once")

# endregion


# region — day rollover

func test_new_day_resets_set_and_clears_completion() -> void:
	DailyQuests._check_reset()
	# Complete a quest today.
	var q: QuestResource = ContentRegistry.quest(StringName(GameState.daily_quests_active[0]))
	_bump(String(q.ledger_field), int(q.threshold))
	DailyQuests.evaluate_progress()
	assert_false(GameState.daily_quests_done.is_empty())
	# Advance two days (guarantees a new local day index regardless of tz).
	TimeManager._test_now_override = _FIXED_NOW + 86400 * 2
	var did_reset: bool = DailyQuests._check_reset()
	assert_true(did_reset, "a new local day rolls the set over")
	assert_eq(GameState.daily_quests_reset_day, _today())
	assert_true(GameState.daily_quests_done.is_empty(), "completion clears on a new day")
	assert_false(GameState.daily_quests_bonus_claimed, "the bonus re-arms on a new day")
	# Baselines re-snapshot to the CURRENT lifetime counters, so today's progress
	# starts at 0 even though the lifetime totals carry the prior day's catches.
	for qid in GameState.daily_quests_active:
		var dq: QuestResource = ContentRegistry.quest(StringName(qid))
		var field: String = String(dq.ledger_field)
		assert_eq(int(GameState.daily_quest_baselines.get(field, -1)),
				int(GameState.ledger.get(field, 0)),
				"baseline for %s re-snapshots to the current lifetime total on rollover" % field)

# endregion


# region — signal-driven path + robustness

func test_signal_driven_evaluation_completes_via_dirty_process() -> void:
	# Exercise the production path: a catch signal marks the autoload dirty, and
	# _process drains it into evaluate_progress (not a direct evaluate call).
	DailyQuests._check_reset()
	var qid: String = ""
	for q_id in GameState.daily_quests_active:
		if String(ContentRegistry.quest(StringName(q_id)).ledger_field) == "total_catches":
			qid = String(q_id)
			break
	assert_ne(qid, "", "the daily set includes a catches quest")
	var q: QuestResource = ContentRegistry.quest(StringName(qid))
	_bump("total_catches", int(q.threshold))
	EventBus.monster_caught.emit("x", 0, false, "tap")  # marks DailyQuests dirty
	assert_true(DailyQuests.is_dirty(), "the catch signal set the dirty flag")
	DailyQuests._process(0.0)  # drains the dirty flag → evaluate
	assert_false(DailyQuests.is_dirty(), "the flag is cleared after _process")
	assert_true(GameState.daily_quests_done.has(qid), "the signal-driven path completed the quest")


func test_stale_quest_id_is_skipped_gracefully() -> void:
	GameState.daily_quests_reset_day = _today()
	GameState.daily_quests_active = ["nonexistent_quest_xyz"]
	GameState.daily_quest_baselines = {}
	GameState.daily_quests_done = {}
	GameState.daily_quests_bonus_claimed = false
	DailyQuests.evaluate_progress()  # must not crash on the missing resource
	var st: Dictionary = DailyQuests.quest_state("nonexistent_quest_xyz")
	assert_null(st["quest"], "quest_state returns a safe null for a missing id")
	assert_eq(int(st["current"]), 0)
	assert_false(DailyQuests.all_complete(), "an all-stale set is never 'complete'")
	assert_false(GameState.daily_quests_bonus_claimed, "no bonus for an unresolvable set")


func test_on_game_loaded_defers_initialization() -> void:
	# game_loaded fires before GameState.from_dict on boot, so the handler must
	# DEFER init (run it post-load) rather than reset against stale state.
	GameState.daily_quests_reset_day = 0
	GameState.daily_quests_active = []
	DailyQuests._on_game_loaded()
	assert_true(GameState.daily_quests_active.is_empty(), "init is deferred, not synchronous")
	await wait_frames(1)
	assert_eq(GameState.daily_quests_active.size(), DailyQuestsSystem.DAILY_COUNT,
			"the deferred _initialize populates today's set after the frame")

# endregion


# region — persistence

func test_daily_quest_fields_round_trip() -> void:
	GameState.daily_quests_reset_day = 123
	GameState.daily_quests_active = ["daily_catch_30", "daily_tap_50"]
	GameState.daily_quest_baselines = {"total_catches": 10}
	GameState.daily_quests_done = {"daily_catch_30": true}
	GameState.daily_quests_bonus_claimed = true
	GameState.from_dict(GameState.to_dict())
	assert_eq(GameState.daily_quests_reset_day, 123)
	assert_eq(GameState.daily_quests_active, ["daily_catch_30", "daily_tap_50"] as Array[String])
	assert_eq(int(GameState.daily_quest_baselines.get("total_catches", -1)), 10)
	assert_true(GameState.daily_quests_done.has("daily_catch_30"))
	assert_true(GameState.daily_quests_bonus_claimed)


func test_daily_quest_state_survives_prestige() -> void:
	GameState.daily_quests_reset_day = 200
	GameState.daily_quests_active = ["daily_catch_30"]
	GameState.daily_quest_baselines = {"total_catches": 50}
	GameState.daily_quests_done = {"daily_catch_30": true}
	GameState.daily_quests_bonus_claimed = true
	GameState.perform_prestige()
	assert_eq(GameState.daily_quests_reset_day, 200, "reset day survives prestige")
	assert_eq(GameState.daily_quests_active, ["daily_catch_30"] as Array[String])
	assert_eq(int(GameState.daily_quest_baselines.get("total_catches", -1)), 50,
			"baselines survive prestige (the ledger they delta against does too)")
	assert_true(GameState.daily_quests_done.has("daily_catch_30"))
	assert_true(GameState.daily_quests_bonus_claimed)


func test_old_save_without_daily_quest_fields_defaults_safely() -> void:
	var legacy := GameState.to_dict()
	for k in ["daily_quests_reset_day", "daily_quests_active", "daily_quest_baselines",
			"daily_quests_done", "daily_quests_bonus_claimed"]:
		legacy.erase(k)
	GameState.daily_quests_bonus_claimed = true  # dirty, to prove from_dict resets it
	GameState.from_dict(legacy)
	assert_eq(GameState.daily_quests_reset_day, 0)
	assert_eq(GameState.daily_quests_active.size(), 0)
	assert_true(GameState.daily_quest_baselines.is_empty())
	assert_true(GameState.daily_quests_done.is_empty())
	assert_false(GameState.daily_quests_bonus_claimed)

# endregion


# region — cloud merge

func test_resolver_same_day_unions_done_and_ors_bonus() -> void:
	var local := {
		"last_saved_unix": 200, "daily_quests_reset_day": 100,
		"daily_quests_active": ["a", "b", "c"], "daily_quest_baselines": {"f": 0},
		"daily_quests_done": {"a": true}, "daily_quests_bonus_claimed": false,
	}
	var remote := {
		"last_saved_unix": 100, "daily_quests_reset_day": 100,
		"daily_quests_active": ["a", "b", "c"], "daily_quest_baselines": {"f": 0},
		"daily_quests_done": {"b": true}, "daily_quests_bonus_claimed": true,
	}
	var m := SaveConflictResolver.resolve(local, remote)
	assert_eq(int(m["daily_quests_reset_day"]), 100)
	assert_true(m["daily_quests_done"].has("a") and m["daily_quests_done"].has("b"),
			"same-day merge unions completions across devices")
	assert_true(bool(m["daily_quests_bonus_claimed"]), "bonus ORs (can't be re-granted)")
	# The active set + baselines stay from the newer base (local here), keeping
	# the {reset_day, active, baselines} triple internally consistent.
	assert_eq(m["daily_quests_active"], ["a", "b", "c"], "active set preserved from the newer base")
	assert_eq(int(m["daily_quest_baselines"]["f"]), 0, "baselines preserved from the newer base")


func test_resolver_different_day_takes_fresh_block_atomically() -> void:
	# Remote is the newer save by timestamp (base), but LOCAL has the more recent
	# daily period — its {reset_day, active, baselines, done} must win as a block,
	# else today's day number would pair with yesterday's quests/baselines.
	var local := {
		"last_saved_unix": 100, "daily_quests_reset_day": 101,
		"daily_quests_active": ["x"], "daily_quest_baselines": {"f": 5},
		"daily_quests_done": {"x": true}, "daily_quests_bonus_claimed": true,
	}
	var remote := {
		"last_saved_unix": 200, "daily_quests_reset_day": 100,
		"daily_quests_active": ["y"], "daily_quest_baselines": {"f": 9},
		"daily_quests_done": {}, "daily_quests_bonus_claimed": false,
	}
	var m := SaveConflictResolver.resolve(local, remote)
	assert_eq(int(m["daily_quests_reset_day"]), 101, "the most recent daily period wins")
	assert_eq(m["daily_quests_active"], ["x"], "active set comes from the fresh day's block")
	assert_eq(int(m["daily_quest_baselines"]["f"]), 5, "baselines come from the same block")
	assert_true(m["daily_quests_done"].has("x"))
	assert_true(bool(m["daily_quests_bonus_claimed"]))

# endregion


# region — nav badge (v0.15.16)

func test_count_helpers_report_done_and_total() -> void:
	GameState.daily_quests_active = ["a", "b", "c"]
	# 'z' is done but NOT in today's active set (stale from a prior day); it must
	# not count. 'b' is active but not done. So completed_count == 2 (a + c only).
	GameState.daily_quests_done = {"a": true, "c": true, "z": true}
	assert_eq(DailyQuests.active_count(), 3)
	assert_eq(DailyQuests.completed_count(), 2,
			"counts only active ids in the done set (ignores undone 'b' + stale 'z')")


func _main() -> Node:
	var main: Node = _MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_frames(1)
	return main


func test_badge_shows_done_over_total_while_incomplete() -> void:
	var main: Node = await _main()
	GameState.daily_quests_active = ["daily_catch_30", "daily_tap_50", "daily_shiny_1"]
	GameState.daily_quests_done = {"daily_catch_30": true}
	main._refresh_daily_badge()
	assert_true(main._daily_badge.visible, "badge shows while daily quests are incomplete")
	assert_eq(main._daily_badge_label.text, "1/3")


func test_badge_hidden_once_all_complete() -> void:
	var main: Node = await _main()
	GameState.daily_quests_active = ["a", "b"]
	GameState.daily_quests_done = {"a": true, "b": true}
	main._refresh_daily_badge()
	assert_false(main._daily_badge.visible, "badge hides when every daily quest is done")


func test_badge_hidden_when_no_daily_set() -> void:
	var main: Node = await _main()
	GameState.daily_quests_active = []
	main._refresh_daily_badge()
	assert_false(main._daily_badge.visible, "badge hides before the daily set is initialized")


func test_badge_updates_live_when_a_quest_completes_via_signal() -> void:
	# The real path: completing a daily quest fires daily_quest_completed, which
	# the badge is subscribed to — so it must repaint WITHOUT a direct refresh.
	var main: Node = await _main()
	# Force a clean set regardless of what the boot save loaded.
	GameState.daily_quests_reset_day = 0
	DailyQuests._check_reset()
	var total: int = DailyQuests.active_count()
	main._refresh_daily_badge()
	assert_eq(main._daily_badge_label.text, "0/%d" % total, "badge starts at 0 done")
	# Complete one daily quest through the signal-driven evaluator.
	var qid: String = String(GameState.daily_quests_active[0])
	var q: QuestResource = ContentRegistry.quest(StringName(qid))
	_bump(String(q.ledger_field), int(q.threshold))
	EventBus.monster_caught.emit("x", 0, false, "tap")  # marks DailyQuests dirty
	DailyQuests._process(0.0)  # drains → evaluate → completes → emits daily_quest_completed
	assert_eq(main._daily_badge_label.text, "1/%d" % total,
			"badge repainted live via the completion signal subscription")


func test_badge_auto_sizes_to_content() -> void:
	# The badge has no fixed size — its PanelContainer must size to the label
	# content (so it actually renders, not collapse to a zero-size point).
	var main: Node = await _main()
	GameState.daily_quests_active = ["a", "b", "c"]
	GameState.daily_quests_done = {"a": true}
	main._refresh_daily_badge()
	await wait_frames(2)  # let the layout pass settle
	assert_true(main._daily_badge.visible)
	assert_gt(main._daily_badge.size.x, 0.0, "badge auto-sizes to its content width")
	assert_gt(main._daily_badge.size.y, 0.0, "badge auto-sizes to its content height")


func test_game_loaded_refreshes_badge_deferred() -> void:
	# On boot game_loaded fires BEFORE GameState.from_dict, so the badge's
	# game_loaded refresh is CONNECT_DEFERRED — it must repaint on the NEXT idle
	# frame (after load), not synchronously during the emit. (A same-day save
	# load emits no reset/completion signal, so this is the only repaint path.)
	var main: Node = await _main()
	GameState.daily_quests_reset_day = _today()
	GameState.daily_quests_active = ["a", "b", "c"]
	GameState.daily_quests_done = {"a": true}
	main._refresh_daily_badge()
	assert_eq(main._daily_badge_label.text, "1/3")
	# Mutate, then emit game_loaded: the deferred refresh must NOT run yet.
	GameState.daily_quests_done = {"a": true, "b": true}
	EventBus.game_loaded.emit()
	assert_eq(main._daily_badge_label.text, "1/3",
			"game_loaded refresh is deferred, not synchronous (would catch a dropped CONNECT_DEFERRED)")
	await wait_frames(1)
	assert_eq(main._daily_badge_label.text, "2/3",
			"the deferred game_loaded refresh repaints on the next frame")

# endregion
