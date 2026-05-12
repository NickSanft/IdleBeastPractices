## Prestige tab: shows projected RP, what's preserved, what's wiped, and a
## double-confirm Prestige button.
##
## v0.13.1 (Phase 12e) polish pass: themed PanelContainer card, brass-
## tinted heading, "vs your best" RP comparison via
## GameState.best_rp_at_prestige, BLOOD_RUBY tint on the destructive
## confirm to mirror the wipe-save UX pattern.
extends PanelContainer

const _PALETTE := preload("res://game/resources/palette_colors.gd")

var _projected_label: Label
var _best_label: Label
var _summary_label: RichTextLabel
var _prestige_button: Button
var _confirm_dialog: ConfirmationDialog

# v0.13.6 — visibility-gated refresh (currency_changed fires per caught tap).
var refresh_count: int = 0
var _dirty: bool = false


func _ready() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	add_child(vbox)

	var heading := Label.new()
	heading.text = "Prestige"
	heading.add_theme_font_size_override("font_size", UiScale.size(26))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(heading)

	_projected_label = Label.new()
	_projected_label.add_theme_font_size_override("font_size", UiScale.size(22))
	_projected_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_projected_label.add_theme_color_override("font_color", _PALETTE.BRASS_ACCENT)
	vbox.add_child(_projected_label)

	_best_label = Label.new()
	_best_label.add_theme_font_size_override("font_size", UiScale.size(14))
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_best_label.add_theme_color_override("font_color", _PALETTE.SEPIA_MID)
	vbox.add_child(_best_label)

	_summary_label = RichTextLabel.new()
	_summary_label.bbcode_enabled = true
	_summary_label.fit_content = true
	_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_summary_label)

	_prestige_button = Button.new()
	_prestige_button.text = "Prestige"
	_prestige_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# v0.13.1: ruby-tint the destructive button so it matches the
	# wipe-save pattern. The confirm dialog still gates the action.
	_prestige_button.add_theme_color_override("font_color", _PALETTE.BLOOD_RUBY)
	_prestige_button.add_theme_color_override("font_hover_color", _PALETTE.BLOOD_RUBY)
	_prestige_button.pressed.connect(_on_prestige_pressed)
	vbox.add_child(_prestige_button)

	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Confirm Prestige"
	_confirm_dialog.dialog_text = ""
	# v0.15.8 (popup-size fix): without an explicit `min_size`, the
	# dialog's RichTextLabel + autowrap loop can size the Window oddly
	# on first popup (esp. when the dialog_text contains [color=…]
	# bbcode spans that resist breaking). Locking min_size matches
	# the pattern welcome_back_dialog uses.
	_confirm_dialog.min_size = Vector2(420, 220)
	# Window subtypes don't inherit Control theme cascade — explicit
	# theme assignment per the v0.10.4 fix.
	_confirm_dialog.theme = preload("res://assets/themes/dusk/amethyst.tres")
	_confirm_dialog.confirmed.connect(_on_prestige_confirmed)
	add_child(_confirm_dialog)

	visibility_changed.connect(_on_visibility_changed)
	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.tier_completed.connect(_on_tier_changed)
	EventBus.tier_unlocked.connect(_on_tier_changed)
	EventBus.upgrade_purchased.connect(_on_upgrade_changed)
	EventBus.prestige_triggered.connect(_on_prestige_triggered)
	EventBus.game_loaded.connect(_mark_dirty_or_refresh)
	_refresh()


func _on_visibility_changed() -> void:
	if visible and _dirty:
		_dirty = false
		_refresh()


func _mark_dirty_or_refresh() -> void:
	if visible:
		_refresh()
	else:
		_dirty = true


func is_dirty() -> bool:
	return _dirty


func _on_currency_changed(_id: String, _v: Variant) -> void:
	_mark_dirty_or_refresh()


func _on_tier_changed(_t: int) -> void:
	_mark_dirty_or_refresh()


func _on_upgrade_changed(_id: String) -> void:
	_mark_dirty_or_refresh()


func _on_prestige_triggered(_rp: int, _count: int) -> void:
	_mark_dirty_or_refresh()


func _refresh() -> void:
	if not is_instance_valid(_projected_label):
		return
	refresh_count += 1
	var rp_gain: int = GameState.projected_rp_gain()
	_projected_label.text = "Projected: +%d RP" % rp_gain
	# Phase 12e: surface "vs your best" so the player has a reference
	# point. Hide the line on the very first run when no best exists.
	var best: int = int(GameState.best_rp_at_prestige)
	if best <= 0:
		_best_label.text = "First prestige run"
	elif rp_gain > best:
		_best_label.text = "New record! Previous best: %d RP" % best
	else:
		_best_label.text = "Your best run: %d RP" % best

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
