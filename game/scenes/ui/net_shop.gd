## List of nets the player can buy. Each card shows name, description, cost,
## and a Buy / Equip button. Refreshes on currency change and game load.
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
	EventBus.game_loaded.connect(_refresh)
	_refresh()


func _on_currency_changed(_currency_id: String, _new_value: Variant) -> void:
	_refresh()


func _refresh() -> void:
	if not is_instance_valid(_list):
		return
	for child in _list.get_children():
		child.queue_free()
	for net_res in ContentRegistry.nets():
		_list.add_child(_build_net_card(net_res))


func _build_net_card(net_res: NetResource) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	var name_label := Label.new()
	name_label.text = net_res.display_name
	name_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = net_res.description
	desc_label.modulate = Color(0.85, 0.85, 0.85)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(desc_label)

	var hbox := HBoxContainer.new()
	vbox.add_child(hbox)

	var owned: bool = GameState.nets_owned.has(String(net_res.id))
	var equipped: bool = GameState.active_net == String(net_res.id)
	var cost := BigNumber.from_dict(net_res.cost)

	var cost_label := Label.new()
	cost_label.text = "Cost: %s g" % cost.format() if not owned else "Owned"
	cost_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(cost_label)

	var btn := Button.new()
	if equipped:
		btn.text = "Equipped"
		btn.disabled = true
	elif owned:
		btn.text = "Equip"
	else:
		btn.text = "Buy"
		btn.disabled = GameState.current_gold().lt(cost)
	btn.pressed.connect(func() -> void: _on_net_button_pressed(net_res))
	hbox.add_child(btn)

	return card


func _on_net_button_pressed(net_res: NetResource) -> void:
	if GameState.purchase_net(net_res):
		_refresh()
