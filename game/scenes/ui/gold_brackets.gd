## Phase 14g — Reusable gold L-bracket corners for pixel-cards.
##
## Per styles.css `.pixel-card::before`:
##   8 gold linear-gradient lines, 6×2 + 2×6 at each of 4 corners.
##   inset: -2px (the brackets extend 2 px past the card border so they
##   read as "RPG window" trim rather than internal padding).
##
## Use as a child of any PanelContainer that wants the gold corner
## treatment. Anchors full-rect and renders 8 small ColorRects via
## `_draw` (cheaper than 8 child Controls) — each ColorRect is fixed
## 6×2 or 2×6 px at the corresponding corner.
##
## Reads the gold color from `PaletteDusk.active()` and subscribes to
## `Settings.theme_changed` so a palette swap repaints the brackets.
##
## Mouse-filter: IGNORE (decoration only — taps must fall through to
## the parent card or to whatever sits beneath).
extends Control

const _DUSK := preload("res://assets/themes/dusk/palette_dusk.gd")
const _BRACKET_LEN_PX := 6.0
const _BRACKET_THICKNESS_PX := 2.0
## styles.css `inset: -2px` — brackets extend past the card edge.
const _INSET_PX := 2.0

var _gold: Color


func _ready() -> void:
	# Decoration only — never block input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchor full-rect so the brackets follow the parent's size.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Inset = -2 px so the brackets paint just outside the parent's
	# visible border, per styles.css `.pixel-card::before { inset: -2px }`.
	offset_left = -_INSET_PX
	offset_top = -_INSET_PX
	offset_right = _INSET_PX
	offset_bottom = _INSET_PX
	_gold = _DUSK.active()["gold"]
	Settings.theme_changed.connect(_on_theme_changed)


func _on_theme_changed() -> void:
	_gold = _DUSK.active()["gold"]
	queue_redraw()


## Draw 8 small filled rects — two per corner — forming an L at each
## corner of the parent card.
##
## Layout (TL corner shown, others mirror):
##
##   ┌──────···
##   │  ___
##   │ |   horizontal bracket (6×2 px)
##   │ |__
##   ·    vertical bracket (2×6 px)
##   :
##
## Renders via `draw_rect` inside `_draw` so we don't allocate 8 child
## Controls. The brackets reposition automatically when the parent
## resizes (they're relative to the Control's own rect).
func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	# Top-left
	draw_rect(Rect2(0, 0, _BRACKET_LEN_PX, _BRACKET_THICKNESS_PX), _gold)
	draw_rect(Rect2(0, 0, _BRACKET_THICKNESS_PX, _BRACKET_LEN_PX), _gold)
	# Top-right
	draw_rect(Rect2(w - _BRACKET_LEN_PX, 0, _BRACKET_LEN_PX, _BRACKET_THICKNESS_PX), _gold)
	draw_rect(Rect2(w - _BRACKET_THICKNESS_PX, 0, _BRACKET_THICKNESS_PX, _BRACKET_LEN_PX), _gold)
	# Bottom-left
	draw_rect(Rect2(0, h - _BRACKET_THICKNESS_PX, _BRACKET_LEN_PX, _BRACKET_THICKNESS_PX), _gold)
	draw_rect(Rect2(0, h - _BRACKET_LEN_PX, _BRACKET_THICKNESS_PX, _BRACKET_LEN_PX), _gold)
	# Bottom-right
	draw_rect(Rect2(w - _BRACKET_LEN_PX, h - _BRACKET_THICKNESS_PX,
			_BRACKET_LEN_PX, _BRACKET_THICKNESS_PX), _gold)
	draw_rect(Rect2(w - _BRACKET_THICKNESS_PX, h - _BRACKET_LEN_PX,
			_BRACKET_THICKNESS_PX, _BRACKET_LEN_PX), _gold)


## Convenience factory: instantiate a GoldBrackets and add it as a
## child of `parent`. Returns the brackets Control for fluent setup.
static func add_to(parent: Control) -> Control:
	var script: GDScript = load("res://game/scenes/ui/gold_brackets.gd")
	var brackets: Control = script.new()
	parent.add_child(brackets)
	return brackets
