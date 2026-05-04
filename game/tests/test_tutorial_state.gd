## Phase 12c — TutorialState persistence + step gating.
extends GutTest


func before_each() -> void:
	TutorialState.steps_seen = {}


func after_each() -> void:
	TutorialState.steps_seen = {}
	TutorialState.save_to_disk()


func test_should_show_returns_true_for_unseen_step() -> void:
	assert_true(TutorialState.should_show(TutorialState.STEP_TAP_FIRST_MONSTER))


func test_mark_seen_flips_should_show_to_false() -> void:
	TutorialState.mark_seen(TutorialState.STEP_TAP_FIRST_MONSTER)
	assert_false(TutorialState.should_show(TutorialState.STEP_TAP_FIRST_MONSTER))


func test_mark_seen_idempotent() -> void:
	TutorialState.mark_seen(TutorialState.STEP_BUY_FIRST_NET)
	TutorialState.mark_seen(TutorialState.STEP_BUY_FIRST_NET)
	assert_eq(TutorialState.steps_seen.size(), 1,
			"marking the same step twice must not duplicate the entry")


func test_reset_clears_all_steps() -> void:
	TutorialState.mark_seen(TutorialState.STEP_TAP_FIRST_MONSTER)
	TutorialState.mark_seen(TutorialState.STEP_BUY_FIRST_NET)
	TutorialState.mark_seen(TutorialState.STEP_ENTER_BATTLE)
	assert_eq(TutorialState.steps_seen.size(), 3)
	TutorialState.reset()
	assert_eq(TutorialState.steps_seen.size(), 0)
	# All steps should be eligible to show again.
	for step in TutorialState.ALL_STEPS:
		assert_true(TutorialState.should_show(step),
				"step %s should be should_show=true after reset" % String(step))


func test_has_any_progress() -> void:
	assert_false(TutorialState.has_any_progress())
	TutorialState.mark_seen(TutorialState.STEP_TAP_FIRST_MONSTER)
	assert_true(TutorialState.has_any_progress())
	TutorialState.reset()
	assert_false(TutorialState.has_any_progress())


func test_round_trip_through_disk() -> void:
	TutorialState.mark_seen(TutorialState.STEP_BUY_FIRST_NET)
	TutorialState.mark_seen(TutorialState.STEP_ENTER_BATTLE)
	# Forget in-memory.
	TutorialState.steps_seen = {}
	TutorialState.load_from_disk()
	assert_false(TutorialState.should_show(TutorialState.STEP_BUY_FIRST_NET),
			"persisted step must remain marked seen across reloads")
	assert_false(TutorialState.should_show(TutorialState.STEP_ENTER_BATTLE))
	assert_true(TutorialState.should_show(TutorialState.STEP_TAP_FIRST_MONSTER),
			"unsaved steps must still be eligible after reload")
