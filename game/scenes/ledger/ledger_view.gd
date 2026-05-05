## Ledger tab: every state.ledger statistic with Peniber-editorialized labels.
##
## Refreshes on every catch / shiny / prestige / craft / save event so the
## visible numbers stay current. Emits on_ledger_opened to the Narrator the
## first time the tab is shown after a session start (handled by signal
## connection in _ready); subsequent opens fire the pool.
extends PanelContainer

var _list: VBoxContainer
var _has_emitted_open_this_session: bool = false


func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)

	visibility_changed.connect(_on_visibility_changed)
	EventBus.monster_caught.connect(_on_state_changed)
	EventBus.first_shiny_caught.connect(_on_first_shiny)
	EventBus.prestige_triggered.connect(_on_prestige)
	EventBus.item_crafted.connect(_on_crafted)
	EventBus.game_loaded.connect(_refresh)
	EventBus.game_saved.connect(_refresh)
	EventBus.achievement_unlocked.connect(_on_achievement_unlocked)
	_refresh()


func _on_visibility_changed() -> void:
	if not visible:
		return
	if not _has_emitted_open_this_session:
		_has_emitted_open_this_session = true
		Narrator.try_speak(&"on_ledger_opened")
	else:
		# Subsequent opens within the session — quieter cadence; still pool.
		Narrator.try_speak(&"on_ledger_opened")
	_refresh()


func _on_state_changed(_a: Variant = null, _b: Variant = null, _c: Variant = null, _d: Variant = null) -> void:
	if visible:
		_refresh()


func _on_first_shiny(_id: String) -> void:
	if visible:
		_refresh()


func _on_prestige(_rp: int, _count: int) -> void:
	if visible:
		_refresh()


func _on_crafted(_recipe_id: String, _output_id: String) -> void:
	if visible:
		_refresh()


func _on_achievement_unlocked(_id: String) -> void:
	if visible:
		_refresh()


func _refresh() -> void:
	if not is_instance_valid(_list):
		return
	for child in _list.get_children():
		child.queue_free()

	var heading := Label.new()
	heading.text = "Peniber's Ledger"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 24)
	_list.add_child(heading)

	var subtitle := Label.new()
	subtitle.text = "A faithful record. Mostly faithful."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.85, 0.85, 0.85)
	subtitle.add_theme_font_size_override("font_size", 14)
	_list.add_child(subtitle)

	_list.add_child(_spacer(8))

	var ledger: Dictionary = GameState.ledger
	# Pairs of (Peniber label, formatted value).
	var rows: Array[Array] = [
		["Specimens captured (in their entirety)", "%d" % int(ledger.get("total_catches", 0))],
		["Manual taps applied to wisplets", "%d" % int(ledger.get("total_taps", 0))],
		["Iridescent oddities encountered", "%d" % int(ledger.get("total_shinies", 0))],
		["Sessions endured", "%d" % int(ledger.get("session_count", 0))],
		["Seconds spent at the desk", "%d" % int(ledger.get("total_play_seconds", 0))],
		["Offline seconds the Synod credited", "%d" % int(ledger.get("total_offline_seconds_credited", 0))],
		["Prestiges performed", "%d" % int(ledger.get("prestige_count", 0))],
		["Quotes Peniber has indulged you with", "%d" % int(ledger.get("peniber_quotes_seen", 0))],
		["Pets in your menagerie", "%d" % GameState.pets_owned.size()],
		["Variant pets logged", "%d" % GameState.pet_variants_owned.size()],
		["Recipes ever crafted", "%d" % GameState.recipes_crafted.size()],
		["Highest tier reached", "%d" % GameState.current_max_tier],
		["Current gold balance", GameState.current_gold().format()],
		["Rancher Points held", "%d" % GameState.current_rancher_points()],
		["Gold earned this run", BigNumber.from_dict(GameState.total_gold_earned_this_run).format()],
	]
	for row in rows:
		_list.add_child(_build_row(row[0], row[1]))

	_list.add_child(_spacer(16))
	_build_achievements_section()


## Phase 12f — achievement grid: 4-column tiles, locked entries shown
## as silhouettes, unlocked ones display the sprite + name. Tooltip
## (Godot Tooltip API not exposed for Controls in this codebase yet)
## could surface the description; for now description sits below.
func _build_achievements_section() -> void:
	var defs := ContentRegistry.achievements()
	if defs.is_empty():
		return
	# Stable display order: locked first not-yet-by-tier? Simpler: tier asc,
	# then id asc. That keeps grid stable regardless of unlock-state churn.
	defs.sort_custom(func(a, b):
		if a.tier != b.tier:
			return a.tier < b.tier
		return String(a.id) < String(b.id))

	var summary: Dictionary = Achievements.progress_summary()
	var heading := Label.new()
	heading.text = "Achievements (%d / %d)" % [int(summary.get("unlocked", 0)), int(summary.get("total", 0))]
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 20)
	_list.add_child(heading)
	_list.add_child(_spacer(6))

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_list.add_child(grid)

	for ach in defs:
		grid.add_child(_build_achievement_tile(ach))


func _build_achievement_tile(ach: AchievementResource) -> Control:
	var unlocked: bool = GameState.achievements_unlocked.has(String(ach.id))
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 84)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Slightly dim locked tiles so the grid reads like a checklist at a glance.
	if not unlocked:
		card.modulate = Color(1.0, 1.0, 1.0, 0.45)

	var margins := MarginContainer.new()
	margins.add_theme_constant_override("margin_left", 6)
	margins.add_theme_constant_override("margin_right", 6)
	margins.add_theme_constant_override("margin_top", 6)
	margins.add_theme_constant_override("margin_bottom", 6)
	card.add_child(margins)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	margins.add_child(vbox)

	var name_label := Label.new()
	name_label.text = ach.display_name if unlocked else "?????"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.modulate = _tier_color(ach.tier)
	vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = ach.description if unlocked else "Locked"
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 10)
	desc_label.modulate = Color(0.85, 0.85, 0.85)
	vbox.add_child(desc_label)
	return card


func _tier_color(tier: int) -> Color:
	# Bronze / Silver / Gold tinting — reuses the parchment palette so
	# the tiles still look at home in the ledger.
	match tier:
		AchievementResource.Tier.BRONZE: return Color(0.78, 0.55, 0.33)
		AchievementResource.Tier.SILVER: return Color(0.85, 0.85, 0.92)
		AchievementResource.Tier.GOLD:   return Color(1.0, 0.92, 0.55)
	return Color.WHITE


func _build_row(label_text: String, value_text: String) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.clip_contents = true
	var margins := MarginContainer.new()
	margins.add_theme_constant_override("margin_left", 10)
	margins.add_theme_constant_override("margin_right", 10)
	margins.add_theme_constant_override("margin_top", 4)
	margins.add_theme_constant_override("margin_bottom", 4)
	card.add_child(margins)
	var hbox := HBoxContainer.new()
	margins.add_child(hbox)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	hbox.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 15)
	value.modulate = Color(1.0, 0.95, 0.6)
	hbox.add_child(value)
	return card


func _spacer(h: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s
