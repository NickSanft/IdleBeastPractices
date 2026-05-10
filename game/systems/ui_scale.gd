## Phase 13a — single resolver for design-px font sizes that respect
## the user's accessibility slider.
##
## Replaces 71 hand-coded `add_theme_font_size_override("font_size", N)`
## call sites that bypassed `Settings.font_scale` (the documented
## limitation in main.gd:272). The user's 0.85 / 1.0 / 1.5
## accessibility slider now scales every label, not just themed ones.
##
## Density compensation across mdpi → xxhdpi devices is handled
## ONCE at the engine level by `DeviceLayout._ready` setting
## `Window.content_scale_factor = DeviceLayout.dpi_bucket`. That
## scales every canvas_item uniformly — fonts, panels, margins,
## tap targets — so individual callers don't have to think about
## DPI. (v0.14.3 cleanup: pre-13c.3 this helper also multiplied by
## `dpi_bucket`, which double-scaled fonts now that content_scale_factor
## carries density.)
##
## Usage:
##   label.add_theme_font_size_override("font_size", UiScale.size(16))
##
## Long-lived labels (cards that don't tear down on every refresh)
## should subscribe to `Settings.accessibility_settings_changed` and
## re-apply on signal. Most call sites in this codebase are inside
## `_refresh()` / `_build_layout()` paths that re-run on a relevant
## event already.
class_name UiScale
extends RefCounted


## Returns the rendered px size for a `base_px` design value, after
## applying `Settings.font_scale`. Density (dpi_bucket) is applied
## globally via `Window.content_scale_factor`.
##
## Test-friendly: reads `Settings.font_scale` via the autoload tree
## so tests can stage values via `Settings.set_font_scale()`.
static func size(base_px: int) -> int:
	if base_px <= 0:
		return 1
	var scale: float = _font_scale()
	return int(round(float(base_px) * scale))


## Returns Material's 48-dp tap-target floor in design px. The
## device's content_scale_factor (set by DeviceLayout from dpi_bucket)
## scales this to physical pixels — no per-call density math needed.
## Phase 13d (touch-target sweep) will route every tappable Control
## through this.
static func tap_target() -> int:
	return 48


## Phase 13c.4 — recommended column count for a responsive card grid.
##
## Pass the container's *own* width (usually `size.x`) and the
## minimum acceptable card width in design dp. Returns an integer ≥ 1
## that the caller assigns to `GridContainer.columns`. Wider views
## (landscape, tablet, foldable open) automatically get more columns;
## narrow views (phone portrait) collapse to 1.
##
## Reading the view's own width — instead of the global viewport —
## means callers don't need to compensate for the Phase-13c.2 left
## rail (which makes view width < viewport width in landscape).
##
## Usage:
##   _grid.columns = UiScale.columns(size.x, 320)
static func columns(view_width: float, min_card_width_dp: float) -> int:
	if min_card_width_dp <= 0.0 or view_width <= 0.0:
		return 1
	return max(1, int(view_width / min_card_width_dp))


# Settings is an autoload; access via the tree so unit tests don't
# need to monkey-patch global symbols. Guaranteed loaded by the
# time gameplay code calls UiScale (project.godot orders Settings
# first among autoloads).
static func _font_scale() -> float:
	var s := Engine.get_main_loop()
	if s == null or not (s is SceneTree):
		return 1.0
	var node := (s as SceneTree).root.get_node_or_null("Settings")
	if node == null or not ("font_scale" in node):
		return 1.0
	return float(node.font_scale)
