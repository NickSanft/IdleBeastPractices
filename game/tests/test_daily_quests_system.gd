## v0.15.15 — DailyQuestsSystem pure-logic tests (retention bundle).
##
## Covers the daily pick rotation (one per ledger-field category, deterministic,
## varies by day), the progress-scaled reward curve, the complete-all RP, and
## the reset countdown.
extends GutTest


func before_each() -> void:
	ContentRegistry.ensure_loaded()


func _daily_pool() -> Array:
	var out: Array = []
	for q in ContentRegistry.quests():
		if q != null and q.quest_tier == QuestResource.QuestTier.DAILY:
			out.append(q)
	return out


# region — pick_for_day

func test_pool_has_daily_quests() -> void:
	assert_gt(_daily_pool().size(), 0, "the DAILY-tier quest pool must be authored")


func test_pick_returns_one_quest_per_category() -> void:
	var pool := _daily_pool()
	var picks := DailyQuestsSystem.pick_for_day(pool, 0)
	assert_eq(picks.size(), DailyQuestsSystem.DAILY_COUNT, "picks one quest per ledger-field category")
	# Every pick is a distinct ledger field (one per category).
	var fields: Dictionary = {}
	for qid in picks:
		var q: QuestResource = ContentRegistry.quest(StringName(qid))
		assert_not_null(q)
		fields[String(q.ledger_field)] = true
	assert_eq(fields.size(), picks.size(), "each daily quest tracks a distinct counter")


func test_pick_is_deterministic_for_a_day() -> void:
	var pool := _daily_pool()
	assert_eq(DailyQuestsSystem.pick_for_day(pool, 42), DailyQuestsSystem.pick_for_day(pool, 42),
			"same day index → same picks (no RNG)")


func test_pick_varies_across_days() -> void:
	var pool := _daily_pool()
	var seen: Dictionary = {}
	for day in range(0, 3):
		seen["|".join(DailyQuestsSystem.pick_for_day(pool, day))] = true
	assert_gt(seen.size(), 1, "the daily set should rotate across consecutive days")

# endregion


# region — reward curve

func test_quest_gold_floor_dominates_with_low_gross() -> void:
	# Tier 1 floor = 25; 1% of 0 gross = 0 → floor wins.
	assert_almost_eq(DailyQuestsSystem.quest_gold(BigNumber.zero(), 1).to_float(), 25.0, 0.5)
	# Tier 3 floor = 25 * 2^2 = 100.
	assert_almost_eq(DailyQuestsSystem.quest_gold(BigNumber.zero(), 3).to_float(), 100.0, 0.5)


func test_quest_gold_scales_with_gross_when_above_floor() -> void:
	# 1% of 1,000,000 = 10,000, which beats the tier-1 floor (25).
	assert_almost_eq(DailyQuestsSystem.quest_gold(BigNumber.from_float(1_000_000.0), 1).to_float(),
			10_000.0, 1.0)


func test_complete_all_rp_scales_with_tier() -> void:
	assert_eq(DailyQuestsSystem.complete_all_rp(1), 6, "5 base + tier 1")
	assert_eq(DailyQuestsSystem.complete_all_rp(10), 15)

# endregion


# region — reset countdown

func test_seconds_until_reset_counts_down_to_local_midnight() -> void:
	# 1 hour into a UTC day, bias 0 → 23h until next midnight.
	var now: int = 86400 * 100 + 3600
	assert_eq(DailyQuestsSystem.seconds_until_reset(now, 0), 86400 - 3600)
	# Right at midnight → a full day remains.
	assert_eq(DailyQuestsSystem.seconds_until_reset(86400 * 100, 0), 86400)

# endregion
