## Phase 12b — colorblind_mode toggle adds shape redundancy on
## bestiary slot pills.
extends GutTest

const _CARD := preload("res://game/scenes/bestiary/bestiary_card.tscn")


func before_each() -> void:
	GameState.from_dict({})
	ContentRegistry.ensure_loaded()
	Settings.colorblind_mode = false


func _new_card_for(monster_id: StringName) -> PanelContainer:
	var monster: MonsterResource = ContentRegistry.monster(monster_id)
	var card: PanelContainer = _CARD.instantiate()
	add_child_autofree(card)
	card.set_monster(monster)
	return card


func test_setter_emits_signal() -> void:
	var fired: Array[bool] = [false]
	var handler := func() -> void: fired[0] = true
	Settings.accessibility_settings_changed.connect(handler)
	Settings.set_colorblind_mode(true)
	assert_true(fired[0])
	Settings.accessibility_settings_changed.disconnect(handler)


func test_no_shape_suffix_when_off() -> void:
	Settings.colorblind_mode = false
	GameState.record_catch(&"green_wisplet", false, "tap")
	var card := _new_card_for(&"green_wisplet")
	await wait_frames(2)
	# Iterate slot pill labels and verify none contain "✓" or "·".
	for child in card._slot_row.get_children():
		if child is Label:
			var text: String = child.text
			assert_false(text.contains("✓") or text.contains("·"),
					"colorblind off → no shape suffix on pills (got '%s')" % text)


func test_shape_suffix_when_on() -> void:
	Settings.colorblind_mode = true
	GameState.record_catch(&"green_wisplet", false, "tap")
	var card := _new_card_for(&"green_wisplet")
	await wait_frames(2)
	# At least one filled pill should carry a ✓ suffix; the others
	# carry · for unfilled.
	var saw_filled: bool = false
	var saw_unfilled: bool = false
	for child in card._slot_row.get_children():
		if child is Label:
			var text: String = child.text
			if text.ends_with("✓"):
				saw_filled = true
			elif text.ends_with("·"):
				saw_unfilled = true
	assert_true(saw_filled, "after a catch, at least one pill should be marked filled (✓)")
	assert_true(saw_unfilled, "other pills should be marked unfilled (·)")


func test_colorblind_mode_round_trips() -> void:
	Settings.set_colorblind_mode(true)
	# Forget in-memory.
	Settings.colorblind_mode = false
	Settings.load_from_disk()
	assert_true(Settings.colorblind_mode,
			"colorblind_mode must round-trip via settings.cfg")
