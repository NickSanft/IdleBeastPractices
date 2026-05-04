## Phase 10c — single currency display unit.
##
## Composes [icon] + [Label] + optional [ProgressBar] into a themed
## PanelContainer. Owns its own tweening logic so callers can just
## drive a target value via set_value(); the chip animates from the
## prior displayed value to the new one over a configurable duration.
##
## Two value flavors are supported:
##   - BigNumber  (gold)  — tweened via BigNumber.add/multiply_float.
##   - int        (RP, prestige) — tweened via lerpf on the displayed
##                                  count, rounded to int per frame.
extends PanelContainer

const _PALETTE := preload("res://game/resources/palette_colors.gd")
const _DEFAULT_TWEEN_SEC := 0.4

# Public configuration. Set via configure() before adding to the tree
# (or anytime after — re-applies on the next frame).
var icon_texture: Texture2D
var accent_color: Color = Color(0.72, 0.55, 0.20, 1.0)   # brass default
var label_prefix: String = ""
## Set via tooltip_text property; the Control base auto-shows on hover.

# Internal display state.
var _value_kind: int = _Kind.NONE
var _displayed_int: int = 0
var _target_int: int = 0
var _displayed_big: BigNumber
var _target_big: BigNumber
var _displayed_at_tween_start_int: int = 0
var _displayed_at_tween_start_big: BigNumber
var _tween: Tween
var _tween_progress: float = 1.0
## Optional next-milestone progress for chips that use the bar (gold).
## Range 0.0..1.0; -1.0 hides the bar entirely.
var _progress_fraction: float = -1.0

var _icon: TextureRect
var _value_label: Label
var _progress: ProgressBar
var _accent_stripe: ColorRect

enum _Kind { NONE, INT, BIG }


func _ready() -> void:
	custom_minimum_size = Vector2(110, 56)
	mouse_filter = Control.MOUSE_FILTER_STOP   # so tooltip + future long-press fire
	# Themed PanelContainer fill comes from the Theme. Add a 4px brass
	# accent stripe along the left edge so chips read as currency cards
	# rather than plain panels.
	_accent_stripe = ColorRect.new()
	_accent_stripe.color = accent_color
	_accent_stripe.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_accent_stripe.offset_right = 4
	_accent_stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_accent_stripe)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.offset_left = 8
	add_child(hbox)

	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(32, 32)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.texture = icon_texture
	hbox.add_child(_icon)

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 2)
	hbox.add_child(stack)

	_value_label = Label.new()
	_value_label.add_theme_font_size_override("font_size", 18)
	_value_label.add_theme_color_override("font_color", _PALETTE.INK_BLACK)
	_value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stack.add_child(_value_label)

	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 6)
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.value = 0.0
	_progress.max_value = 1.0
	_progress.step = 0.0   # smooth interpolation, not snap
	_progress.visible = false
	stack.add_child(_progress)

	_refresh_label()


## One-shot configuration: icon, accent color, and a static label prefix
## (e.g. "Gold"). Safe to call before _ready.
func configure(p_icon: Texture2D, p_accent: Color, p_prefix: String, p_tooltip: String = "") -> void:
	icon_texture = p_icon
	accent_color = p_accent
	label_prefix = p_prefix
	tooltip_text = p_tooltip
	if is_inside_tree():
		_icon.texture = icon_texture
		_accent_stripe.color = accent_color
		_refresh_label()


## Drive a new int value. Tween-animates from the currently displayed
## count to `value` over `duration` seconds. Pass `animate=false` for
## instant snap (used on first paint to avoid a 0→N tween at startup).
func set_int_value(value: int, animate: bool = true, duration: float = _DEFAULT_TWEEN_SEC) -> void:
	_value_kind = _Kind.INT
	_target_int = value
	if not animate or not is_inside_tree():
		_displayed_int = value
		_refresh_label()
		return
	_displayed_at_tween_start_int = _displayed_int
	_start_tween(duration)


## Drive a new BigNumber value. Same semantics as set_int_value.
func set_big_value(value: BigNumber, animate: bool = true, duration: float = _DEFAULT_TWEEN_SEC) -> void:
	_value_kind = _Kind.BIG
	_target_big = value
	if not animate or not is_inside_tree() or _displayed_big == null:
		_displayed_big = value
		_refresh_label()
		return
	_displayed_at_tween_start_big = _displayed_big
	_start_tween(duration)


## Drive the next-milestone progress bar. Pass -1 to hide.
func set_progress_fraction(fraction: float) -> void:
	_progress_fraction = fraction
	if _progress == null:
		return
	if fraction < 0.0:
		_progress.visible = false
	else:
		_progress.visible = true
		_progress.value = clamp(fraction, 0.0, 1.0)


func _start_tween(duration: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween_progress = 0.0
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_apply_tween_progress, 0.0, 1.0, duration)


func _apply_tween_progress(t: float) -> void:
	_tween_progress = t
	match _value_kind:
		_Kind.INT:
			_displayed_int = int(round(lerpf(
					float(_displayed_at_tween_start_int),
					float(_target_int),
					t)))
		_Kind.BIG:
			# Linear lerp of BigNumbers: from + (to - from) * t.
			# Falls back to instant-snap when subtract isn't available
			# (BigNumber API is on by default in this project).
			if _displayed_at_tween_start_big == null or _target_big == null:
				_displayed_big = _target_big
			else:
				var delta: BigNumber = _target_big.subtract(_displayed_at_tween_start_big)
				var step: BigNumber = delta.multiply_float(t)
				_displayed_big = _displayed_at_tween_start_big.add(step)
	_refresh_label()


func _refresh_label() -> void:
	if _value_label == null:
		return
	match _value_kind:
		_Kind.INT:
			_value_label.text = _format_with_prefix("%d" % _displayed_int)
		_Kind.BIG:
			var text: String = "0" if _displayed_big == null else _displayed_big.format()
			_value_label.text = _format_with_prefix(text)
		_:
			_value_label.text = label_prefix


func _format_with_prefix(value_text: String) -> String:
	if label_prefix == "":
		return value_text
	return "%s  %s" % [label_prefix, value_text]
