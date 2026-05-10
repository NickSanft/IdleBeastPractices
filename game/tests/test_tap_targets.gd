## v0.14.5 (Phase 13d) — touch-target sweep regression tests.
##
## Walks the scene tree of every primary view, finds tappable
## Controls (Buttons or anything with mouse_filter=STOP plus a
## handler), and asserts each is at least `UiScale.tap_target()` dp
## tall. Pinning this catches future regressions where a developer
## adds a 30-dp Button and forgets the floor.
##
## "Tappable" definition for the test:
##   - Any Button whose `disabled` is false. (Disabled buttons aren't
##     interactive anyway.)
##   - Any Control whose `mouse_filter == STOP` AND has a connected
##     `gui_input` listener (i.e., custom tap handlers).
##
## Carve-outs (small Controls inside larger tappable parents that
## ARE the actual touch surface):
##   - bestiary_card pills — Labels, no mouse_filter, not tappable.
##   - quest_strip mini-bars — visual indicators only.
##
## We measure the live `size.y` after a frame so layout has settled.
extends GutTest

const _MAIN_SCENE := preload("res://game/scenes/main.tscn")


func _instantiate_main() -> Node:
	var main: Node = _MAIN_SCENE.instantiate()
	add_child_autofree(main)
	return main


func _walk_tappables(root: Node, out: Array[Control]) -> void:
	if root is Control:
		var ctrl: Control = root
		# Skip Controls that aren't currently visible in the tree —
		# typical case is dialog content (welcome-back, sell-all,
		# language picker) parented but with their popup hidden by
		# default. Those Buttons still count as "tappable" by raw API
		# but the user only encounters them via popup_centered, after
		# which the popup's own theme governs sizing.
		if not ctrl.is_visible_in_tree():
			return
		var tappable: bool = false
		if ctrl is Button and not (ctrl as Button).disabled:
			tappable = true
		elif ctrl.mouse_filter == Control.MOUSE_FILTER_STOP and ctrl.gui_input.get_connections().size() > 0:
			tappable = true
		if tappable:
			out.append(ctrl)
	for child in root.get_children():
		_walk_tappables(child, out)


func test_every_tappable_meets_material_floor() -> void:
	var main: Node = _instantiate_main()
	# Wait a couple of frames so anchors / sizes settle. Without this
	# the live `size.y` reads as 0 for anchor-based Controls before
	# the first layout pass.
	await wait_frames(3)
	var floor_dp: int = UiScale.tap_target()
	# v0.14.8 — bumped from Material's bare 48 dp floor to 58 dp
	# (= 48 × BASE_SCALE) so the floor matches popular-Android-idle
	# norms (Egg Inc / Idle Heroes / AdVenture Capitalist).
	assert_eq(floor_dp, 58, "popular-Android-idle tap-target floor")

	var tappables: Array[Control] = []
	_walk_tappables(main, tappables)
	assert_gt(tappables.size(), 0, "expected to find at least some tappable Controls")

	var offenders: Array[String] = []
	for ctrl in tappables:
		if not is_instance_valid(ctrl):
			continue
		# Use the visible size or the custom_minimum_size, whichever
		# is greater — covers anchor-based layouts that haven't been
		# constrained by their parent yet.
		var effective_height: float = max(ctrl.size.y, ctrl.custom_minimum_size.y)
		if effective_height < float(floor_dp):
			offenders.append("  %s [%s]: %.0f dp tall" % [
				ctrl.name, ctrl.get_class(), effective_height,
			])

	assert_true(offenders.is_empty(),
		"Tappable Controls below %d dp:\n%s" % [floor_dp, "\n".join(offenders)])


func test_ui_scale_tap_target_returns_design_dp() -> void:
	# Density compensation lives in Window.content_scale_factor, NOT
	# in UiScale.tap_target. So tap_target should return a constant
	# design-dp value regardless of dpi_bucket. v0.14.8 bumped to 58
	# (= 48 × BASE_SCALE) so the floor matches popular-Android-idle
	# norms instead of Material's bare minimum.
	DeviceLayout._test_set_dpi_bucket(0.85)
	assert_eq(UiScale.tap_target(), 58)
	DeviceLayout._test_set_dpi_bucket(1.30)
	assert_eq(UiScale.tap_target(), 58)
	DeviceLayout._test_set_dpi_bucket(1.0)
