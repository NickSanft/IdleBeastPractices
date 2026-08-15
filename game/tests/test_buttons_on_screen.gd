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
	# Reset the accessibility font scale so the max-font overflow test
	# below doesn't leak its 1.5× into other tests' layout assertions.
	Settings.font_scale = 1.0


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


# region — cards never push their parent past the viewport
#
# v0.15.1.3 — user report: "Buttons are off the screen in Upgrades"
# and "Buttons are off the screen in Crafting". Root cause: card
# name_labels didn't autowrap, so a wide title (e.g., "CARVE
# AGITATOR CHARM") forced the card's min_width past its grid column,
# which forced the grid past viewport.x, which forced the
# orientation_root VBox past viewport.x, which dragged the bottom
# nav off-screen.
#
# These tests instantiate each affected view, drain layout, and
# assert that the view's own size.x doesn't exceed the viewport
# width — proving that no internal widget is forcing a layout spill.

func _view_fits_horizontally(view: Control, view_size: Vector2) -> bool:
	return view.size.x <= view_size.x + 1.0


func test_upgrade_tree_view_fits_in_viewport_width() -> void:
	var _main: Node = await _instantiate_main_and_drain()
	# Find the upgrades view in the tab tree.
	var tabs: TabContainer = _main.get("_tabs")
	var upgrade_view: Control = tabs.find_child("Upgrades", false, false) as Control
	assert_not_null(upgrade_view, "Upgrades tab must exist")
	# Switch tabs to force layout.
	for i in tabs.get_tab_count():
		if tabs.get_tab_title(i) == "Upgrades":
			tabs.current_tab = i
			break
	await wait_frames(3)
	var view_size: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	assert_true(_view_fits_horizontally(upgrade_view, view_size),
		"upgrade_tree view spilled past viewport: size.x=%.1f vs viewport.x=%.1f" % [
			upgrade_view.size.x, view_size.x,
		])


func test_crafting_view_fits_in_viewport_width() -> void:
	var _main: Node = await _instantiate_main_and_drain()
	var tabs: TabContainer = _main.get("_tabs")
	var crafting_view: Control = tabs.find_child("Crafting", false, false) as Control
	assert_not_null(crafting_view, "Crafting tab must exist")
	for i in tabs.get_tab_count():
		if tabs.get_tab_title(i) == "Crafting":
			tabs.current_tab = i
			break
	await wait_frames(3)
	var view_size: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	assert_true(_view_fits_horizontally(crafting_view, view_size),
		"crafting view spilled past viewport: size.x=%.1f vs viewport.x=%.1f" % [
			crafting_view.size.x, view_size.x,
		])


func test_orientation_root_fits_in_viewport_after_tab_switches() -> void:
	# The composite assertion: walk through every tab, drain, assert
	# orientation_root never exceeds viewport.x. Pre-fix, switching
	# to Upgrades or Crafting pushed orientation_root past viewport
	# and dragged the nav row sideways.
	var main: Node = await _instantiate_main_and_drain()
	var tabs: TabContainer = main.get("_tabs")
	var orientation_root: Control = main.get("_orientation_root")
	var view_size: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	var offenders: Array[String] = []
	for i in tabs.get_tab_count():
		var title: String = tabs.get_tab_title(i)
		tabs.current_tab = i
		await wait_frames(3)
		if orientation_root.size.x > view_size.x + 1.0:
			offenders.append("  tab '%s': orientation_root.size.x=%.1f > viewport.x=%.1f" % [
				title, orientation_root.size.x, view_size.x,
			])
	assert_true(offenders.is_empty(),
		"orientation_root spilled past viewport on these tabs:\n%s" % "\n".join(offenders))


## Walks the subtree and reports the Controls whose combined MINIMUM width
## exceeds the viewport — the minimum is what actually forces a parent wider,
## so it points at the cause rather than at every container that inherited the
## spill. Deepest-and-widest first, capped so the message survives a GitHub
## annotation's length limit.
func _widest_offenders(root: Control, limit_x: float) -> String:
	var found: Array = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control:
			var c: Control = n
			if c.is_visible_in_tree():
				var mn: float = c.get_combined_minimum_size().x
				if mn > limit_x + 1.0:
					# Class + any text: on a Label or Button that is usually
					# enough to identify the widget without a second round-trip.
					var txt: String = ""
					if c.has_method("get_text"):
						txt = String(c.call("get_text"))
					found.append({
						"path": String(root.get_path_to(c)), "min": mn, "size": c.size.x,
						"cls": c.get_class(), "txt": txt,
					})
		for child in n.get_children():
			stack.append(child)
	if found.is_empty():
		return "no single Control has an over-wide minimum — the spill is from layout/margins, not a widget"
	# Keep only the LEAF-most offenders. Every ancestor inherits the same
	# over-wide minimum, so ranking by width just names the chain from the root
	# down (`.` -> TabContainer -> Shop) and stops before the widget actually
	# responsible. Drop any offender that has an offending descendant.
	var leaves: Array = []
	for a in found:
		var pa: String = String(a["path"])
		var has_offending_child: bool = false
		for b in found:
			var pb: String = String(b["path"])
			if pb == pa:
				continue
			# get_path_to returns "." for the root itself, which is an ancestor
			# of everything else in the set.
			if pa == "." or pb.begins_with(pa + "/"):
				has_offending_child = true
				break
		if not has_offending_child:
			leaves.append(a)
	if leaves.is_empty():
		leaves = found
	leaves.sort_custom(func(a, b): return float(a["min"]) > float(b["min"]))
	var parts: Array[String] = []
	for i in mini(2, leaves.size()):
		parts.append("%s[%s] min=%.0f size=%.0f txt='%s'" % [
			leaves[i]["path"], leaves[i]["cls"], leaves[i]["min"], leaves[i]["size"],
			String(leaves[i]["txt"]).substr(0, 24),
		])
	return "deepest over-wide: " + "; ".join(parts)


func test_hud_fits_viewport_at_max_font_scale() -> void:
	# v0.15.13 — bumping the accessibility font slider now scales the
	# theme's baked text (was a no-op). Verify the larger HUD/nav still
	# fits the viewport at max scale so theme text growth never drags the
	# nav row off-screen (the v0.15.1.3 overflow-cascade bug class).
	Settings.font_scale = 1.5
	var main: Node = await _instantiate_main_and_drain()
	var tabs: TabContainer = main.get("_tabs")
	var orientation_root: Control = main.get("_orientation_root")
	var view_size: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	var offenders: Array[String] = []
	for i in tabs.get_tab_count():
		tabs.current_tab = i
		# Poll for the layout to settle rather than trusting a fixed frame
		# count — a theme rebuild at 1.5x plus size-flag resolution can take
		# more than three frames under load. Kept because it costs nothing,
		# but note it did NOT fix the CI failure below: the width settles at
		# 1308 and stays there, so the overflow is real, not a mid-layout
		# artifact.
		var width: float = 0.0
		for _attempt in 10:
			await wait_frames(3)
			width = orientation_root.size.x
			if width <= view_size.x + 1.0:
				break
		if width > view_size.x + 1.0:
			# Name the widget responsible. This overflow reproduces only on CI
			# (Linux/4.6.3 font metrics) and never locally on Windows/4.7.x, so
			# "which node is too wide" cannot be answered from a dev machine —
			# it has to travel back in the failure message.
			offenders.append("  tab '%s': orientation_root.size.x=%.1f > viewport.x=%.1f | %s" % [
				tabs.get_tab_title(i), width, view_size.x,
				_widest_offenders(orientation_root, view_size.x),
			])
	assert_true(offenders.is_empty(),
		"at font_scale 1.5 the HUD overflowed the viewport on:\n%s" % "\n".join(offenders))

# endregion


# region — background ColorRect uses Dusk, not parchment
#
# v0.15.1.3 — user report: "background color isn't correct in the
# Catch Screen". The Background ColorRect in main.tscn was painted
# parchment (#d6c79e), so any gap in the foreground content showed
# parchment underneath. Repainted to Dusk's bg_deep (#0c0820).

func test_main_background_color_is_dusk_bg_deep() -> void:
	var main: Node = await _instantiate_main_and_drain()
	# Find the Background ColorRect (direct child of Main per main.tscn).
	var bg: ColorRect = main.get_node_or_null("Background")
	assert_not_null(bg, "main.tscn must declare a Background ColorRect")
	# Dusk bg_deep == #0c0820 == Color(0.047, 0.031, 0.125, 1).
	# Explicit Color typing because Dictionary lookup returns Variant
	# and `.r` would otherwise be an unresolved property access.
	var expected: Color = PaletteDusk.amethyst()["bg_deep"]
	assert_almost_eq(bg.color.r, expected.r, 0.01,
		"Background.color.r drifted from Dusk bg_deep (parchment regression?)")
	assert_almost_eq(bg.color.g, expected.g, 0.01)
	assert_almost_eq(bg.color.b, expected.b, 0.01)

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
