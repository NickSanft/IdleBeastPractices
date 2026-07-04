## v0.15.20 — calendar boost events (pure system + GameState composition
## + catching-view banner).
##
## All clock-dependent paths run under TimeManager._test_now_override with
## tz handled explicitly — the pure system never reads the wall clock.
## Weekday reference: unix day 0 (1970-01-01) was a Thursday, so
## weekday(d) = posmod(d + 4, 7) with 0=Sunday … 6=Saturday.
extends GutTest

const _CATCHING := preload("res://game/scenes/catching/catching_view.tscn")


func before_each() -> void:
	GameState._reset_to_defaults()
	ContentRegistry.ensure_loaded()


func after_each() -> void:
	TimeManager._test_now_override = -1
	GameState._reset_to_defaults()


## A local-noon unix time for a day with the given weekday (0=Sun..6=Sat),
## valid on ANY machine timezone: derives the target day index near the
## fixed test epoch, then converts back through the machine's tz bias.
func _local_noon_on_weekday(target_weekday: int) -> int:
	var tz: int = TimeManager.tz_bias_minutes()
	var base_day: int = DailyLoginSystem.local_day_index(2_000_000_000, tz)
	var delta: int = posmod(target_weekday - CalendarEventsSystem.weekday(base_day), 7)
	var day: int = base_day + delta
	return day * CalendarEventsSystem.SECONDS_PER_DAY + 12 * 3600 - tz * 60


# region — pure system

func test_weekday_reference_points() -> void:
	assert_eq(CalendarEventsSystem.weekday(0), 4, "unix day 0 was a Thursday")
	assert_eq(CalendarEventsSystem.weekday(2), 6, "1970-01-03 was a Saturday")
	assert_eq(CalendarEventsSystem.weekday(3), 0, "1970-01-04 was a Sunday")


func test_weekdays_have_no_event() -> void:
	for d in [0, 1, 4, 5, 6]:  # Thu Fri Mon Tue Wed of the first week
		assert_true(CalendarEventsSystem.active_event(d).is_empty(),
				"day %d (weekday %d) must be event-free" % [d, CalendarEventsSystem.weekday(d)])


func test_saturday_and_sunday_share_one_event() -> void:
	var sat := CalendarEventsSystem.active_event(2)   # 1970-01-03
	var sun := CalendarEventsSystem.active_event(3)   # 1970-01-04
	assert_false(sat.is_empty())
	assert_eq(sat["id"], sun["id"], "a boost never swaps mid-weekend")


func test_rotation_advances_weekly_and_cycles() -> void:
	var first := CalendarEventsSystem.active_event(2)
	var second := CalendarEventsSystem.active_event(2 + 7)
	var third := CalendarEventsSystem.active_event(2 + 14)
	var fourth := CalendarEventsSystem.active_event(2 + 21)
	assert_ne(first["id"], second["id"])
	assert_ne(second["id"], third["id"])
	assert_ne(first["id"], third["id"])
	assert_eq(first["id"], fourth["id"], "cycle length == EVENTS.size()")


func test_event_multiplier_whitelists_by_effect_id() -> void:
	var sat_day: int = 2
	var ev := CalendarEventsSystem.active_event(sat_day)
	assert_almost_eq(
			CalendarEventsSystem.event_multiplier(ev["effect_id"], sat_day), 2.0, 1.0e-6)
	assert_almost_eq(
			CalendarEventsSystem.event_multiplier(&"rp_mult", sat_day), 1.0, 1.0e-6,
			"non-event effect ids are untouched")
	assert_almost_eq(
			CalendarEventsSystem.event_multiplier(ev["effect_id"], 4), 1.0, 1.0e-6,
			"weekdays contribute nothing")


func test_seconds_until_event_end() -> void:
	# Local noon Saturday: rest of Sat (12h) + all of Sunday (24h).
	var sat_noon_local: int = 2 * CalendarEventsSystem.SECONDS_PER_DAY + 12 * 3600
	assert_eq(CalendarEventsSystem.seconds_until_event_end(sat_noon_local, 0), 36 * 3600)
	# Local noon Sunday: 12h left.
	var sun_noon_local: int = 3 * CalendarEventsSystem.SECONDS_PER_DAY + 12 * 3600
	assert_eq(CalendarEventsSystem.seconds_until_event_end(sun_noon_local, 0), 12 * 3600)
	# Weekday: 0.
	var wed_local: int = 6 * CalendarEventsSystem.SECONDS_PER_DAY + 12 * 3600
	assert_eq(CalendarEventsSystem.seconds_until_event_end(wed_local, 0), 0)


func test_seconds_until_event_end_respects_tz_bias() -> void:
	# The same INSTANT viewed from +60 min: pick unix so that LOCAL time is
	# Saturday noon under bias 60 (local = unix + 60*60). Remaining must be
	# the same 36h — the countdown is a local-timeline computation.
	var local_sat_noon: int = 2 * CalendarEventsSystem.SECONDS_PER_DAY + 12 * 3600
	var unix: int = local_sat_noon - 60 * 60
	assert_eq(CalendarEventsSystem.seconds_until_event_end(unix, 60), 36 * 3600)
	# And under a negative bias (-8h, Pacific-style).
	var unix_west: int = local_sat_noon + 8 * 3600
	assert_eq(CalendarEventsSystem.seconds_until_event_end(unix_west, -480), 36 * 3600)


func test_tz_bias_shifts_the_weekend_boundary() -> void:
	# 23:30 UTC Friday 1970-01-02 (day 1). With +60 min bias it is already
	# local Saturday (day 2) -> event active locally, none in UTC terms.
	var utc_fri_2330: int = 1 * CalendarEventsSystem.SECONDS_PER_DAY + 23 * 3600 + 1800
	var day_utc: int = DailyLoginSystem.local_day_index(utc_fri_2330, 0)
	var day_plus1h: int = DailyLoginSystem.local_day_index(utc_fri_2330, 60)
	assert_true(CalendarEventsSystem.active_event(day_utc).is_empty())
	assert_false(CalendarEventsSystem.active_event(day_plus1h).is_empty())

# endregion


# region — GameState composition

func test_gamestate_multiplier_composes_event_boost() -> void:
	var sat := _local_noon_on_weekday(6)
	TimeManager._test_now_override = sat
	var day: int = DailyLoginSystem.local_day_index(sat, TimeManager.tz_bias_minutes())
	var ev := CalendarEventsSystem.active_event(day)
	assert_false(ev.is_empty(), "precondition: Saturday has an event")
	assert_almost_eq(GameState.multiplier(ev["effect_id"]), 2.0, 1.0e-6,
			"no upgrades: event alone doubles its effect id")
	assert_almost_eq(GameState.multiplier(&"rp_mult"), 1.0, 1.0e-6,
			"rp_mult is never event-boosted")


func test_gamestate_multiplier_untouched_on_weekdays() -> void:
	TimeManager._test_now_override = _local_noon_on_weekday(3)  # Wednesday
	assert_almost_eq(GameState.multiplier(&"gold_mult"), 1.0, 1.0e-6)
	assert_almost_eq(GameState.multiplier(&"shiny_rate"), 1.0, 1.0e-6)

# endregion


# region — banner

func test_banner_visible_on_weekend_hidden_on_weekday() -> void:
	TimeManager._test_now_override = _local_noon_on_weekday(6)
	var view: Control = _CATCHING.instantiate()
	add_child_autofree(view)
	await wait_frames(1)
	view._refresh_event_banner()
	assert_true(view._event_banner.visible)
	assert_string_contains(view._event_banner.text, "this weekend")
	assert_string_contains(view._event_banner.text, "2×", "whole multipliers render without a decimal")
	# Local noon Saturday -> 36h remain; the fixture makes this exact.
	assert_string_contains(view._event_banner.text, "ends in 36h")
	TimeManager._test_now_override = _local_noon_on_weekday(3)
	view._refresh_event_banner()
	assert_false(view._event_banner.visible, "weekday hides the banner")

# endregion
