## v0.15.20 — calendar boost events: deterministic, server-less live-ops.
##
## Weekends (local Saturday + Sunday) carry a boost that rotates weekly
## among three types. Everything is derived from the LOCAL day index
## (DailyLoginSystem's local-midnight convention): no save fields, no
## server, works fully offline, and two devices in the same timezone
## always agree. Tests fix the clock via TimeManager._test_now_override
## and pass tz_bias explicitly — this class never touches the wall clock.
class_name CalendarEventsSystem
extends RefCounted

const SECONDS_PER_DAY := 86400

## Weekly rotation. effect_id matches UpgradeEffectsSystem's multiplier ids
## so a boost composes multiplicatively with the player's upgrades — and
## anything NOT named here (rp_mult, tap_speed, offline_cap, …) is
## implicitly whitelisted out: event_multiplier returns 1.0 for it.
const EVENTS := [
	{"id": &"gold_rush", "display_name": "Gold Rush", "icon": "🪙", "effect_id": &"gold_mult", "multiplier": 2.0},
	{"id": &"shiny_weekend", "display_name": "Shiny Weekend", "icon": "✨", "effect_id": &"shiny_rate", "multiplier": 2.0},
	{"id": &"harvest_weekend", "display_name": "Harvest Weekend", "icon": "🧺", "effect_id": &"drop_amount", "multiplier": 2.0},
]


## 0=Sunday … 6=Saturday. Unix day 0 (1970-01-01) was a Thursday (=4).
## posmod keeps pre-1970 (negative) indices sane.
static func weekday(day_index: int) -> int:
	return posmod(day_index + 4, 7)


static func is_weekend(day_index: int) -> bool:
	var wd: int = weekday(day_index)
	return wd == 0 or wd == 6


## The active event for a local day, or {} on weekdays. Saturday and its
## following Sunday share ONE event (the rotation is anchored on the
## Saturday), so a boost never swaps mid-weekend.
##
## NOTE: with the current epoch alignment (Saturdays ≡ 2 mod 7) a plain
## floor(day/7) would happen to give the same pairing — the explicit
## Saturday anchor is kept because it states the INTENT and stays correct
## if the week bucketing ever changes.
static func active_event(day_index: int) -> Dictionary:
	if not is_weekend(day_index):
		return {}
	var saturday_index: int = day_index if weekday(day_index) == 6 else day_index - 1
	var week: int = int(floor(float(saturday_index) / 7.0))
	return EVENTS[posmod(week, EVENTS.size())]


## The multiplier the active event contributes to `effect_id` — 1.0 when
## no event is running or the event boosts something else.
static func event_multiplier(effect_id: StringName, day_index: int) -> float:
	var ev: Dictionary = active_event(day_index)
	if ev.is_empty() or ev["effect_id"] != effect_id:
		return 1.0
	return float(ev["multiplier"])


## Seconds until the running event ends (end of the local Sunday), or 0
## when no event is active. Same local-midnight convention as the daily
## systems. The countdown assumes the CURRENT tz bias holds until the end:
## a DST transition mid-weekend drifts the estimate by the DST delta until
## the transition happens, after which the 1 s banner refresh self-heals —
## display-only, whole-hour granularity, accepted.
static func seconds_until_event_end(now_unix: int, tz_bias_minutes: int) -> int:
	var day_index: int = DailyLoginSystem.local_day_index(now_unix, tz_bias_minutes)
	if active_event(day_index).is_empty():
		return 0
	var days_left: int = 1 if weekday(day_index) == 6 else 0  # Sat runs through Sun
	var local_unix: int = now_unix + tz_bias_minutes * 60
	var end_local: int = (day_index + days_left + 1) * SECONDS_PER_DAY
	return end_local - local_unix
