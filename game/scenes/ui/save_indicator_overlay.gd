## Small bottom-right "Saved <HH:MM:SS>" toast that flashes briefly
## whenever SaveManager emits `EventBus.game_saved`.
##
## Diagnostic for the v0.8.2 cycle: the user reported save persistence
## failing on a Galaxy Z Fold7 (Android 16) despite the v0.7.5
## NOTIFICATION_APPLICATION_PAUSED handler. With this overlay visible,
## you can confirm saves are actually firing in-app — periodic 10 s
## auto-saves should produce a flash every ~10 seconds, and
## backgrounding-then-resuming should produce a flash near the
## background event.
##
## Once persistence is confirmed reliable, gate this behind a debug
## flag or remove it.
extends Control

const VISIBLE_SECONDS := 1.5
const FADE_SECONDS := 0.25

var _label: Label
var _hide_timer: Timer
var _current_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchor bottom-right with a small inset so it doesn't overlap the
	# tab bar or the catching view's drops-2x button.
	anchor_left = 1.0
	anchor_top = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = -180
	offset_top = -32
	offset_right = -16
	offset_bottom = -8

	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.add_theme_font_size_override("font_size", 12)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.modulate = Color(0.6, 1.0, 0.7, 0.0)   # green, start hidden
	add_child(_label)

	_hide_timer = Timer.new()
	_hide_timer.one_shot = true
	_hide_timer.timeout.connect(_fade_out)
	add_child(_hide_timer)

	EventBus.game_saved.connect(_on_game_saved)


func _on_game_saved() -> void:
	var now: Dictionary = Time.get_time_dict_from_system()
	_label.text = "Saved %02d:%02d:%02d" % [now["hour"], now["minute"], now["second"]]
	if _current_tween != null and _current_tween.is_valid():
		_current_tween.kill()
	_current_tween = create_tween()
	_current_tween.tween_property(_label, "modulate:a", 1.0, FADE_SECONDS)
	_hide_timer.start(VISIBLE_SECONDS)


func _fade_out() -> void:
	if _current_tween != null and _current_tween.is_valid():
		_current_tween.kill()
	_current_tween = create_tween()
	_current_tween.tween_property(_label, "modulate:a", 0.0, FADE_SECONDS)
