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


# region — initial layout

func test_default_safe_area_yields_zero_margins() -> void:
	# Set safe area to the full design viewport before instantiation
	# so _build_ui() picks it up on first pass.
	DeviceLayout._test_set_safe_area(Rect2(0, 0, 720, 1280))
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
	# Start from a clean default, then push a notched-phone profile.
	DeviceLayout._test_set_safe_area(Rect2(0, 0, 720, 1280))
	var main: Node = _instantiate_main()
	var margin: MarginContainer = _find_safe_margin(main)

	# Profile: 24-px status bar at top, 32-px gesture bar at bottom,
	# 0 horizontal insets — typical Android phone.
	DeviceLayout._test_set_safe_area(Rect2(0, 24, 720, 1224))

	assert_eq(margin.get_theme_constant("margin_top"), 24,
		"status bar should push content down by 24 px")
	assert_eq(margin.get_theme_constant("margin_bottom"), 32,
		"viewport_height (1280) - safe.bottom (24+1224) = 32 px gesture bar")


func test_landscape_notch_inset_propagates() -> void:
	DeviceLayout._test_set_safe_area(Rect2(0, 0, 720, 1280))
	var main: Node = _instantiate_main()
	var margin: MarginContainer = _find_safe_margin(main)

	# Landscape with a 80-px notch on the left.
	# The viewport is virtual 720x1280 (portrait design); the test
	# isn't actually rotating the viewport, just verifying that a
	# horizontal-inset safe area maps to margin_left correctly.
	DeviceLayout._test_set_safe_area(Rect2(80, 0, 640, 1280))

	assert_eq(margin.get_theme_constant("margin_left"), 80)
	assert_eq(margin.get_theme_constant("margin_right"), 0,
		"viewport (720) - safe.right (80+640) = 0")

# endregion
