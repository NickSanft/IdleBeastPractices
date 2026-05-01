## Phase 2: flat list of upgrades. The visual tree is Phase 5 polish.
##
## Each row shows: name, description, current level / max, cost-for-next,
## and a Buy button. Refreshes on currency / upgrade events.
extends PanelContainer

var _list: VBoxContainer


func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_list)

	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.upgrade_purchased.connect(_on_upgrade_changed)
	EventBus.game_loaded.connect(_refresh)
	_refresh()


func _on_currency_changed(_currency_id: String, _new_value: Variant) -> void:
	_refresh()


func _on_upgrade_changed(_id: String) -> void:
	_refresh()


func _refresh() -> void:
	if not is_instance_valid(_list):
		return
	for child in _list.get_children():
		child.queue_free()
	for u in ContentRegistry.upgrades():
		_list.add_child(_build_card(u))


func _build_card(u: UpgradeResource) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	var current_level: int = GameState.get_upgrade_level(u.id)

	var name_label := Label.new()
	name_label.text = "%s   [Lv %d / %d]" % [u.display_name, current_level, u.max_level]
	name_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = u.description
	desc_label.modulate = Color(0.85, 0.85, 0.85)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(desc_label)

	var hbox := HBoxContainer.new()
	vbox.add_child(hbox)

	var cost: BigNumber = UpgradeEffectsSystem.cost_for_next_level(u, current_level)
	var cost_label := Label.new()
	if current_level >= u.max_level:
		cost_label.text = "Maxed"
	else:
		var currency_str: String = "g" if u.cost_currency == UpgradeResource.Currency.GOLD else "RP"
		cost_label.text = "Next: %s %s" % [cost.format(), currency_str]
	cost_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(cost_label)

	var btn := Button.new()
	if current_level >= u.max_level:
		btn.text = "Maxed"
		btn.disabled = true
	else:
		btn.text = "Buy"
		btn.disabled = not _can_afford(u, cost)
	btn.pressed.connect(func() -> void: _on_buy_pressed(u))
	hbox.add_child(btn)

	return card


func _can_afford(u: UpgradeResource, cost: BigNumber) -> bool:
	if u.cost_currency == UpgradeResource.Currency.GOLD:
		return GameState.current_gold().gte(cost)
	return GameState.current_rancher_points() >= int(cost.to_float())


func _on_buy_pressed(u: UpgradeResource) -> void:
	GameState.try_purchase_upgrade(u)
