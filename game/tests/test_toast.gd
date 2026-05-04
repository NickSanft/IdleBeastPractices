## Phase 11a — toast queue + visibility contract.
extends GutTest

const _SCENE := preload("res://game/scenes/ui/toast.tscn")


func _new_toast() -> CanvasLayer:
	var t: CanvasLayer = _SCENE.instantiate()
	add_child_autofree(t)
	return t


func test_show_toast_marks_showing() -> void:
	var t := _new_toast()
	await wait_frames(1)
	t.show_toast("Pet acquired: Green Wisplet", 1.0)
	# show_toast triggers _run_queue which awaits — wait_frames after
	# show_toast lets the first slide-in tween start.
	await wait_frames(2)
	assert_true(t.is_showing(),
			"toast must report showing after show_toast")


func test_label_shows_provided_text() -> void:
	var t := _new_toast()
	await wait_frames(1)
	t.show_toast("Recipe unlocked: Wraith Net", 1.0)
	await wait_frames(2)
	assert_eq(t._label.text, "Recipe unlocked: Wraith Net")


func test_queue_size_grows_when_multiple_toasts_fire() -> void:
	# Three rapid toast calls. The first runs immediately, the next
	# two queue. queue_size() reports the COUNT of queued behind the
	# active one, so it should be 2 after three calls.
	var t := _new_toast()
	await wait_frames(1)
	t.show_toast("First", 0.5)
	t.show_toast("Second", 0.5)
	t.show_toast("Third", 0.5)
	assert_eq(t.queue_size(), 2,
			"with 3 toasts and 1 actively showing, 2 must be queued")


func test_toast_dismisses_after_duration() -> void:
	# Short duration so the test runs quickly. Slide-in (0.22) +
	# duration (0.5) + slide-out (0.22) = 0.94s total. Wait 1.3s.
	var t := _new_toast()
	await wait_frames(1)
	t.show_toast("Brief", 0.5)
	await wait_seconds(1.3)
	assert_false(t.is_showing(),
			"toast should auto-dismiss after the slide-in + duration + slide-out cycle")


func test_queued_toast_runs_after_first_finishes() -> void:
	var t := _new_toast()
	await wait_frames(1)
	t.show_toast("First toast", 0.4)
	t.show_toast("Second toast", 0.4)
	# After ~1.3s the first should be gone and the second showing.
	await wait_seconds(1.3)
	assert_eq(t._label.text, "Second toast",
			"second queued toast should be showing after the first finishes")


func test_duration_is_floored_to_minimum() -> void:
	# show_toast(text, 0.0) shouldn't immediately auto-dismiss with
	# zero hold — the implementation floors to 0.5s so the slide-in
	# isn't wasted.
	var t := _new_toast()
	await wait_frames(1)
	t.show_toast("Min duration", 0.0)
	await wait_frames(2)
	assert_true(t.is_showing(),
			"toast with duration=0 must still floor to a minimum visible window")
