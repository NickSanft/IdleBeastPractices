## Scrollable list of items currently in GameState.inventory. Refreshes on
## item_gained / game_loaded events. Empty state shows a "no catches yet" hint.
extends PanelContainer

var _list: VBoxContainer
var _empty_label: Label


func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)

	_empty_label = Label.new()
	_empty_label.text = "Nothing caught yet."
	_empty_label.modulate = Color(0.7, 0.7, 0.7)
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_child(_empty_label)

	EventBus.item_gained.connect(_on_item_gained)
	EventBus.game_loaded.connect(_refresh)
	_refresh()


func _on_item_gained(_item_id: String, _amount: int) -> void:
	_refresh()


func _refresh() -> void:
	if not is_instance_valid(_list):
		return
	for child in _list.get_children():
		if child == _empty_label:
			continue
		child.queue_free()
	if GameState.inventory.is_empty():
		_empty_label.visible = true
		return
	_empty_label.visible = false
	for item_id_str in GameState.inventory.keys():
		var count: int = int(GameState.inventory[item_id_str])
		var item_res := ContentRegistry.item(StringName(item_id_str))
		var label_text: String
		if item_res != null:
			label_text = "%s × %d" % [item_res.display_name, count]
		else:
			label_text = "%s × %d" % [item_id_str, count]
		var row := Label.new()
		row.text = label_text
		row.add_theme_font_size_override("font_size", 18)
		_list.add_child(row)
