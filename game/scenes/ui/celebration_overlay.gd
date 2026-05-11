## Phase 11a — full-screen celebration modal.
##
## Use for the rarest, most-celebrated events: tier complete, first
## pet, first shiny, stage cleared, prestige triggered. The overlay
## fades in with a parchment-and-brass card, plays a brief glow tween,
## and dismisses on tap or after `duration` seconds.
##
## Tier 4 of the feedback spectrum (per POLISH_PLAN's research synthesis):
## these events should feel distinctly bigger than common-event
## feedback. The overlay pauses player input briefly (~250 ms) before
## allowing dismissal so the moment registers.
##
## Public API:
##   show_celebration(title, body, sprite=null, duration=0.0)
##     - duration=0  → require tap to dismiss
##     - duration>0  → auto-dismiss after that many seconds
##
## All animations honour `Settings.reduce_motion` (added in 11b — for
## now the flag is consulted defensively so the wiring is in place).
extends CanvasLayer

signal dismissed

const _PALETTE := preload("res://game/resources/palette_colors.gd")
const _FADE_IN_SECS := 0.25
const _FADE_OUT_SECS := 0.18
const _INPUT_LOCK_SECS := 0.25
const _SHOW_LAYER := 80   # above narrator overlay (which lives in default layer)

var _backdrop: ColorRect
var _card: PanelContainer
var _title_label: Label
var _body_label: Label
var _sprite_rect: TextureRect
var _tap_locked_until: float = 0.0
var _auto_dismiss_timer: SceneTreeTimer
var _showing: bool = false


func _ready() -> void:
	layer = _SHOW_LAYER
	visible = false

	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.05, 0.04, 0.03, 0.55)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.gui_input.connect(_on_backdrop_input)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	# Card: a centered PanelContainer using the parchment theme. The
	# theme is assigned explicitly because CanvasLayer is a Window-
	# adjacent context and theme cascade is unreliable.
	_card = PanelContainer.new()
	_card.theme = preload("res://assets/themes/dusk/amethyst.tres")
	_card.set_anchors_preset(Control.PRESET_CENTER)
	_card.custom_minimum_size = Vector2(360, 0)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.gui_input.connect(_on_card_input)
	add_child(_card)

	var margins := MarginContainer.new()
	margins.add_theme_constant_override("margin_left", 20)
	margins.add_theme_constant_override("margin_right", 20)
	margins.add_theme_constant_override("margin_top", 20)
	margins.add_theme_constant_override("margin_bottom", 20)
	_card.add_child(margins)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margins.add_child(vbox)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", UiScale.size(26))
	_title_label.add_theme_color_override("font_color", _PALETTE.INK_BLACK)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_title_label)

	_sprite_rect = TextureRect.new()
	_sprite_rect.custom_minimum_size = Vector2(96, 96)
	_sprite_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_sprite_rect.visible = false
	vbox.add_child(_sprite_rect)

	_body_label = Label.new()
	_body_label.add_theme_font_size_override("font_size", UiScale.size(16))
	_body_label.add_theme_color_override("font_color", _PALETTE.SEPIA_DARK)
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_body_label)

	var hint := Label.new()
	hint.text = "Tap anywhere to dismiss"
	hint.add_theme_font_size_override("font_size", UiScale.size(12))
	hint.add_theme_color_override("font_color", _PALETTE.SEPIA_MID)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)


func show_celebration(
		title: String,
		body: String,
		sprite: Texture2D = null,
		duration: float = 0.0) -> void:
	_title_label.text = title
	_body_label.text = body
	if sprite != null:
		_sprite_rect.texture = sprite
		_sprite_rect.visible = true
	else:
		_sprite_rect.visible = false
	visible = true
	_showing = true
	# Brief input lock so the user notices the moment before
	# accidentally tapping it away mid-action.
	_tap_locked_until = Time.get_ticks_msec() / 1000.0 + _INPUT_LOCK_SECS

	if _is_reduce_motion():
		_backdrop.modulate.a = 1.0
		_card.modulate = Color.WHITE
		_card.scale = Vector2.ONE
	else:
		_backdrop.modulate.a = 0.0
		_card.modulate.a = 0.0
		_card.scale = Vector2(0.92, 0.92)
		var t := create_tween()
		t.set_parallel(true)
		t.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_property(_backdrop, "modulate:a", 1.0, _FADE_IN_SECS)
		t.tween_property(_card, "modulate:a", 1.0, _FADE_IN_SECS)
		t.tween_property(_card, "scale", Vector2.ONE, _FADE_IN_SECS)

	# Cancel any pending auto-dismiss from a prior celebration.
	_auto_dismiss_timer = null
	if duration > 0.0:
		_auto_dismiss_timer = get_tree().create_timer(duration)
		_auto_dismiss_timer.timeout.connect(_on_auto_dismiss_fired.bind(_auto_dismiss_timer))


func _on_auto_dismiss_fired(scheduling_timer: SceneTreeTimer) -> void:
	# Re-entrancy guard: if a NEW celebration replaced this one, the
	# scheduled-timer reference no longer matches and we skip.
	if scheduling_timer != _auto_dismiss_timer:
		return
	dismiss()


func _on_backdrop_input(event: InputEvent) -> void:
	if not _showing:
		return
	if Time.get_ticks_msec() / 1000.0 < _tap_locked_until:
		return
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed):
		dismiss()


func _on_card_input(event: InputEvent) -> void:
	# Tapping the card itself also dismisses — players should never
	# have to hunt for the right pixel to close the overlay.
	_on_backdrop_input(event)


func dismiss() -> void:
	if not _showing:
		return
	_showing = false
	_auto_dismiss_timer = null
	if _is_reduce_motion():
		visible = false
		dismissed.emit()
		return
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_backdrop, "modulate:a", 0.0, _FADE_OUT_SECS)
	t.tween_property(_card, "modulate:a", 0.0, _FADE_OUT_SECS)
	t.tween_callback(func() -> void:
		visible = false
		dismissed.emit())


func is_showing() -> bool:
	return _showing


## Reads the persisted-but-not-yet-wired Settings flag. Phase 11b
## fully wires this; for 11a we just consult it defensively so the
## hook is in place. Returns false if the flag isn't available.
func _is_reduce_motion() -> bool:
	if not has_node("/root/Settings"):
		return false
	var s := get_node("/root/Settings")
	if "reduce_motion" in s:
		return bool(s.reduce_motion)
	return false
