class_name CraftingRecipeResource
extends Resource

@export var id: StringName
@export var display_name: String
@export var sprite: Texture2D
@export var description: String = ""
@export var inputs: Array[Dictionary] = []
@export var output_item: ItemResource
@export var output_net: NetResource
## Phase 12e: equipment recipes produce an EquipmentResource that
## auto-equips on the first eligible pet (any pet with an empty
## matching slot). Mutually exclusive with output_item / output_net.
@export var output_equipment: EquipmentResource
@export var output_amount: int = 1
@export var gold_cost: Dictionary = {"m": 0.0, "e": 0}
@export var prereq_recipe_ids: Array[StringName] = []
@export var tier_required: int = 1
@export var duration_seconds: float = 0.0
