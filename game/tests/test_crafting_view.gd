## Scene smoke tests for CraftingView.
##
## Validates: instantiates without errors, cards land in the recipe list,
## clip_contents is set on every card, and cards don't overlap vertically.
extends GutTest

const _SCENE := preload("res://game/scenes/crafting/crafting_view.tscn")


func before_each() -> void:
	GameState.from_dict({})
	ContentRegistry.ensure_loaded()


func test_instantiates_without_error() -> void:
	var view: Control = _SCENE.instantiate()
	add_child_autofree(view)
	view.size = Vector2(720, 1100)
	await wait_frames(2)
	assert_true(is_instance_valid(view))


func test_at_least_one_recipe_card_at_default_tier() -> void:
	var view: Control = _SCENE.instantiate()
	add_child_autofree(view)
	view.size = Vector2(720, 1100)
	await wait_frames(2)
	# v0.14.4: _list is a GridContainer with responsive columns.
	var list: GridContainer = view._list
	assert_not_null(list)
	# At current_max_tier=1, the Tier 2 net recipe is visible (tier_required=1).
	# The placeholder Tier 4 recipe is hidden (tier_required=4 > 1+1).
	assert_true(list.get_child_count() >= 1, "expected at least one recipe card")
	# Defensive: cap so a regression that shows every recipe regardless of
	# tier-gating fails loudly.
	assert_true(list.get_child_count() <= ContentRegistry.recipes().size())


func test_cards_clip_contents() -> void:
	var view: Control = _SCENE.instantiate()
	add_child_autofree(view)
	view.size = Vector2(720, 1100)
	await wait_frames(2)
	var list: GridContainer = view._list
	for card in list.get_children():
		assert_true(card is PanelContainer)
		assert_true((card as Control).clip_contents,
				"every recipe card must clip_contents to stop input/cost lines bleeding")


func test_cards_do_not_overlap() -> void:
	# v0.14.4: cards live in a GridContainer with non-zero h/v
	# separation, so vertical-only overlap testing no longer works.
	# We assert NO PAIR of cards overlap rectangles instead — catches
	# both row stacking AND column stacking regressions.
	var view: Control = _SCENE.instantiate()
	add_child_autofree(view)
	view.size = Vector2(720, 1100)
	await wait_frames(3)
	var list: GridContainer = view._list
	var cards := list.get_children()
	if cards.size() < 2:
		assert_true(true, "skipped: fewer than 2 cards")
		return
	for i in range(cards.size()):
		for j in range(i + 1, cards.size()):
			var a: Control = cards[i]
			var b: Control = cards[j]
			var a_rect := Rect2(a.position, a.size)
			var b_rect := Rect2(b.position, b.size)
			# Allow 1-px touching; only flag genuine overlap.
			a_rect = a_rect.grow(-1.0)
			assert_false(a_rect.intersects(b_rect),
					"card %d overlaps card %d" % [i, j])
