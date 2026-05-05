## Phase 12g — three-slot quest strip pinned above the bottom nav.
##
## One row per QuestTier (SHORT / MEDIUM / LONG); each row shows the
## active quest's display_name, a progress bar, current/target text,
## and a small reward chip (+N RP / +N gold). Empty slots collapse
## the row to "No active quest" rather than going invisible — the
## fixed three-row strip prevents content from jumping when a quest
## completes.
##
## Tappable detail (full description in a modal) is a 12g-followup.
## For now, the row text is informative enough for the loop.
extends PanelContainer

const _PALETTE := preload("res://game/resources/palette_colors.gd")
const _SLOT_HEIGHT := 28
const _ROW_TINTS := [
	Color(0.78, 0.55, 0.33),  # SHORT — bronze
	Color(0.85, 0.85, 0.92),  # MEDIUM — silver
	Color(1.0, 0.92, 0.55),   # LONG — gold
]

var _rows: Array[Dictionary] = []   # [{label, bar, value_label}]


func _ready() -> void:
	custom_minimum_size = Vector2(0, _SLOT_HEIGHT * 3 + 12)
	mouse_filter = Control.MOUSE_FILTER_PASS

	var margins := MarginContainer.new()
	margins.add_theme_constant_override("margin_left", 8)
	margins.add_theme_constant_override("margin_right", 8)
	margins.add_theme_constant_override("margin_top", 4)
	margins.add_theme_constant_override("margin_bottom", 4)
	add_child(margins)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	margins.add_child(vbox)

	for i in 3:
		_rows.append(_build_row(vbox, i))

	EventBus.quest_activated.connect(_on_quest_activated)
	EventBus.quest_completed.connect(_on_quest_completed)
	EventBus.quest_progress_changed.connect(_on_progress_changed)
	EventBus.game_loaded.connect(_refresh_all)
	# Defer initial paint until QuestLog has had a chance to fill slots.
	call_deferred("_refresh_all")


func _build_row(parent: VBoxContainer, slot: int) -> Dictionary:
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 6)
	parent.add_child(hbox)

	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 12)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.modulate = _ROW_TINTS[slot]
	label.text = _row_default_text(slot)
	hbox.add_child(label)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(96, 12)
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 0.0
	hbox.add_child(bar)

	var value_label := Label.new()
	value_label.add_theme_font_size_override("font_size", 11)
	value_label.custom_minimum_size = Vector2(60, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.modulate = Color(0.85, 0.85, 0.85)
	value_label.text = ""
	hbox.add_child(value_label)

	return {"label": label, "bar": bar, "value_label": value_label}


func _row_default_text(slot: int) -> String:
	match slot:
		QuestLog.SLOT_SHORT: return "Short: ..."
		QuestLog.SLOT_MEDIUM: return "Medium: ..."
		QuestLog.SLOT_LONG: return "Long: ..."
	return "..."


func _on_quest_activated(slot: int, _quest_id: String) -> void:
	_refresh_slot(slot)


func _on_quest_completed(_quest_id: String) -> void:
	# QuestLog refills + emits quest_activated for the new quest in
	# the same call frame, but emit-order between them isn't
	# guaranteed; refresh all three rows to be safe.
	_refresh_all()


func _on_progress_changed(slot: int, _current: int, _target: int) -> void:
	_refresh_slot(slot)


func _refresh_all() -> void:
	for slot in [QuestLog.SLOT_SHORT, QuestLog.SLOT_MEDIUM, QuestLog.SLOT_LONG]:
		_refresh_slot(slot)


func _refresh_slot(slot: int) -> void:
	if slot < 0 or slot >= _rows.size():
		return
	var row: Dictionary = _rows[slot]
	var label: Label = row["label"]
	var bar: ProgressBar = row["bar"]
	var value_label: Label = row["value_label"]
	var state: Dictionary = QuestLog.slot_state(slot)
	var quest: QuestResource = state.get("quest")
	if quest == null:
		label.text = _row_default_text(slot)
		bar.value = 0.0
		value_label.text = ""
		return
	label.text = "%s: %s" % [_slot_prefix(slot), quest.display_name]
	bar.value = float(state.get("progress", 0.0))
	var current: int = int(state.get("current", 0))
	var target: int = int(state.get("target", 1))
	value_label.text = "%d / %d" % [min(current, target), target]


func _slot_prefix(slot: int) -> String:
	match slot:
		QuestLog.SLOT_SHORT: return "Short"
		QuestLog.SLOT_MEDIUM: return "Medium"
		QuestLog.SLOT_LONG: return "Long"
	return "?"
