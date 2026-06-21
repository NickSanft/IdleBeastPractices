## Tests for the v0.9.0 bottom-nav restructure.
##
## Loads the main scene, walks its node tree, and asserts:
##   - The TabContainer's tab bar is hidden (tabs_visible = false).
##   - Each of the 4 PRIMARY_NAV destinations has a corresponding
##     bottom-nav Button. Tapping each one switches the
##     TabContainer's current_tab to the right index.
##   - Only the active primary's button is `button_pressed = true`;
##     the others are unpressed.
##   - When navigating to a SECONDARY destination via the nav helper,
##     no primary button is pressed.
##
## We exercise `Main._navigate_to_tab(name)` directly rather than
## simulating button presses; the press-handler is a one-line
## delegate (`_on_nav_button_pressed` -> `_navigate_to_tab`) and
## driving the helper keeps the test deterministic without input
## simulation.
extends GutTest

const _MAIN_SCENE := preload("res://game/scenes/main.tscn")


var _main: Node


func before_each() -> void:
	# Reset GameState so the welcome-back dialog (which the main
	# scene pops on a save with offline progress) doesn't dirty the
	# tree mid-test.
	GameState.from_dict({})
	_main = _MAIN_SCENE.instantiate()
	add_child_autofree(_main)
	# Wait two frames so _ready -> _build_ui -> bottom_nav build all
	# complete before assertions run.
	await wait_frames(2)


func test_tab_bar_is_hidden() -> void:
	assert_false(_main._tabs.tabs_visible,
			"v0.9.0: TabContainer's built-in tab bar must be hidden — nav lives in bottom_nav now.")


func test_each_primary_nav_destination_has_a_button() -> void:
	for tab_name in _main._PRIMARY_NAV:
		assert_true(_main._nav_buttons.has(tab_name),
				"primary nav destination %s should have a bottom-nav button" % tab_name)


func test_more_button_exists_alongside_primaries() -> void:
	assert_not_null(_main._more_button)
	# v0.9.1: button label is now "<icon>  More" (emoji + double space).
	# Don't assert the exact glyph (depends on system font); just that
	# the destination name is present.
	assert_true(
			_main._more_button.text.contains("More"),
			"More button label should contain the word 'More'; was: %s" % _main._more_button.text)


func test_navigate_switches_tab_container_current_tab() -> void:
	for tab_name in _main._PRIMARY_NAV:
		_main._navigate_to_tab(tab_name)
		var idx: int = _main._find_tab_index(tab_name)
		assert_ne(idx, -1, "tab named '%s' should exist in TabContainer" % tab_name)
		assert_eq(_main._tabs.current_tab, idx,
				"navigating to '%s' should set current_tab=%d" % [tab_name, idx])


func test_only_active_primary_button_is_pressed() -> void:
	_main._navigate_to_tab("Battle")
	for tab_name in _main._nav_buttons:
		var btn: Button = _main._nav_buttons[tab_name]
		var should_be_active: bool = (tab_name == "Battle")
		assert_eq(btn.button_pressed, should_be_active,
				"%s nav button.button_pressed should be %s while Battle is active" % [tab_name, should_be_active])


func test_secondary_destination_unpresses_all_primary_buttons() -> void:
	# Catch is the default selection (set by _build_bottom_nav).
	# Navigating to a SECONDARY tab via _navigate_to_tab should leave
	# no primary highlighted.
	_main._navigate_to_tab("Catch")
	assert_true(_main._nav_buttons["Catch"].button_pressed)

	_main._navigate_to_tab("Crafting")   # SECONDARY (v0.15.11: Bestiary is now primary)
	for tab_name in _main._nav_buttons:
		assert_false(_main._nav_buttons[tab_name].button_pressed,
				"%s should not be pressed while a secondary destination is active" % tab_name)
	# And the TabContainer should have switched to Crafting's index.
	var crafting_idx: int = _main._find_tab_index("Crafting")
	assert_eq(_main._tabs.current_tab, crafting_idx)


## v0.15.11 — the More button lights up while a secondary (More-sheet)
## screen is active, and goes dark on a primary screen, so the player
## always has a "you are here" cue.
func test_more_button_highlights_for_secondary_destination() -> void:
	_main._navigate_to_tab("Catch")   # primary
	assert_false(_main._more_button.button_pressed,
			"More must NOT be lit while a primary destination is active")
	_main._navigate_to_tab("Crafting")   # secondary
	assert_true(_main._more_button.button_pressed,
			"More must light up while a secondary (More-sheet) destination is active")
	_main._navigate_to_tab("Bestiary")   # back to a primary
	assert_false(_main._more_button.button_pressed,
			"More must go dark again when returning to a primary destination")


func test_all_ten_destinations_are_navigable() -> void:
	# Sanity: PRIMARY (4) + SECONDARY (6) covers every TabContainer
	# child. Catches anyone adding a new tab and forgetting to wire
	# it into the nav.
	var all_destinations: Array[String] = []
	all_destinations.append_array(_main._PRIMARY_NAV)
	all_destinations.append_array(_main._SECONDARY_NAV)
	assert_eq(all_destinations.size(), _main._tabs.get_tab_count(),
			"PRIMARY + SECONDARY should cover every TabContainer tab")
	# Each declared destination should resolve to a tab index.
	for name in all_destinations:
		assert_ne(_main._find_tab_index(name), -1,
				"declared nav destination '%s' should map to a TabContainer tab" % name)
