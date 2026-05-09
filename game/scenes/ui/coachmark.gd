## Phase 12c — coachmark overlay.
##
## A focused tooltip that points at a specific UI target with a hint
## string. Used by the FTUE tutorial to teach mechanics one at a time
## as they unlock. Composed of:
##   - Dim backdrop (darkens everything except the target rect)
##   - Pulsing arrow / pointer aimed at the target
##   - Text bubble with the hint copy
##   - Tap-anywhere-to-dismiss (tap on target also dismisses)
##
## Public API:
##   show_for(target: Control, hint: String, step_id: StringName)
##     - target: Control whose global rect the coachmark anchors to
##     - hint: tooltip text
##     - step_id: marked seen via TutorialState on dismiss
##
## Honours `Settings.reduce_motion` — pulsing animation is disabled
## when the flag is on.
extends CanvasLayer

signal dismissed(step_id: StringName)

const _PALETTE := preload("res://game/resources/palette_colors.gd")
const _SHOW_LAYER := 75   # below celebration_overlay (80), above narrator
const _PULSE_HZ: float = 1.5
const _ARROW_OFFSET: float = 24.0
const _BUBBLE_MIN_WIDTH: float = 240.0

var _backdrop: ColorRect
var _bubble: PanelContainer
var _hint_label: Label
var _arrow: Polygon2D
var _arrow_node: Node2D
var _target: Control
var _step_id: StringName = &""
var _pulse_phase: float = 0.0


func _ready() -> void:
	layer = _SHOW_LAYER
	visible = false

	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.05, 0.04, 0.03, 0.50)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.gui_input.connect(_on_input)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	# Arrow — Polygon2D triangle anchored on the canvas. Position is
	# updated each _process so it tracks the target's screen rect.
	_arrow_node = Node2D.new()
	add_child(_arrow_node)
	_arrow = Polygon2D.new()
	_arrow.color = _PALETTE.BRASS_ACCENT
	_arrow.polygon = PackedVector2Array([
			Vector2(0, 0),
			Vector2(-12, -16),
			Vector2(12, -16),
	])
	_arrow_node.add_child(_arrow)

	# Hint bubble.
	_bubble = PanelContainer.new()
	_bubble.theme = preload("res://game/resources/main_theme.tres")
	_bubble.custom_minimum_size = Vector2(_BUBBLE_MIN_WIDTH, 0)
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bubble)
	var margins := MarginContainer.new()
	margins.add_theme_constant_override("margin_left", 12)
	margins.add_theme_constant_override("margin_right", 12)
	margins.add_theme_constant_override("margin_top", 10)
	margins.add_theme_constant_override("margin_bottom", 10)
	_bubble.add_child(margins)
	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", UiScale.size(14))
	_hint_label.add_theme_color_override("font_color", _PALETTE.INK_BLACK)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	margins.add_child(_hint_label)
	set_process(false)


func show_for(target: Control, hint: String, step_id: StringName) -> void:
	_target = target
	_hint_label.text = hint
	_step_id = step_id
	visible = true
	_pulse_phase = 0.0
	set_process(true)
	_reposition()


func _process(delta: float) -> void:
	# Pulse the arrow so the eye is drawn to the target. Skip in
	# reduce-motion mode.
	if not Settings.reduce_motion:
		_pulse_phase += delta * _PULSE_HZ
		var pulse: float = (sin(_pulse_phase * TAU) * 0.5 + 0.5) * 0.4 + 0.8
		_arrow_node.scale = Vector2(pulse, pulse)
	else:
		_arrow_node.scale = Vector2.ONE
	_reposition()


## Re-anchors the arrow + bubble each frame so the coachmark tracks
## the target even if it moves (e.g. catching screen monsters wander).
func _reposition() -> void:
	if not is_instance_valid(_target):
		return
	# Target's global screen rect → centered arrow position above the
	# target. If the target is in the bottom half of the screen, place
	# the bubble above; otherwise below.
	var rect: Rect2 = _target.get_global_rect()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var target_center: Vector2 = rect.position + rect.size * 0.5

	# Arrow points downward at the target's top edge by default; if
	# the bubble would overlap the screen top, flip to point upward.
	var arrow_above: bool = target_center.y > viewport_size.y * 0.4
	if arrow_above:
		_arrow_node.position = Vector2(target_center.x, rect.position.y - _ARROW_OFFSET)
		_arrow_node.rotation = 0.0   # tip points down
		_bubble.position = Vector2(
				clampf(target_center.x - _BUBBLE_MIN_WIDTH * 0.5, 12, viewport_size.x - _BUBBLE_MIN_WIDTH - 12),
				rect.position.y - _ARROW_OFFSET - _bubble.size.y - 12)
	else:
		_arrow_node.position = Vector2(target_center.x, rect.end.y + _ARROW_OFFSET)
		_arrow_node.rotation = PI   # tip points up
		_bubble.position = Vector2(
				clampf(target_center.x - _BUBBLE_MIN_WIDTH * 0.5, 12, viewport_size.x - _BUBBLE_MIN_WIDTH - 12),
				rect.end.y + _ARROW_OFFSET + 12)


func _on_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed):
		dismiss()


func dismiss() -> void:
	visible = false
	set_process(false)
	if _step_id != &"":
		TutorialState.mark_seen(_step_id)
		dismissed.emit(_step_id)
		_step_id = &""
