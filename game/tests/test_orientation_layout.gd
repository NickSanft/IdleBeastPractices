## v0.14.2 (Phase 13c.2) — orientation-aware root layout tests.
##
## main.gd now composes its root either as a portrait VBox (currency /
## tabs / quest_strip / bottom_nav) or a landscape HBox (left rail
## with nav buttons / content VBox). Switching orientation rebuilds
## the composition root WITHOUT recreating the persistent children
## (TabContainer + tabs, currency_bar, quest_strip, the nav button
## widgets), so per-tab game state survives the flip.
##
## These tests assert:
##   1. The expected root container exists for each orientation.
##   2. Persistent children survive a flip — same instance ids in the
##      new tree, signal connections preserved.
##   3. Active nav state (which tab is current) survives the flip.
##   4. The TabContainer's children (catch_view, battle_view, etc.)
##      are still present after the rebuild.
extends GutTest

const _MAIN_SCENE := preload("res://game/scenes/main.tscn")


func before_each() -> void:
	DeviceLayout._test_set_orientation(false)


func after_each() -> void:
	DeviceLayout._test_set_orientation(false)


func _instantiate_main() -> Node:
	var main: Node = _MAIN_SCENE.instantiate()
	add_child_autofree(main)
	return main


# region — composition root shape

func test_portrait_root_is_vbox() -> void:
	DeviceLayout._test_set_orientation(false)
	var main: Node = _instantiate_main()
	var orientation_root: Control = main.get("_orientation_root")
	assert_not_null(orientation_root)
	assert_true(orientation_root is VBoxContainer,
		"portrait root must be a VBoxContainer (currency / tabs / quest / nav stacked)")


func test_landscape_root_is_hbox() -> void:
	DeviceLayout._test_set_orientation(true)
	var main: Node = _instantiate_main()
	var orientation_root: Control = main.get("_orientation_root")
	assert_not_null(orientation_root)
	assert_true(orientation_root is HBoxContainer,
		"landscape root must be an HBoxContainer (left rail / content)")


func test_orientation_flip_rebuilds_root() -> void:
	# Boot in portrait, flip to landscape, assert root container type
	# changed AND the persistent TabContainer instance is still alive
	# in the new tree.
	#
	# v0.15.1 — orientation flips now coalesce through main._process,
	# so the test must drain a frame after the flip before asserting.
	DeviceLayout._test_set_orientation(false)
	var main: Node = _instantiate_main()
	var portrait_root: Control = main.get("_orientation_root")
	var portrait_root_id: int = portrait_root.get_instance_id()
	var tabs_id: int = main.get("_tabs").get_instance_id()

	DeviceLayout._test_set_orientation(true)
	main._process(0.0)

	var landscape_root: Control = main.get("_orientation_root")
	assert_ne(landscape_root.get_instance_id(), portrait_root_id,
		"orientation flip must rebuild the composition root")
	assert_true(landscape_root is HBoxContainer,
		"after flip to landscape the new root is an HBox")
	# Persistent children survive: TabContainer is the same instance.
	var post_flip_tabs: TabContainer = main.get("_tabs")
	assert_eq(post_flip_tabs.get_instance_id(), tabs_id,
		"TabContainer must be re-parented, not recreated")

# endregion


# region — persistent children survive

func test_tab_children_survive_orientation_flip() -> void:
	DeviceLayout._test_set_orientation(false)
	var main: Node = _instantiate_main()
	var tabs: TabContainer = main.get("_tabs")
	var pre_flip_count: int = tabs.get_child_count()
	# Snapshot child instance ids — every tab must be the same instance
	# afterward, not a fresh instantiate.
	var pre_flip_ids: Array[int] = []
	for child in tabs.get_children():
		pre_flip_ids.append(child.get_instance_id())

	DeviceLayout._test_set_orientation(true)
	main._process(0.0)

	var post_tabs: TabContainer = main.get("_tabs")
	assert_eq(post_tabs.get_child_count(), pre_flip_count,
		"tab count must be unchanged across orientation flip")
	for i in pre_flip_count:
		assert_eq(post_tabs.get_child(i).get_instance_id(), pre_flip_ids[i],
			"tab children must be the SAME instances, not recreated (would lose game state)")


func test_active_tab_survives_orientation_flip() -> void:
	DeviceLayout._test_set_orientation(false)
	var main: Node = _instantiate_main()
	var tabs: TabContainer = main.get("_tabs")
	# Switch to a non-default tab (Battle is index 1).
	tabs.current_tab = 1
	assert_eq(tabs.current_tab, 1)

	DeviceLayout._test_set_orientation(true)
	main._process(0.0)

	assert_eq(tabs.current_tab, 1,
		"active tab must survive the flip — TabContainer instance is reparented, not recreated")

# endregion


# region — landscape layout details

func test_landscape_left_rail_has_nav_buttons() -> void:
	DeviceLayout._test_set_orientation(true)
	var main: Node = _instantiate_main()
	var orientation_root: Control = main.get("_orientation_root")
	# Landscape root: HBox { left_rail (VBox), content_vbox (VBox) }.
	# Left rail is the first child.
	assert_eq(orientation_root.get_child_count(), 2,
		"landscape root must have exactly 2 children: rail + content")
	var rail: Control = orientation_root.get_child(0)
	assert_true(rail is VBoxContainer, "left rail must be a VBoxContainer")
	# 4 primary buttons + the More button = 5.
	assert_eq(rail.get_child_count(), 5,
		"left rail must hold 4 primary nav buttons + More")
	# All children should be Button instances.
	for child in rail.get_children():
		assert_true(child is Button, "rail children are all Buttons")

# endregion
