## Phase 14c — Dusk pixel-RPG currency chip.
##
## Reskinned per `docs/design_handoff_theming/reference_files/styles.css`
## `.currency` block. Replaces the parchment-era texture-based icon
## with a 22×22 colored glyph square + a vertical [lbl, val] stack.
## Three flavors share the same chip; the caller picks colors + glyph:
##
##   GOLD glyph "G" — bg gold       (#f5c46b), ink #2b1a05
##   RP   glyph "R" — bg teal       (#5fd3c2), ink #052420
##   ★    glyph "★" — bg magenta    (#d96fb8), ink #2a0820
##
## Layout (left-to-right):
##
##   ┌──────────┬────────────────┐
##   │ [GLYPH]  │  LBL (7px)     │
##   │  22×22   │  Value (11px)  │
##   └──────────┴────────────────┘
##
## The panel chrome (card bg, 2-px border, hard drop shadow) comes
## from the Dusk theme's `Panel` stylebox — no inline overrides.
## Inline labels use `theme_type_variation` ("UiTiny" for lbl,
## default Silkscreen 11 for val, "DisplaySmall" Press Start 2P
## 10 for the glyph) so font_scale + density still flow through.
##
## Public API preserved from the Phase 10c version:
##   - configure(glyph, accent, label_text, tooltip)  — was (icon, accent, prefix, tooltip)
##   - set_int_value / set_big_value                  — same value-tween semantics
##   - set_progress_fraction                          — gold's next-milestone bar
extends PanelContainer

const _DEFAULT_TWEEN_SEC := 0.4

# Public configuration. Set via configure() before adding to the tree
# (or anytime after — re-applies on the next frame).
var glyph_text: String = "G"
var accent_color: Color = Color("#f5c46b")  # Dusk gold default
var label_text: String = ""
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

var _glyph_panel: PanelContainer
var _glyph_label: Label
var _lbl_label: Label
var _value_label: Label
var _progress: ProgressBar

enum _Kind { NONE, INT, BIG }


func _ready() -> void:
	# Per styles.css: `.hud .currency` flex: 1, padding 6px 8px. The
	# panel stylebox provides bg / border / drop-shadow from the Dusk
	# theme. We set a custom_minimum_size so the chip doesn't collapse
	# when its value happens to be short ("0").
	custom_minimum_size = Vector2(96, 44)
	mouse_filter = Control.MOUSE_FILTER_STOP   # tooltip + future long-press

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(hbox)

	# Glyph cell — 22×22 ColorRect with a centered single-char Label.
	# We use a small inner PanelContainer to layer a 1-px gold_dark
	# border on top of the colored bg per `.currency .glyph` in
	# styles.css (`border: 1px solid var(--gold-dark)` etc.).
	_glyph_panel = PanelContainer.new()
	_glyph_panel.custom_minimum_size = Vector2(22, 22)
	_glyph_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_glyph_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_glyph_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_glyph_panel)
	_apply_glyph_stylebox()

	_glyph_label = Label.new()
	_glyph_label.text = glyph_text
	_glyph_label.theme_type_variation = "DisplaySmall"
	_glyph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glyph_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Glyph ink is dark (matches the bright glyph bg). Per styles.css
	# `.currency .glyph { color: #2b1a05 }`. The "DisplaySmall"
	# variation defaults to gold ink; override here.
	_glyph_label.add_theme_color_override("font_color", Color("#2b1a05"))
	_glyph_panel.add_child(_glyph_label)

	# Stack: 7-px UPPERCASE lbl above the value.
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 2)
	hbox.add_child(stack)

	_lbl_label = Label.new()
	_lbl_label.theme_type_variation = "UiTiny"
	_lbl_label.text = label_text.to_upper()
	_lbl_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_child(_lbl_label)

	_value_label = Label.new()
	# Default theme font + size = Silkscreen 11px per Dusk default.
	_value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(_value_label)

	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 4)
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.value = 0.0
	_progress.max_value = 1.0
	_progress.step = 0.0   # smooth interpolation, not snap
	_progress.visible = false
	stack.add_child(_progress)

	_refresh_label()


## Per-glyph 22×22 stylebox: `accent_color` bg + 1-px darker border.
## Rebuilt on `configure()` so the gold chip can re-tint to gold,
## the RP chip to teal, etc.
func _apply_glyph_stylebox() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent_color
	sb.border_color = accent_color.darkened(0.35)
	sb.set_border_width_all(1)
	# Square corners — handoff is explicit.
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	# Tight content margin so the glyph character has room.
	sb.content_margin_left = 2.0
	sb.content_margin_right = 2.0
	sb.content_margin_top = 2.0
	sb.content_margin_bottom = 2.0
	_glyph_panel.add_theme_stylebox_override("panel", sb)


## One-shot configuration: glyph character, accent color (drives the
## glyph cell's bg), label text (uppercased), and tooltip. Safe to
## call before _ready or any time after.
func configure(p_glyph: String, p_accent: Color, p_label: String, p_tooltip: String = "") -> void:
	glyph_text = p_glyph
	accent_color = p_accent
	label_text = p_label
	tooltip_text = p_tooltip
	if is_inside_tree():
		_glyph_label.text = glyph_text
		_lbl_label.text = label_text.to_upper()
		_apply_glyph_stylebox()
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
			_value_label.text = "%d" % _displayed_int
		_Kind.BIG:
			_value_label.text = "0" if _displayed_big == null else _displayed_big.format()
		_:
			_value_label.text = ""
