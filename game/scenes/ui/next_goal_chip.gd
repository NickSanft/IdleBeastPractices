## Phase 11d — "Next Goal" indicator on the catching view.
##
## Surfaces the nearest meaningful progression goal so the player
## always knows what they're working toward. Currently shows current-
## tier completion progress: "Tier N: max_count / threshold caught".
## The threshold reads from catching_view's _TIER_DEBUG_THRESHOLD vs
## _TIER_COMPLETE_CATCH_THRESHOLD pair via the same Settings.debug_
## fast_pets check the awarding loop uses, so the chip and the actual
## unlock condition stay in sync.
##
## Anchored top-right of the catching view (just below currency_bar).
## Subscribes to EventBus.monster_caught and game_loaded; doesn't
## need its own _process loop.
extends PanelContainer

const _PALETTE := preload("res://game/resources/palette_colors.gd")
const _TIER_COMPLETE_CATCH_THRESHOLD := 25
const _TIER_DEBUG_THRESHOLD := 2

var _label: Label
var _bar: ProgressBar


func _ready() -> void:
	custom_minimum_size = Vector2(180, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", _PALETTE.SEPIA_DARK)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_label)

	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 6)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.value = 0.0
	_bar.max_value = 1.0
	_bar.step = 0.0
	vbox.add_child(_bar)

	EventBus.monster_caught.connect(_on_monster_caught)
	EventBus.tier_completed.connect(_on_tier_completed)
	EventBus.game_loaded.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if EventBus.monster_caught.is_connected(_on_monster_caught):
		EventBus.monster_caught.disconnect(_on_monster_caught)
	if EventBus.tier_completed.is_connected(_on_tier_completed):
		EventBus.tier_completed.disconnect(_on_tier_completed)
	if EventBus.game_loaded.is_connected(_refresh):
		EventBus.game_loaded.disconnect(_refresh)


func _on_monster_caught(_id: String, _ix: int, _is_shiny: bool, _src: String) -> void:
	_refresh()


func _on_tier_completed(_tier: int) -> void:
	_refresh()


func _refresh() -> void:
	var tier: int = int(GameState.current_max_tier)
	var threshold: int = _TIER_DEBUG_THRESHOLD if Settings.debug_fast_pets else _TIER_COMPLETE_CATCH_THRESHOLD
	var status: Dictionary = CatchingSystem.tier_completion_status(
			ContentRegistry.monsters(),
			GameState.monsters_caught,
			tier,
			threshold)
	var max_count: int = int(status.get("max_count", 0))
	var missing: Array = status.get("missing_species", [])
	# Cap displayed count at threshold so the bar never overflows
	# visually even when tier_completion_status caches a higher count.
	var displayed: int = min(max_count, threshold)
	_bar.value = float(displayed) / float(threshold)
	if missing.size() > 0:
		# Player still has un-seen species in this tier — surface the
		# count of remaining species rather than the catch progress.
		# "See" before "grind" is the natural ordering: completion
		# requires every species touched at least once.
		_label.text = "Tier %d: %d species left to find" % [tier, missing.size()]
	else:
		_label.text = "Tier %d: %d / %d catches" % [tier, displayed, threshold]
