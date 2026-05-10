## v0.15.1 (Phase 14b) — resize-latency regression tests.
##
## Asserts the per-frame coalescing + flip-only-on-change machinery
## main.gd adopted in 14b. Pre-fix, every `DeviceLayout.layout_changed`
## emit ran a full safe-area apply AND a composition-root tear-down
## + rebuild. A desktop window drag fires `size_changed` dozens of
## times per second; a foldable mid-fold can fire several times per
## animation. With the old direct subscriptions each event ran the
## heavy pipeline.
##
## Post-fix:
##   1. Both handlers route through a single `_on_layout_changed`
##      that just sets dirty flags.
##   2. `_process` drains the flags once per frame.
##   3. Orientation rebuild ONLY runs when `is_landscape` actually
##      flipped from the last applied value. Most resize events
##      change only safe area, not orientation.
##
## These tests pin all three behaviors plus a wall-clock budget for
## the full pipeline, so a future maintainer who re-introduces
## per-event apply (or accidentally removes the flip-only check)
## fails on a named test.
extends GutTest

const _MAIN_SCENE := preload("res://game/scenes/main.tscn")


func _instantiate_main() -> Node:
	var main: Node = _MAIN_SCENE.instantiate()
	add_child_autofree(main)
	# Initial paint via _build_ui ran safe_area_apply + orientation_apply
	# each exactly once. Reset so tests measure only the post-init burst.
	main.reset_layout_apply_counters()
	return main


func before_each() -> void:
	DeviceLayout._test_set_orientation(false)
	DeviceLayout._test_set_safe_area(Rect2(0, 0, 720, 1280))


func after_each() -> void:
	DeviceLayout._test_set_orientation(false)


# region — coalescing budget

func test_burst_of_layout_changed_defers_apply_until_process() -> void:
	# Same pattern as Phase 13e's Achievements / QuestLog coalesce:
	# emit N signals in a tight loop, verify NO applies happen
	# before _process drains.
	var main: Node = _instantiate_main()
	for _i in 10:
		DeviceLayout.layout_changed.emit()
	assert_eq(main.safe_area_apply_count, 0,
		"10 layout_changed emits must NOT run safe_area apply until _process drains")
	assert_eq(main.orientation_apply_count, 0,
		"10 layout_changed emits must NOT run orientation apply until _process drains")
	# Drain.
	main._process(0.0)
	assert_eq(main.safe_area_apply_count, 1,
		"after _process drain, safe_area apply must have run exactly once")
	# Orientation didn't flip, so its apply should still be zero.
	assert_eq(main.orientation_apply_count, 0,
		"orientation apply must be skipped when is_landscape didn't flip")


func test_idle_frame_does_no_layout_work() -> void:
	# 60 idle _process ticks must cost zero applies — no work when
	# nothing changed.
	var main: Node = _instantiate_main()
	for _i in 60:
		main._process(0.0)
	assert_eq(main.safe_area_apply_count, 0)
	assert_eq(main.orientation_apply_count, 0)


func test_burst_across_two_frames_drains_twice() -> void:
	# Proves the coalesce is per-frame, not "ever". Two bursts
	# separated by a _process drain produce two drained applies.
	var main: Node = _instantiate_main()
	DeviceLayout.layout_changed.emit()
	main._process(0.0)
	DeviceLayout.layout_changed.emit()
	main._process(0.0)
	assert_eq(main.safe_area_apply_count, 2,
		"two single-emit bursts separated by drain = two applies")

# endregion


# region — orientation flip is the only thing that triggers a heavy rebuild

func test_orientation_flip_triggers_one_rebuild() -> void:
	var main: Node = _instantiate_main()
	DeviceLayout._test_set_orientation(true)
	main._process(0.0)
	assert_eq(main.orientation_apply_count, 1,
		"an orientation flip must trigger exactly one rebuild")


func test_burst_emits_with_no_flip_skip_rebuild_entirely() -> void:
	# 100 layout_changed emits with no orientation flip → zero
	# rebuilds. The orientation pipeline is the expensive one
	# (queue_free + recreate root + reparent five children); skipping
	# when nothing flipped is the load-bearing perf fix.
	var main: Node = _instantiate_main()
	for _i in 100:
		DeviceLayout.layout_changed.emit()
	main._process(0.0)
	assert_eq(main.orientation_apply_count, 0,
		"100 emits with no orientation flip must NOT rebuild the composition root")


func test_two_flips_in_one_frame_collapse_to_one_rebuild() -> void:
	# Edge case: user rotates rapidly back and forth within one
	# frame. Final state matters more than transient values; we
	# expect ONE rebuild matching the FINAL orientation.
	var main: Node = _instantiate_main()
	DeviceLayout._test_set_orientation(true)
	DeviceLayout._test_set_orientation(false)
	DeviceLayout._test_set_orientation(true)
	main._process(0.0)
	assert_eq(main.orientation_apply_count, 1,
		"rapid back-and-forth flips in one frame must coalesce to one rebuild matching the final orientation")
	var orientation_root: Control = main.get("_orientation_root")
	assert_true(orientation_root is HBoxContainer,
		"final orientation root must be HBoxContainer (landscape)")

# endregion


# region — wall-clock budget

func test_burst_resize_completes_under_100ms() -> void:
	# Real-world worst case: desktop window drag, 60 emits across
	# many frames at 60 FPS. We approximate by emitting 60 then
	# draining; the total wall-clock must stay well under 100 ms
	# on a slow CI runner (typical local run is <5 ms). A budget
	# of 100 ms gives headroom for emulator variability.
	var main: Node = _instantiate_main()
	var t0_us: int = Time.get_ticks_usec()
	for _i in 60:
		DeviceLayout.layout_changed.emit()
	main._process(0.0)
	var elapsed_us: int = Time.get_ticks_usec() - t0_us
	var elapsed_ms: float = float(elapsed_us) / 1000.0
	assert_lt(elapsed_ms, 100.0,
		"60-emit burst + drain must complete under 100 ms (took %.2f ms)" % elapsed_ms)
	# Sanity: at least the safe area applied.
	assert_eq(main.safe_area_apply_count, 1)


func test_single_orientation_flip_completes_under_250ms() -> void:
	# The heavy path: rebuild composition root. In headless test
	# mode it routinely takes ~120 ms (no GPU acceleration, slower
	# tree mutation). A 250-ms budget catches genuine regressions
	# (the pre-coalesce burst-drain hit >2 s) while staying generous
	# for slow CI runners. On a real device the same operation
	# completes well under one frame at 60 FPS.
	var main: Node = _instantiate_main()
	var t0_us: int = Time.get_ticks_usec()
	DeviceLayout._test_set_orientation(true)
	main._process(0.0)
	var elapsed_us: int = Time.get_ticks_usec() - t0_us
	var elapsed_ms: float = float(elapsed_us) / 1000.0
	assert_lt(elapsed_ms, 250.0,
		"single orientation flip + drain must complete under 250 ms in headless mode (took %.2f ms)" % elapsed_ms)
	assert_eq(main.orientation_apply_count, 1)

# endregion


# region — initial paint isn't deferred

func test_initial_paint_applies_immediately() -> void:
	# _build_ui calls _apply_safe_area_margins() + _apply_orientation_layout()
	# directly (NOT through the dirty flag path) so the first frame
	# isn't blank. Without resetting counters, both should be at 1.
	var main: Node = _MAIN_SCENE.instantiate()
	add_child_autofree(main)
	# Don't reset_layout_apply_counters — measure the initial state.
	assert_eq(main.safe_area_apply_count, 1,
		"_build_ui must apply safe area immediately (no deferred drain)")
	assert_eq(main.orientation_apply_count, 1,
		"_build_ui must apply orientation layout immediately")

# endregion
