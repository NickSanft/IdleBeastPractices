## Phase 13a — single resolver for design-px → physical-px font sizes.
##
## Replaces 71 hand-coded `add_theme_font_size_override("font_size", N)`
## call sites that bypassed `Settings.font_scale` (the documented
## limitation in main.gd:272). Combined with `DeviceLayout.dpi_bucket`,
## a `font_size = 16` design value renders at the same physical size
## across mdpi → xxhdpi devices, and the user's 0.85 / 1.0 / 1.5
## accessibility slider scales every label, not just themed ones.
##
## Usage:
##   label.add_theme_font_size_override("font_size", UiScale.size(16))
##
## Long-lived labels (cards that don't tear down on every refresh)
## should subscribe to `Settings.accessibility_settings_changed` AND
## `DeviceLayout.layout_changed` and re-apply on signal. Most call
## sites in this codebase are inside `_refresh()` / `_build_layout()`
## paths that re-run on a relevant event already.
class_name UiScale
extends RefCounted


## Returns the rendered px size for a `base_px` design value, after
## applying `Settings.font_scale` and `DeviceLayout.dpi_bucket`.
##
## Test-friendly: read both globals via the autoload tree so tests
## can stage values via `Settings.set_font_scale()` +
## `DeviceLayout._test_set_dpi_bucket()`.
static func size(base_px: int) -> int:
	if base_px <= 0:
		return 1
	var scale: float = _font_scale() * _dpi_bucket()
	return int(round(float(base_px) * scale))


## Returns a recommended tap-target height in viewport px, derived
## from Material's 48 dp floor and the active dpi bucket. Phase 13d
## (touch-target sweep) will route every tappable Control through
## this. Currently unused; landed alongside `size()` so the helper
## class has a single import surface.
static func tap_target() -> int:
	return int(round(48.0 * _dpi_bucket()))


# Settings + DeviceLayout are autoloads; access via the tree so unit
# tests don't need to monkey-patch global symbols. Both are guaranteed
# loaded by the time gameplay code calls UiScale (project.godot
# orders Settings first, DeviceLayout last).
static func _font_scale() -> float:
	var s := Engine.get_main_loop()
	if s == null or not (s is SceneTree):
		return 1.0
	var node := (s as SceneTree).root.get_node_or_null("Settings")
	if node == null or not ("font_scale" in node):
		return 1.0
	return float(node.font_scale)


static func _dpi_bucket() -> float:
	var s := Engine.get_main_loop()
	if s == null or not (s is SceneTree):
		return 1.0
	var node := (s as SceneTree).root.get_node_or_null("DeviceLayout")
	if node == null or not ("dpi_bucket" in node):
		return 1.0
	return float(node.dpi_bucket)
