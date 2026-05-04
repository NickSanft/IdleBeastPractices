## Phase 12e — equippable item that boosts pet combat stats.
##
## Three slots per pet (HEAD / BODY / TRINKET) so equipping isn't a
## simple "best stat wins" decision. Stat modifiers are additive and
## stack across slots; multiplicative effects (ability cooldown
## reduction) are bounded so a fully-decked pet doesn't drop every
## ability to 0-tick spam.
##
## Equipment is acquired by crafting: each `EquipmentResource`
## references a `CraftingRecipeResource.output_equipment` (added to
## CraftingRecipeResource as part of this phase).
class_name EquipmentResource
extends Resource

enum Slot { HEAD, BODY, TRINKET }

@export var id: StringName
@export var display_name: String
@export var description: String = ""
@export var sprite: Texture2D
@export var slot: Slot = Slot.HEAD
@export var tier: int = 1

# Additive stat modifiers — applied when BattleSystem builds the
# combatant dict from the PetResource + equipped EquipmentResources.
@export var attack_add: float = 0.0
@export var defense_add: float = 0.0
@export var hp_add: float = 0.0
## Cooldown reduction in ticks. Caps at 4 ticks total across all
## slots so the math stays sensible at endgame.
@export var ability_cooldown_reduction: int = 0
