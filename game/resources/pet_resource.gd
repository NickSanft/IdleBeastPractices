class_name PetResource
extends Resource

@export var id: StringName
@export var display_name: String
@export var source_monster_id: StringName
@export var sprite: Texture2D
@export var variant_sprite: Texture2D
@export var variant_rate: float = 0.02
@export var base_attack: float = 10.0
@export var base_defense: float = 5.0
@export var base_hp: float = 50.0
@export var ability_id: StringName = &"strike"
