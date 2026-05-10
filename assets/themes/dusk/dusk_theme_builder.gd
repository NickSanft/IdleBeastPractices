## Phase 14 — programmatic builder for the Dusk pixel-RPG theme.
##
## A pure function: feed it a `palette` dict from `PaletteDusk` plus
## the three FontFile resources, get back a fully-populated `Theme`.
## All three palettes (Amethyst / Twilight / Ember) are built from
## the same tokens, so adding a new palette is a one-line change in
## `tools/build_dusk_themes.gd`.
##
## Source of truth for sizes / colors / margins:
##   - docs/design_handoff_theming/README.md (Design Tokens table)
##   - docs/design_handoff_theming/reference_files/styles.css (component blocks)
##
## When you tune a value here, mirror the change in styles.css so the
## handoff docs stay accurate.
##
## Theme structure:
##
##   Defaults:
##     default_font      — Silkscreen 400 (UI font)
##     default_font_size — 11 (button / label baseline)
##
##   Control class entries (every Control under the Window theme inherits these):
##     Panel       — pixel-card stylebox (card bg, 2-px border, inset shadow + drop)
##     PanelContainer — same panel stylebox
##     Button       — chunky pixel button (card_2 bg, 2-px border, 3-px drop)
##     CheckBox + OptionButton — same as Button (Phase 13d theme parity)
##     Label        — ink color via theme color
##     ProgressBar  — bg = inset black, fg = teal/magenta gradient (single color
##                    here; gradient is applied per-instance via texture progress)
##
##   Type variations (selected via `Control.theme_type_variation`):
##     "DisplayHeading"   — Press Start 2P 18 gold (catch screen title)
##     "DisplaySmall"     — Press Start 2P 10 gold (Peniber name, currency glyph)
##     "UiTiny"           — Silkscreen 7 ink_mute (currency lbl, vignette)
##     "UiCaption"        — Silkscreen 9 ink_dim (tier %, tab labels)
##     "BodyText"         — VT323 18 ink (Peniber dialog body)
##     "BodyIntro"        — VT323 19 ink (Peniber intro overlay)
##     "PixelButtonGold"  — gold-bg variant of Button for primary CTAs
class_name DuskThemeBuilder
extends RefCounted


# Sizes from the README's Typography table + styles.css. Keep these
# as named constants so a future tune (e.g. "make body text bigger
# for older players") is one number, not a sweep.
const SIZE_DEFAULT_BODY_PX := 11        # Silkscreen, button baseline
const SIZE_DISPLAY_HEADING := 18        # Press Start 2P, catch title
const SIZE_DISPLAY_SMALL := 10          # Press Start 2P, name labels
const SIZE_UI_TINY := 7                 # Silkscreen, currency lbl
const SIZE_UI_CAPTION := 9              # Silkscreen, tab label
const SIZE_BODY_TEXT := 18              # VT323, peniber dialog
const SIZE_BODY_INTRO := 19             # VT323, peniber intro

# Margins in design dp. styles.css uses 10–14 px content padding for
# cards and 10×14 for buttons. Choosing the upper bound for
# tappability (Phase 13d's 58-dp tap target floor still applies).
const CARD_MARGIN_LR := 14
const CARD_MARGIN_TB := 12
const BTN_MARGIN_LR := 14
const BTN_MARGIN_TB := 10
const BORDER_WIDTH := 2

# styles.css `box-shadow: 0 4px 0 0 #00000080` (cards) and
# `0 3px 0 0 #00000080` (buttons). StyleBoxFlat shadow_size is the
# blur radius — we want a hard-edged offset block, so blur is 0 and
# offset.y carries the height.
const CARD_DROP_OFFSET := Vector2(0, 4)
const BTN_DROP_OFFSET := Vector2(0, 3)


## Build the full Theme. `palette` is one of `PaletteDusk.amethyst()`
## / `.twilight()` / `.ember()`. Fonts are passed in (rather than
## loaded inside) so the builder runs both in-editor (where load()
## would block on resource imports) and at runtime (where preloads
## work). The runner script wires the load.
static func build(
		palette: Dictionary,
		display_font: FontFile,
		ui_font: FontFile,
		body_font: FontFile) -> Theme:
	var t := Theme.new()
	t.default_font = ui_font
	t.default_font_size = SIZE_DEFAULT_BODY_PX

	# Default ink color for Labels via Control.font_color override.
	t.set_color("font_color", "Label", palette["ink"])

	_apply_panel_styleboxes(t, palette)
	_apply_button_styleboxes(t, palette)
	_apply_progress_bar(t, palette)
	_apply_type_variations(t, palette, display_font, ui_font, body_font)
	return t


# region — control classes

static func _apply_panel_styleboxes(t: Theme, palette: Dictionary) -> void:
	# Panel + PanelContainer share the same chrome — a "pixel-card":
	# `card` background, 2-px `border` outline, hard 4-px drop, inset
	# 2-px black tint via shadow_color (no separate inset stylebox in
	# Godot — we approximate with shadow_offset + shadow_color).
	var sb := _pixel_card(palette)
	t.set_stylebox("panel", "Panel", sb)
	t.set_stylebox("panel", "PanelContainer", sb)


static func _apply_button_styleboxes(t: Theme, palette: Dictionary) -> void:
	# Default Button: card_2 background (the inner-highlight tier),
	# 2-px border, 3-px drop. Matches `.pixel-btn` in styles.css.
	# Hover bumps to slightly brighter card_2; pressed flattens the
	# drop to 1 px to mimic the styles.css `transform: translateY(2px)`.
	var btn_normal := _pixel_button(palette, palette["card_2"], palette["border"], BTN_DROP_OFFSET)
	var btn_hover := _pixel_button(palette, palette["card_2"].lightened(0.06), palette["border"], BTN_DROP_OFFSET)
	var btn_pressed := _pixel_button(palette, palette["card_2"], palette["border"], Vector2(0, 1))
	var btn_disabled := _pixel_button(palette, palette["card"].darkened(0.2), palette["border_soft"], BTN_DROP_OFFSET)
	btn_disabled.bg_color.a = 0.5

	for cls in ["Button", "CheckBox", "OptionButton"]:
		t.set_stylebox("normal", cls, btn_normal)
		t.set_stylebox("hover", cls, btn_hover)
		t.set_stylebox("pressed", cls, btn_pressed)
		t.set_stylebox("disabled", cls, btn_disabled)
		t.set_color("font_color", cls, palette["ink"])
		t.set_color("font_hover_color", cls, palette["ink"])
		t.set_color("font_pressed_color", cls, palette["ink"])
		t.set_color("font_disabled_color", cls, palette["ink_mute"])


static func _apply_progress_bar(t: Theme, palette: Dictionary) -> void:
	# Background = inset black with `border_soft` 1-px border,
	# matching `.tier-ribbon .progress` and `.autonet .bar`.
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	bg.border_color = palette["border_soft"]
	bg.set_border_width_all(1)
	bg.content_margin_left = 0
	bg.content_margin_top = 0
	bg.content_margin_right = 0
	bg.content_margin_bottom = 0
	t.set_stylebox("background", "ProgressBar", bg)

	# Foreground = teal solid (per-instance code can override with a
	# gradient texture for the tier ribbon's teal→magenta look).
	var fg := StyleBoxFlat.new()
	fg.bg_color = palette["teal"]
	t.set_stylebox("fill", "ProgressBar", fg)
	t.set_color("font_color", "ProgressBar", palette["ink_dim"])

# endregion


# region — type variations

static func _apply_type_variations(
		t: Theme,
		palette: Dictionary,
		display_font: FontFile,
		ui_font: FontFile,
		body_font: FontFile) -> void:
	# DisplayHeading — gold pixel title (catch-screen header, intro title).
	t.set_type_variation("DisplayHeading", "Label")
	t.set_font("font", "DisplayHeading", display_font)
	t.set_font_size("font_size", "DisplayHeading", SIZE_DISPLAY_HEADING)
	t.set_color("font_color", "DisplayHeading", palette["gold"])

	# DisplaySmall — Press Start 2P at 10 px (Peniber name, currency glyph).
	t.set_type_variation("DisplaySmall", "Label")
	t.set_font("font", "DisplaySmall", display_font)
	t.set_font_size("font_size", "DisplaySmall", SIZE_DISPLAY_SMALL)
	t.set_color("font_color", "DisplaySmall", palette["gold"])

	# UiTiny — Silkscreen 7, currency lbl / vignette.
	t.set_type_variation("UiTiny", "Label")
	t.set_font("font", "UiTiny", ui_font)
	t.set_font_size("font_size", "UiTiny", SIZE_UI_TINY)
	t.set_color("font_color", "UiTiny", palette["ink_mute"])

	# UiCaption — Silkscreen 9, tier %, tab labels.
	t.set_type_variation("UiCaption", "Label")
	t.set_font("font", "UiCaption", ui_font)
	t.set_font_size("font_size", "UiCaption", SIZE_UI_CAPTION)
	t.set_color("font_color", "UiCaption", palette["ink_dim"])

	# BodyText — VT323 18 (Peniber dialog).
	t.set_type_variation("BodyText", "Label")
	t.set_font("font", "BodyText", body_font)
	t.set_font_size("font_size", "BodyText", SIZE_BODY_TEXT)
	t.set_color("font_color", "BodyText", palette["ink"])

	# BodyIntro — VT323 19 (Peniber intro overlay; one-pixel bigger
	# than the in-game body for visual emphasis).
	t.set_type_variation("BodyIntro", "Label")
	t.set_font("font", "BodyIntro", body_font)
	t.set_font_size("font_size", "BodyIntro", SIZE_BODY_INTRO)
	t.set_color("font_color", "BodyIntro", palette["ink"])

	# Same family for RichTextLabel so Peniber's caret-suffixed dialog
	# can use BBCode without losing the VT323 face.
	t.set_type_variation("BodyTextRich", "RichTextLabel")
	t.set_font("normal_font", "BodyTextRich", body_font)
	t.set_font_size("normal_font_size", "BodyTextRich", SIZE_BODY_TEXT)
	t.set_color("default_color", "BodyTextRich", palette["ink"])

	# PixelButtonGold — gold CTA per styles.css `.pixel-btn--gold`.
	# Same chunky chrome but gold bg + dark-brown ink. Used by
	# upgrades/CTAs.
	var gold_normal := _pixel_button(palette, palette["gold"], palette["gold_dark"], BTN_DROP_OFFSET)
	var gold_hover := _pixel_button(palette, palette["gold"].lightened(0.05), palette["gold_dark"], BTN_DROP_OFFSET)
	var gold_pressed := _pixel_button(palette, palette["gold"], palette["gold_dark"], Vector2(0, 1))
	t.set_type_variation("PixelButtonGold", "Button")
	t.set_stylebox("normal", "PixelButtonGold", gold_normal)
	t.set_stylebox("hover", "PixelButtonGold", gold_hover)
	t.set_stylebox("pressed", "PixelButtonGold", gold_pressed)
	t.set_color("font_color", "PixelButtonGold", Color("#2b1a05"))
	t.set_color("font_hover_color", "PixelButtonGold", Color("#2b1a05"))
	t.set_color("font_pressed_color", "PixelButtonGold", Color("#2b1a05"))

# endregion


# region — stylebox factories

## Build the canonical pixel-card stylebox. Used for Panel /
## PanelContainer + as the seed for the inset gold-bracketed card
## variation that lands in Phase 14b.
static func _pixel_card(palette: Dictionary) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = palette["card"]
	sb.border_color = palette["border"]
	sb.set_border_width_all(BORDER_WIDTH)
	# Square corners — README is explicit. Set every radius to 0 in
	# case Godot's defaults change.
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	sb.content_margin_left = float(CARD_MARGIN_LR)
	sb.content_margin_right = float(CARD_MARGIN_LR)
	sb.content_margin_top = float(CARD_MARGIN_TB)
	sb.content_margin_bottom = float(CARD_MARGIN_TB)
	# styles.css `box-shadow: 0 4px 0 0 rgba(0,0,0,0.6)` — hard,
	# unblurred. Shadow_size = 0 keeps it crisp; shadow_offset.y = 4
	# is the chunky drop. shadow_color is the inset-tinted version
	# (40% black) blended over the drop direction.
	sb.shadow_color = PaletteDusk.shadow_color()
	sb.shadow_size = 0
	sb.shadow_offset = CARD_DROP_OFFSET
	return sb


## Build a chunky pixel button. Bg + border + drop are parameterised
## so the gold CTA, normal/hover/pressed variants, and disabled
## variants share one factory.
static func _pixel_button(
		_palette: Dictionary,
		bg: Color,
		border_color: Color,
		drop_offset: Vector2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border_color
	sb.set_border_width_all(BORDER_WIDTH)
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	sb.content_margin_left = float(BTN_MARGIN_LR)
	sb.content_margin_right = float(BTN_MARGIN_LR)
	sb.content_margin_top = float(BTN_MARGIN_TB)
	sb.content_margin_bottom = float(BTN_MARGIN_TB)
	sb.shadow_color = PaletteDusk.shadow_color()
	sb.shadow_size = 0
	sb.shadow_offset = drop_offset
	return sb

# endregion
