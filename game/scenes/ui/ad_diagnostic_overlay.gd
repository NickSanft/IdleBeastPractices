## Top-of-screen banner that surfaces ad lifecycle events for debugging.
##
## v0.7.1 lands this so the user can see why an ad request silently
## failed on the foldable: `requested` -> `rewarded_completed` /
## `rewarded_failed(reason)` are visualized as colored text that holds
## for VISIBLE_SECONDS then fades. Mouse_filter is IGNORE on the wrapper
## and the bubble so background taps reach the gameplay underneath.
##
## Once the AdMob account is fully serving and we've stabilized, this
## overlay can be removed or gated behind a debug flag.
extends Control

const VISIBLE_SECONDS := 6.0
const FADE_SECONDS := 0.3

const _COLOR_REQUEST := Color(0.7, 0.85, 1.0)   # cool blue — in flight
const _COLOR_SUCCESS := Color(0.55, 0.95, 0.55) # green — granted
const _COLOR_FAILURE := Color(1.0, 0.55, 0.55)  # red — failure / cancel

var _bubble: PanelContainer
var _label: Label
var _hide_timer: Timer
var _current_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	custom_minimum_size = Vector2(0, 56)
	# Sit just below the currency bar with a small inset on each side.
	offset_top = 64
	offset_bottom = 116
	offset_left = 16
	offset_right = -16

	_bubble = PanelContainer.new()
	_bubble.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bubble.modulate = Color(1, 1, 1, 0)   # start invisible
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bubble)

	var margins := MarginContainer.new()
	margins.add_theme_constant_override("margin_left", 12)
	margins.add_theme_constant_override("margin_right", 12)
	margins.add_theme_constant_override("margin_top", 8)
	margins.add_theme_constant_override("margin_bottom", 8)
	_bubble.add_child(margins)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	margins.add_child(_label)

	_hide_timer = Timer.new()
	_hide_timer.one_shot = true
	_hide_timer.timeout.connect(_fade_out)
	add_child(_hide_timer)

	AdsManager.requested.connect(_on_requested)
	AdsManager.rewarded_completed.connect(_on_completed)
	AdsManager.rewarded_failed.connect(_on_failed)


func _on_requested(reward_id: String) -> void:
	_show_message("[ad] requested: %s …" % reward_id, _COLOR_REQUEST)


func _on_completed(reward_id: String, granted: bool) -> void:
	if granted:
		_show_message("[ad] %s — reward granted" % reward_id, _COLOR_SUCCESS)
	else:
		_show_message("[ad] %s — completed without grant" % reward_id, _COLOR_FAILURE)


func _on_failed(reward_id: String, reason: String) -> void:
	_show_message("[ad] %s — failed: %s" % [reward_id, reason], _COLOR_FAILURE)


func _show_message(text: String, color: Color) -> void:
	_label.text = text
	_label.modulate = color
	if _current_tween != null and _current_tween.is_valid():
		_current_tween.kill()
	_current_tween = create_tween()
	_current_tween.tween_property(_bubble, "modulate:a", 1.0, FADE_SECONDS)
	_hide_timer.start(VISIBLE_SECONDS)


func _fade_out() -> void:
	if _current_tween != null and _current_tween.is_valid():
		_current_tween.kill()
	_current_tween = create_tween()
	_current_tween.tween_property(_bubble, "modulate:a", 0.0, FADE_SECONDS)
