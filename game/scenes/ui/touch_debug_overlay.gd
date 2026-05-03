## Diagnostic overlay that paints a crosshair at every touch position
## AND outlines every Button's hit-test rect, so we can see whether
## Godot's hit-test coordinate matches the visible button surface.
##
## v0.8.5 used `_unhandled_input` which only fires AFTER `_gui_input`
## has consumed the event — so when a Button received a tap, the
## overlay never saw it. v0.8.6 switches to `_input` which sees every
## event before GUI dispatching, so taps register regardless of where
## they land.
##
## v0.8.6 also paints every Button's `get_global_rect()` as a faint
## green outline. The crosshair lands at the touch position; the green
## outline shows where Godot thinks each Button accepts taps. If a tap
## crosshair lands inside the green outline of a Button but the button
## doesn't respond, we have direct evidence of the hit-test bug.
extends Control

const _CROSSHAIR_LIFETIME := 1.5
const _BUTTON_OUTLINE_COLOR := Color(0.4, 1.0, 0.4, 0.35)

var _markers: Array[Dictionary] = []   # [{pos: Vector2, age: float}]
var _info_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(true)
	# v0.8.6: `_input` fires BEFORE `_gui_input` so the overlay sees
	# every touch even when a Button consumes it. The previous
	# `_unhandled_input` only saw taps that nothing else handled.
	set_process_input(true)

	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 11)
	_info_label.modulate = Color(1.0, 1.0, 0.5, 0.9)
	_info_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_info_label.position = Vector2(8, 96)
	add_child(_info_label)


func _input(event: InputEvent) -> void:
	# Capture both finger touches and mouse clicks. Position is in the
	# coordinate space Godot uses for hit-tests against Control rects.
	var pos: Vector2
	var got: bool = false
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position
		got = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
		got = true
	if got:
		_markers.append({"pos": pos, "age": 0.0})
		queue_redraw()


func _process(delta: float) -> void:
	# Update the info label every frame so we can read viewport/window
	# size + scale at a glance from a screenshot.
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var win_size: Vector2i = get_window().size
	_info_label.text = "viewport=%dx%d  window=%dx%d  scale=%.2f" % [
		int(vp_size.x), int(vp_size.y),
		win_size.x, win_size.y,
		float(win_size.x) / max(1.0, vp_size.x),
	]
	if _markers.is_empty():
		queue_redraw()  # still need to repaint button outlines
		return
	for m in _markers:
		m["age"] += delta
	_markers = _markers.filter(func(m: Dictionary) -> bool:
		return m["age"] < _CROSSHAIR_LIFETIME)
	queue_redraw()


func _draw() -> void:
	# Outline every Button's hit-test rect so the user can compare
	# visible button surface vs. what Godot considers tappable.
	_outline_buttons(get_tree().root)
	# Then paint each touch crosshair on top.
	for m in _markers:
		var pos: Vector2 = m["pos"]
		var age: float = m["age"]
		var alpha: float = 1.0 - (age / _CROSSHAIR_LIFETIME)
		var color := Color(1.0, 0.4, 0.4, alpha)
		draw_line(pos + Vector2(-20, 0), pos + Vector2(20, 0), color, 3.0)
		draw_line(pos + Vector2(0, -20), pos + Vector2(0, 20), color, 3.0)
		var radius: float = 10.0 + age * 30.0
		draw_arc(pos, radius, 0.0, TAU, 32, color, 3.0)


func _outline_buttons(node: Node) -> void:
	if node is Button and node.is_visible_in_tree():
		var rect: Rect2 = node.get_global_rect()
		draw_rect(rect, _BUTTON_OUTLINE_COLOR, false, 2.0)
	for child in node.get_children():
		_outline_buttons(child)
