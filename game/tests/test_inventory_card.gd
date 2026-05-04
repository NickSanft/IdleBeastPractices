## Phase 12a — inventory_card binds an ItemResource + count, applies
## the rarity-tinted border via a per-card StyleBoxFlat override, and
## emits card_tapped / card_long_pressed.
extends GutTest

const _CARD := preload("res://game/scenes/ui/inventory_card.tscn")


func _new_item(rarity_value: int = 0) -> ItemResource:
	var item := ItemResource.new()
	item.id = &"test_item"
	item.display_name = "Test Item"
	item.rarity = rarity_value
	return item


func _new_card(item: ItemResource = null, count: int = 0) -> PanelContainer:
	var card: PanelContainer = _CARD.instantiate()
	add_child_autofree(card)
	if item != null:
		card.bind(item, count)
	return card


func test_bind_displays_name_and_count() -> void:
	var card := _new_card(_new_item(), 7)
	await wait_frames(1)
	assert_string_contains(card._name_label.text, "Test Item")
	assert_string_contains(card._count_label.text, "7")


func test_qmark_visible_when_no_sprite() -> void:
	# ItemResource without a sprite should fall through to the "?" glyph.
	var card := _new_card(_new_item(), 1)
	await wait_frames(1)
	assert_true(card._qmark.visible)
	assert_false(card._icon_rect.visible)


func test_rarity_applies_distinct_border_colors() -> void:
	# Common (0) should differ from epic (3) on the per-card stylebox
	# border. We can't easily assert the exact color, but we can
	# confirm the override exists and the colors aren't equal.
	var common_card := _new_card(_new_item(0), 1)
	await wait_frames(1)
	var epic_card := _new_card(_new_item(3), 1)
	await wait_frames(1)
	assert_true(common_card.has_theme_stylebox_override("panel"))
	assert_true(epic_card.has_theme_stylebox_override("panel"))
	var common_sb: StyleBoxFlat = common_card.get_theme_stylebox("panel")
	var epic_sb: StyleBoxFlat = epic_card.get_theme_stylebox("panel")
	assert_true(common_sb.border_color != epic_sb.border_color,
			"common and epic rarity must paint distinct border colors")


func test_short_press_emits_card_tapped() -> void:
	var card := _new_card(_new_item(), 1)
	await wait_frames(1)
	var captured: Array = []
	card.card_tapped.connect(func(id: StringName) -> void: captured.append(id))
	# Simulate press + release within long-press threshold.
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	card._gui_input(press)
	# Brief hold under 500 ms.
	await wait_frames(2)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	card._gui_input(release)
	assert_eq(captured.size(), 1)
	assert_eq(captured[0], &"test_item")


func test_long_hold_emits_card_long_pressed() -> void:
	var card := _new_card(_new_item(), 1)
	await wait_frames(1)
	var captured: Array = []
	card.card_long_pressed.connect(func(id: StringName) -> void: captured.append(id))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	card._gui_input(press)
	# Wait past the 500 ms threshold so the _process polling fires
	# the long-press signal mid-hold.
	await wait_seconds(0.6)
	assert_gte(captured.size(), 1, "long_pressed must fire after 500ms hold")
	assert_eq(captured[0], &"test_item")
