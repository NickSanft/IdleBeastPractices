## SFX/music dispatch. Phase 0 stub: subscribes to relevant signals and logs.
## Phase 5 fills in actual playback against AudioStreamPlayer pools.
extends Node


func _ready() -> void:
	EventBus.monster_caught.connect(_on_monster_caught)
	EventBus.first_shiny_caught.connect(_on_first_shiny_caught)
	EventBus.tier_completed.connect(_on_tier_completed)
	EventBus.upgrade_purchased.connect(_on_upgrade_purchased)


func _on_monster_caught(_monster_id: String, _instance_id: int, _is_shiny: bool, _source: String) -> void:
	pass  # TODO Phase 5: play catch SFX (different stream for shiny)


func _on_first_shiny_caught(_monster_id: String) -> void:
	pass  # TODO Phase 5: shiny sting


func _on_tier_completed(_tier: int) -> void:
	pass  # TODO Phase 5: tier-up jingle


func _on_upgrade_purchased(_upgrade_id: String) -> void:
	pass  # TODO Phase 5: purchase confirm SFX
