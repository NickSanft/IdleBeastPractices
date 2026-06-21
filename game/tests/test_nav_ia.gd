## v0.15.11 — Nav/IA changes: primary-nav reorder + Android Back handling.
##
## Covers:
##   - The research-driven primary order (Catch · Bestiary · Shop · Battle)
##     with Inventory + Upgrades demoted to the More sheet.
##   - Android hardware Back (NOTIFICATION_WM_GO_BACK_REQUEST) back-stack:
##     close an open More sheet → return to Catch from a secondary →
##     confirm exit on Catch. Plus quit_on_go_back disabled so the
##     SceneTree doesn't quit before our handler runs.
##   - The More button's active-state resync.
##
## Exercises Main's helpers directly (deterministic, no input sim).
extends GutTest

const _MAIN_SCENE := preload("res://game/scenes/main.tscn")

var _main: Node


func before_each() -> void:
	GameState.from_dict({})
	_main = _MAIN_SCENE.instantiate()
	add_child_autofree(_main)
	await wait_frames(2)


## On a fresh GameState (0 catches) the first-launch "tap a monster"
## coachmark is showing, and Back correctly dismisses IT first (a higher
## back-stack priority). Quiesce the overlays we DON'T want in a given
## test so the tab/exit branches are reachable deterministically. Called
## in the test body (after all _ready deferreds have settled — hiding in
## before_each races the deferred `_check_tap_first_monster`).
func _quiesce_overlays() -> void:
	# The first-launch Peniber intro (in the "peniber_intro" group) makes
	# Back a no-op, so clear it for tests targeting the lower branches.
	for n in get_tree().get_nodes_in_group("peniber_intro"):
		n.remove_from_group("peniber_intro")
		n.queue_free()
	if _main._coachmark != null:
		_main._coachmark.visible = false
	if _main._more_popup != null:
		_main._more_popup.visible = false
	if _main._celebration_overlay != null and _main._celebration_overlay.has_method("dismiss"):
		_main._celebration_overlay.dismiss()


# region — primary-nav reorder (item #1)

func test_primary_nav_matches_research_order() -> void:
	assert_eq(_main._PRIMARY_NAV, ["Catch", "Bestiary", "Shop", "Battle"],
			"primary nav must be Catch · Bestiary · Shop · Battle (the chosen research model)")


func test_bestiary_and_shop_are_primary_buttons() -> void:
	assert_true(_main._nav_buttons.has("Bestiary"),
			"Bestiary must be a primary bottom-nav button (promoted from More)")
	assert_true(_main._nav_buttons.has("Shop"),
			"Shop must be a primary bottom-nav button (promoted from More)")


func test_inventory_and_upgrades_demoted_to_more() -> void:
	assert_false(_main._nav_buttons.has("Inventory"),
			"Inventory must NOT be a primary button (demoted to More)")
	assert_false(_main._nav_buttons.has("Upgrades"),
			"Upgrades must NOT be a primary button (demoted to More)")
	assert_true(_main._SECONDARY_NAV.has("Inventory"))
	assert_true(_main._SECONDARY_NAV.has("Upgrades"))


func test_all_ten_tabs_still_covered_after_reorder() -> void:
	var all: Array[String] = []
	all.append_array(_main._PRIMARY_NAV)
	all.append_array(_main._SECONDARY_NAV)
	assert_eq(all.size(), _main._tabs.get_tab_count(),
			"PRIMARY + SECONDARY must still cover every TabContainer tab")
	for name in all:
		assert_ne(_main._find_tab_index(name), -1,
				"declared destination '%s' must map to a tab" % name)

# endregion


# region — Android Back handling (item #2)

func test_quit_on_go_back_is_disabled() -> void:
	# Without this, the SceneTree quits the app on Back before our
	# handler can run.
	assert_false(get_tree().quit_on_go_back,
			"Main._ready must disable quit_on_go_back so we own the Back button")


func test_back_from_secondary_returns_to_catch() -> void:
	_main._navigate_to_tab("Crafting")   # a secondary screen
	var catch_idx: int = _main._find_tab_index("Catch")
	assert_ne(_main._tabs.current_tab, catch_idx, "precondition: not on Catch")
	_quiesce_overlays()   # no FTUE coachmark up — test the tab branch
	_main._handle_go_back()
	assert_eq(_main._tabs.current_tab, catch_idx,
			"Back from a non-Catch tab must return to Catch")


func test_back_closes_more_sheet_first() -> void:
	# With the More sheet open, Back closes the sheet and does NOT also
	# navigate (one Back resolves exactly one level).
	_main._navigate_to_tab("Battle")   # a primary, non-Catch tab
	var battle_idx: int = _main._find_tab_index("Battle")
	_quiesce_overlays()   # clear the first-launch intro confound
	_main._build_more_popup()
	_main._more_popup.visible = true
	_main._handle_go_back()
	assert_false(_main._more_popup.visible,
			"Back must close the open More sheet first")
	assert_eq(_main._tabs.current_tab, battle_idx,
			"Back that closed the sheet must NOT also change tabs")


func test_back_on_catch_shows_exit_confirm_not_quit() -> void:
	_main._navigate_to_tab("Catch")
	_quiesce_overlays()   # no FTUE coachmark up — test the exit branch
	_main._handle_go_back()
	assert_not_null(_main._exit_confirm,
			"Back on Catch must build an exit-confirm dialog")
	assert_true(_main._exit_confirm.visible,
			"Back on Catch must show the exit-confirm dialog (never quit silently)")


func test_back_is_noop_during_peniber_intro() -> void:
	# The forced first-launch intro modal owns the screen: Back must do
	# nothing (not pop Exit, not navigate) while it's up.
	_main._navigate_to_tab("Catch")
	_quiesce_overlays()
	var stub := Node.new()
	_main.add_child(stub)
	stub.add_to_group("peniber_intro")
	_main._handle_go_back()
	assert_null(_main._exit_confirm,
			"Back during the first-launch intro must NOT pop the exit confirm")
	stub.remove_from_group("peniber_intro")
	stub.queue_free()


func test_back_dismisses_welcome_back_dialog() -> void:
	# Returning-player launch path: the welcome-back dialog is up on
	# Catch. Back must cancel it, not pop the exit confirm behind it.
	_main._navigate_to_tab("Catch")
	_quiesce_overlays()
	var summary: Dictionary = {
		"seconds": 120.0,
		"gold_gained": BigNumber.zero(),
		"shinies_caught": 0,
		"items_gained": {},
	}
	_main._show_welcome_back(summary)
	await wait_frames(1)
	assert_true(_main._welcome_back_dialog.visible, "precondition: welcome-back dialog up")
	_main._handle_go_back()
	assert_false(_main._welcome_back_dialog.visible,
			"Back must dismiss the welcome-back dialog")
	assert_null(_main._exit_confirm,
			"Back on the welcome-back dialog must NOT pop the exit confirm")


func test_back_cancels_exit_confirm_instead_of_repopping() -> void:
	# Back while the exit-confirm dialog is open must cancel (hide) it —
	# Android "Back == cancel dialog" — not re-pop it.
	_main._navigate_to_tab("Catch")
	_quiesce_overlays()
	_main._show_exit_confirm()
	assert_true(_main._exit_confirm.visible, "precondition: exit confirm up")
	_main._handle_go_back()
	assert_false(_main._exit_confirm.visible,
			"Back on the exit-confirm dialog must cancel it, not re-pop")


func test_back_dismisses_coachmark_before_navigating() -> void:
	# A visible coachmark (with no higher modal up) is dismissed by Back,
	# which must NOT also change tabs (one level per press).
	_main._navigate_to_tab("Battle")
	var battle_idx: int = _main._find_tab_index("Battle")
	_quiesce_overlays()   # clear the intro confound, then re-show a coachmark
	# &"" step id so dismiss() just hides without mutating TutorialState.
	_main._coachmark.show_for(_main._nav_buttons["Catch"], "test hint", &"")
	assert_true(_main._coachmark.visible, "precondition: coachmark up")
	_main._handle_go_back()
	assert_false(_main._coachmark.visible, "Back must dismiss the coachmark first")
	assert_eq(_main._tabs.current_tab, battle_idx,
			"Back that dismissed the coachmark must NOT also change tabs")

# endregion


# region — More active-state resync (item #3)

func test_more_resync_clears_highlight_on_primary() -> void:
	_main._navigate_to_tab("Catch")
	# Simulate the toggle flipping on when the sheet is opened.
	_main._more_button.button_pressed = true
	_main._build_more_popup()
	_main._resync_more_active_state()
	assert_false(_main._more_button.button_pressed,
			"dismissing the sheet from a primary screen must clear the More highlight")


func test_more_resync_keeps_highlight_on_secondary() -> void:
	_main._navigate_to_tab("Ledger")   # secondary
	_main._build_more_popup()
	_main._resync_more_active_state()
	assert_true(_main._more_button.button_pressed,
			"dismissing the sheet while on a secondary screen must keep More lit")

# endregion
