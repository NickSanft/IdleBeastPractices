class_name ItemResource
extends Resource

enum Category { DROP, MATERIAL, CONSUMABLE }

## Phase 12a — visual rarity tier. Drives the inventory card's
## border tint via [PaletteColors]. Defaults to COMMON so existing
## items render without any .tres edits; per-item overrides land
## later as content is authored.
##   COMMON    — sepia/parchment border (the default)
##   UNCOMMON  — sage green
##   RARE      — dusk blue
##   EPIC      — blood ruby
enum Rarity { COMMON, UNCOMMON, RARE, EPIC }

@export var id: StringName
@export var display_name: String
@export var sprite: Texture2D
@export var description: String = ""
@export var category: Category = Category.DROP
@export var rarity: Rarity = Rarity.COMMON
@export var stack_max: int = 9_999_999
@export var sell_value: Dictionary = {"m": 0.0, "e": 0}
@export var flavor_text: String = ""
