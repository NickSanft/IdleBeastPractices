## Modal shown at boot when a daily-login reward is granted. v0.15.14.
##
## The reward is applied to GameState by main._apply_daily_login BEFORE this
## dialog opens (the same pre-apply pattern WelcomeBackDialog uses), so a
## force-quit at the dialog never loses the reward — this dialog is purely an
## acknowledgment / summary. Caller invokes:
##   show_reward({cycle_day, streak, gold: BigNumber, rp, missed})
##
## v0.15.18 — "Collect 2× (watch ad)": the top-performing idle-genre daily
## placement. Mirrors WelcomeBackDialog's contract exactly: the base reward is
## already applied, so a granted ad emits `doubled(summary)` and the caller
## applies ANOTHER summary's worth of GOLD — total 2×. Gold only: the day-7
## RP milestone stays single (RP is the scarce prestige currency; an
## ad-doubled weekly RP drip would distort the prestige economy — deliberate).
extends AcceptDialog

signal doubled(summary: Dictionary)

const _CYCLE_LENGTH := DailyLoginSystem.CYCLE_LENGTH

var _body_label: RichTextLabel
var _pips: HBoxContainer
var _watch_ad_button: Button
var _summary: Dictionary = {}
var _ad_in_flight: bool = false


func _ready() -> void:
	title = "Daily Reward"
	get_ok_button().text = "Collect"
	min_size = Vector2(460, 300)
	# AcceptDialog is a Window subtype — Window subtrees don't inherit the
	# parent Control's theme, so assign the Dusk theme for the current palette
	# explicitly or it falls back to Godot's default styleboxes.
	theme = load("res://assets/themes/dusk/%s.tres" % Settings.theme_id)

	_watch_ad_button = add_button("Collect 2× (watch ad)", true, "watch_ad")
	custom_action.connect(_on_custom_action)
	AdsManager.rewarded_completed.connect(_on_rewarded_completed)
	AdsManager.rewarded_failed.connect(_on_rewarded_failed)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = true
	_body_label.fit_content = true
	_body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_body_label)

	# 7-day cycle strip — today highlighted, the day-7 jackpot starred.
	_pips = HBoxContainer.new()
	_pips.alignment = BoxContainer.ALIGNMENT_CENTER
	_pips.add_theme_constant_override("separation", 6)
	box.add_child(_pips)


func show_reward(summary: Dictionary) -> void:
	_summary = summary
	_ad_in_flight = false
	_body_label.text = _format_summary(summary)
	_rebuild_pips(int(summary.get("cycle_day", 1)))
	if _watch_ad_button != null:
		_watch_ad_button.disabled = not AdsManager.is_available()
	popup_centered()


func _on_custom_action(action: StringName) -> void:
	if String(action) != "watch_ad":
		return
	if _ad_in_flight:
		return
	_ad_in_flight = true
	if _watch_ad_button != null:
		_watch_ad_button.disabled = true
	AdsManager.show_rewarded(AdsManager.REWARD_DAILY_2X)


func _on_rewarded_completed(reward_id: String, granted: bool) -> void:
	if reward_id != AdsManager.REWARD_DAILY_2X:
		return
	_ad_in_flight = false
	if granted:
		# Base reward was pre-applied by main._apply_daily_login; emitting
		# the ORIGINAL summary makes the caller apply the gold AGAIN —
		# total 2× (the WelcomeBackDialog contract).
		EventBus.rewarded_video_completed.emit(reward_id, true)
		doubled.emit(_summary)
		hide()
	else:
		EventBus.rewarded_video_completed.emit(reward_id, false)
		# Canceled — keep the modal open; Collect still works.
		if _watch_ad_button != null:
			_watch_ad_button.disabled = false


func _on_rewarded_failed(reward_id: String, _reason: String) -> void:
	if reward_id != AdsManager.REWARD_DAILY_2X:
		return
	_ad_in_flight = false
	if _watch_ad_button != null:
		_watch_ad_button.disabled = false


func _format_summary(summary: Dictionary) -> String:
	var streak: int = int(summary.get("streak", 1))
	var gold: BigNumber = summary.get("gold", BigNumber.zero())
	var rp: int = int(summary.get("rp", 0))
	var missed: bool = bool(summary.get("missed", false))
	var day: int = int(summary.get("cycle_day", 1))
	var lines: Array[String] = []
	lines.append("[b]Day %d streak[/b] — welcome back!" % streak)
	if missed:
		lines.append("[color=#cc9966](streak restarted — don't miss a day!)[/color]")
	lines.append("")
	lines.append("Gold: [color=#ffdd66]+%s[/color]" % gold.format())
	if rp > 0:
		lines.append("Rancher Points: [color=#ffe4a0]+%d[/color]  [color=#cc9966](weekly bonus!)[/color]" % rp)
	if day < _CYCLE_LENGTH:
		lines.append("")
		lines.append("[color=#9d8fb5]Day %d brings a big bonus + Rancher Points.[/color]" % _CYCLE_LENGTH)
	return "\n".join(lines)


func _rebuild_pips(today: int) -> void:
	for c in _pips.get_children():
		c.queue_free()
	var palette: Dictionary = PaletteDusk.active()
	for day in range(1, _CYCLE_LENGTH + 1):
		var is_today: bool = day == today
		var is_past: bool = day < today
		var pip := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.set_content_margin_all(6)
		sb.set_border_width_all(1)
		if is_today:
			sb.bg_color = palette["gold"]
			sb.border_color = palette["gold"]
		elif is_past:
			sb.bg_color = palette["card_2"]
			sb.border_color = palette["border"]
		else:
			sb.bg_color = palette["card"]
			sb.border_color = palette["border"]
		pip.add_theme_stylebox_override("panel", sb)

		var lbl := Label.new()
		lbl.text = "★" if day == _CYCLE_LENGTH else str(day)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.custom_minimum_size = Vector2(28, 24)
		var ink: Color = palette["bg_deep"] if is_today else (palette["ink"] if is_past else palette["ink_dim"])
		lbl.add_theme_color_override("font_color", ink)
		pip.add_child(lbl)
		_pips.add_child(pip)
