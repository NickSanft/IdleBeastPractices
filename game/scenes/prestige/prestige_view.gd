## Prestige tab: shows projected RP, what's preserved, what's wiped, and a
## double-confirm Prestige button.
extends PanelContainer

var _projected_label: Label
var _summary_label: RichTextLabel
var _prestige_button: Button
var _confirm_dialog: ConfirmationDialog


func _ready() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	add_child(vbox)

	var heading := Label.new()
	heading.text = "Prestige"
	heading.add_theme_font_size_override("font_size", 26)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(heading)

	_projected_label = Label.new()
	_projected_label.add_theme_font_size_override("font_size", 22)
	_projected_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_projected_label.modulate = Color(1.0, 0.86, 0.4)
	vbox.add_child(_projected_label)

	_summary_label = RichTextLabel.new()
	_summary_label.bbcode_enabled = true
	_summary_label.fit_content = true
	_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_summary_label)

	_prestige_button = Button.new()
	_prestige_button.text = "Prestige"
	_prestige_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prestige_button.pressed.connect(_on_prestige_pressed)
	vbox.add_child(_prestige_button)

	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Confirm Prestige"
	_confirm_dialog.dialog_text = ""
	_confirm_dialog.confirmed.connect(_on_prestige_confirmed)
	add_child(_confirm_dialog)

	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.tier_completed.connect(_on_tier_changed)
	EventBus.tier_unlocked.connect(_on_tier_changed)
	EventBus.upgrade_purchased.connect(_on_upgrade_changed)
	EventBus.prestige_triggered.connect(_on_prestige_triggered)
	EventBus.game_loaded.connect(_refresh)
	_refresh()


func _on_currency_changed(_id: String, _v: Variant) -> void:
	_refresh()


func _on_tier_changed(_t: int) -> void:
	_refresh()


func _on_upgrade_changed(_id: String) -> void:
	_refresh()


func _on_prestige_triggered(_rp: int, _count: int) -> void:
	_refresh()


func _refresh() -> void:
	if not is_instance_valid(_projected_label):
		return
	var rp_gain: int = GameState.projected_rp_gain()
	_projected_label.text = "Projected: +%d RP" % rp_gain

	var earned: BigNumber = BigNumber.from_dict(GameState.total_gold_earned_this_run)
	var rp_balance: int = GameState.current_rancher_points()
	var lines: Array[String] = []
	lines.append("[b]Current run[/b]")
	lines.append("  Gold earned this run: [color=#ffdd66]%s[/color]" % earned.format())
	lines.append("  Highest tier: %d" % GameState.current_max_tier)
	lines.append("  Prestiges so far: %d" % GameState.prestige_count)
	lines.append("  Current RP balance: [color=#aac8ff]%d[/color]" % rp_balance)
	lines.append("")
	lines.append("[b]On Prestige[/b]")
	lines.append("  • All gold, items, current tier, and non-persistent upgrades are reset.")
	lines.append("  • Pets, bestiary, persistent (Prestige) upgrades, and ledger stats are kept.")
	lines.append("  • You earn [color=#ffdd66]+%d RP[/color] (formula: floor(√(gold/1M) × rp_mult)).")
	if GameState.get_upgrade_level(&"prestige_starting_net") >= 1:
		lines.append("  • Headstart equips the Basic Net immediately on the new run.")
	_summary_label.text = "\n".join(lines)

	_prestige_button.disabled = rp_gain <= 0
	if rp_gain <= 0:
		_prestige_button.text = "Earn 1M+ gold this run to prestige"
	else:
		_prestige_button.text = "Prestige (+%d RP)" % rp_gain


func _on_prestige_pressed() -> void:
	var rp_gain: int = GameState.projected_rp_gain()
	if rp_gain <= 0:
		return
	_confirm_dialog.dialog_text = "Reset this run for +%d RP?\n\nGold, items, current tier, and non-persistent upgrades will be cleared. Pets and Prestige upgrades stay." % rp_gain
	_confirm_dialog.popup_centered()


func _on_prestige_confirmed() -> void:
	GameState.perform_prestige()
