## Peniber. Listens to EventBus, picks dialogue lines, emits narrator_line_chosen.
##
## Phase 0 stub: connects to representative signals and emits a placeholder line.
## Phase 5 implements the full trigger taxonomy, weighted-random selection,
## and sliding-window anti-clustering.
extends Node


func _ready() -> void:
	EventBus.first_catch_of_species.connect(_on_first_catch_of_species)
	EventBus.first_shiny_caught.connect(_on_first_shiny_caught)
	EventBus.tier_completed.connect(_on_tier_completed)
	EventBus.prestige_triggered.connect(_on_prestige_triggered)
	EventBus.idle_too_long.connect(_on_idle_too_long)


func _on_first_catch_of_species(monster_id: String) -> void:
	_speak_placeholder("first_catch_" + monster_id, "smug")


func _on_first_shiny_caught(monster_id: String) -> void:
	_speak_placeholder("first_shiny_" + monster_id, "reverent")


func _on_tier_completed(tier: int) -> void:
	_speak_placeholder("tier_" + str(tier) + "_complete", "begrudging")


func _on_prestige_triggered(_rp_gained: int, prestige_count: int) -> void:
	_speak_placeholder("prestige_" + str(prestige_count), "weary")


func _on_idle_too_long(seconds: float) -> void:
	_speak_placeholder("idle_" + str(int(seconds)), "exasperated")


func _speak_placeholder(line_id: String, mood: String) -> void:
	EventBus.narrator_line_chosen.emit(line_id, "[Peniber says nothing yet]", mood)
