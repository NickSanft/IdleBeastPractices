## Phase 12c — coachmark anchors to a target Control, displays a
## hint, and dismisses on tap (marking the step as seen via
## TutorialState).
extends GutTest

const _SCENE := preload("res://game/scenes/ui/coachmark.tscn")


func before_each() -> void:
	TutorialState.steps_seen = {}


func after_each() -> void:
	TutorialState.steps_seen = {}


func _new_coachmark() -> CanvasLayer:
	var c: CanvasLayer = _SCENE.instantiate()
	add_child_autofree(c)
	return c


func _new_target() -> Control:
	# Lightweight Control to act as a target. add_child_autofree
	# cleans up at test end.
	var c := Button.new()
	c.text = "T"
	c.size = Vector2(48, 48)
	c.position = Vector2(100, 200)
	add_child_autofree(c)
	return c


func test_starts_hidden() -> void:
	var c := _new_coachmark()
	await wait_frames(1)
	assert_false(c.visible)


func test_show_for_makes_visible_and_sets_hint() -> void:
	var c := _new_coachmark()
	var target := _new_target()
	await wait_frames(1)
	c.show_for(target, "Tap here.", TutorialState.STEP_TAP_FIRST_MONSTER)
	assert_true(c.visible)
	assert_eq(c._hint_label.text, "Tap here.")


func test_dismiss_marks_step_seen() -> void:
	var c := _new_coachmark()
	var target := _new_target()
	await wait_frames(1)
	c.show_for(target, "Tap here.", TutorialState.STEP_BUY_FIRST_NET)
	assert_true(TutorialState.should_show(TutorialState.STEP_BUY_FIRST_NET))
	c.dismiss()
	assert_false(TutorialState.should_show(TutorialState.STEP_BUY_FIRST_NET),
			"dismiss must mark the step as seen so it doesn't re-fire")
	assert_false(c.visible)


func test_tap_on_backdrop_dismisses() -> void:
	var c := _new_coachmark()
	var target := _new_target()
	await wait_frames(1)
	c.show_for(target, "Tap here.", TutorialState.STEP_ENTER_BATTLE)
	# Synthesize a left-click on the backdrop.
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	c._on_input(event)
	assert_false(c.visible)
	assert_false(TutorialState.should_show(TutorialState.STEP_ENTER_BATTLE))
