class_name UpgradeResource
extends Resource

enum Currency { GOLD, RANCHER_POINTS }

@export var id: StringName
@export var display_name: String
@export var sprite: Texture2D
@export var description: String = ""
@export var effect_id: StringName
@export var magnitude: float = 1.0
@export var cost: Dictionary = {"m": 0.0, "e": 0}
@export var cost_currency: Currency = Currency.GOLD
@export var cost_growth: float = 1.5
@export var max_level: int = 1
@export var prereq_ids: Array[StringName] = []
@export var tier_required: int = 1
@export var persists_through_prestige: bool = false
