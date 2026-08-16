class_name PetResource
extends Resource

@export var id: StringName
@export var display_name: String
@export var source_monster_id: StringName
@export var sprite: Texture2D
@export var variant_sprite: Texture2D
## Phase 15a: pets for tiers 2-20 are recolors of the same two base
## sprites their source monsters use, so the tint carries the visual
## identity. Mirrors MonsterResource.tint; defaults to WHITE so the
## hand-authored tier-1 pets render exactly as before.
@export var tint: Color = Color.WHITE
@export var variant_rate: float = 0.02
@export var base_attack: float = 10.0
@export var base_defense: float = 5.0
@export var base_hp: float = 50.0
@export var ability_id: StringName = &"strike"
