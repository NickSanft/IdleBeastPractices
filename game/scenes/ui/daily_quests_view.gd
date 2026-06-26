## v0.15.15 — dedicated "Daily" view (More menu). Shows the day's daily quests
## with progress bars, a complete-all Rancher-Points bonus, and a countdown to
## the next local-midnight reset. Reads the DailyQuests autoload for state and
## repaints on its EventBus signals.
extends PanelContainer

var _countdown_label: Label
var _bonus_label: Label
var _list: VBoxContainer
var _rows: Dictionary = {}   # quest_id -> {name, bar, value}
var _countdown_accum: float = 1.0


func _ready() -> void:
	var margins := MarginContainer.new()
	margins.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margins.add_theme_constant_override(m, 12)
	add_child(margins)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margins.add_child(root)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Daily Quests"
	title.theme_type_variation = "DisplayHeading"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_countdown_label = Label.new()
	_countdown_label.theme_type_variation = "UiCaption"
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_countdown_label)
	root.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)

	_bonus_label = Label.new()
	_bonus_label.theme_type_variation = "BodyText"
	_bonus_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_bonus_label)

	EventBus.game_loaded.connect(_rebuild)
	EventBus.daily_quests_reset.connect(_rebuild)
	EventBus.daily_quest_progress_changed.connect(_on_progress)
	EventBus.daily_quest_completed.connect(_on_completed)
	EventBus.daily_quests_all_completed.connect(_on_all_completed)
	visibility_changed.connect(_on_visibility_changed)
	call_deferred("_rebuild")


func _process(delta: float) -> void:
	# Tick the reset countdown about once a second (only matters while visible).
	if not visible:
		return
	_countdown_accum += delta
	if _countdown_accum >= 1.0:
		_countdown_accum = 0.0
		_update_countdown()


func _on_visibility_changed() -> void:
	if visible:
		_rebuild()


func _rebuild() -> void:
	if not is_instance_valid(_list):
		return
	for c in _list.get_children():
		c.queue_free()
	_rows.clear()
	if GameState.daily_quests_active.is_empty():
		# Brief window before the DailyQuests autoload initializes today's set.
		var placeholder := Label.new()
		placeholder.text = "Daily quests are loading…"
		placeholder.theme_type_variation = "BodyText"
		placeholder.modulate = Color(0.7, 0.7, 0.7)
		_list.add_child(placeholder)
	for qid_v in GameState.daily_quests_active:
		var qid: String = String(qid_v)
		var row: Dictionary = _build_row(qid)
		if not row.is_empty():
			_rows[qid] = row
	_update_bonus()
	_update_countdown()


func _build_row(qid: String) -> Dictionary:
	var state: Dictionary = DailyQuests.quest_state(qid)
	var quest: QuestResource = state.get("quest")
	if quest == null:
		return {}
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	_list.add_child(box)

	var top := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = quest.display_name
	name_label.theme_type_variation = "BodyText"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	var value := Label.new()
	value.theme_type_variation = "UiCaption"
	top.add_child(value)
	box.add_child(top)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 14)
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	box.add_child(bar)

	var row := {"name": name_label, "bar": bar, "value": value}
	_apply_row(row, state)
	return row


func _apply_row(row: Dictionary, state: Dictionary) -> void:
	var done: bool = bool(state.get("done", false))
	row["bar"].value = float(state.get("progress", 0.0))
	var cur: int = int(state.get("current", 0))
	var tgt: int = int(state.get("target", 1))
	row["value"].text = "✓ Done" if done else "%d / %d" % [cur, tgt]
	row["name"].modulate = Color(0.55, 0.85, 0.55) if done else Color(1, 1, 1)


func _on_progress(qid: String, _current: int, _target: int) -> void:
	if _rows.has(qid):
		_apply_row(_rows[qid], DailyQuests.quest_state(qid))


func _on_completed(qid: String) -> void:
	if _rows.has(qid):
		_apply_row(_rows[qid], DailyQuests.quest_state(qid))
	_update_bonus()


func _on_all_completed(_bonus_rp: int) -> void:
	_update_bonus()


func _update_bonus() -> void:
	if not is_instance_valid(_bonus_label):
		return
	var rp: int = DailyQuestsSystem.complete_all_rp(GameState.current_max_tier)
	if GameState.daily_quests_bonus_claimed:
		_bonus_label.text = "✓ Complete-all bonus claimed: +%d RP" % rp
		_bonus_label.modulate = Color(0.55, 0.85, 0.55)
	else:
		_bonus_label.text = "Complete all daily quests for +%d Rancher Points." % rp
		_bonus_label.modulate = Color(0.92, 0.85, 0.55)


@warning_ignore("integer_division")
func _update_countdown() -> void:
	if not is_instance_valid(_countdown_label):
		return
	var secs: int = DailyQuestsSystem.seconds_until_reset(
			TimeManager.now_unix(), TimeManager.tz_bias_minutes())
	var h: int = secs / 3600
	var m: int = (secs % 3600) / 60
	_countdown_label.text = "Resets in %dh %02dm" % [h, m]
