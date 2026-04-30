class_name NetResource
extends Resource

@export var id: StringName
@export var display_name: String
@export var sprite: Texture2D
@export var description: String = ""
@export var tier_required: int = 1
@export var cost: Dictionary = {"m": 0.0, "e": 0}
@export var catches_per_second: float = 0.5
@export var catch_speed_multiplier: float = 1.0
@export var spawn_max: int = 3
@export var targets_tiers: Array[int] = [1]
@export var sfx_catch: AudioStream
