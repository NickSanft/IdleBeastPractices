class_name ItemResource
extends Resource

enum Category { DROP, MATERIAL, CONSUMABLE }

@export var id: StringName
@export var display_name: String
@export var sprite: Texture2D
@export var description: String = ""
@export var category: Category = Category.DROP
@export var stack_max: int = 9_999_999
@export var sell_value: Dictionary = {"m": 0.0, "e": 0}
@export var flavor_text: String = ""
