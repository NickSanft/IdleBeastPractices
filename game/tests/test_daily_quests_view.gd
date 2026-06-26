## v0.15.15 — DailyQuestsView rendering (retention bundle).
##
## Verifies the dedicated Daily view renders a row per daily quest, the reset
## countdown, the complete-all bonus line, and the done-state on completion.
extends GutTest

const _SCENE := preload("res://game/scenes/ui/daily_quests_view.tscn")
const _FIXED_NOW := 2_000_000_000


func before_each() -> void:
	TimeManager._test_now_override = _FIXED_NOW
	ContentRegistry.ensure_loaded()
	GameState.from_dict({})
	DailyQuests._last_progress.clear()
	DailyQuests._dirty = false
	DailyQuests._check_reset()  # populate today's active set


func after_each() -> void:
	TimeManager._test_now_override = -1


func _make() -> Control:
	var view: Control = _SCENE.instantiate()
	add_child_autofree(view)
	await wait_frames(1)
	return view


func test_renders_a_row_per_daily_quest() -> void:
	var view: Control = await _make()
	assert_eq(view._rows.size(), GameState.daily_quests_active.size())
	assert_eq(view._rows.size(), DailyQuestsSystem.DAILY_COUNT, "one row per daily quest")


func test_shows_reset_countdown() -> void:
	var view: Control = await _make()
	assert_string_contains(view._countdown_label.text, "Resets in")


func test_shows_complete_all_bonus_line() -> void:
	var view: Control = await _make()
	assert_string_contains(view._bonus_label.text, "Rancher Points")


func test_marks_completed_quest_done() -> void:
	var view: Control = await _make()
	var qid: String = String(GameState.daily_quests_active[0])
	var q: QuestResource = ContentRegistry.quest(StringName(qid))
	GameState.ledger[String(q.ledger_field)] = int(GameState.ledger.get(String(q.ledger_field), 0)) + int(q.threshold)
	DailyQuests.evaluate_progress()  # completes it + emits daily_quest_completed
	await wait_frames(1)
	assert_true(view._rows.has(qid))
	assert_string_contains(view._rows[qid]["value"].text, "Done", "completed row shows a done marker")
