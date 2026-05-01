class_name MonsterResource
extends Resource

@export var id: StringName
@export var display_name: String
@export var tier: int = 1
@export var sprite: Texture2D
@export var shiny_sprite: Texture2D
@export var tint: Color = Color.WHITE
@export var spawn_weight: float = 1.0
@export var base_catch_difficulty: float = 1.0
@export var drop_item: ItemResource
@export var drop_amount_min: int = 1
@export var drop_amount_max: int = 1
@export var gold_base: int = 1
@export var shiny_rate: float = 0.05
@export var pet: PetResource
@export var flavor_text: String = ""
