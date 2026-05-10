## v0.14.7 (Phase 13g) — accessibility-label coverage tests.
##
## In Godot 4 a Control's `tooltip_text` doubles as the screen-reader
## label, so adding tooltips to top-level interactive surfaces gives
## TalkBack / VoiceOver users a name to announce alongside the emoji
## icons.
##
## These tests pin the labels we just added so a future maintainer
## who removes a tooltip (or strips the emoji-only text) fails by
## name.
##
## Also pins the Settings cleanup: the placeholder language picker
## was a single-entry OptionButton that printed to console on tap
## while a subtitle promised future locales — read as a dead control.
## Hidden in 13g until i18n actually ships; the test asserts it does
## NOT appear in the live settings tree.
extends GutTest

const _MAIN_SCENE := preload("res://game/scenes/main.tscn")
const _SETTINGS_VIEW := preload("res://game/scenes/ui/settings_view.tscn")
const _CURRENCY_BAR := preload("res://game/scenes/ui/currency_bar.tscn")


func _instantiate_main() -> Node:
	var main: Node = _MAIN_SCENE.instantiate()
	add_child_autofree(main)
	return main


# region — bottom-nav tooltips

func test_primary_nav_buttons_have_tooltip_text() -> void:
	var main: Node = _instantiate_main()
	await wait_frames(2)
	# main.gd stores the nav buttons in `_nav_buttons` (Dictionary
	# keyed by tab name).
	var nav_buttons: Dictionary = main.get("_nav_buttons")
	assert_not_null(nav_buttons)
	for tab_name in nav_buttons.keys():
		var btn: Button = nav_buttons[tab_name]
		assert_ne(btn.tooltip_text, "",
			"primary nav button %s must have a tooltip_text" % tab_name)


func test_more_button_has_tooltip_text() -> void:
	var main: Node = _instantiate_main()
	await wait_frames(2)
	var more_btn: Button = main.get("_more_button")
	assert_not_null(more_btn)
	assert_ne(more_btn.tooltip_text, "",
		"More button must have a tooltip_text for screen readers")

# endregion


# region — currency-bar chip tooltips

func test_every_currency_chip_has_tooltip_text() -> void:
	var bar = _CURRENCY_BAR.instantiate()
	add_child_autofree(bar)
	await wait_frames(2)
	# All three chips: gold, RP, prestige.
	var chips := [
		bar.get("_gold_chip"),
		bar.get("_rp_chip"),
		bar.get("_prestige_chip"),
	]
	for chip in chips:
		assert_not_null(chip)
		assert_ne(chip.tooltip_text, "",
			"every currency chip must expose a tooltip_text label")

# endregion


# region — Settings IA cleanup

func test_settings_view_omits_dead_language_picker() -> void:
	# 13g hid the placeholder language section. Walk the settings
	# tree for a Label with text "Language" — should not exist.
	var view = _SETTINGS_VIEW.instantiate()
	add_child_autofree(view)
	await wait_frames(2)
	var heading_count: int = _count_labels_with_text(view, "Language")
	assert_eq(heading_count, 0,
		"Language section was a dead placeholder and should be hidden until i18n ships")


func _count_labels_with_text(root: Node, target: String) -> int:
	var n: int = 0
	if root is Label and (root as Label).text == target:
		n += 1
	for child in root.get_children():
		n += _count_labels_with_text(child, target)
	return n

# endregion
