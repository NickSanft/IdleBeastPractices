## Pure validation for crafting recipes.
##
## can_craft returns {can: bool, reason: String}. Reasons enumerated for UI:
##   "ok" / "tier_locked" / "missing_prereq" / "insufficient_input" /
##   "insufficient_gold" / "no_output"
##
## Side effects (deduct inputs/gold, add output, emit events) live in
## GameState.craft_recipe so the autoload remains the source of truth.
class_name CraftingSystem
extends RefCounted


static func can_craft(
		recipe: CraftingRecipeResource,
		inventory: Dictionary,
		gold: BigNumber,
		current_max_tier: int,
		recipes_crafted: Array) -> Dictionary:
	if recipe == null:
		return {"can": false, "reason": "no_output"}
	if recipe.output_item == null and recipe.output_net == null:
		return {"can": false, "reason": "no_output"}
	if int(recipe.tier_required) > int(current_max_tier):
		return {"can": false, "reason": "tier_locked"}
	for prereq in recipe.prereq_recipe_ids:
		if not recipes_crafted.has(String(prereq)):
			return {"can": false, "reason": "missing_prereq"}
	for entry in recipe.inputs:
		if not (entry is Dictionary):
			continue
		var item_id: String = String(entry.get("item_id", ""))
		var needed: int = int(entry.get("amount", 0))
		if item_id == "" or needed <= 0:
			continue
		var have: int = int(inventory.get(item_id, 0))
		if have < needed:
			return {"can": false, "reason": "insufficient_input"}
	var cost := BigNumber.from_dict(recipe.gold_cost)
	if not cost.is_zero() and gold.lt(cost):
		return {"can": false, "reason": "insufficient_gold"}
	return {"can": true, "reason": "ok"}


## Build the deltas the caller should apply on craft. Pure: doesn't mutate
## anything. Returns:
##   {
##     items_to_consume:  [{item_id, amount}, ...],
##     gold_to_spend:     BigNumber,
##     output_item_id:    StringName,    # empty if recipe outputs a net
##     output_amount:     int,
##     output_net_id:     StringName,    # empty if recipe outputs an item
##   }
##
## Caller is expected to have already passed can_craft.
static func compute_deltas(recipe: CraftingRecipeResource) -> Dictionary:
	var deltas: Dictionary = {
		"items_to_consume": [],
		"gold_to_spend": BigNumber.from_dict(recipe.gold_cost),
		"output_item_id": StringName(""),
		"output_amount": int(recipe.output_amount),
		"output_net_id": StringName(""),
	}
	for entry in recipe.inputs:
		if not (entry is Dictionary):
			continue
		deltas["items_to_consume"].append({
			"item_id": StringName(entry.get("item_id", "")),
			"amount": int(entry.get("amount", 0)),
		})
	if recipe.output_item != null:
		deltas["output_item_id"] = recipe.output_item.id
	if recipe.output_net != null:
		deltas["output_net_id"] = recipe.output_net.id
	return deltas
