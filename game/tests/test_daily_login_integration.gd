## v0.15.14 — daily-login persistence, cloud-merge, and Main wiring.
##
## Covers: GameState round-trip + safe defaults + prestige survival of the
## streak fields; SaveConflictResolver MAX-merge (anti double-claim); and
## Main._apply_daily_login granting + showing the modal, the no-regrant guard,
## and the welcome-back → daily-reward sequencing queue.
extends GutTest

const _MAIN_SCENE := preload("res://game/scenes/main.tscn")
## Fixed wall-clock for deterministic day-boundary maths (else a run straddling
## local midnight could shift the day index mid-test). A future value (2033) so
## it stays ahead of any on-disk last_saved_unix and never trips the
## TimeManager clock-backward warning during a boot in these tests.
const _FIXED_NOW := 2_000_000_000


func before_each() -> void:
	TimeManager._test_now_override = _FIXED_NOW
	GameState.from_dict({})
	ContentRegistry.ensure_loaded()


func after_each() -> void:
	# Never let the fixed clock leak into another test file.
	TimeManager._test_now_override = -1


func _today() -> int:
	return DailyLoginSystem.local_day_index(TimeManager.now_unix(), TimeManager.tz_bias_minutes())


# region — persistence

func test_daily_login_fields_round_trip() -> void:
	GameState.daily_login_last_day = 123
	GameState.daily_login_streak = 5
	var data := GameState.to_dict()
	GameState.from_dict(data)
	assert_eq(GameState.daily_login_last_day, 123)
	assert_eq(GameState.daily_login_streak, 5)


func test_old_save_without_fields_defaults_to_zero() -> void:
	# A pre-v0.15.14 save dict simply lacks the keys — must load as 0/0, not crash.
	var legacy := GameState.to_dict()
	legacy.erase("daily_login_last_day")
	legacy.erase("daily_login_streak")
	GameState.daily_login_streak = 9  # dirty in-memory value to prove from_dict resets it
	GameState.from_dict(legacy)
	assert_eq(GameState.daily_login_last_day, 0)
	assert_eq(GameState.daily_login_streak, 0)


func test_streak_survives_prestige() -> void:
	# Daily-login is account-level meta (like achievements) — a run reset must
	# not break the player's login streak.
	GameState.daily_login_last_day = 200
	GameState.daily_login_streak = 6
	GameState.perform_prestige()
	assert_eq(GameState.daily_login_last_day, 200, "last-claim day must persist through prestige")
	assert_eq(GameState.daily_login_streak, 6, "streak must persist through prestige")

# endregion


# region — cloud-merge (SaveConflictResolver)

func test_resolver_maxes_daily_login_fields() -> void:
	# Newer (local) save has the more recent calendar day but a SHORTER streak;
	# remote is older but has a longer streak. MAX on each field: last-day from
	# local (blocks same-day re-claim), streak from remote (never under-reward).
	var local := {"last_saved_unix": 200, "daily_login_last_day": 100, "daily_login_streak": 4}
	var remote := {"last_saved_unix": 100, "daily_login_last_day": 99, "daily_login_streak": 7}
	var merged := SaveConflictResolver.resolve(local, remote)
	assert_eq(int(merged["daily_login_last_day"]), 100, "last-claim day takes the MAX (anti double-claim)")
	assert_eq(int(merged["daily_login_streak"]), 7, "streak takes the MAX")


func test_resolver_defaults_missing_daily_fields_to_zero() -> void:
	# One side predates the feature entirely.
	var local := {"last_saved_unix": 200, "daily_login_last_day": 50, "daily_login_streak": 2}
	var remote := {"last_saved_unix": 100}
	var merged := SaveConflictResolver.resolve(local, remote)
	assert_eq(int(merged["daily_login_last_day"]), 50)
	assert_eq(int(merged["daily_login_streak"]), 2)

# endregion


# region — Main wiring

func _fresh_main() -> Node:
	var main: Node = _MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_frames(1)
	# Clear any boot-time modals (an empty disk save grants day 1 at _ready) so
	# they don't interfere with the direct _apply_daily_login calls below.
	for d in [main._welcome_back_dialog, main._daily_reward_dialog]:
		if d != null and is_instance_valid(d):
			d.queue_free()
	main._welcome_back_dialog = null
	main._daily_reward_dialog = null
	main._pending_daily_summary = {}
	await wait_frames(1)
	return main


func test_apply_daily_login_grants_and_shows_modal() -> void:
	var main: Node = await _fresh_main()
	var today: int = _today()
	GameState.daily_login_last_day = today - 1
	GameState.daily_login_streak = 3
	var gold_before: BigNumber = GameState.current_gold()
	main._apply_daily_login()
	await wait_frames(1)
	assert_eq(GameState.daily_login_streak, 4, "consecutive login bumps the streak")
	assert_eq(GameState.daily_login_last_day, today, "last-claim day advances to today")
	assert_true(GameState.current_gold().gt(gold_before), "the reward adds gold")
	assert_not_null(main._daily_reward_dialog, "a daily-reward modal is shown")
	assert_true(main._daily_reward_dialog.visible)


func test_second_login_same_day_does_not_regrant() -> void:
	var main: Node = await _fresh_main()
	var today: int = _today()
	GameState.daily_login_last_day = today
	GameState.daily_login_streak = 4
	var gold_before: BigNumber = GameState.current_gold()
	main._apply_daily_login()
	await wait_frames(1)
	assert_eq(GameState.daily_login_streak, 4, "streak unchanged on a same-day relaunch")
	assert_true(GameState.current_gold().eq(gold_before), "no extra gold on a same-day relaunch")
	assert_null(main._daily_reward_dialog, "no modal when nothing to claim")


func test_daily_modal_queues_behind_welcome_back() -> void:
	var main: Node = await _fresh_main()
	# Simulate an open welcome-back (offline) dialog.
	var wb := AcceptDialog.new()
	main.add_child(wb)
	wb.popup_centered()
	main._welcome_back_dialog = wb
	await wait_frames(1)
	var today: int = _today()
	GameState.daily_login_last_day = today - 1
	GameState.daily_login_streak = 2
	main._apply_daily_login()
	await wait_frames(1)
	# Reward applied immediately, but the modal is queued (not stacked on WB).
	assert_eq(GameState.daily_login_streak, 3, "reward still applies immediately")
	assert_false(main._pending_daily_summary.is_empty(), "daily modal is queued")
	assert_null(main._daily_reward_dialog, "daily modal not shown while welcome-back is up")
	# Dismiss welcome-back → daily modal now appears (deferred a frame so the
	# welcome-back window releases its exclusive slot first), queue cleared.
	wb.hide()
	await wait_frames(2)
	assert_not_null(main._daily_reward_dialog, "daily modal shows after welcome-back closes")
	assert_true(main._daily_reward_dialog.visible)
	assert_true(main._pending_daily_summary.is_empty(), "the queue is drained")


func test_doubled_signal_grants_the_gold_again_but_not_rp() -> void:
	# v0.15.18 — the ad doubler applies another summary's worth of GOLD on
	# top of the pre-applied base (total 2×); RP stays single by design.
	var main: Node = await _fresh_main()
	var summary := {
		"cycle_day": 7, "streak": 7,
		"gold": BigNumber.from_float(400.0),
		"rp": 5, "missed": false,
	}
	main._show_daily_reward(summary)
	await wait_frames(1)
	var gold_before: BigNumber = GameState.current_gold()
	var rp_before: int = GameState.current_rancher_points()
	# Stands in for the button tap — the handler only claims a grant this
	# instance started, so an ad must be in flight for the emit to belong to it.
	main._daily_reward_dialog._ad_in_flight = true
	AdsManager.rewarded_completed.emit(AdsManager.REWARD_DAILY_2X, true)
	await wait_frames(1)
	var gained: float = GameState.current_gold().to_float() - gold_before.to_float()
	assert_almost_eq(gained, 400.0, 0.01, "granted ad adds exactly the summary gold again")
	assert_eq(GameState.current_rancher_points(), rp_before,
			"the day-7 RP milestone is deliberately NOT doubled")
	assert_false(main._daily_reward_dialog.visible, "modal closed after collecting 2×")

# endregion
