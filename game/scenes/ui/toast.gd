## Phase 11a — slide-down toast notification.
##
## Use for medium-importance events that don't warrant a full-screen
## celebration: subsequent pet acquisitions (after the first), recipe
## unlocks, milestone catches. Slides in from off-screen top, holds
## for `duration` seconds, slides back out.
##
## Internally maintains a queue so multiple rapid `show_toast` calls
## don't clip each other — each toast plays in turn.
##
## Public API:
##   show_toast(text, duration=3.0)
##
## Tier 2 of the feedback spectrum: visible enough to register but
## not interruptive of play. Honours `Settings.reduce_motion` (jumps
## directly to visible, no tween) when wired in 11b.
extends CanvasLayer

const _PALETTE := preload("res://game/resources/palette_colors.gd")
const _SHOW_LAYER := 70   # below celebration_overlay (80), above narrator
const _SLIDE_SECS := 0.22
const _DEFAULT_DURATION := 3.0
const _BANNER_Y_OFFSET := 12.0   # px from top edge to settled position

var _banner: PanelContainer
var _label: Label
var _queue: Array[Dictionary] = []
var _showing: bool = false


func _ready() -> void:
	layer = _SHOW_LAYER

	_banner = PanelContainer.new()
	_banner.theme = preload("res://game/resources/main_theme.tres")
	# Anchor to top-center; manual offset_top keeps the slide-in math simple.
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.anchor_top = 0.0
	_banner.anchor_bottom = 0.0
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.custom_minimum_size = Vector2(280, 0)
	# Hidden off-screen above the top edge initially.
	_banner.offset_top = -100.0
	_banner.offset_bottom = -36.0
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)

	var margins := MarginContainer.new()
	margins.add_theme_constant_override("margin_left", 16)
	margins.add_theme_constant_override("margin_right", 16)
	margins.add_theme_constant_override("margin_top", 10)
	margins.add_theme_constant_override("margin_bottom", 10)
	_banner.add_child(margins)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", _PALETTE.INK_BLACK)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	margins.add_child(_label)


func show_toast(text: String, duration: float = _DEFAULT_DURATION) -> void:
	_queue.append({"text": text, "duration": max(0.5, duration)})
	if not _showing:
		_run_queue()


func _run_queue() -> void:
	if _queue.is_empty():
		_showing = false
		return
	_showing = true
	var entry: Dictionary = _queue.pop_front()
	_label.text = String(entry.get("text", ""))
	if _is_reduce_motion():
		_banner.offset_top = _BANNER_Y_OFFSET
		_banner.offset_bottom = _BANNER_Y_OFFSET + 56.0
		await get_tree().create_timer(float(entry.get("duration", _DEFAULT_DURATION))).timeout
		_banner.offset_top = -100.0
		_banner.offset_bottom = -36.0
		_run_queue()
		return
	# Slide in.
	var t_in := create_tween()
	t_in.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t_in.tween_property(_banner, "offset_top", _BANNER_Y_OFFSET, _SLIDE_SECS)
	t_in.parallel().tween_property(
			_banner, "offset_bottom", _BANNER_Y_OFFSET + 56.0, _SLIDE_SECS)
	await t_in.finished

	await get_tree().create_timer(float(entry.get("duration", _DEFAULT_DURATION))).timeout

	var t_out := create_tween()
	t_out.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t_out.tween_property(_banner, "offset_top", -100.0, _SLIDE_SECS)
	t_out.parallel().tween_property(_banner, "offset_bottom", -36.0, _SLIDE_SECS)
	await t_out.finished

	_run_queue()


## Public read-only: how many toasts are queued behind the current one?
## Used by tests; the live UI doesn't need to inspect it.
func queue_size() -> int:
	return _queue.size()


func is_showing() -> bool:
	return _showing


func _is_reduce_motion() -> bool:
	if not has_node("/root/Settings"):
		return false
	var s := get_node("/root/Settings")
	if "reduce_motion" in s:
		return bool(s.reduce_motion)
	return false
