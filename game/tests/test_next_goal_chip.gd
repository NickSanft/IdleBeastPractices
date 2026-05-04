## Phase 11d — next_goal_chip surfaces tier completion progress.
##
## Verifies the chip's two text modes ("species left to find" before
## all species are seen, "X / N catches" after) and that catching a
## monster live updates the bar.
extends GutTest

const _SCENE := preload("res://game/scenes/ui/next_goal_chip.tscn")


func before_each() -> void:
	GameState.from_dict({})
	ContentRegistry.ensure_loaded()
	Settings.debug_fast_pets = false


func test_starts_with_species_left_message() -> void:
	# Fresh state — no monsters caught means every tier-1 species is
	# "left to find". Chip should report that count, not catch progress.
	var chip: PanelContainer = _SCENE.instantiate()
	add_child_autofree(chip)
	await wait_frames(2)
	assert_string_contains(chip._label.text, "species left to find",
			"chip should report missing-species count when none are seen")


func test_shows_catch_progress_after_seeing_each_species() -> void:
	# Catch one of each tier-1 species so missing list is empty —
	# chip should switch to catch progress mode.
	for m in ContentRegistry.monsters():
		if m.tier == 1:
			GameState.record_catch(m.id, false, "tap")
	var chip: PanelContainer = _SCENE.instantiate()
	add_child_autofree(chip)
	await wait_frames(2)
	assert_string_contains(chip._label.text, "/ 25 catches",
			"chip should switch to catch progress once every species is seen")


func test_progress_bar_advances_with_catches() -> void:
	# Catch many of one species — bar should track max_count / threshold.
	# Catch 1 of each first to clear the missing-species gate.
	for m in ContentRegistry.monsters():
		if m.tier == 1:
			GameState.record_catch(m.id, false, "tap")
	# Then 14 more of green_wisplet (so max_count = 15 of 25 = 0.6).
	for i in 14:
		GameState.record_catch(&"green_wisplet", false, "tap")
	var chip: PanelContainer = _SCENE.instantiate()
	add_child_autofree(chip)
	await wait_frames(2)
	assert_almost_eq(chip._bar.value, 15.0 / 25.0, 0.05,
			"bar should reflect max_count / threshold (15/25 ≈ 0.6)")


func test_bar_clamps_at_one() -> void:
	# Catch past the threshold — bar shouldn't overflow.
	for m in ContentRegistry.monsters():
		if m.tier == 1:
			for i in 30:
				GameState.record_catch(m.id, false, "tap")
	var chip: PanelContainer = _SCENE.instantiate()
	add_child_autofree(chip)
	await wait_frames(2)
	assert_almost_eq(chip._bar.value, 1.0, 0.001,
			"bar must cap at 1.0 even when max_count exceeds threshold")
