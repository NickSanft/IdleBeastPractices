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
var _ad_in_flight: bool = false


func _ready() -> void:
	title = "Welcome back!"
	get_ok_button().text = "Claim"
	confirmed.connect(_on_confirmed)
	min_size = Vector2(440, 280)
	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = true
	_body_label.fit_content = true
	_body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_body_label)

	# Custom action button — added before the OK button so it appears
	# on the left. Drives the rewarded-video flow.
	_watch_ad_button = add_button("Claim 2× (watch ad)", true, "watch_ad")
	custom_action.connect(_on_custom_action)

	AdsManager.rewarded_completed.connect(_on_rewarded_completed)
	AdsManager.rewarded_failed.connect(_on_rewarded_failed)


func show_summary(summary: Dictionary) -> void:
	_summary = summary
	_ad_in_flight = false
	_body_label.text = _format_summary(summary)
	if _watch_ad_button != null:
		_watch_ad_button.disabled = not AdsManager.is_available()
	popup_centered()


func _format_summary(summary: Dictionary) -> String:
	var seconds: float = float(summary.get("seconds", 0))
	var minutes: int = int(seconds / 60.0)
	var head: String = "[b]Away for %d minute%s.[/b]" % [
		minutes, "" if minutes == 1 else "s",
	]
	if bool(summary.get("capped", false)):
		head += "  [color=#cc9966](capped at the offline limit)[/color]"
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
	# Claim with no ad: emit the base summary.
	claimed.emit(_summary)


func _on_custom_action(action: StringName) -> void:
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
		# Double the summary's monetary rewards before emitting.
		var doubled: Dictionary = _summary.duplicate(true)
		var gold: BigNumber = doubled.get("gold_gained", BigNumber.zero())
		doubled["gold_gained"] = gold.multiply_float(2.0)
		var items: Dictionary = doubled.get("items_gained", {})
		var doubled_items: Dictionary = {}
		for k in items.keys():
			doubled_items[k] = int(items[k]) * 2
		doubled["items_gained"] = doubled_items
		var catches: Dictionary = doubled.get("catches_by_species", {})
		var doubled_catches: Dictionary = {}
		for k in catches.keys():
			var entry: Dictionary = catches[k]
			doubled_catches[k] = {
				"normal": int(entry.get("normal", 0)) * 2,
				"shiny": int(entry.get("shiny", 0)) * 2,
			}
		doubled["catches_by_species"] = doubled_catches
		EventBus.rewarded_video_completed.emit(reward_id, true)
		claimed.emit(doubled)
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
