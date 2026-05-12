## Phase 14g — Dusk gold-bordered toast banner.
##
## Reskinned per `docs/design_handoff_theming/reference_files/styles.css`
## `.toast` block. Replaces the parchment-era panel-with-dark-text
## banner with a Dusk card-on-card with a gold border + gold text +
## hard drop shadow + (deferred) soft gold glow.
##
## styles.css contract:
##   bg: var(--card)
##   border: 2px solid var(--gold)
##   color: var(--gold)
##   font: var(--font-ui) 10 px (with letter-spacing 0.05em)
##   box-shadow: 0 4px 0 #00000080, 0 0 24px rgba(245, 196, 107, 0.3)
##   position: top: 96px (below the currency bar + tier ribbon)
##   animation: toast-in 240ms ease-out, toast-out 240ms ease-in 1.6s forwards
##
## Total visible duration: 240 in + 1600 hold + 240 out = 2080 ms.
## Pre-14g default was 3000 ms (3.0 s); styles.css 1.6 s is tighter
## so toasts read as "secondary beats" and don't crowd the screen
## during rapid-fire prestige/recipe-unlock chains.
##
## Public API preserved: `show_toast(text, duration=2.08)` still works.
## Queue semantics + queue_size() + is_showing() unchanged.
##
## Mood compat: the parchment-era version painted dark text on a light
## bg. The Dusk version inverts to gold-on-card with a gold border.
## Subscribers (achievements, recipe unlocks, milestone catches) keep
## working with no API change.
extends CanvasLayer

const _DUSK := preload("res://assets/themes/dusk/palette_dusk.gd")
const _SHOW_LAYER := 70   # below celebration_overlay (80), above narrator
const _SLIDE_SECS := 0.24   # styles.css 240 ms
const _DEFAULT_DURATION := 1.6   # styles.css `toast-out 240ms ease-in 1.6s forwards`
const _BANNER_Y_OFFSET := 96.0   # styles.css `top: 96px` — clears HUD + tier ribbon
## v0.15.8 — fixed banner width. Pre-fix the toast used
## `grow_horizontal = BOTH + custom_minimum_size.x = 280` which floors
## but doesn't CAP the width; autowrap labels expanded the panel for
## any text longer than ~30 chars. Locking the rect to an exact 280 px
## via anchor offsets means the inner label gets a finite wrap budget.
const _BANNER_WIDTH := 280.0

var _banner: PanelContainer
var _label: Label
var _queue: Array[Dictionary] = []
var _showing: bool = false


func _ready() -> void:
	layer = _SHOW_LAYER
	_build_banner()
	# Phase 14g: subscribe to theme_changed so a Settings palette swap
	# repaints the toast's gold border + card bg without a scene reload.
	Settings.theme_changed.connect(_apply_banner_stylebox)


func _build_banner() -> void:
	# v0.15.8 (popup-size fix): pre-fix used `grow_horizontal = BOTH +
	# custom_minimum_size.x = 280` which floors the banner at 280 px but
	# does NOT cap the width — autowrap labels with no finite parent
	# width expand the panel to fit their longest line of text. Mirrors
	# the celebration-overlay + coachmark bugs.
	#
	# Fix: lock the banner to an exact `_BANNER_WIDTH` (280 px) via
	# offset_left = -140, offset_right = +140 anchored at 0.5/0.5
	# horizontally. The PanelContainer's child Label receives a finite
	# 280 - 24 = 256 px wrap budget, so long toast strings wrap to
	# multiple lines instead of expanding the banner.
	_banner = PanelContainer.new()
	# Anchor to top-center; manual offset_top keeps the slide-in math simple.
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.anchor_top = 0.0
	_banner.anchor_bottom = 0.0
	_banner.offset_left = -_BANNER_WIDTH * 0.5
	_banner.offset_right = _BANNER_WIDTH * 0.5
	# Hidden off-screen above the top edge initially.
	_banner.offset_top = -100.0
	_banner.offset_bottom = -36.0
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)
	_apply_banner_stylebox()

	var margins := MarginContainer.new()
	# styles.css `.toast` padding: 6px 12px. We give it slightly more
	# vertical space so the 58-dp tap-target floor doesn't trip on
	# something the test thinks is tappable (toast isn't interactive,
	# but mouse_filter = IGNORE keeps it out of the tappable sweep).
	margins.add_theme_constant_override("margin_left", 12)
	margins.add_theme_constant_override("margin_right", 12)
	margins.add_theme_constant_override("margin_top", 6)
	margins.add_theme_constant_override("margin_bottom", 6)
	margins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(margins)

	_label = Label.new()
	# styles.css: var(--font-ui) 10 px. UiCaption is Silkscreen 9 px in
	# DuskThemeBuilder; bumping font_size to 11 (post-UiScale) lands
	# close to the styles.css spec while keeping the variation.
	_label.theme_type_variation = &"UiCaption"
	_label.add_theme_font_size_override("font_size", UiScale.size(10))
	_label.add_theme_color_override("font_color", _DUSK.active()["gold"])
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margins.add_child(_label)


## styles.css `.toast`: bg `--card`, 2-px gold border, hard 4-px drop
## shadow + soft 24-px gold glow (Godot can't render soft glow via
## StyleBoxFlat — the hard shadow conveys most of the visual weight).
## Called on _ready + on Settings.theme_changed so palette swaps
## repaint the toast.
func _apply_banner_stylebox() -> void:
	if _banner == null:
		return
	var palette: Dictionary = _DUSK.active()
	var sb := StyleBoxFlat.new()
	sb.bg_color = palette["card"]
	sb.border_color = palette["gold"]
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 4)
	_banner.add_theme_stylebox_override("panel", sb)
	# Also retint the gold text — the label might already exist from
	# a previous build.
	if _label != null:
		_label.add_theme_color_override("font_color", palette["gold"])


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
	# Slide in. styles.css `toast-in` is a 240-ms slide from
	# translateY(-8) → translateY(0) with opacity 0 → 1. Our anchor
	# math fakes the translateY by tweening offset_top from -100 to
	# _BANNER_Y_OFFSET (deeper distance than the 8-px CSS spec — Godot
	# starts fully off-screen, CSS animates from a partially-visible
	# pose). The visual effect ("slides in from above") matches.
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
