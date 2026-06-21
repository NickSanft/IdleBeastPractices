## Phase 14e — first-launch Peniber intro overlay.
##
## Plays the 4-beat intro from `docs/design_handoff_theming/reference_files/data.js`
## → `PENIBER_INTRO` exactly once per save. Reskinned per
## styles.css `.intro-overlay` block:
##
##   ┌────────────────────────────────┐
##   │                                │
##   │         IDLE BEASTS            │  ← title (gold flicker)
##   │         the awakening          │
##   │                                │
##   │           [hat]                │
##   │           ┌──┐                 │  ← wizard stage
##   │           │  │                 │     (geometric stand-in)
##   │          /────\                │
##   │                                │
##   │   ┌──────────────────────┐     │
##   │   │ PENIBER             ▢│     │  ← dialog bubble + gold pin
##   │   │ You're awake.       …│     │     + page dots
##   │   │ ● ● ○ ○       SKIP   │     │
##   │   └──────────────────────┘     │
##   └────────────────────────────────┘
##
## - Dim full-screen backdrop (rgba(7,5,15,0.92)) + radial teal glow
## - Title: Press Start 2P 18-px gold with text-shadow + 4-s flicker loop
## - Wizard sprite: stylized geometric stand-in (real pixel-art Peniber
##   is a separate art commission, see PHASED_RESKIN_PLAN.md)
## - Body bubble: Dusk card + 2-px border + gold "PENIBER" pin tag,
##   VT323 19-px (BodyIntro variation) typewriter at 22 ms/char
## - Page dots: 4 small squares at the bottom, active one tints gold
## - SKIP button skips to end and dismisses
## - Tapping the bubble advances to the next page; on last page it
##   dismisses + marks TutorialState.STEP_PENIBER_INTRO_SHOWN.
##
## Gating: only shown when `TutorialState.should_show(STEP_PENIBER_INTRO_SHOWN)`
## returns true. Main calls `show_intro_if_unseen()` after _ready.
extends CanvasLayer

signal intro_dismissed

const _DUSK := preload("res://assets/themes/dusk/palette_dusk.gd")

## styles.css typewriter: 22 ms/char during intro (slower than the
## ribbon's 18 ms/char — the intro is the player's first impression).
const _TYPE_MS_PER_CHAR := 22.0
## styles.css `title-flicker 4s infinite`: 0%/90%/100% = opacity 1,
## 92% = 0.6, 94% = 1. We approximate via a tween loop that drops
## opacity briefly inside a 4-s window.
const _TITLE_FLICKER_PERIOD := 4.0
## styles.css `pen-float 3.4s ease-in-out infinite`: ±6 px vertical bob.
const _WIZARD_FLOAT_PERIOD := 3.4
const _WIZARD_FLOAT_AMPLITUDE := 6.0
## styles.css `spark-spin 2s linear infinite`: hat-spark opacity + scale pulse.
const _SPARK_PERIOD := 2.0

## Hardcoded mirror of `data.js → PENIBER_INTRO`. Each entry is
## `{mood, text}`. Mood drives a subtle name-tint shift in the bubble
## (see `_apply_mood_tint`) so the four beats feel like four distinct
## reads of Peniber's voice rather than the same tone repeated.
const _BEATS: Array[Dictionary] = [
	{
		"mood": "weary",
		"text": "Oh. You're awake. Marvelous. I had begun to suspect the contract was void.",
	},
	{
		"mood": "explaining",
		"text": "I am Peniber. Your wizard, technically. Your supervisor, functionally. Try not to make either fact embarrassing.",
	},
	{
		"mood": "dry",
		"text": "These are slimes. They are stupid. You catch them by tapping. Yes — that is the whole of it. We will work up to harder verbs.",
	},
	{
		"mood": "exiting",
		"text": "I'll be hovering. Nominally helpful. Spiritually appalled. Begin.",
	},
]

const _MOOD_NAME_TINTS := {
	"weary":      Color(0.85, 0.78, 0.55),
	"explaining": Color(0.95, 0.85, 0.55),
	"dry":        Color(0.80, 0.75, 0.55),
	"exiting":    Color(0.85, 0.75, 0.55),
}

var _backdrop: ColorRect
var _title_label: Label
var _sub_label: Label
var _wizard_stage: Control
var _wizard_root: Control
var _hat_spark: ColorRect
var _bubble: PanelContainer
var _bubble_pin: Label
var _bubble_text: RichTextLabel
var _bubble_skip: Button
var _bubble_dots: HBoxContainer
var _bubble_dot_rects: Array[ColorRect] = []

var _current_beat: int = 0
var _typewriter_tween: Tween
var _flicker_tween: Tween
var _float_tween: Tween
var _spark_tween: Tween


## v0.15.11 — group the live intro overlay so Main's Android Back
## handler can detect that the forced first-launch intro owns the
## screen and make Back a no-op (the intro is dismissed via tap / SKIP,
## never Back — and Back must not pop the exit-confirm behind it).
const GROUP_NAME := "peniber_intro"


func _ready() -> void:
	add_to_group(GROUP_NAME)
	layer = 30   # styles.css `z-index: 30` — above coachmark / toast.
	# Block input across the entire viewport while the overlay is up.
	# Backdrop is a fullscreen ColorRect with mouse_filter = STOP so
	# clicks outside the bubble are absorbed (not the dismiss target).
	_build_backdrop()
	_build_title()
	_build_wizard()
	_build_bubble()
	_render_beat(0)
	_start_flicker_tween()
	_start_float_tween()
	_start_spark_tween()


## Public entry point. Main calls this after the autoloads have loaded
## (so TutorialState's persisted state is current). Returns true if
## the overlay was shown, false if the player has already seen it.
##
## Static method: caller doesn't need to instantiate the scene first
## (we do that inside the function only if the gate is open).
static func show_intro_if_unseen(parent: Node) -> bool:
	if not TutorialState.should_show(TutorialState.STEP_PENIBER_INTRO_SHOWN):
		return false
	var scene := preload("res://game/scenes/ui/peniber_intro_overlay.tscn")
	var overlay = scene.instantiate()
	parent.add_child(overlay)
	overlay.intro_dismissed.connect(func() -> void:
		TutorialState.mark_seen(TutorialState.STEP_PENIBER_INTRO_SHOWN)
		overlay.queue_free())
	return true


func _build_backdrop() -> void:
	# Wrapper Control fills the viewport.
	var wrapper := Control.new()
	wrapper.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrapper.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(wrapper)
	_backdrop = ColorRect.new()
	# styles.css: `radial-gradient(... rgba(95,211,194,0.15) ...),
	# rgba(7,5,15,0.92)`. Flat tint suffices for v0.15.4; a shader-
	# painted radial glow is 14g polish.
	_backdrop.color = Color(0.027, 0.020, 0.059, 0.92)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	wrapper.add_child(_backdrop)


func _build_title() -> void:
	# Title block anchored top, centered horizontally. styles.css
	# positions at `top: 80px`; we approximate via offset_top.
	var palette: Dictionary = _DUSK.active()
	var title_box := VBoxContainer.new()
	title_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title_box.offset_top = 80.0
	title_box.add_theme_constant_override("separation", 4)
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_box)

	_title_label = Label.new()
	_title_label.theme_type_variation = "DisplayHeading"   # Press Start 2P 18 px
	_title_label.text = "IDLE BEASTS"
	_title_label.add_theme_color_override("font_color", palette["gold"])
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Drop-shadow approximation. styles.css uses `text-shadow: 2px 2px 0 #000`
	# + `0 0 24px rgba(245,196,107,0.4)`. Godot Label exposes a font
	# shadow color/offset via theme overrides — use these for the hard
	# 2-px shadow; the soft gold glow is shipped as a 14g polish item.
	_title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	_title_label.add_theme_constant_override("shadow_offset_x", 2)
	_title_label.add_theme_constant_override("shadow_offset_y", 2)
	title_box.add_child(_title_label)

	_sub_label = Label.new()
	_sub_label.theme_type_variation = "UiCaption"   # Silkscreen 9 px
	_sub_label.text = "T H E   A W A K E N I N G"   # letter-spaced via spaces
	_sub_label.add_theme_color_override("font_color", palette["ink_dim"])
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_child(_sub_label)


## Builds the wizard "stand-in" stage. styles.css `.pen-stage` is a
## composite of CSS gradients + clip-path polygons; we render close-
## enough geometry via Panels + ColorRects. Real pixel-art Peniber is
## a separate art commission per PHASED_RESKIN_PLAN.md.
func _build_wizard() -> void:
	var palette: Dictionary = _DUSK.active()
	# Stage sized 120×160 per styles.css `.pen-stage`.
	_wizard_stage = Control.new()
	_wizard_stage.set_anchors_preset(Control.PRESET_CENTER)
	_wizard_stage.custom_minimum_size = Vector2(120, 160)
	_wizard_stage.size = Vector2(120, 160)
	_wizard_stage.position = Vector2(-60, -120)   # offset from center; bubble sits below
	_wizard_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wizard_stage)

	_wizard_root = Control.new()
	# 88×132 root per styles.css. Bottom-anchored; horizontal-center.
	_wizard_root.size = Vector2(88, 132)
	_wizard_root.position = Vector2((120 - 88) / 2.0, 160 - 132)
	_wizard_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wizard_stage.add_child(_wizard_root)

	# Robe — bottom 70 px, purple gradient stand-in (flat Dusk card_2).
	# Real CSS uses `clip-path: polygon(20% 0, 80% 0, 100% 100%, 0 100%)`.
	# In Godot we approximate via a trapezoid-shaped Panel; a real clip
	# is 14g polish.
	var robe := Panel.new()
	robe.position = Vector2(0, 132 - 70)
	robe.size = Vector2(88, 70)
	var robe_sb := StyleBoxFlat.new()
	robe_sb.bg_color = Color("#3a1f60")
	robe_sb.border_color = palette["border"]
	robe_sb.set_border_width_all(2)
	robe_sb.set_corner_radius_all(0)
	robe.add_theme_stylebox_override("panel", robe_sb)
	_wizard_root.add_child(robe)

	# Head — 32×32 skin-tone square, centered above the robe.
	var head := Panel.new()
	head.position = Vector2((88 - 32) / 2.0, 38)
	head.size = Vector2(32, 32)
	var head_sb := StyleBoxFlat.new()
	head_sb.bg_color = Color("#ffd9b4")
	head_sb.border_color = Color("#8a5a3a")
	head_sb.set_border_width_all(2)
	head_sb.set_corner_radius_all(0)
	head.add_theme_stylebox_override("panel", head_sb)
	_wizard_root.add_child(head)

	# Eyes — two 4×4 black squares on top of the head. ColorRects so
	# we don't pay theme overhead for tiny props.
	var eye_l := ColorRect.new()
	eye_l.color = Color.BLACK
	eye_l.size = Vector2(4, 4)
	eye_l.position = Vector2(8, 10)
	head.add_child(eye_l)
	var eye_r := ColorRect.new()
	eye_r.color = Color.BLACK
	eye_r.size = Vector2(4, 4)
	eye_r.position = Vector2(20, 10)
	head.add_child(eye_r)

	# Hat — large triangle. CSS uses border-* tricks; the simplest
	# Godot equivalent is a Polygon2D, but we'd lose the Control layout.
	# Approximate with a Panel that has all the proportion + colour,
	# and accept the rectangular silhouette in v0.15.4.
	var hat := Panel.new()
	hat.position = Vector2((88 - 36) / 2.0, 0)
	hat.size = Vector2(36, 38)
	var hat_sb := StyleBoxFlat.new()
	hat_sb.bg_color = Color("#4a2a78")
	hat_sb.set_corner_radius_all(0)
	hat.add_theme_stylebox_override("panel", hat_sb)
	_wizard_root.add_child(hat)

	# Hat spark — 8×8 gold square that pulses via _spark_tween.
	_hat_spark = ColorRect.new()
	_hat_spark.color = palette["gold"]
	_hat_spark.size = Vector2(8, 8)
	_hat_spark.position = Vector2(-2, 18)
	hat.add_child(_hat_spark)

	# Beard — small grey trapezoid below head. Flat panel approximation.
	var beard := Panel.new()
	beard.position = Vector2((88 - 36) / 2.0, 60)
	beard.size = Vector2(36, 30)
	var beard_sb := StyleBoxFlat.new()
	beard_sb.bg_color = Color("#e0d8d0")
	beard_sb.set_corner_radius_all(0)
	beard.add_theme_stylebox_override("panel", beard_sb)
	_wizard_root.add_child(beard)


func _build_bubble() -> void:
	var palette: Dictionary = _DUSK.active()
	# Bubble anchored bottom, full width minus 14-px gutter, sits above
	# the bottom edge. styles.css `.pen-bubble` is `width: calc(100% - 28px)`,
	# `margin-bottom: 16px`.
	_bubble = PanelContainer.new()
	_bubble.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bubble.offset_left = 14
	_bubble.offset_right = -14
	_bubble.offset_top = -180
	_bubble.offset_bottom = -40
	_bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = palette["card"]
	sb.border_color = palette["border"]
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 16.0
	sb.content_margin_bottom = 14.0
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 4)
	_bubble.add_theme_stylebox_override("panel", sb)
	add_child(_bubble)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_bubble.add_child(vbox)

	_bubble_text = RichTextLabel.new()
	_bubble_text.theme_type_variation = "BodyIntro"   # VT323 19 px
	_bubble_text.bbcode_enabled = true
	_bubble_text.fit_content = true
	_bubble_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_text.scroll_active = false
	_bubble_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bubble_text.custom_minimum_size = Vector2(0, 76)   # styles.css min-height
	_bubble_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_bubble_text)

	# Controls row: dots (left) + skip (right).
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	vbox.add_child(controls)

	_bubble_dots = HBoxContainer.new()
	_bubble_dots.add_theme_constant_override("separation", 4)
	_bubble_dots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(_bubble_dots)
	# Build one ColorRect per beat. _render_beat() flips the active one
	# to gold and the rest to ink_mute. styles.css: 6×6, square, the
	# active one has a gold glow (boxShadow) which we approximate via
	# the same gold fill — bloom is 14g polish.
	for i in _BEATS.size():
		var dot := ColorRect.new()
		dot.color = palette["ink_mute"]
		dot.custom_minimum_size = Vector2(6, 6)
		_bubble_dots.add_child(dot)
		_bubble_dot_rects.append(dot)

	_bubble_skip = Button.new()
	_bubble_skip.text = "SKIP"
	_bubble_skip.theme_type_variation = "UiCaption"
	_bubble_skip.add_theme_color_override("font_color", palette["ink_mute"])
	_bubble_skip.flat = true
	# styles.css `.skip` is small (padding 6/8), but on mobile the
	# 58-dp tap-target floor (UiScale.tap_target) takes precedence —
	# without this, test_tap_targets fails the intro overlay's only
	# real interactive element.
	_bubble_skip.custom_minimum_size = Vector2(UiScale.tap_target() + 12, UiScale.tap_target())
	_bubble_skip.pressed.connect(_on_skip_pressed)
	controls.add_child(_bubble_skip)

	# Gold "PENIBER" pin — sits at the top-left of the bubble (overlay
	# anchor). styles.css uses `position: absolute; top: -8px; left:14px`.
	# We anchor it via the bubble's own coordinate space; a separate
	# child of the overlay (not the bubble) so the pin can extend past
	# the bubble's content margin.
	_bubble_pin = Label.new()
	_bubble_pin.theme_type_variation = "DisplaySmall"   # Press Start 2P 10 px
	_bubble_pin.text = "PENIBER"
	_bubble_pin.add_theme_color_override("font_color", Color("#2b1a05"))   # dark ink on gold
	var pin_sb := StyleBoxFlat.new()
	pin_sb.bg_color = palette["gold"]
	pin_sb.border_color = palette["gold_dark"]
	pin_sb.set_border_width_all(2)
	pin_sb.set_corner_radius_all(0)
	pin_sb.content_margin_left = 6.0
	pin_sb.content_margin_right = 6.0
	pin_sb.content_margin_top = 2.0
	pin_sb.content_margin_bottom = 2.0
	# Labels don't render a stylebox bg by default; wrap in a Panel.
	var pin_panel := PanelContainer.new()
	pin_panel.add_theme_stylebox_override("panel", pin_sb)
	pin_panel.add_child(_bubble_pin)
	pin_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	# Position the pin slightly above the bubble top, indented from its
	# left edge.
	pin_panel.position = _bubble.position + Vector2(28, -8)
	pin_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pin_panel)

	# Bubble tap → advance to next beat.
	_bubble.gui_input.connect(_on_bubble_input)


func _render_beat(index: int) -> void:
	if index < 0 or index >= _BEATS.size():
		return
	_current_beat = index
	var beat: Dictionary = _BEATS[index]
	var text: String = String(beat.get("text", ""))
	var mood: String = String(beat.get("mood", "explaining"))

	# Mood tint applies to the pin (only the pin color carries mood;
	# the body text always reads as primary ink to keep legibility).
	var tint: Color = _MOOD_NAME_TINTS.get(mood, _DUSK.active()["gold"])
	if _bubble_pin != null:
		# Subtle: lerp gold toward the mood color rather than overwriting,
		# so the pin still reads as gold first.
		var blended: Color = _DUSK.active()["gold"].lerp(tint, 0.35)
		_bubble_pin.add_theme_color_override("font_color", blended)

	# Update dots.
	var palette: Dictionary = _DUSK.active()
	for i in _bubble_dot_rects.size():
		var dot: ColorRect = _bubble_dot_rects[i]
		dot.color = palette["gold"] if i == index else palette["ink_mute"]

	# Typewriter on body text.
	_bubble_text.text = text
	_bubble_text.visible_characters = 0
	if _typewriter_tween != null and _typewriter_tween.is_running():
		_typewriter_tween.kill()
	var total: int = text.length()
	if total > 0:
		var duration: float = (_TYPE_MS_PER_CHAR * float(total)) / 1000.0
		_typewriter_tween = create_tween()
		_typewriter_tween.tween_property(_bubble_text, "visible_characters", total, duration)


## Tap the bubble to advance — but only after the typewriter finishes.
## A tap during typewriter fast-forwards to the end (skip the type).
func _on_bubble_input(event: InputEvent) -> void:
	var is_tap: bool = false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		is_tap = true
	elif event is InputEventScreenTouch and event.pressed:
		is_tap = true
	if not is_tap:
		return
	# Fast-forward the typewriter if still revealing.
	if _bubble_text.visible_characters < _bubble_text.text.length():
		if _typewriter_tween != null and _typewriter_tween.is_running():
			_typewriter_tween.kill()
		_bubble_text.visible_characters = _bubble_text.text.length()
		return
	# Already finished — advance to next beat or dismiss.
	var next: int = _current_beat + 1
	if next >= _BEATS.size():
		_dismiss()
	else:
		_render_beat(next)


func _on_skip_pressed() -> void:
	_dismiss()


func _dismiss() -> void:
	# Fade out backdrop + bubble in parallel, then emit + free.
	var t: Tween = create_tween()
	t.set_parallel(true)
	t.tween_property(_backdrop, "modulate:a", 0.0, 0.2)
	t.tween_property(_bubble, "modulate:a", 0.0, 0.2)
	t.chain().tween_callback(func() -> void:
		intro_dismissed.emit())


# region — looping animations (flicker / float / spark)

func _start_flicker_tween() -> void:
	# styles.css `title-flicker 4s infinite`: 0/90/100 = 1, 92 = 0.6, 94 = 1.
	# Approximate via a 4-s loop that dips at the 92% mark.
	if _flicker_tween != null and _flicker_tween.is_running():
		_flicker_tween.kill()
	_flicker_tween = create_tween()
	_flicker_tween.set_loops()
	_flicker_tween.tween_property(_title_label, "modulate:a", 1.0, 3.68)
	_flicker_tween.tween_property(_title_label, "modulate:a", 0.6, 0.08)
	_flicker_tween.tween_property(_title_label, "modulate:a", 1.0, 0.24)


func _start_float_tween() -> void:
	if _float_tween != null and _float_tween.is_running():
		_float_tween.kill()
	_float_tween = create_tween()
	_float_tween.set_loops()
	_float_tween.set_ease(Tween.EASE_IN_OUT)
	_float_tween.set_trans(Tween.TRANS_SINE)
	var base_y: float = _wizard_root.position.y
	_float_tween.tween_property(_wizard_root, "position:y",
			base_y - _WIZARD_FLOAT_AMPLITUDE, _WIZARD_FLOAT_PERIOD * 0.5)
	_float_tween.tween_property(_wizard_root, "position:y",
			base_y, _WIZARD_FLOAT_PERIOD * 0.5)


func _start_spark_tween() -> void:
	if _spark_tween != null and _spark_tween.is_running():
		_spark_tween.kill()
	_spark_tween = create_tween()
	_spark_tween.set_loops()
	_spark_tween.set_trans(Tween.TRANS_SINE)
	# styles.css spark-spin: 0/100 = scale 1 + opacity 1; 50 = scale 0.7 + opacity 0.4.
	_spark_tween.tween_property(_hat_spark, "scale", Vector2(0.7, 0.7), _SPARK_PERIOD * 0.5)
	_spark_tween.parallel().tween_property(_hat_spark, "modulate:a", 0.4, _SPARK_PERIOD * 0.5)
	_spark_tween.tween_property(_hat_spark, "scale", Vector2.ONE, _SPARK_PERIOD * 0.5)
	_spark_tween.parallel().tween_property(_hat_spark, "modulate:a", 1.0, _SPARK_PERIOD * 0.5)

# endregion
