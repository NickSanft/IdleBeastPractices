## v0.15.17 — WelcomeBackDialog capped-summary UX.
##
## Pins the actionable offline-cap copy ("Away for X — earned for the first
## Y") and the Extend Away Time CTA: visible only on capped summaries, and
## routing to the Upgrades tab via EventBus.tab_switch_requested (main's
## existing nav seam). Pre-v0.15.17 the "(capped)" note was dead code —
## main pre-clamped the elapsed, so compute()'s capped flag never fired.
extends GutTest

const _SCENE := preload("res://game/scenes/ui/welcome_back_dialog.tscn")
const _MAIN_SCENE := preload("res://game/scenes/main.tscn")
## Fixed wall-clock (2033) — same rationale as test_daily_login_integration:
## deterministic day/elapsed maths, ahead of any on-disk last_saved_unix.
const _FIXED_NOW := 2_000_000_000


func before_each() -> void:
	TimeManager._test_now_override = _FIXED_NOW
	GameState.from_dict({})
	ContentRegistry.ensure_loaded()


func after_each() -> void:
	# Never let the fixed clock leak into another test file.
	TimeManager._test_now_override = -1


func _make() -> AcceptDialog:
	var dlg: AcceptDialog = _SCENE.instantiate()
	add_child_autofree(dlg)
	await wait_frames(1)
	return dlg


func _make_summary(seconds: float, raw_seconds: float, capped: bool) -> Dictionary:
	return {
		"seconds": seconds,
		"raw_seconds": raw_seconds,
		"catches_by_species": {},
		"items_gained": {},
		"gold_gained": BigNumber.from_float(100.0),
		"shinies_caught": 0,
		"capped": capped,
	}


func test_capped_summary_names_both_windows() -> void:
	var dlg: AcceptDialog = await _make()
	# Away 9h12m, credited 4h.
	dlg.show_summary(_make_summary(14400.0, 33120.0, true))
	await wait_frames(1)
	assert_string_contains(dlg._body_label.text, "Away for 9h 12m")
	assert_string_contains(dlg._body_label.text, "earned for the first 4h 00m")
	assert_string_contains(dlg._body_label.text, "Offline limit reached")


func test_capped_summary_shows_extend_button() -> void:
	var dlg: AcceptDialog = await _make()
	dlg.show_summary(_make_summary(3600.0, 7200.0, true))
	await wait_frames(1)
	assert_true(dlg._extend_cap_button.visible, "capped -> CTA visible")


func test_uncapped_summary_hides_extend_button_and_cap_copy() -> void:
	var dlg: AcceptDialog = await _make()
	dlg.show_summary(_make_summary(2700.0, 2700.0, false))
	await wait_frames(1)
	assert_false(dlg._extend_cap_button.visible, "uncapped -> no CTA chrome")
	assert_string_contains(dlg._body_label.text, "Away for 45 minutes")
	assert_false(dlg._body_label.text.contains("Offline limit"),
			"no cap note on an uncapped summary")


func test_extend_action_requests_upgrades_tab_and_hides() -> void:
	var dlg: AcceptDialog = await _make()
	dlg.show_summary(_make_summary(3600.0, 7200.0, true))
	await wait_frames(1)
	watch_signals(EventBus)
	# Drive the BUTTON, not the private handler — this pins the
	# add_button -> custom_action("extend_cap") wiring too.
	dlg._extend_cap_button.pressed.emit()
	assert_signal_emitted_with_parameters(
			EventBus, "tab_switch_requested", ["Upgrades"])
	assert_false(dlg.visible, "dialog closes after routing to Upgrades")


func test_old_summary_without_raw_seconds_degrades_gracefully() -> void:
	# Summaries from before v0.15.17 have no raw_seconds; the copy falls
	# back to the credited window instead of claiming 0 time away.
	var dlg: AcceptDialog = await _make()
	var legacy := _make_summary(3600.0, 0.0, true)
	legacy.erase("raw_seconds")
	dlg.show_summary(legacy)
	await wait_frames(1)
	assert_string_contains(dlg._body_label.text, "Away for 1h 00m")


func test_barely_capped_summary_keeps_single_window_sentence() -> void:
	# raw within 60 s of the cap: "Away for 1h 00m — earned for the first
	# 1h 00m" would read as a bug, so the two-window sentence is skipped —
	# but the amber note and CTA still show (capped is capped).
	var dlg: AcceptDialog = await _make()
	dlg.show_summary(_make_summary(3600.0, 3630.0, true))
	await wait_frames(1)
	assert_false(dlg._body_label.text.contains("earned for the first"),
			"identical windows must not be spelled out twice")
	assert_string_contains(dlg._body_label.text, "Offline limit reached")
	assert_true(dlg._extend_cap_button.visible)


func test_multi_day_absence_formats_with_days() -> void:
	# raw_seconds is unbounded (forward-jumped clocks); "87600h" reads as
	# a bug, so >= 24h formats as days.
	var dlg: AcceptDialog = await _make()
	dlg.show_summary(_make_summary(3600.0, 3.0 * 86400.0 + 4.0 * 3600.0, true))
	await wait_frames(1)
	assert_string_contains(dlg._body_label.text, "Away for 3d 4h")


# region — Main wiring (v0.15.17 regression: the capped flag actually fires)

## Pre-v0.15.17, main clamped the elapsed BEFORE OfflineProgressSystem.compute
## saw it, so raw == cap inside compute and `capped` was always false — the
## dialog's cap copy was dead code. This pins the INF-cap wiring end to end.
func test_main_passes_uncapped_elapsed_so_capped_flag_fires() -> void:
	GameState.active_net = "basic_net"
	var main: Node = _MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_frames(1)
	# Clear boot-time modals so the direct call below owns the dialog slot
	# (the _fresh_main pattern from test_daily_login_integration).
	for d in [main._welcome_back_dialog, main._daily_reward_dialog]:
		if d != null and is_instance_valid(d):
			d.queue_free()
	main._welcome_back_dialog = null
	main._daily_reward_dialog = null
	main._pending_daily_summary = {}
	await wait_frames(1)
	# Away 3h against the default 1h cap.
	main._apply_offline_progress({"last_saved_unix": _FIXED_NOW - 3 * 3600})
	await wait_frames(1)
	var dlg: AcceptDialog = main._welcome_back_dialog
	assert_not_null(dlg, "welcome-back dialog shows for a 3h absence")
	if dlg == null:
		return
	assert_string_contains(dlg._body_label.text, "Away for 3h 00m")
	assert_string_contains(dlg._body_label.text, "earned for the first 1h 00m")
	assert_true(dlg._extend_cap_button.visible, "capped boot shows the CTA")

# endregion
