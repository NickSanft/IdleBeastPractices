## Phase 12a — bulk crafting wraps `try_craft` in a count-bounded
## loop. Verifies Craft N consumes N × inputs, stops early when
## materials run out, and that _max_craftable returns the correct
## ceiling for the player's current materials + gold.
extends GutTest

const _SCENE := preload("res://game/scenes/crafting/crafting_view.tscn")


func before_each() -> void:
	GameState.from_dict({})
	ContentRegistry.ensure_loaded()


func _seed_for_tier2_net(target_count: int) -> void:
	# Ensure the player has enough materials + gold to craft the
	# requested number of tier_2_net recipes. Recipe needs 50
	# wisplet_ectoplasm + 5K gold per craft.
	GameState.inventory["wisplet_ectoplasm"] = 50 * target_count
	GameState.currencies["gold"] = BigNumber.from_float(5000.0 * target_count).to_dict()
	# Recipe gates on tier_required (1); set current_max_tier so the
	# can_craft check passes.
	GameState.current_max_tier = 1


func test_craft_5_consumes_5x_materials() -> void:
	_seed_for_tier2_net(5)
	var view: PanelContainer = _SCENE.instantiate()
	add_child_autofree(view)
	await wait_frames(2)
	var recipe: CraftingRecipeResource = ContentRegistry.recipe(&"recipe_tier2_net")
	view._on_craft_n_pressed(recipe, 5)
	# After 5 crafts: ectoplasm -> 0, gold -> 0.
	assert_eq(int(GameState.inventory.get("wisplet_ectoplasm", 0)), 0,
			"Craft 5 must consume 5 × the input requirement")
	# Recipes that produce nets append to nets_owned. tier2_net should
	# now be owned (owning is idempotent so the 5 crafts effectively
	# count as 1 add — the test just verifies materials drained).
	assert_true(GameState.nets_owned.has("tier2_net"))


func test_craft_n_stops_early_when_materials_run_out() -> void:
	# Seed enough for 3 crafts; ask for 5. Should consume 3 × inputs
	# and bail without erroring.
	_seed_for_tier2_net(3)
	var view: PanelContainer = _SCENE.instantiate()
	add_child_autofree(view)
	await wait_frames(2)
	var recipe: CraftingRecipeResource = ContentRegistry.recipe(&"recipe_tier2_net")
	view._on_craft_n_pressed(recipe, 5)
	assert_eq(int(GameState.inventory.get("wisplet_ectoplasm", 0)), 0,
			"loop should drain exactly the available materials, not error")


func test_max_craftable_caps_at_material_floor() -> void:
	# Materials for 3, gold for 7. Max should be min(3, 7) = 3.
	GameState.inventory["wisplet_ectoplasm"] = 50 * 3
	GameState.currencies["gold"] = BigNumber.from_float(5000.0 * 7).to_dict()
	GameState.current_max_tier = 1
	var view: PanelContainer = _SCENE.instantiate()
	add_child_autofree(view)
	await wait_frames(2)
	var recipe: CraftingRecipeResource = ContentRegistry.recipe(&"recipe_tier2_net")
	assert_eq(view._max_craftable(recipe), 3)


func test_max_craftable_caps_at_gold_floor() -> void:
	# Materials for 7, gold for 3. Max should be min(7, 3) = 3.
	GameState.inventory["wisplet_ectoplasm"] = 50 * 7
	GameState.currencies["gold"] = BigNumber.from_float(5000.0 * 3).to_dict()
	GameState.current_max_tier = 1
	var view: PanelContainer = _SCENE.instantiate()
	add_child_autofree(view)
	await wait_frames(2)
	var recipe: CraftingRecipeResource = ContentRegistry.recipe(&"recipe_tier2_net")
	assert_eq(view._max_craftable(recipe), 3)


func test_max_craftable_zero_when_either_floor_is_zero() -> void:
	# No materials at all.
	GameState.inventory["wisplet_ectoplasm"] = 0
	GameState.currencies["gold"] = BigNumber.from_float(50_000.0).to_dict()
	GameState.current_max_tier = 1
	var view: PanelContainer = _SCENE.instantiate()
	add_child_autofree(view)
	await wait_frames(2)
	var recipe: CraftingRecipeResource = ContentRegistry.recipe(&"recipe_tier2_net")
	assert_eq(view._max_craftable(recipe), 0)
