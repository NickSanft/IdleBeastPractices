extends GutTest


var item_a: ItemResource
var item_b: ItemResource
var output_item: ItemResource


func before_each() -> void:
	item_a = ItemResource.new()
	item_a.id = &"item_a"
	item_b = ItemResource.new()
	item_b.id = &"item_b"
	output_item = ItemResource.new()
	output_item.id = &"output_item"


func _make_recipe(
		id: StringName,
		inputs: Array[Dictionary],
		gold_cost: float = 0.0,
		tier_required: int = 1,
		prereq_ids: Array[StringName] = []) -> CraftingRecipeResource:
	var r := CraftingRecipeResource.new()
	r.id = id
	r.inputs = inputs
	r.gold_cost = BigNumber.from_float(gold_cost).to_dict()
	r.tier_required = tier_required
	r.prereq_recipe_ids = prereq_ids
	r.output_item = output_item
	r.output_amount = 1
	return r


func test_can_craft_happy_path():
	var recipe := _make_recipe(&"r1", ([{"item_id": &"item_a", "amount": 5}] as Array[Dictionary]))
	var inv: Dictionary = {"item_a": 10}
	var result := CraftingSystem.can_craft(recipe, inv, BigNumber.from_float(0.0), 1, [])
	assert_true(bool(result["can"]))
	assert_eq(String(result["reason"]), "ok")


func test_can_craft_fails_on_insufficient_input():
	var recipe := _make_recipe(&"r1", ([{"item_id": &"item_a", "amount": 5}] as Array[Dictionary]))
	var inv: Dictionary = {"item_a": 2}
	var result := CraftingSystem.can_craft(recipe, inv, BigNumber.from_float(0.0), 1, [])
	assert_false(bool(result["can"]))
	assert_eq(String(result["reason"]), "insufficient_input")


func test_can_craft_fails_on_tier_lock():
	var recipe := _make_recipe(&"r1", ([] as Array[Dictionary]), 0.0, 5)
	var result := CraftingSystem.can_craft(recipe, {}, BigNumber.from_float(0.0), 1, [])
	assert_false(bool(result["can"]))
	assert_eq(String(result["reason"]), "tier_locked")


func test_can_craft_fails_on_missing_prereq():
	var recipe := _make_recipe(&"r2", ([] as Array[Dictionary]), 0.0, 1, [&"r1"] as Array[StringName])
	var result := CraftingSystem.can_craft(recipe, {}, BigNumber.from_float(0.0), 1, [])
	assert_false(bool(result["can"]))
	assert_eq(String(result["reason"]), "missing_prereq")


func test_can_craft_passes_with_prereq_in_recipes_crafted():
	var recipe := _make_recipe(&"r2", ([] as Array[Dictionary]), 0.0, 1, [&"r1"] as Array[StringName])
	var result := CraftingSystem.can_craft(recipe, {}, BigNumber.from_float(0.0), 1, ["r1"])
	assert_true(bool(result["can"]))


func test_can_craft_fails_on_insufficient_gold():
	var recipe := _make_recipe(&"r1", [], 1000.0)
	var result := CraftingSystem.can_craft(recipe, {}, BigNumber.from_float(50.0), 1, [])
	assert_false(bool(result["can"]))
	assert_eq(String(result["reason"]), "insufficient_gold")


func test_can_craft_fails_on_no_output():
	var recipe := CraftingRecipeResource.new()
	recipe.id = &"empty_recipe"
	# No output_item or output_net.
	var result := CraftingSystem.can_craft(recipe, {}, BigNumber.from_float(0.0), 1, [])
	assert_false(bool(result["can"]))
	assert_eq(String(result["reason"]), "no_output")


func test_compute_deltas_extracts_inputs_and_gold():
	var recipe := _make_recipe(
			&"r1",
			([{"item_id": &"item_a", "amount": 3}, {"item_id": &"item_b", "amount": 7}] as Array[Dictionary]),
			500.0)
	var deltas := CraftingSystem.compute_deltas(recipe)
	assert_eq(deltas["items_to_consume"].size(), 2)
	assert_eq(String(deltas["items_to_consume"][0]["item_id"]), "item_a")
	assert_eq(int(deltas["items_to_consume"][0]["amount"]), 3)
	assert_almost_eq((deltas["gold_to_spend"] as BigNumber).to_float(), 500.0, 1.0e-6)
	assert_eq(String(deltas["output_item_id"]), "output_item")
	assert_eq(int(deltas["output_amount"]), 1)


# region — GameState.try_craft integration

func before_each_game_state() -> void:
	GameState.from_dict({})


func test_try_craft_consumes_inputs_and_produces_output():
	GameState.from_dict({})
	GameState.add_item(&"wisplet_ectoplasm", 100)
	GameState.add_gold(BigNumber.from_float(10000.0))
	var recipe := ContentRegistry.recipe(&"recipe_tier2_net")
	assert_not_null(recipe, "recipe_tier2_net should be registered")
	var result := GameState.try_craft(recipe)
	assert_true(bool(result["success"]))
	# Should have consumed 50 ectoplasm.
	assert_eq(int(GameState.inventory.get("wisplet_ectoplasm", 0)), 50)
	# Should have added the net to nets_owned.
	assert_true(GameState.nets_owned.has("tier2_net"))
	# Should record the recipe as crafted.
	assert_true(GameState.recipes_crafted.has("recipe_tier2_net"))


func test_try_craft_rejects_when_inputs_short():
	GameState.from_dict({})
	GameState.add_item(&"wisplet_ectoplasm", 5)
	GameState.add_gold(BigNumber.from_float(1.0e6))
	var recipe := ContentRegistry.recipe(&"recipe_tier2_net")
	var result := GameState.try_craft(recipe)
	assert_false(bool(result["success"]))
	assert_eq(String(result["reason"]), "insufficient_input")
	# State unchanged.
	assert_eq(int(GameState.inventory.get("wisplet_ectoplasm", 0)), 5)
	assert_false(GameState.nets_owned.has("tier2_net"))


func test_try_craft_persists_crafted_recipe_through_prestige():
	GameState.from_dict({})
	GameState.add_item(&"wisplet_ectoplasm", 100)
	GameState.add_gold(BigNumber.from_float(1.0e7))
	GameState.try_craft(ContentRegistry.recipe(&"recipe_tier2_net"))
	# Force enough gold to prestige meaningfully.
	GameState.add_gold(BigNumber.from_float(2.0e6))
	GameState.perform_prestige()
	# recipes_crafted survives prestige (unlocks-bestiary class of state).
	assert_true(GameState.recipes_crafted.has("recipe_tier2_net"))

# endregion
