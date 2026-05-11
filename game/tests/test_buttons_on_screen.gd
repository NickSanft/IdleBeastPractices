## v0.15.1.2 — visual-regression: every interactive Control is on-screen.
##
## User report: "many of the buttons are now off the screen" after the
## v0.15.1.x theme changes. The previous test_visual_regression.gd
## suite verified that the safe-margin had 0 insets and that
## orientation_root filled its parent — but it didn't check whether
## CHILDREN of those containers (nav buttons, settings checkboxes,
## crafting cards' craft/x5/Max buttons, etc.) actually had rects
## inside the viewport.
##
## This file walks the tree for every visible-in-tree Button after
## main is instantiated + layout drains, and asserts each one's rect
## sits inside the viewport. Adds named diagnostic prints so a
## regression points straight at the broken element.
extends GutTest

const _MAIN_SCENE := preload("res://game/scenes/main.tscn")


func before_each() -> void:
	# Other tests in the suite call DeviceLayout._test_set_safe_area
	# and don't always reset. Recompute from the live viewport here.
	DeviceLayout.recompute()


func _instantiate_main_and_drain() -> Node:
	var main: Node = _MAIN_SCENE.instantiate()
	add_child_autofree(main)
	# Drain layout. _process pumps the dirty flags; wait_frames lets
	# Godot's layout pass finish so size_flags + EXPAND_FILL settle.
	main._process(0.0)
	await wait_frames(3)
	return main


func _collect_visible_buttons(n: Node, out: Array[Button]) -> void:
	if n is Button:
		var b: Button = n
		if b.is_visible_in_tree():
			out.append(b)
	for c in n.get_children():
		_collect_visible_buttons(c, out)


# region — every visible Button has its rect inside the viewport

func test_every_visible_button_is_within_viewport() -> void:
	var main: Node = await _instantiate_main_and_drain()
	var view_size: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	var btns: Array[Button] = []
	_collect_visible_buttons(main, btns)
	assert_gt(btns.size(), 0, "expected to find some visible buttons after _ready")

	var offenders: Array[String] = []
	for b in btns:
		var rect := Rect2(b.global_position, b.size)
		var off_right: bool = rect.position.x + rect.size.x > view_size.x + 1.0
		var off_bottom: bool = rect.position.y + rect.size.y > view_size.y + 1.0
		var off_left: bool = rect.position.x < -1.0
		var off_top: bool = rect.position.y < -1.0
		if off_right or off_bottom or off_left or off_top:
			# Describe which edge spilled over so the failure points at the cause.
			var why: Array[String] = []
			if off_left: why.append("LEFT")
			if off_top: why.append("TOP")
			if off_right: why.append("RIGHT(viewport.x=%.0f, btn.right=%.0f)" % [view_size.x, rect.position.x + rect.size.x])
			if off_bottom: why.append("BOTTOM(viewport.y=%.0f, btn.bottom=%.0f)" % [view_size.y, rect.position.y + rect.size.y])
			offenders.append("  %s text='%s' rect=%s — off-screen at %s" % [
				b.get_path(), b.text, str(rect), ", ".join(why),
			])
	assert_true(offenders.is_empty(),
		"Some visible Buttons extend off-screen:\n%s" % "\n".join(offenders))


func test_nav_buttons_each_fit_their_horizontal_slot() -> void:
	# Bottom-nav row has 5 buttons in an HBoxContainer with all
	# SIZE_EXPAND_FILL. They share the viewport width. Each button's
	# rect must fit within viewport.x / 5 design dp plus tolerance —
	# otherwise text + emoji + content_margin overflowed the slot
	# (would push later buttons off the right).
	var main: Node = await _instantiate_main_and_drain()
	var view_size: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	var nav_buttons: Dictionary = main.get("_nav_buttons")
	assert_not_null(nav_buttons)
	# 4 primary + 1 More = 5
	var more_button: Button = main.get("_more_button")
	assert_not_null(more_button)
	var all_nav: Array[Button] = []
	for k in nav_buttons.keys():
		all_nav.append(nav_buttons[k])
	all_nav.append(more_button)
	# Sum of widths must equal (roughly) viewport.x.
	var total_width: float = 0.0
	for b in all_nav:
		total_width += b.size.x
		assert_gt(b.size.x, 0.0,
			"nav button '%s' has zero width — likely the SIZE_EXPAND_FILL slot collapsed" % b.text)
	# Tolerance: HBoxContainer separation + rounding (~10 px on a 5-button row).
	assert_almost_eq(total_width, view_size.x, 10.0,
		"sum of 5 nav-button widths (%.1f) should equal viewport width (%.1f); a mismatch means content didn't expand to fill" % [total_width, view_size.x])
	# Last button's right edge must not exceed viewport.x.
	var last_right: float = more_button.global_position.x + more_button.size.x
	assert_lte(last_right, view_size.x + 1.0,
		"the rightmost nav button extends %.1f px past viewport.x (=%.1f)" % [last_right, view_size.x])


# endregion


# region — Catch nav button is clickable and routes to the catching tab

func test_pressing_catch_nav_button_switches_to_catch_tab() -> void:
	# User report: "The catch button no longer seems to work." Most
	# likely they mean the Catch nav button — pressing it should
	# switch the (hidden) TabContainer's current_tab to 0.
	var main: Node = await _instantiate_main_and_drain()
	var tabs: TabContainer = main.get("_tabs")
	assert_not_null(tabs)
	# Force away from Catch first.
	tabs.current_tab = 1   # Battle
	assert_eq(tabs.current_tab, 1)
	# Find the Catch button.
	var nav_buttons: Dictionary = main.get("_nav_buttons")
	var catch_btn: Button = nav_buttons["Catch"]
	assert_not_null(catch_btn, "Catch nav button must exist")
	# Emit the pressed signal — same path as a real tap. This is the
	# integration the user reported broken; if some signal connection
	# got lost during the theme/re-parent shuffle, this fails by name.
	catch_btn.pressed.emit()
	await wait_frames(1)
	assert_eq(tabs.current_tab, 0,
		"pressing the Catch nav button must switch the TabContainer to tab index 0 (Catch)")

# endregion
