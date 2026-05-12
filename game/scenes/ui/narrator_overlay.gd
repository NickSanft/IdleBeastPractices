## Phase 14e — Dusk Peniber dialog ribbon (formerly narrator_overlay).
##
## Reskinned per `docs/design_handoff_theming/reference_files/styles.css`
## `.peniber` block. Bottom-anchored ribbon with:
##
##   ┌──┬──────────────────────┬─────┐
##   │🧙│ PENIBER · just now   │  ×  │  ← pen-head row
##   ├──┴──────────────────────┴─────┤
##   │ He typewrites his line in     │  ← body (VT323 BodyText)
##   │ VT323 with a blinking gold    │
##   │ caret at the end.           ▌ │
##   └────────────────────────────────┘
##
## Stylesheet contract (styles.css `.peniber`):
##   - bg = `--card`, border = 2-px `--border`, square corners
##   - position: bottom safe-area + 12-px gap above tab bar
##   - name: Press Start 2P 10-px gold (DisplaySmall variation)
##   - timestamp: Silkscreen 8-px ink-mute (UiTiny)
##   - body: VT323 17-px ink (BodyText)
##   - caret: 6×14-px gold block, blink at 600 ms
##   - intro animation: 280-ms slide-up (translateY: 8px→0) + fade
##
## Public API (preserved):
##   - subscribes to EventBus.narrator_line_chosen and shows the line
##   - tap anywhere on the ribbon to dismiss early
##   - hides after VISIBLE_SECONDS
##
## Mouse-filter contract (kept from v0.8.8): the wrapper Control is
## always IGNORE so background taps fall through. The bubble itself
## flips between STOP (during display, so a tap dismisses) and IGNORE
## (during fade-out / hidden, so battle/catch buttons stay tappable).
extends Control

const _DUSK := preload("res://assets/themes/dusk/palette_dusk.gd")
## Phase 14h — gold L-bracket corner trim per styles.css `.pixel-card::before`.
const _GOLD_BRACKETS := preload("res://game/scenes/ui/gold_brackets.gd")

const VISIBLE_SECONDS := 8.0
const FADE_SECONDS := 0.25
## styles.css: `peniber-in 280ms ease-out` slides up 8 px and fades in.
const _SLIDE_DISTANCE_PX := 8.0
const _SLIDE_DURATION := 0.28
## styles.css: `blink 600ms steps(2) infinite` — 50% opacity, square step.
const _CARET_BLINK_MS := 600
## styles.css: typewriter cadence — 18 ms/char during gameplay (faster
## than the 22 ms/char intro overlay so an idle bark isn't sluggish).
const _TYPE_MS_PER_CHAR := 18.0

# Mood-tint compat layer. Phase-pre-14e used these to recolor the whole
# bubble; the Dusk handoff uses one stable `card` bg. We keep the keys
# so the Narrator autoload's existing emit shape still works, but tint
# only the name label slightly — mood is conveyed by text + word
# choice, not bubble color.
const _MOOD_NAME_TINTS := {
	"smug":        Color(1.00, 0.85, 0.50),   # gold (default)
	"begrudging":  Color(0.95, 0.78, 0.45),
	"reverent":    Color(1.00, 0.90, 0.60),
	"weary":       Color(0.85, 0.78, 0.55),
	"exasperated": Color(0.95, 0.60, 0.55),
	"explaining":  Color(0.95, 0.85, 0.55),
	"dry":         Color(0.80, 0.75, 0.55),
	"exiting":     Color(0.85, 0.75, 0.55),
}

var _bubble: PanelContainer
var _portrait: Control
var _name_label: Label
var _timestamp_label: Label
var _text_label: RichTextLabel
## Caret is a 6×14 filled gold `ColorRect` rather than a Label —
## styles.css `.peniber .caret` is a filled block (`background:
## var(--gold)`), not a glyph. Using ColorRect renders correctly
## without forcing a text-shaping pass per blink-toggle.
var _caret_label: ColorRect
var _hide_timer: Timer
var _current_tween: Tween
var _typewriter_tween: Tween
var _caret_blink_tween: Tween
var _full_text: String = ""
## Tracks "X seconds ago" for the timestamp label. Re-rendered on
## each show() and again if the same line stays visible long enough
## to tick past one minute (which it generally doesn't — VISIBLE_SECONDS
## is 8 s — but the field reads "just now" to match the handoff).
var _last_shown_unix_ms: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	custom_minimum_size = Vector2(0, 140)
	# Tuck against the bottom with a small inset so it sits above the tab bar.
	# styles.css: `bottom: calc(var(--tab-h) + 12px)`. Our tab bar lives
	# inside the orientation root so we use a slightly smaller offset
	# than the previous era — the bottom-nav row is ~64 px (DeviceLayout
	# tab_h) + 12 px gap.
	offset_top = -180
	offset_bottom = -76
	offset_left = 14
	offset_right = -14

	_build_bubble()
	_build_hide_timer()

	# Start invisible (modulate.a = 0). _show() runs the slide-up + fade.
	_bubble.modulate = Color(1, 1, 1, 0)
	_bubble.position.y = _SLIDE_DISTANCE_PX

	EventBus.narrator_line_chosen.connect(_on_narrator_line_chosen)
	# Phase 14h — repaint the bubble's stylebox + labels when the
	# player swaps palette in Settings. Bubble bg / border / name gold /
	# timestamp ink / caret gold all read from PaletteDusk.active().
	Settings.theme_changed.connect(_on_theme_changed)


## Phase 14h — Settings.theme_changed handler. Rebuilds the bubble
## stylebox + retints labels with the new palette tokens. Cheaper
## than rebuilding the whole bubble since the layout doesn't change.
func _on_theme_changed() -> void:
	if _bubble == null:
		return
	var palette: Dictionary = _DUSK.active()
	var sb: StyleBoxFlat = _bubble.get_theme_stylebox("panel")
	if sb != null:
		var new_sb: StyleBoxFlat = sb.duplicate()
		new_sb.bg_color = palette["card"]
		new_sb.border_color = palette["border"]
		_bubble.add_theme_stylebox_override("panel", new_sb)
	if _name_label != null:
		_name_label.add_theme_color_override("font_color", palette["gold"])
	if _timestamp_label != null:
		_timestamp_label.add_theme_color_override("font_color", palette["ink_mute"])
	if _caret_label != null:
		_caret_label.color = palette["gold"]
	# Repaint the portrait's stylebox (purple bg + gold border).
	if _portrait != null:
		var port_sb: StyleBoxFlat = _portrait.get_theme_stylebox("panel")
		if port_sb != null:
			var new_port_sb: StyleBoxFlat = port_sb.duplicate()
			new_port_sb.border_color = palette["gold"]
			_portrait.add_theme_stylebox_override("panel", new_port_sb)


## Build the bubble + pen-head row + body text. Single _ready-time
## construction; subsequent `_show` calls just retarget labels.
func _build_bubble() -> void:
	var palette: Dictionary = _DUSK.active()

	_bubble = PanelContainer.new()
	_bubble.set_anchors_preset(Control.PRESET_FULL_RECT)
	# v0.8.8: gate STOP on visibility. _show() flips to STOP so a tap
	# dismisses; _hide() flips back to IGNORE once the fade completes.
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Override the default theme Panel stylebox with the .peniber chrome.
	# styles.css: bg `--card`, 2-px `--border`, hard 4-px black shadow
	# below + 1-px inner shadow. The shadow is part of the Dusk theme's
	# default Panel stylebox already; we adjust bg / border / padding.
	var sb := StyleBoxFlat.new()
	sb.bg_color = palette["card"]
	sb.border_color = palette["border"]
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 12.0
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 4)
	_bubble.add_theme_stylebox_override("panel", sb)
	add_child(_bubble)
	# Phase 14h — gold L-brackets on the Peniber bubble. Added as a
	# child of the bubble (not the wrapper) so the corners track the
	# bubble's slide-up + fade-in animation. mouse_filter = IGNORE on
	# the brackets keeps the bubble's tap-to-dismiss path intact.
	var brackets: Control = _GOLD_BRACKETS.new()
	_bubble.add_child(brackets)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_child(vbox)

	# pen-head row: portrait + name + timestamp.
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 8)
	head_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(head_row)

	# Portrait — 28×28 wizard stand-in per styles.css `.peniber .portrait`.
	# Real pixel-art portrait is a separate art pass; for v0.15.4 we use a
	# stylized geometric Control (purple gradient bg + gold border) that
	# matches the handoff's intent.
	_portrait = _build_portrait()
	head_row.add_child(_portrait)

	_name_label = Label.new()
	_name_label.theme_type_variation = "DisplaySmall"   # Press Start 2P 10 px
	_name_label.text = "PENIBER"
	_name_label.add_theme_color_override("font_color", palette["gold"])
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_row.add_child(_name_label)

	_timestamp_label = Label.new()
	_timestamp_label.theme_type_variation = "UiTiny"   # Silkscreen 7 px
	_timestamp_label.text = "just now"
	_timestamp_label.add_theme_color_override("font_color", palette["ink_mute"])
	_timestamp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_row.add_child(_timestamp_label)

	# Body row: VT323 RichTextLabel with bbcode + a caret block to its right.
	var body_row := HBoxContainer.new()
	body_row.add_theme_constant_override("separation", 2)
	body_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(body_row)

	_text_label = RichTextLabel.new()
	_text_label.theme_type_variation = "BodyText"   # VT323 18 px
	_text_label.bbcode_enabled = true
	_text_label.fit_content = true
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.scroll_active = false
	_text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body_row.add_child(_text_label)

	# Caret block — 6×14 px gold square, sits flush-right with the body.
	# styles.css `.peniber .caret`: 6×14, `background: var(--gold)`,
	# `blink 600ms steps(2) infinite` (square step, 50 % opacity gate).
	_caret_label = ColorRect.new()
	_caret_label.color = palette["gold"]
	_caret_label.custom_minimum_size = Vector2(6, 14)
	_caret_label.size_flags_vertical = Control.SIZE_SHRINK_END
	_caret_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body_row.add_child(_caret_label)
	_caret_label.visible = false   # hidden until first line


## Build the 28×28 portrait — styles.css `.peniber .portrait` is a
## composite of CSS pseudo-elements (gradient bg + hat + eyes). In
## Godot we approximate with a `PanelContainer` carrying a Dusk-purple
## bg + 2-px gold border. The "real wizard sprite" is a separate art
## pass tracked in PHASED_RESKIN_PLAN.md as out-of-scope for Phase 14.
func _build_portrait() -> Control:
	var palette: Dictionary = _DUSK.active()
	var portrait := PanelContainer.new()
	portrait.custom_minimum_size = Vector2(28, 28)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	# Approximate the radial gradient `circle at 50% 35%, #ffd9b4 4px,
	# transparent 4px` + the purple wizard-robe gradient with a flat
	# Dusk-purple base. The gold border (styles.css explicit) ties the
	# portrait to the name label's gold.
	sb.bg_color = Color("#3a1f60")
	sb.border_color = palette["gold"]
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(0)
	portrait.add_theme_stylebox_override("panel", sb)
	return portrait


func _build_hide_timer() -> void:
	_hide_timer = Timer.new()
	_hide_timer.one_shot = true
	_hide_timer.wait_time = VISIBLE_SECONDS
	_hide_timer.timeout.connect(_hide)
	add_child(_hide_timer)
	_bubble.gui_input.connect(_on_bubble_gui_input)


func _on_narrator_line_chosen(_line_id: String, text: String, mood: String) -> void:
	_full_text = text
	# Mood now tints the name only (per styles.css `.name` is always gold,
	# but a subtle mood shift on the gold reads as voice-acting flavor).
	var name_tint: Color = _MOOD_NAME_TINTS.get(mood, _DUSK.active()["gold"])
	_name_label.add_theme_color_override("font_color", name_tint)
	_timestamp_label.text = "just now"
	_last_shown_unix_ms = Time.get_ticks_msec()
	_show()


func _show() -> void:
	if _current_tween != null and _current_tween.is_running():
		_current_tween.kill()
	# Bubble is becoming visible; switch to STOP so a tap dismisses it.
	_bubble.mouse_filter = Control.MOUSE_FILTER_STOP

	# Start the body text empty + the caret visible. Then run the
	# typewriter tween over `visible_characters` so the text reveals
	# character-by-character per styles.css typewriter cadence.
	_text_label.text = _full_text
	_text_label.visible_characters = 0
	_caret_label.visible = true
	_start_caret_blink()

	# 280-ms slide-up + fade-in animation per `peniber-in` keyframes.
	# Initial state was set in _ready (position.y = SLIDE_DISTANCE_PX,
	# modulate.a = 0); animate both back to their resting values.
	var t: Tween = create_tween()
	t.set_parallel(true)
	t.set_ease(Tween.EASE_OUT)
	t.tween_property(_bubble, "modulate:a", 1.0, _SLIDE_DURATION)
	t.tween_property(_bubble, "position:y", 0.0, _SLIDE_DURATION)
	_current_tween = t

	# Typewriter — tween visible_characters from 0 to full length.
	# Duration scales with text length so longer barks reveal at a
	# steady cadence rather than always over 0.5 s.
	if _typewriter_tween != null and _typewriter_tween.is_running():
		_typewriter_tween.kill()
	var total_chars: int = _full_text.length()
	if total_chars > 0:
		var type_duration: float = (_TYPE_MS_PER_CHAR * float(total_chars)) / 1000.0
		_typewriter_tween = create_tween()
		_typewriter_tween.tween_property(_text_label, "visible_characters", total_chars, type_duration)

	_hide_timer.start()


func _start_caret_blink() -> void:
	if _caret_blink_tween != null and _caret_blink_tween.is_running():
		_caret_blink_tween.kill()
	# styles.css uses `steps(2)` so the blink is square (full → off,
	# no fade). Tween `visible` on a 0.3 s interval matches the
	# 600-ms `blink` keyframes (one full toggle cycle = 600 ms).
	_caret_blink_tween = create_tween()
	_caret_blink_tween.set_loops()
	_caret_blink_tween.tween_callback(_toggle_caret).set_delay(0.3)


func _toggle_caret() -> void:
	if _caret_label != null:
		_caret_label.visible = not _caret_label.visible


func _hide() -> void:
	if _current_tween != null and _current_tween.is_running():
		_current_tween.kill()
	if _typewriter_tween != null and _typewriter_tween.is_running():
		_typewriter_tween.kill()
	if _caret_blink_tween != null and _caret_blink_tween.is_running():
		_caret_blink_tween.kill()
	# Slide-down + fade-out — mirrors the slide-up entry. styles.css
	# doesn't spec a custom exit animation, so we reuse `peniber-in`
	# in reverse for symmetry.
	var t: Tween = create_tween()
	t.set_parallel(true)
	t.tween_property(_bubble, "modulate:a", 0.0, FADE_SECONDS)
	t.tween_property(_bubble, "position:y", _SLIDE_DISTANCE_PX, FADE_SECONDS)
	# Once the fade-out completes, flip back to IGNORE so the
	# invisible bubble's rect doesn't keep blocking taps on the
	# Battle / Catch buttons that sit beneath it.
	t.chain().tween_callback(func() -> void:
		_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_caret_label.visible = false)
	_current_tween = t


func _on_bubble_gui_input(event: InputEvent) -> void:
	# Tap the bubble to dismiss early.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_hide_timer.stop()
		_hide()
	elif event is InputEventScreenTouch and event.pressed:
		_hide_timer.stop()
		_hide()
