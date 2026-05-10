## v0.14.0 (Phase 13b) — main.gd safe-area MarginContainer tests.
##
## Asserts the contract: changing `DeviceLayout.safe_area` propagates
## into the root MarginContainer's four margin theme constants. This
## is what keeps the currency bar from sliding under the status bar
## and the bottom nav from drifting into the gesture-bar zone.
##
## Tests bypass the live `DisplayServer.window_get_safe_area` probe
## via `DeviceLayout._test_set_safe_area(...)`, so they're hardware-
## independent.
extends GutTest

const _MAIN_SCENE := preload("res://game/scenes/main.tscn")


func before_each() -> void:
	# Restore a "no special safe area" state so prior tests don't
	# leak custom rects into this suite.
	var rect := Rect2(Vector2.ZERO, Vector2(720, 1280))
	DeviceLayout._test_set_safe_area(rect)


func _instantiate_main() -> Node:
	# main.tscn boots the full game (loads save, builds tabs). We
	# need only the root layout to inspect the MarginContainer; tests
	# free the instance after to avoid polluting state.
	var main: Node = _MAIN_SCENE.instantiate()
	add_child_autofree(main)
	# main._ready ran during add_child; the MarginContainer is now built.
	return main


func _find_safe_margin(main: Node) -> MarginContainer:
	# Convention: main.gd stores the root margin in `_safe_margin`.
	if "_safe_margin" in main:
		return main.get("_safe_margin")
	# Fallback walk: first MarginContainer in main's children.
	for child in main.get_children():
		if child is MarginContainer:
			return child
	return null


## Helper — returns the live test viewport size. With v0.14.3's
## stretch_aspect="expand", the viewport adapts to the actual window
## (whatever the test harness allocates) instead of staying at the
## design 720×1280. Tests that compute expected margins must read
## the live size rather than hardcode design dimensions.
func _live_viewport() -> Vector2:
	return Vector2(get_viewport().get_visible_rect().size)


# region — initial layout

func test_default_safe_area_yields_zero_margins() -> void:
	# Stage safe area = full live viewport so all four margins should be 0.
	var view_size: Vector2 = _live_viewport()
	DeviceLayout._test_set_safe_area(Rect2(Vector2.ZERO, view_size))
	var main: Node = _instantiate_main()
	var margin: MarginContainer = _find_safe_margin(main)
	assert_not_null(margin, "main.gd must expose a root safe-area MarginContainer")
	assert_eq(margin.get_theme_constant("margin_top"), 0)
	assert_eq(margin.get_theme_constant("margin_bottom"), 0)
	assert_eq(margin.get_theme_constant("margin_left"), 0)
	assert_eq(margin.get_theme_constant("margin_right"), 0)

# endregion


# region — safe area reactivity

func test_safe_area_change_propagates_to_margins() -> void:
	var view_size: Vector2 = _live_viewport()
	DeviceLayout._test_set_safe_area(Rect2(Vector2.ZERO, view_size))
	var main: Node = _instantiate_main()
	var margin: MarginContainer = _find_safe_margin(main)

	# Profile: 24-px status bar at top, 32-px gesture bar at bottom,
	# 0 horizontal insets — typical Android phone. Build the safe
	# rect relative to the live viewport so the math doesn't assume
	# a specific design height.
	var status_bar: int = 24
	var gesture_bar: int = 32
	DeviceLayout._test_set_safe_area(Rect2(
			Vector2(0, float(status_bar)),
			Vector2(view_size.x, view_size.y - float(status_bar + gesture_bar))))
	# v0.15.1 — layout_changed coalesces through main._process.
	main._process(0.0)

	assert_eq(margin.get_theme_constant("margin_top"), status_bar,
		"status bar should push content down by %d px" % status_bar)
	assert_eq(margin.get_theme_constant("margin_bottom"), gesture_bar,
		"gesture bar inset = viewport.y - safe.y - safe.height")


func test_landscape_notch_inset_propagates() -> void:
	var view_size: Vector2 = _live_viewport()
	DeviceLayout._test_set_safe_area(Rect2(Vector2.ZERO, view_size))
	var main: Node = _instantiate_main()
	var margin: MarginContainer = _find_safe_margin(main)

	# Landscape with an 80-px notch on the left. We set the safe area
	# to start 80 px in and consume the rest of the live viewport
	# width, so margin_right should land at 0.
	var notch: int = 80
	DeviceLayout._test_set_safe_area(Rect2(
			Vector2(float(notch), 0),
			Vector2(view_size.x - float(notch), view_size.y)))
	main._process(0.0)

	assert_eq(margin.get_theme_constant("margin_left"), notch)
	assert_eq(margin.get_theme_constant("margin_right"), 0,
		"viewport.x - safe.x - safe.width should be 0")

# endregion
