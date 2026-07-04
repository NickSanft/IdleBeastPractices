## Modal popup shown on game start when offline progress was credited.
##
## Caller invokes show_summary(summary_dict) where summary matches
## OfflineProgressSystem.compute()'s return shape. The dialog renders
## the items / gold / shinies and two ways to collect:
##   - "Claim"        → fires `claimed(summary)` with the original numbers
##   - "Claim 2× (ad)" → triggers a rewarded video; on grant, fires
##                       `claimed(doubled_summary)` instead
extends AcceptDialog

signal claimed(summary: Dictionary)

var _summary: Dictionary
var _body_label: RichTextLabel
var _watch_ad_button: Button
var _extend_cap_button: Button
var _ad_in_flight: bool = false


func _ready() -> void:
	title = "Welcome back!"
	get_ok_button().text = "Claim"
	confirmed.connect(_on_confirmed)
	min_size = Vector2(440, 280)
	# AcceptDialog is a Window subtype — Window subtrees don't inherit
	# the parent Control's theme, so without this assignment the dialog
	# falls back to Godot's default styleboxes (visibly: white-on-parch
	# RichTextLabel + teal-green button focus that doesn't match the
	# rest of the parchment/brass UI).
	theme = preload("res://assets/themes/dusk/amethyst.tres")
	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = true
	_body_label.fit_content = true
	_body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_body_label)

	# Custom action button — added before the OK button so it appears
	# on the left. Drives the rewarded-video flow.
	_watch_ad_button = add_button("Claim 2× (watch ad)", true, "watch_ad")
	# v0.15.17 — capped-summary CTA: routes to the Upgrades tab where the
	# two Away-Time upgrades live. Hidden unless the summary was capped
	# (show_summary toggles it), so uncapped players see no extra chrome.
	_extend_cap_button = add_button("Extend Away Time", true, "extend_cap")
	_extend_cap_button.visible = false
	custom_action.connect(_on_custom_action)

	AdsManager.rewarded_completed.connect(_on_rewarded_completed)
	AdsManager.rewarded_failed.connect(_on_rewarded_failed)


func show_summary(summary: Dictionary) -> void:
	_summary = summary
	_ad_in_flight = false
	_body_label.text = _format_summary(summary)
	if _watch_ad_button != null:
		_watch_ad_button.disabled = not AdsManager.is_available()
	if _extend_cap_button != null:
		_extend_cap_button.visible = bool(summary.get("capped", false))
	popup_centered()


## "3d 4h" past a day, "9h 05m" past the hour mark, "37 minutes" under it —
## the welcome-back head reads as a sentence, so short trips keep the word
## form. Days matter because raw_seconds is unbounded (a forward-jumped
## clock can report years; "87600h" would read as a bug).
static func _format_duration(seconds: float) -> String:
	var total_minutes: int = int(seconds / 60.0)
	@warning_ignore("integer_division")
	var hours: int = total_minutes / 60
	var minutes: int = total_minutes % 60
	if hours >= 24:
		@warning_ignore("integer_division")
		var days: int = hours / 24
		return "%dd %dh" % [days, hours % 24]
	if hours > 0:
		return "%dh %02dm" % [hours, minutes]
	return "%d minute%s" % [total_minutes, "" if total_minutes == 1 else "s"]


func _format_summary(summary: Dictionary) -> String:
	var seconds: float = float(summary.get("seconds", 0))
	# raw_seconds is v0.15.17+; older summaries fall back to the credited
	# window so the copy degrades to the uncapped form gracefully.
	var raw_seconds: float = max(float(summary.get("raw_seconds", 0.0)), seconds)
	var head: String
	if bool(summary.get("capped", false)):
		# v0.15.17 — actionable cap copy: name both windows so the player
		# sees what the cap cost them, and point at the fix (the Extend
		# Away Time button show_summary reveals alongside this text).
		# The two-window sentence needs the windows to visibly DIFFER:
		# for raw in [cap, cap+60s) both format identically ("Away for
		# 1h 00m — earned for the first 1h 00m" reads as a bug), so a
		# barely-capped trip keeps the single-window sentence. The amber
		# note + Extend button still show — capped is capped.
		if raw_seconds - seconds >= 60.0:
			head = "[b]Away for %s — earned for the first %s.[/b]\n" % [
				_format_duration(raw_seconds), _format_duration(seconds),
			]
		else:
			head = "[b]Away for %s.[/b]\n" % _format_duration(seconds)
		head += "[color=#cc9966]Offline limit reached. Extend it with the Away-Time upgrades.[/color]"
	else:
		head = "[b]Away for %s.[/b]" % _format_duration(seconds)
	var gold: BigNumber = summary.get("gold_gained", BigNumber.zero())
	var shinies: int = int(summary.get("shinies_caught", 0))
	var lines: Array[String] = [head, ""]
	lines.append("Gold: [color=#ffdd66]+%s[/color]" % gold.format())
	if shinies > 0:
		lines.append("Shinies: [color=#ffe4a0]%d[/color]" % shinies)
	var items_gained: Dictionary = summary.get("items_gained", {})
	if not items_gained.is_empty():
		lines.append("")
		lines.append("[b]Items[/b]")
		for item_id_str in items_gained.keys():
			var count: int = int(items_gained[item_id_str])
			var item_res := ContentRegistry.item(StringName(item_id_str))
			var item_name: String = item_res.display_name if item_res != null else String(item_id_str)
			lines.append("  • %s × %d" % [item_name, count])
	return "\n".join(lines)


func _on_confirmed() -> void:
	# v0.11.4 (Phase 11e fix for F48): rewards are pre-applied by
	# main._apply_offline_progress before this dialog opens, so
	# tapping Claim no longer needs to re-emit. Just hide.
	# (The signal is preserved for the 2x ad path which DOES need
	# to add another summary's worth on top of the pre-applied base.)
	pass


func _on_custom_action(action: StringName) -> void:
	if String(action) == "extend_cap":
		# v0.15.17 — jump to the Upgrades tab (offline_cap upgrades).
		# tab_switch_requested is main's existing nav seam; the rewards
		# were pre-applied before this dialog opened, so closing here
		# loses nothing.
		EventBus.tab_switch_requested.emit("Upgrades")
		hide()
		return
	if String(action) != "watch_ad":
		return
	if _ad_in_flight:
		return
	_ad_in_flight = true
	if _watch_ad_button != null:
		_watch_ad_button.disabled = true
	AdsManager.show_rewarded(AdsManager.REWARD_OFFLINE_2X)


func _on_rewarded_completed(reward_id: String, granted: bool) -> void:
	if reward_id != AdsManager.REWARD_OFFLINE_2X:
		return
	_ad_in_flight = false
	if granted:
		# v0.11.4 (Phase 11e fix for F48): the base summary was already
		# applied by main._apply_offline_progress before this dialog
		# opened. To deliver "2x rewards", emit the ORIGINAL summary so
		# the claim handler applies it AGAIN — total then equals 2x.
		# (Pre-fix, this path emitted a doubled summary which, combined
		# with pre-application, would have produced 3x; pre-application
		# didn't exist before, so the doubled-emit was correct then.)
		EventBus.rewarded_video_completed.emit(reward_id, true)
		claimed.emit(_summary)
		hide()
	else:
		EventBus.rewarded_video_completed.emit(reward_id, false)
		# User canceled, but no ill effect — keep the dialog open so they
		# can still hit "Claim".
		if _watch_ad_button != null:
			_watch_ad_button.disabled = false


func _on_rewarded_failed(reward_id: String, _reason: String) -> void:
	if reward_id != AdsManager.REWARD_OFFLINE_2X:
		return
	_ad_in_flight = false
	if _watch_ad_button != null:
		_watch_ad_button.disabled = false
