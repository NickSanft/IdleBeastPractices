## Top-of-screen currency display. Subscribes to currency_changed and
## refreshes labels via BigNumber.format().
extends PanelContainer

var _gold_label: Label
var _rp_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(0, 48)
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	hbox.add_theme_constant_override("separation", 24)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(hbox)

	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 22)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.4))
	hbox.add_child(_gold_label)

	_rp_label = Label.new()
	_rp_label.add_theme_font_size_override("font_size", 22)
	_rp_label.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	_rp_label.visible = false
	hbox.add_child(_rp_label)

	EventBus.currency_changed.connect(_on_currency_changed)
	_refresh()


func _on_currency_changed(_currency_id: String, _new_value: Variant) -> void:
	_refresh()


func _refresh() -> void:
	if not is_instance_valid(_gold_label):
		return
	_gold_label.text = "Gold: %s" % GameState.current_gold().format()
	var rp: int = GameState.current_rancher_points()
	if rp > 0:
		_rp_label.text = "RP: %d" % rp
		_rp_label.visible = true
	else:
		_rp_label.visible = false
