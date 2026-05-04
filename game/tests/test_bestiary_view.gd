## Scene smoke tests for BestiaryView.
##
## v0.10.3 (Phase 10d): the view now lays cards out in a GridContainer
## of `bestiary_card` instances rather than a VBoxContainer of inline
## panels, and unseen species use a silhouette `ShaderMaterial` rather
## than a "?" placeholder label. Tests updated accordingly.
##
## Validates: instantiates without errors, builds one card per registered
## monster, swaps the "??? — Tier X" placeholder for the species name on
## first catch, marks the count after a catch, keeps card contents
## clipped, and that no two cards visually overlap as Rect2 regions.
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
	var list: GridContainer = view._list
	assert_not_null(list, "_list GridContainer should be set after _ready")
	assert_eq(list.get_child_count(), ContentRegistry.monsters().size(),
			"one card per monster in the registry")


func test_unseen_species_show_placeholder_name() -> void:
	# Fresh state: no catches.
	var view: Control = _SCENE.instantiate()
	add_child_autofree(view)
	view.size = Vector2(720, 1100)
	await wait_frames(2)
	var labels := view.find_children("*", "Label", true, false)
	var saw_unknown_name: bool = false
	for label in labels:
		if String(label.text).begins_with("??? — Tier"):
			saw_unknown_name = true
			break
	assert_true(saw_unknown_name, "expected '??? — Tier X' name for unseen species")


func test_unseen_species_use_silhouette_shader() -> void:
	# Phase 10d: silhouettes for uncaught species apply a ShaderMaterial
	# to the sprite TextureRect. At least one card (any unseen species)
	# should have a TextureRect with a ShaderMaterial attached.
	var view: Control = _SCENE.instantiate()
	add_child_autofree(view)
	view.size = Vector2(720, 1100)
	await wait_frames(2)
	var rects := view.find_children("*", "TextureRect", true, false)
	var saw_silhouette: bool = false
	for tex in rects:
		if tex.material is ShaderMaterial:
			saw_silhouette = true
			break
	assert_true(saw_silhouette,
			"at least one card should apply a ShaderMaterial silhouette to its sprite")


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


func test_caught_count_displays_after_catch() -> void:
	# Catch a few of one species — the count line should reflect the count.
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
	# Regression for the v0.6.x bug: every card must clip overflow so a
	# runaway sprite or label can't bleed into the next card.
	var view: Control = _SCENE.instantiate()
	add_child_autofree(view)
	view.size = Vector2(720, 1100)
	await wait_frames(2)
	var list: GridContainer = view._list
	for card in list.get_children():
		assert_true(card is PanelContainer, "card root must be a PanelContainer")
		assert_true((card as Control).clip_contents,
				"each card must have clip_contents=true to prevent overflow")


func test_cards_do_not_overlap_as_rects() -> void:
	# Phase 10d: cards lay out in a GridContainer (2 cols at 720px width),
	# so the prior "next card y >= prev card y + h" invariant no longer
	# holds. Replace with a Rect2 pairwise intersection check that's
	# correct for any layout.
	var view: Control = _SCENE.instantiate()
	add_child_autofree(view)
	view.size = Vector2(720, 1100)
	await wait_frames(3)   # extra frame so the GridContainer settles
	var list: GridContainer = view._list
	var cards := list.get_children()
	if cards.size() < 2:
		assert_true(true, "skipped: fewer than 2 cards")
		return
	for i in range(cards.size()):
		var a: Control = cards[i]
		var rect_a := Rect2(a.position, a.size).grow(-1.0)
		for j in range(i + 1, cards.size()):
			var b: Control = cards[j]
			var rect_b := Rect2(b.position, b.size).grow(-1.0)
			assert_false(rect_a.intersects(rect_b),
					"cards %d and %d overlap: %s vs %s" % [i, j, rect_a, rect_b])
