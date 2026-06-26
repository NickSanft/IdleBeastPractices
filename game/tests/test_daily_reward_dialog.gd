## v0.15.14 — DailyRewardDialog rendering (retention bundle).
##
## Verifies the modal renders the streak / gold / RP summary and the 7-day
## cycle strip with the day-7 jackpot starred and the missed-streak note.
extends GutTest

const _SCENE := preload("res://game/scenes/ui/daily_reward_dialog.tscn")


func _make() -> AcceptDialog:
	var dlg: AcceptDialog = _SCENE.instantiate()
	add_child_autofree(dlg)
	await wait_frames(1)
	return dlg


func test_renders_streak_and_gold_and_seven_pips() -> void:
	var dlg: AcceptDialog = await _make()
	dlg.show_reward({"cycle_day": 3, "streak": 3, "gold": BigNumber.from_float(540.0), "rp": 0, "missed": false})
	await wait_frames(1)
	assert_string_contains(dlg._body_label.text, "Day 3")
	assert_string_contains(dlg._body_label.text, "540")
	assert_eq(dlg._pips.get_child_count(), 7, "renders a 7-day cycle strip")


func test_day_seven_shows_rp_and_starred_pip() -> void:
	var dlg: AcceptDialog = await _make()
	dlg.show_reward({"cycle_day": 7, "streak": 7, "gold": BigNumber.from_float(5000.0), "rp": 8, "missed": false})
	await wait_frames(1)
	assert_string_contains(dlg._body_label.text, "Rancher Points", "day-7 body teases the RP bonus")
	# Find the starred jackpot pip by content rather than a hardcoded index, so
	# a future layout tweak (spacers, reordering) doesn't break the assertion.
	var star_count: int = 0
	for pip in dlg._pips.get_children():
		for child in pip.get_children():
			if child is Label and (child as Label).text == "★":
				star_count += 1
	assert_eq(star_count, 1, "exactly one pip (day 7) is the starred jackpot")


func test_missed_streak_shows_restart_note() -> void:
	var dlg: AcceptDialog = await _make()
	dlg.show_reward({"cycle_day": 1, "streak": 1, "gold": BigNumber.from_float(50.0), "rp": 0, "missed": true})
	await wait_frames(1)
	assert_string_contains(dlg._body_label.text, "restarted", "a broken streak is called out")
