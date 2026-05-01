## Scene smoke tests for BestiaryView.
##
## Validates: instantiates without errors, builds one card per registered
## monster, swaps "??? — Tier X" for the species name on first catch, marks
## the Caught / Shiny / Variant slots based on GameState, and (the bug this
## suite was created for) keeps card contents within the card's own rect.
extends GutTest

const _SCENE := preload("res://game/scenes/bestiary/bestiary_view.tscn")


func before_each() -> void:
	GameState.from_dict({})
	ContentRegistry.ensure_loaded()


func test_instantiates_without_error() -> void:
	var view: Control = _SCENE.instantiate()
	add_child_autofree(view)
	# size matters for layout — give it room.
	view.size = Vector2(720, 1100)
	await wait_frames(2)
	assert_true(is_instance_valid(view))


func test_card_count_matches_monster_pool() -> void:
	var view: Control = _SCENE.instantiate()
	add_child_autofree(view)
	view.size = Vector2(720, 1100)
	await wait_frames(2)
	var list: VBoxContainer = view._list
	assert_not_null(list, "_list VBoxContainer should be set after _ready")
	assert_eq(list.get_child_count(), ContentRegistry.monsters().size(),
			"one card per monster in the registry")


func test_unseen_species_render_as_placeholder() -> void:
	# Fresh state: no catches.
	var view: Control = _SCENE.instantiate()
	add_child_autofree(view)
	view.size = Vector2(720, 1100)
	await wait_frames(2)
	var labels := view.find_children("*", "Label", true, false)
	var saw_qmark: bool = false
	var saw_unknown_name: bool = false
	for label in labels:
		var text: String = label.text
		if text == "?":
			saw_qmark = true
		if text.begins_with("??? — Tier"):
			saw_unknown_name = true
	assert_true(saw_qmark, "expected at least one '?' sprite placeholder for unseen species")
	assert_true(saw_unknown_name, "expected '??? — Tier X' name for unseen species")


func test_caught_species_show_display_name() -> void:
	GameState.record_catch(&"green_wisplet", false, "tap")
	var view: Control = _SCENE.instantiate()
	add_child_autofree(view)
	view.size = Vector2(720, 1100)
	await wait_frames(2)
	var labels := view.find_children("*", "Label", true, false)
	var saw_named: bool = false
	for label in labels:
		if String(label.text).begins_with("Green Wisplet"):
			saw_named = true
			break
	assert_true(saw_named, "expected 'Green Wisplet — Tier 1' header after first catch")


func test_caught_slot_marks_filled_after_catch() -> void:
	# Catch a few of one species — slots should reflect the count.
	for i in 3:
		GameState.record_catch(&"red_wisplet", false, "tap")
	var view: Control = _SCENE.instantiate()
	add_child_autofree(view)
	view.size = Vector2(720, 1100)
	await wait_frames(2)
	var labels := view.find_children("*", "Label", true, false)
	var saw_caught_count: bool = false
	for label in labels:
		if String(label.text) == "Caught × 3":
			saw_caught_count = true
			break
	assert_true(saw_caught_count, "expected 'Caught × 3' on the Red Wisplet card")


func test_cards_clip_contents_to_prevent_bleed() -> void:
	# Regression for the original bug: every card must clip overflow so a
	# runaway sprite or label can't bleed into the next card.
	var view: Control = _SCENE.instantiate()
	add_child_autofree(view)
	view.size = Vector2(720, 1100)
	await wait_frames(2)
	var list: VBoxContainer = view._list
	for card in list.get_children():
		assert_true(card is PanelContainer, "card root must be a PanelContainer")
		assert_true((card as Control).clip_contents,
				"each card must have clip_contents=true to prevent overflow")


func test_cards_do_not_overlap_vertically() -> void:
	# Each card's vertical extent should be strictly disjoint from its
	# neighbour. If the layout regresses (cards overlapping each other),
	# this trips immediately.
	var view: Control = _SCENE.instantiate()
	add_child_autofree(view)
	view.size = Vector2(720, 1100)
	await wait_frames(3)   # extra frame so the VBoxContainer settles
	var list: VBoxContainer = view._list
	var cards := list.get_children()
	if cards.size() < 2:
		assert_true(true, "skipped: fewer than 2 cards")
		return
	for i in range(cards.size() - 1):
		var a: Control = cards[i]
		var b: Control = cards[i + 1]
		# The next card's top must be >= the current card's bottom (within
		# the VBoxContainer's separation tolerance).
		assert_true(b.position.y >= a.position.y + a.size.y - 1,
				"card %d (y=%.1f h=%.1f) overlaps card %d (y=%.1f)" % [
					i, a.position.y, a.size.y, i + 1, b.position.y,
				])
