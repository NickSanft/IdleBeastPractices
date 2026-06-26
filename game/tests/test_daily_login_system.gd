## v0.15.14 — DailyLoginSystem pure-logic tests (retention bundle).
##
## Covers the day-index maths (incl. timezone bias), the streak decision
## tree (first claim / consecutive / missed gap / already-claimed /
## clock-backward), the 7-day cycle wrap, and the progress-scaled reward
## curve (tier floor vs gross-fraction, day-7 milestone RP).
extends GutTest


# region — local_day_index

func test_local_day_index_utc_midnight() -> void:
	# Exactly 100 days after the epoch at UTC, bias 0 → day index 100.
	assert_eq(DailyLoginSystem.local_day_index(86400 * 100, 0), 100)
	# Later the same UTC day stays 100.
	assert_eq(DailyLoginSystem.local_day_index(86400 * 100 + 3600, 0), 100)


func test_local_day_index_respects_timezone_bias() -> void:
	# 100 seconds into UTC day 100, in UTC-5 (bias -300 min), local time is
	# still the previous evening → day 99.
	var now: int = 86400 * 100 + 100
	assert_eq(DailyLoginSystem.local_day_index(now, -300), 99,
			"a westward tz should roll a just-past-UTC-midnight time back a day")
	# In UTC+2 (bias +120) it's already day 100.
	assert_eq(DailyLoginSystem.local_day_index(now, 120), 100)

# endregion


# region — evaluate decision tree

func test_first_ever_claim_starts_streak_at_one() -> void:
	var d := DailyLoginSystem.evaluate(100, 0, 0)
	assert_true(d["claimable"])
	assert_eq(d["new_streak"], 1)
	assert_eq(d["cycle_day"], 1)
	assert_false(d["missed"], "a never-claimed player hasn't 'missed' a streak")


func test_consecutive_day_increments_streak() -> void:
	var d := DailyLoginSystem.evaluate(101, 100, 3)
	assert_true(d["claimable"])
	assert_eq(d["new_streak"], 4)
	assert_eq(d["cycle_day"], 4)
	assert_false(d["missed"])


func test_gap_resets_streak_and_flags_missed() -> void:
	# Last claimed day 100, now day 105 → broke the streak.
	var d := DailyLoginSystem.evaluate(105, 100, 4)
	assert_true(d["claimable"])
	assert_eq(d["new_streak"], 1, "a 2+ day gap restarts the streak at 1")
	assert_eq(d["cycle_day"], 1)
	assert_true(d["missed"], "breaking a real streak should flag missed")


func test_already_claimed_today_is_not_claimable() -> void:
	var d := DailyLoginSystem.evaluate(100, 100, 3)
	assert_false(d["claimable"])
	assert_eq(d["new_streak"], 3, "no change when already claimed today")


func test_clock_moved_backward_is_not_claimable() -> void:
	# Device clock now reads day 99 but we last claimed day 100 — a backward
	# clock change within tolerance. Guard like TimeManager's offline anti-tamper.
	var d := DailyLoginSystem.evaluate(99, 100, 3)
	assert_false(d["claimable"])
	assert_eq(d["new_streak"], 3)


func test_corrupt_far_future_last_claim_resets_instead_of_locking_out() -> void:
	# A poisoned cloud MAX-merge (or a wildly-wrong clock) could leave a
	# last-claim day far in the future. Without a guard the clock-backward check
	# would block daily rewards until the real date caught up (~years). Treat an
	# implausibly far-future value as corrupt → reset to a fresh claimable day.
	var d := DailyLoginSystem.evaluate(5, 1000, 4)
	assert_true(d["claimable"], "a corrupt far-future last-claim must not lock the player out")
	assert_eq(d["new_streak"], 1, "corrupt value resets the streak")
	assert_eq(d["cycle_day"], 1)
	assert_true(d["missed"])


func test_forward_clock_jump_is_claimable_by_design() -> void:
	# DOCUMENTED behavior: the system trusts the device clock, so advancing it a
	# day reads as a new (consecutive) day and is claimable. This is an accepted
	# self-only limitation of an offline single-player game — a real-time
	# throttle would wrongly deny the legitimate 11:59pm→12:01am claim.
	var d := DailyLoginSystem.evaluate(101, 100, 1)
	assert_true(d["claimable"])
	assert_eq(d["new_streak"], 2, "a forward jump to the next day reads as consecutive")


func test_nonpositive_today_is_not_claimable() -> void:
	assert_false(DailyLoginSystem.evaluate(0, 0, 0)["claimable"])

# endregion


# region — cycle_day_for wrap

func test_cycle_day_wraps_every_seven() -> void:
	assert_eq(DailyLoginSystem.cycle_day_for(1), 1)
	assert_eq(DailyLoginSystem.cycle_day_for(7), 7)
	assert_eq(DailyLoginSystem.cycle_day_for(8), 1, "day 8 wraps back to cycle day 1")
	assert_eq(DailyLoginSystem.cycle_day_for(14), 7)
	assert_eq(DailyLoginSystem.cycle_day_for(15), 1)
	# Defensive: non-positive streak clamps to day 1.
	assert_eq(DailyLoginSystem.cycle_day_for(0), 1)


func test_gap_from_cycle_max_resets_to_day_one() -> void:
	# A player at the end of the cycle (streak 7, cycle day 7) who then misses a
	# day must restart cleanly at streak 1 / cycle day 1, flagged missed.
	var d := DailyLoginSystem.evaluate(108, 105, 7)
	assert_true(d["claimable"])
	assert_eq(d["new_streak"], 1)
	assert_eq(d["cycle_day"], 1)
	assert_true(d["missed"])

# endregion


# region — reward_for curve

func test_reward_escalates_across_cycle() -> void:
	# With zero gross gold the tier floor (tier 1 = 50) is the base; the gold
	# weight escalates 1× (day 1) → 10× (day 7).
	var day1: Dictionary = DailyLoginSystem.reward_for(1, BigNumber.zero(), 1)
	var day7: Dictionary = DailyLoginSystem.reward_for(7, BigNumber.zero(), 1)
	assert_almost_eq(day1["gold"].to_float(), 50.0, 0.5,
			"day 1 gold == tier-1 floor (50) × weight 1")
	assert_almost_eq(day7["gold"].to_float(), 500.0, 1.0,
			"day 7 gold == floor 50 × weight 10")
	assert_true(day7["gold"].gt(day1["gold"]), "day 7 must reward more than day 1")


func test_day_seven_grants_milestone_rp_scaled_by_tier() -> void:
	assert_eq(DailyLoginSystem.reward_for(7, BigNumber.zero(), 1)["rp"], 4,
			"day 7 RP == base 3 + tier 1")
	assert_eq(DailyLoginSystem.reward_for(7, BigNumber.zero(), 10)["rp"], 13,
			"day 7 RP scales with current max tier (3 + 10)")
	# Non-milestone days grant no RP.
	for day in [1, 2, 3, 4, 5, 6]:
		assert_eq(DailyLoginSystem.reward_for(day, BigNumber.zero(), 5)["rp"], 0,
				"only day 7 pays RP")


func test_reward_scales_with_gross_run_gold_when_above_floor() -> void:
	# 1,000,000 gross × 2% = 20,000, which dwarfs the tier-1 floor (50), so the
	# fraction path drives the reward (keeps it relevant in the late game).
	var r: Dictionary = DailyLoginSystem.reward_for(1, BigNumber.from_float(1_000_000.0), 1)
	assert_almost_eq(r["gold"].to_float(), 20_000.0, 1.0,
			"day-1 gold == 2% of gross (20k) when that beats the floor")


func test_reward_floor_dominates_early_and_post_prestige() -> void:
	# Tiny gross (just prestiged): the tier floor keeps the reward meaningful.
	var r: Dictionary = DailyLoginSystem.reward_for(1, BigNumber.from_float(100.0), 3)
	# Tier-3 floor = 50 × 2^2 = 200; 2% of 100 = 2 → floor wins.
	assert_almost_eq(r["gold"].to_float(), 200.0, 1.0,
			"tier-3 floor (200) beats 2%-of-100 (2)")

# endregion
