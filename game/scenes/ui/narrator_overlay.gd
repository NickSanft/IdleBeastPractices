## Bottom-of-screen text bubble for Peniber's narration.
##
## Subscribes to EventBus.narrator_line_chosen, fades in, holds for
## VISIBLE_SECONDS (or until tapped), fades out. Mouse_filter is IGNORE on
## the wrapper so background taps still reach the catch view; only the
## bubble itself catches taps to dismiss.
extends Control

const VISIBLE_SECONDS := 8.0
const FADE_SECONDS := 0.25
const _MOOD_TINTS := {
	"smug":        Color(0.9, 0.9, 1.0),
	"begrudging":  Color(0.95, 0.85, 0.7),
	"reverent":    Color(1.0, 0.95, 0.7),
	"weary":       Color(0.8, 0.8, 0.85),
	"exasperated": Color(1.0, 0.75, 0.75),
}

var _bubble: PanelContainer
var _text_label: RichTextLabel
var _hide_timer: Timer
var _current_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	custom_minimum_size = Vector2(0, 140)
	# Tuck against the bottom with a small inset so it sits above the tab bar.
	offset_top = -180
	offset_bottom = -40
	offset_left = 16
	offset_right = -16

	_bubble = PanelContainer.new()
	_bubble.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bubble.modulate = Color(1, 1, 1, 0)   # start invisible
	_bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bubble)

	var margins := MarginContainer.new()
	margins.add_theme_constant_override("margin_left", 16)
	margins.add_theme_constant_override("margin_right", 16)
	margins.add_theme_constant_override("margin_top", 12)
	margins.add_theme_constant_override("margin_bottom", 12)
	_bubble.add_child(margins)

	var vbox := VBoxContainer.new()
	margins.add_child(vbox)

	var name_label := Label.new()
	name_label.text = "Peniber"
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.modulate = Color(1.0, 0.85, 0.5)
	vbox.add_child(name_label)

	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = true
	_text_label.fit_content = true
	_text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_label.add_theme_font_size_override("normal_font_size", 16)
	vbox.add_child(_text_label)

	_hide_timer = Timer.new()
	_hide_timer.one_shot = true
	_hide_timer.wait_time = VISIBLE_SECONDS
	_hide_timer.timeout.connect(_hide)
	add_child(_hide_timer)

	_bubble.gui_input.connect(_on_bubble_gui_input)

	EventBus.narrator_line_chosen.connect(_on_narrator_line_chosen)


func _on_narrator_line_chosen(_line_id: String, text: String, mood: String) -> void:
	_text_label.text = text
	var tint: Color = _MOOD_TINTS.get(mood, Color.WHITE)
	_bubble.modulate = Color(tint.r, tint.g, tint.b, _bubble.modulate.a)
	_show()


func _show() -> void:
	if _current_tween != null and _current_tween.is_running():
		_current_tween.kill()
	var t: Tween = create_tween()
	t.tween_property(_bubble, "modulate:a", 1.0, FADE_SECONDS)
	_current_tween = t
	_hide_timer.start()


func _hide() -> void:
	if _current_tween != null and _current_tween.is_running():
		_current_tween.kill()
	var t: Tween = create_tween()
	t.tween_property(_bubble, "modulate:a", 0.0, FADE_SECONDS)
	_current_tween = t


func _on_bubble_gui_input(event: InputEvent) -> void:
	# Tap the bubble to dismiss early.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_hide_timer.stop()
		_hide()
	elif event is InputEventScreenTouch and event.pressed:
		_hide_timer.stop()
		_hide()
