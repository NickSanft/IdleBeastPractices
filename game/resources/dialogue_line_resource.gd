class_name DialogueLineResource
extends Resource

@export var id: StringName
@export var trigger_id: StringName
@export_multiline var text: String = ""
@export var mood: StringName = &"smug"
@export var weight: float = 1.0
@export var max_uses: int = 0
@export var min_total_catches: int = 0
@export var min_prestige_count: int = 0
@export var conditions: Dictionary = {}
