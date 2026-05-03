## Diagnostic overlay that paints a crosshair at every touch / click
## position so we can see whether Godot's hit-test coordinate matches
## where the user thought they were tapping.
##
## v0.8.5 — added in response to a Galaxy Z Fold7 / Android 16 report
## that buttons "didn't match their clickable area". Toggle with F4 in
## the editor; on Android, toggle via a hidden tap on the version line
## in Settings (TBD) or via Settings.touch_debug_enabled.
##
## When it stays silent on real devices we'll know the tap genuinely
## isn't reaching Godot; if the crosshair appears at a different spot
## than the user thinks they tapped, that's the canvas_items stretch
## input bug confirmed.
extends Control

const _CROSSHAIR_LIFETIME := 0.8

var _markers: Array[Dictionary] = []   # [{pos: Vector2, age: float}]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(true)
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	# Capture both finger touches and mouse clicks so the overlay works
	# on desktop testing too. We sample the global position; that's the
	# coordinate Godot believes the tap landed at.
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
	if _markers.is_empty():
		return
	var any_alive: bool = false
	for m in _markers:
		m["age"] += delta
		if m["age"] < _CROSSHAIR_LIFETIME:
			any_alive = true
	# Drop dead markers (age >= lifetime).
	_markers = _markers.filter(func(m: Dictionary) -> bool:
		return m["age"] < _CROSSHAIR_LIFETIME)
	if any_alive:
		queue_redraw()


func _draw() -> void:
	for m in _markers:
		var pos: Vector2 = m["pos"]
		var age: float = m["age"]
		var alpha: float = 1.0 - (age / _CROSSHAIR_LIFETIME)
		var color := Color(1.0, 0.4, 0.4, alpha)
		# Crosshair lines.
		draw_line(pos + Vector2(-20, 0), pos + Vector2(20, 0), color, 2.0)
		draw_line(pos + Vector2(0, -20), pos + Vector2(0, 20), color, 2.0)
		# Outer ring scales with age — implies "fresh tap" before fading.
		var radius: float = 8.0 + age * 24.0
		draw_arc(pos, radius, 0.0, TAU, 32, color, 2.0)
