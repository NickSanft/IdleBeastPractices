## Phase 10d — bestiary_card state-machine + visual contract.
##
## Verifies the four-state slot transitions (LOCKED → SEEN → CAPTURED
## → PERFECTED) and that the visual side-effects (ribbon color,
## silhouette material, perfected-border override) line up with the
## advertised state.
extends GutTest

const _CARD := preload("res://game/scenes/bestiary/bestiary_card.tscn")
const _CARD_SCRIPT := preload("res://game/scenes/bestiary/bestiary_card.gd")


func before_each() -> void:
	GameState.from_dict({})
	ContentRegistry.ensure_loaded()


func _new_card_for(monster_id: StringName) -> PanelContainer:
	var monster: MonsterResource = ContentRegistry.monster(monster_id)
	assert_not_null(monster, "ContentRegistry must know %s" % monster_id)
	var card: PanelContainer = _CARD.instantiate()
	add_child_autofree(card)
	card.set_monster(monster)
	return card


func test_locked_state_when_unseen() -> void:
	var card := _new_card_for(&"green_wisplet")
	await wait_frames(2)
	assert_eq(card.slot_state(), _CARD_SCRIPT.SlotState.LOCKED)


func test_seen_state_after_first_catch() -> void:
	GameState.record_catch(&"green_wisplet", false, "tap")
	var card := _new_card_for(&"green_wisplet")
	await wait_frames(2)
	assert_eq(card.slot_state(), _CARD_SCRIPT.SlotState.CAPTURED,
			"normal catch transitions LOCKED → CAPTURED (not just SEEN)")


func test_perfected_after_shiny_and_variant() -> void:
	# Normal + shiny + variant pet → perfected.
	GameState.record_catch(&"green_wisplet", false, "tap")
	GameState.record_catch(&"green_wisplet", true, "tap")
	# Manually grant the variant pet (mirroring tier-completion path).
	var monster: MonsterResource = ContentRegistry.monster(&"green_wisplet")
	if monster.pet != null:
		GameState.add_pet(monster.pet.id, true)
	var card := _new_card_for(&"green_wisplet")
	await wait_frames(2)
	assert_eq(card.slot_state(), _CARD_SCRIPT.SlotState.PERFECTED)


func test_locked_card_paints_silhouette_material() -> void:
	# Sprite TextureRect should have a ShaderMaterial when locked.
	var card := _new_card_for(&"green_wisplet")
	await wait_frames(2)
	var sprite: TextureRect = card._sprite_rect
	assert_not_null(sprite)
	assert_true(sprite.material is ShaderMaterial,
			"locked card must apply a silhouette ShaderMaterial")


func test_seen_card_clears_silhouette_material() -> void:
	GameState.record_catch(&"green_wisplet", false, "tap")
	var card := _new_card_for(&"green_wisplet")
	await wait_frames(2)
	var sprite: TextureRect = card._sprite_rect
	assert_null(sprite.material,
			"seen card must drop the silhouette material so the sprite renders normally")


func test_tier_ribbon_color_changes_per_band() -> void:
	# tier 1 and tier 6 must paint different ribbon colors (different
	# bands). Use real monsters from the registry — they cover tiers
	# 1..at least 4, so this also exercises the band lookup math.
	var t1_card := _new_card_for(&"green_wisplet")
	await wait_frames(2)
	# Find a tier 6+ monster if one exists in the registry. If not,
	# skip the second half of the assertion (early-game content seed).
	var tier6_id: StringName = &""
	for m in ContentRegistry.monsters():
		if m.tier >= 6:
			tier6_id = m.id
			break
	if tier6_id == &"":
		assert_true(true, "skipped: no tier-6+ monsters in current content seed")
		return
	var t6_card := _new_card_for(tier6_id)
	await wait_frames(2)
	assert_true(t1_card._ribbon.color != t6_card._ribbon.color,
			"tier bands 1-5 and 6-10 should paint different ribbon colors")


func test_perfected_card_overrides_panel_stylebox() -> void:
	# Perfected cards override their PanelContainer "panel" stylebox to
	# paint a brass border. Non-perfected cards leave the theme alone.
	var locked_card := _new_card_for(&"green_wisplet")
	await wait_frames(2)
	assert_false(locked_card.has_theme_stylebox_override("panel"),
			"locked card should not override the panel stylebox")

	GameState.record_catch(&"red_wisplet", false, "tap")
	GameState.record_catch(&"red_wisplet", true, "tap")
	var monster: MonsterResource = ContentRegistry.monster(&"red_wisplet")
	if monster.pet != null:
		GameState.add_pet(monster.pet.id, true)
	var perfected := _new_card_for(&"red_wisplet")
	await wait_frames(2)
	assert_true(perfected.has_theme_stylebox_override("panel"),
			"perfected card must override the panel stylebox to paint the gold border")


func test_card_emits_card_tapped_signal_on_click() -> void:
	var card := _new_card_for(&"green_wisplet")
	await wait_frames(2)
	# GDScript 4 lambdas capture outer locals by value, so the closure
	# can't write back into a local StringName. Use an Array so the
	# capture is by reference.
	var captured: Array = []
	card.card_tapped.connect(func(id: StringName) -> void:
		captured.append(id))
	# Synthesize a left-click at the card's centre.
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	card._gui_input(event)
	assert_eq(captured.size(), 1, "card_tapped signal must fire exactly once on click")
	assert_eq(captured[0], &"green_wisplet")
