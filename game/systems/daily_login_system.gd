## Pure daily-login reward logic — streak tracking + escalating 7-day cycle.
##
## v0.15.14 (retention bundle). Kept side-effect-free (no GameState /
## TimeManager / EventBus) so the day-boundary maths and the reward curve
## are deterministically unit-testable: callers inject `now_unix` + the
## timezone bias and pass in the current progress numbers; this returns
## plain dictionaries.
##
## Day model: a "day" is a LOCAL calendar day, expressed as a day index =
## floor((utc_unix + tz_bias_seconds) / 86400). Consecutive day indices
## continue the streak; a gap of two or more resets it. The streak maps
## onto a repeating 7-day cycle whose rewards escalate (day 7 spikes and
## also pays Rancher Points).
class_name DailyLoginSystem
extends RefCounted

const CYCLE_LENGTH := 7

## Gold multiplier per cycle day (index 0 == day 1). Day 7 spikes to make
## keeping the streak alive for the full week feel worth it.
const CYCLE_GOLD_WEIGHTS: Array[float] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 10.0]

## The progress-scaled base reward is a small fraction of the player's
## gross gold earned this run, floored by a tier-scaled minimum so the
## reward stays meaningful early on and right after a prestige (when
## gross-this-run is ~0).
const GROSS_FRACTION := 0.02
const FLOOR_BASE := 50.0
const FLOOR_GROWTH := 2.0

## Day-7 milestone Rancher Points: a flat base plus the current max tier,
## so the prestige-surviving reward grows with progress.
const MILESTONE_RP_BASE := 3

const SECONDS_PER_DAY := 86400

## A last-claim day index more than this many days in the FUTURE of "today" is
## treated as corrupt rather than blocking (see evaluate()).
const FUTURE_TOLERANCE_DAYS := 1


## Local calendar-day index for a UTC unix timestamp. `tz_bias_minutes`
## is minutes east of UTC (Time.get_time_zone_from_system()["bias"]).
static func local_day_index(now_unix: int, tz_bias_minutes: int) -> int:
	var local_unix: int = now_unix + tz_bias_minutes * 60
	return int(floor(float(local_unix) / float(SECONDS_PER_DAY)))


## Decide whether today's login is claimable and what the resulting streak
## + cycle day would be. Pure — no clock access.
##
## Returns: {
##   claimable: bool,      # is there a reward to grant right now?
##   new_streak: int,      # streak AFTER claiming (== current if not claimable)
##   cycle_day: int,       # 1..CYCLE_LENGTH position to reward (0 if not claimable)
##   missed: bool,         # true if a prior streak was broken by a gap
## }
##
## `last_claim_index` is 0 for a player who has never claimed.
##
## DEVICE-CLOCK TRUST: this trusts the device's local clock as authoritative,
## like the offline-progress system. It therefore cannot stop a player who sets
## their clock FORWARD to claim early — an accepted, self-only limitation of an
## offline single-player game (unfixable without a trusted server clock; and a
## real-time throttle would wrongly deny the legitimate 11:59pm→12:01am
## midnight-boundary claim). A clock set BACKWARD by ≤ FUTURE_TOLERANCE_DAYS is
## simply not-claimable (no double-grant; the next forward day claims normally).
static func evaluate(today_index: int, last_claim_index: int, current_streak: int) -> Dictionary:
	# Defensive: a non-positive "today" (pre-epoch / bad clock) is never claimable.
	if today_index <= 0:
		return {"claimable": false, "new_streak": current_streak, "cycle_day": 0, "missed": false}
	# Last-claim is in the FUTURE of today.
	if last_claim_index > today_index:
		# A small overshoot is a backward clock nudge / timezone jitter across a
		# day boundary — don't grant (avoids a double-claim).
		if last_claim_index - today_index <= FUTURE_TOLERANCE_DAYS:
			return {"claimable": false, "new_streak": current_streak, "cycle_day": 0, "missed": false}
		# An implausibly far-future last-claim is a corrupt value — e.g. a
		# poisoned cloud MAX-merge (a stale device wrote a huge day index) or a
		# wildly-wrong clock. Reset rather than block: otherwise the clock-tamper
		# guard would lock the player out of daily rewards until the date caught
		# up. Resetting grants exactly ONE claim, so it's not a farm vector.
		return {"claimable": true, "new_streak": 1, "cycle_day": cycle_day_for(1), "missed": true}
	# Already claimed today.
	if last_claim_index == today_index:
		return {"claimable": false, "new_streak": current_streak, "cycle_day": cycle_day_for(current_streak), "missed": false}
	# Claimable. Consecutive day continues the streak; any larger gap (or a
	# never-claimed player) starts a fresh streak at 1.
	var new_streak: int
	var missed := false
	if last_claim_index == today_index - 1:
		new_streak = current_streak + 1
	else:
		new_streak = 1
		missed = last_claim_index > 0  # only "missed" if a real streak existed
	return {
		"claimable": true,
		"new_streak": new_streak,
		"cycle_day": cycle_day_for(new_streak),
		"missed": missed,
	}


## Map a streak length onto its 1..CYCLE_LENGTH position in the cycle.
static func cycle_day_for(streak: int) -> int:
	if streak <= 0:
		return 1
	return ((streak - 1) % CYCLE_LENGTH) + 1


## Reward for a given cycle day, scaled to the player's progress.
##
## Returns {gold: BigNumber, rp: int, cycle_day: int}.
static func reward_for(cycle_day: int, gross_gold_this_run: BigNumber, current_max_tier: int) -> Dictionary:
	var day: int = clampi(cycle_day, 1, CYCLE_LENGTH)
	var weight: float = CYCLE_GOLD_WEIGHTS[day - 1]
	# Progress-scaled base = max(tier floor, fraction of gross run gold).
	var floor_gold: BigNumber = _tier_floor_gold(current_max_tier)
	var gross: BigNumber = gross_gold_this_run if gross_gold_this_run != null else BigNumber.zero()
	var pct_gold: BigNumber = gross.multiply_float(GROSS_FRACTION)
	var base: BigNumber = floor_gold if floor_gold.gt(pct_gold) else pct_gold
	var gold: BigNumber = base.multiply_float(weight)
	var rp: int = 0
	if day == CYCLE_LENGTH:
		rp = MILESTONE_RP_BASE + max(0, current_max_tier)
	return {"gold": gold, "rp": rp, "cycle_day": day}


static func _tier_floor_gold(current_max_tier: int) -> BigNumber:
	var tier: int = max(1, current_max_tier)
	return BigNumber.from_float(FLOOR_BASE * pow(FLOOR_GROWTH, float(tier - 1)))
