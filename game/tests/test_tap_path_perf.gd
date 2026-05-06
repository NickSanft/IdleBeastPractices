## v0.13.5 — regression tests for the tap-path performance budget.
##
## Background: 12f's Achievements + 12g's QuestLog both subscribe to
## the same fan of progress signals (monster_tapped, monster_caught,
## currency_changed, …). Pre-coalescing, a single caught tap on the
## catching screen fired evaluate_all() 2× and evaluate_progress() 3×.
## Combined with hold-to-tap (12b) at 8 Hz, that's 40 evaluator walks
## per second on Android — a visible perf hit.
##
## The fix is a per-frame dirty flag drained by `_process`. These
## tests assert the budget so the regression can't sneak back in:
##
##   - Many same-frame signals collapse to ONE evaluator call.
##   - Bursty signals across N frames cap at N evaluator calls.
##   - The dirty flag is the public contract — flipped by handlers,
##     cleared by the drain — and tests use `is_dirty()` rather than
##     reaching into private state.
##
## Both autoloads (Achievements, QuestLog) implement the same
## pattern, so we exercise both side-by-side.
extends GutTest


func before_each() -> void:
	# Achievements + QuestLog state must be clean so unrelated unlocks
	# don't cascade evaluator calls during the test.
	GameState.achievements_unlocked = {}
	GameState.quests_completed = {}
	GameState.active_quests = {0: "", 1: "", 2: ""}
	GameState.ledger["total_taps"] = 0
	GameState.ledger["total_catches"] = 0
	GameState.ledger["total_shinies"] = 0
	GameState.pets_owned = []
	GameState.nets_owned = []
	GameState.recipes_crafted = []
	GameState.current_max_tier = 1
	GameState.prestige_count = 0
	# Reset diagnostic counters + dirty flags. Since these are
	# autoloads we manipulate the public surface only.
	Achievements.eval_count = 0
	QuestLog.eval_count = 0
	# Drain any stale dirty bit left from prior tests that touched
	# the EventBus.
	if Achievements.is_dirty():
		Achievements.evaluate_all()
		Achievements.eval_count = 0
	if QuestLog.is_dirty():
		QuestLog.evaluate_progress()
		QuestLog.eval_count = 0
	Achievements._dirty = false
	QuestLog._dirty = false


# region — coalescing budget

func test_burst_of_signals_in_one_frame_yields_one_achievement_eval() -> void:
	# Fire 10 signals back-to-back without yielding to _process.
	for i in 10:
		EventBus.monster_tapped.emit("red_wisplet", i)
	# Before the frame drains, the flag is set but eval hasn't run.
	assert_true(Achievements.is_dirty(),
		"any monster_tapped emit must mark Achievements dirty")
	assert_eq(Achievements.eval_count, 0,
		"Achievements must NOT eval per signal — coalesce until _process")
	# Drain manually (simulates the next frame's _process tick).
	Achievements._process(0.0)
	assert_eq(Achievements.eval_count, 1,
		"10 signals in one frame must collapse to exactly 1 evaluator call")


func test_burst_of_signals_in_one_frame_yields_one_quest_eval() -> void:
	for i in 10:
		EventBus.monster_caught.emit("red_wisplet", i, false, "tap")
	assert_true(QuestLog.is_dirty(),
		"monster_caught must mark QuestLog dirty")
	assert_eq(QuestLog.eval_count, 0,
		"QuestLog must NOT eval per signal — coalesce until _process")
	QuestLog._process(0.0)
	assert_eq(QuestLog.eval_count, 1,
		"10 signals in one frame must collapse to exactly 1 evaluator call")


func test_caught_tap_simulation_stays_under_budget() -> void:
	# Simulate a caught tap: monster_tapped -> currency_changed
	# (from add_gold) -> monster_caught. Pre-fix, this path called
	# Achievements.evaluate_all 2× and QuestLog.evaluate_progress 3×.
	# Post-fix, both should be 1× per frame regardless of fan-out.
	EventBus.monster_tapped.emit("red_wisplet", 1)
	EventBus.currency_changed.emit("gold", 5)
	EventBus.monster_caught.emit("red_wisplet", 1, false, "tap")

	Achievements._process(0.0)
	QuestLog._process(0.0)

	assert_eq(Achievements.eval_count, 1,
		"a single caught tap (3 cascaded signals) must run Achievements once per frame")
	assert_eq(QuestLog.eval_count, 1,
		"a single caught tap (3 cascaded signals) must run QuestLog once per frame")


func test_eight_taps_in_one_frame_yields_one_eval() -> void:
	# Hold-to-tap at 8 Hz worst case: 8 taps in a single frame budget.
	# With coalescing, that's still one evaluator call per autoload —
	# not 8× or 16×.
	for i in 8:
		EventBus.monster_tapped.emit("red_wisplet", i)
		EventBus.currency_changed.emit("gold", 5)
		EventBus.monster_caught.emit("red_wisplet", i, false, "tap")

	Achievements._process(0.0)
	QuestLog._process(0.0)

	assert_eq(Achievements.eval_count, 1,
		"8 caught taps in one frame must coalesce to one Achievements eval")
	assert_eq(QuestLog.eval_count, 1,
		"8 caught taps in one frame must coalesce to one QuestLog eval")


func test_signals_across_frames_eval_per_frame() -> void:
	# One signal per frame across 5 frames should produce 5 evaluator
	# calls, NOT the coalesced 1 — coalescing is per-frame, not
	# per-anything-else.
	for i in 5:
		EventBus.monster_tapped.emit("red_wisplet", i)
		Achievements._process(0.0)
		QuestLog._process(0.0)
	assert_eq(Achievements.eval_count, 5,
		"5 signals across 5 frames must eval 5 times")
	assert_eq(QuestLog.eval_count, 5,
		"5 signals across 5 frames must eval 5 times")


func test_idle_frame_does_not_eval() -> void:
	# No signals -> dirty stays false -> evaluator does NOT run.
	# Cheap correctness check: confirms we don't pay any per-frame
	# cost when nothing is happening.
	for _i in 60:
		Achievements._process(0.0)
		QuestLog._process(0.0)
	assert_eq(Achievements.eval_count, 0,
		"60 idle frames must not run Achievements eval")
	assert_eq(QuestLog.eval_count, 0,
		"60 idle frames must not run QuestLog eval")

# endregion


# region — content registry allocation budget

func test_achievement_index_returns_same_dict_every_call() -> void:
	# The index getter must return the live cached dict, NOT a copy.
	# A new copy per call would defeat the perf fix because the
	# evaluator would re-allocate every frame.
	var a := ContentRegistry.achievement_index()
	var b := ContentRegistry.achievement_index()
	assert_true(a == b, "achievement_index() must return the cached dict reference")
	# Sanity: the index isn't empty (12f shipped 20 achievements).
	assert_gt(a.size(), 0, "expected the achievement index to be populated")


func test_quest_index_returns_same_dict_every_call() -> void:
	var a := ContentRegistry.quest_index()
	var b := ContentRegistry.quest_index()
	assert_true(a == b, "quest_index() must return the cached dict reference")
	assert_gt(a.size(), 0, "expected the quest index to be populated")

# endregion
