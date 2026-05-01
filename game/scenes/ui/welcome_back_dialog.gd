## Modal popup shown on game start when offline progress was credited.
##
## Caller invokes show_summary(summary_dict) where summary matches
## OfflineProgressSystem.compute()'s return shape. The dialog renders the
## items / gold / shinies and a Claim button that emits a signal so the
## caller can reapply the rewards to GameState.
extends AcceptDialog

signal claimed(summary: Dictionary)

var _summary: Dictionary
var _body_label: RichTextLabel


func _ready() -> void:
	title = "Welcome back!"
	get_ok_button().text = "Claim"
	confirmed.connect(_on_confirmed)
	min_size = Vector2(420, 280)
	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = true
	_body_label.fit_content = true
	_body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_body_label)


func show_summary(summary: Dictionary) -> void:
	_summary = summary
	_body_label.text = _format_summary(summary)
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
			var name: String = item_res.display_name if item_res != null else String(item_id_str)
			lines.append("  • %s × %d" % [name, count])
	return "\n".join(lines)


func _on_confirmed() -> void:
	claimed.emit(_summary)
