## Pure helpers for the daily-resetting quest set. v0.15.15 (retention bundle).
##
## Kept side-effect-free (no GameState / EventBus) so the daily pick rotation,
## the progress-scaled reward curve, and the reset countdown are deterministically
## unit-testable. The stateful orchestration lives in the DailyQuests autoload.
##
## A "daily quest" tracks a per-day DELTA of a lifetime ledger counter: at the
## start of each local day the current counter is snapshotted as a baseline, and
## progress = current_counter - baseline. The day boundary reuses
## DailyLoginSystem.local_day_index (local midnight).
class_name DailyQuestsSystem
extends RefCounted

## How many daily quests are active per day (one per ledger-field category).
const DAILY_COUNT := 3

## Progress-scaled individual reward (smaller than the once-a-day login reward
## since there are several per day): max(tier floor, 1% of gross run gold).
const QUEST_FLOOR_BASE := 25.0
const QUEST_FLOOR_GROWTH := 2.0
const QUEST_GROSS_FRACTION := 0.01

## Complete-all-three bonus Rancher Points (the retention driver), scaled by tier.
const COMPLETE_ALL_RP_BASE := 5


## Choose the day's daily quests from the DAILY-tier pool: one quest per distinct
## ledger field (category), rotating the threshold within each category by the
## day index so the set varies day to day. Deterministic (no RNG) — returns a
## list of quest-id strings sorted by category for stable ordering.
static func pick_for_day(daily_pool: Array, day_index: int) -> Array:
	var groups: Dictionary = {}  # ledger_field -> Array[QuestResource]
	for q in daily_pool:
		if q == null:
			continue
		var field: String = String(q.ledger_field)
		if not groups.has(field):
			groups[field] = []
		groups[field].append(q)
	var field_keys: Array = groups.keys()
	field_keys.sort()
	var out: Array = []
	var d: int = day_index if day_index >= 0 else 0
	for field in field_keys:
		var arr: Array = groups[field]
		arr.sort_custom(func(a, b): return int(a.threshold) < int(b.threshold))
		out.append(String(arr[d % arr.size()].id))
	return out


## Progress-scaled gold for completing one daily quest.
static func quest_gold(gross_gold_this_run: BigNumber, current_max_tier: int) -> BigNumber:
	var tier: int = max(1, current_max_tier)
	var floor_gold: BigNumber = BigNumber.from_float(QUEST_FLOOR_BASE * pow(QUEST_FLOOR_GROWTH, float(tier - 1)))
	var gross: BigNumber = gross_gold_this_run if gross_gold_this_run != null else BigNumber.zero()
	var pct: BigNumber = gross.multiply_float(QUEST_GROSS_FRACTION)
	return floor_gold if floor_gold.gt(pct) else pct


## Rancher Points for completing ALL of the day's daily quests.
static func complete_all_rp(current_max_tier: int) -> int:
	return COMPLETE_ALL_RP_BASE + max(0, current_max_tier)


## Seconds remaining until the next local-midnight reset, for the countdown UI.
static func seconds_until_reset(now_unix: int, tz_bias_minutes: int) -> int:
	var today: int = DailyLoginSystem.local_day_index(now_unix, tz_bias_minutes)
	# Next local midnight, expressed back in UTC unix seconds.
	var next_midnight_utc: int = (today + 1) * DailyLoginSystem.SECONDS_PER_DAY - tz_bias_minutes * 60
	return max(0, next_midnight_utc - now_unix)
