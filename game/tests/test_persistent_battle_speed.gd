## Phase 11e — battle speed persistence across sessions.
##
## The audit's F42 finding: BattleView reset to 1× every entry.
## Fixed by storing speed_index in Settings and reading on _ready.
extends GutTest

const _BATTLE_VIEW := preload("res://game/scenes/battle/battle_view.tscn")


func before_each() -> void:
	GameState.from_dict({})
	ContentRegistry.ensure_loaded()
	Settings.battle_speed_index = 0


func test_set_battle_speed_index_clamps() -> void:
	Settings.set_battle_speed_index(-5)
	assert_eq(Settings.battle_speed_index, 0)
	Settings.set_battle_speed_index(99)
	assert_eq(Settings.battle_speed_index, 2,
			"index clamps to the top of the _SPEED_OPTIONS range")


func test_set_battle_speed_idempotent_at_current_value() -> void:
	# Already 0 from before_each; setting 0 should not write to disk.
	# We can't easily intercept writes; just verify the setter is a
	# no-op early-return path.
	Settings.battle_speed_index = 1
	Settings.set_battle_speed_index(1)
	assert_eq(Settings.battle_speed_index, 1)


func test_battle_view_reads_persisted_speed() -> void:
	# Persist 4× (index 2). A fresh BattleView should boot with that
	# speed instead of the old hardcoded 1× default.
	Settings.battle_speed_index = 2
	var view: PanelContainer = _BATTLE_VIEW.instantiate()
	add_child_autofree(view)
	await wait_frames(2)
	assert_eq(view._speed_index, 2,
			"battle_view must initialize _speed_index from Settings.battle_speed_index")


func test_battle_view_writes_through_on_cycle() -> void:
	Settings.battle_speed_index = 0
	var view: PanelContainer = _BATTLE_VIEW.instantiate()
	add_child_autofree(view)
	await wait_frames(2)
	# Set state to BATTLING so _on_action_pressed routes to _cycle_speed.
	view._state = view._State.BATTLING
	view._cycle_speed()
	assert_eq(view._speed_index, 1)
	assert_eq(Settings.battle_speed_index, 1,
			"_cycle_speed must persist the new index via Settings.set_battle_speed_index")
	view._cycle_speed()
	assert_eq(Settings.battle_speed_index, 2)
	view._cycle_speed()
	assert_eq(Settings.battle_speed_index, 0,
			"_cycle_speed wraps from index 2 back to 0 — persistence must follow")


func test_battle_speed_round_trips_through_disk() -> void:
	Settings.set_battle_speed_index(2)
	# Forget in-memory.
	Settings.battle_speed_index = 0
	Settings.load_from_disk()
	assert_eq(Settings.battle_speed_index, 2,
			"battle_speed_index must round-trip through settings.cfg")
