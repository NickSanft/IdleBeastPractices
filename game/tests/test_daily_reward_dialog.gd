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


# region — v0.15.18: "Collect 2× (watch ad)" doubler


func _reward(gold: float) -> Dictionary:
	return {"cycle_day": 2, "streak": 2, "gold": BigNumber.from_float(gold), "rp": 0, "missed": false}


func test_ad_button_present_and_enabled_when_ads_available() -> void:
	var dlg: AcceptDialog = await _make()
	dlg.show_reward(_reward(100.0))
	await wait_frames(1)
	assert_not_null(dlg._watch_ad_button)
	# Stub backend (editor/CI) always reports available.
	assert_false(dlg._watch_ad_button.disabled)


func test_granted_ad_emits_doubled_with_original_summary_and_hides() -> void:
	var dlg: AcceptDialog = await _make()
	var summary := _reward(250.0)
	dlg.show_reward(summary)
	await wait_frames(1)
	watch_signals(dlg)
	# Simulate the backend granting the reward (bypasses the stub's
	# confirmation dialog, which would block a headless run). Standing in for
	# the button tap: the handler only claims a grant this instance started,
	# so an ad must be in flight for the emit to belong to it.
	dlg._ad_in_flight = true
	AdsManager.rewarded_completed.emit(AdsManager.REWARD_DAILY_2X, true)
	assert_signal_emitted_with_parameters(dlg, "doubled", [summary])
	assert_false(dlg.visible, "granted ad collects and closes the modal")


func test_canceled_ad_keeps_modal_open_no_double() -> void:
	var dlg: AcceptDialog = await _make()
	dlg.show_reward(_reward(250.0))
	await wait_frames(1)
	watch_signals(dlg)
	# Mirror a real tap so the cancel path genuinely exercises the re-enable
	# below rather than passing because the button was never disabled.
	dlg._ad_in_flight = true
	dlg._watch_ad_button.disabled = true
	AdsManager.rewarded_completed.emit(AdsManager.REWARD_DAILY_2X, false)
	assert_signal_not_emitted(dlg, "doubled")
	assert_true(dlg.visible, "cancel keeps the modal; Collect still works")
	assert_false(dlg._watch_ad_button.disabled, "button re-enabled for retry")


func test_other_reward_ids_are_ignored() -> void:
	var dlg: AcceptDialog = await _make()
	dlg.show_reward(_reward(250.0))
	await wait_frames(1)
	watch_signals(dlg)
	AdsManager.rewarded_completed.emit(AdsManager.REWARD_OFFLINE_2X, true)
	assert_signal_not_emitted(dlg, "doubled")
	assert_true(dlg.visible)

# endregion
