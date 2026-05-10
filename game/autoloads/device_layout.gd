## Phase 13b — device-aware layout context.
##
## Centralises three things every responsive view needs to ask:
##   1. `safe_area`   — Rect2 in viewport coords excluding status bar,
##                      gesture bar, notches. Layouts use this to pad
##                      their root container.
##   2. `dpi_bucket`  — float in `{0.85, 1.0, 1.15, 1.30}` chosen from
##                      the screen's reported DPI. UiScale.size() reads
##                      it so a `font_size=16` design value renders at
##                      the same physical size on mdpi / hdpi / xhdpi /
##                      xxhdpi devices.
##   3. `is_landscape`/`is_tablet` — booleans for view layout branches
##                                   (Phase 13c uses these).
##
## Single source of truth. Recomputed on viewport resize +
## DisplayServer events; emits `layout_changed` so subscribed views
## can re-anchor without polling.
##
## Test seam: every value can be overridden via `_test_*` setters
## that emit `layout_changed`. Tests don't need a real DisplayServer.
extends Node

@warning_ignore("unused_signal")
signal layout_changed

# DPI bucket cutoffs roughly aligned with Android density buckets:
#   < 140 dpi → mdpi-ish    (older / cheap phones)        bucket 0.85
#   140-200  → hdpi-ish     (mid-range)                   bucket 1.0
#   200-280  → xhdpi        (most current phones)         bucket 1.15
#   > 280    → xxhdpi+      (flagships, foldables open)   bucket 1.30
const _DPI_CUTOFFS: Array[float] = [140.0, 200.0, 280.0]
const _DPI_BUCKETS: Array[float] = [0.85, 1.0, 1.15, 1.30]
const _DEFAULT_BUCKET := 1.0

# Tablet cutoff: Material's "small tablet" threshold. Below this we
# treat the device as a phone.
const _TABLET_MIN_DP: float = 600.0

var safe_area: Rect2 = Rect2()
var dpi_bucket: float = _DEFAULT_BUCKET
var is_landscape: bool = false
var is_tablet: bool = false


func _ready() -> void:
	# Step 1 — initial recompute. This sets `dpi_bucket` from the
	# detected screen DPI (the value we're about to push to
	# `content_scale_factor`). `safe_area` it picks up here may be
	# stale because the viewport hasn't yet been scaled — we recompute
	# below after the scale factor takes effect.
	_recompute()
	# Step 2 — push content_scale_factor. Under
	# `stretch_aspect="expand"` this changes the effective viewport
	# size in design dp (window_size / content_scale_factor). On a
	# 720×1280 window with dpi_bucket=0.85 the viewport becomes
	# 847×1505 design dp.
	var root := get_tree().root
	root.content_scale_factor = dpi_bucket
	# Step 3 — connect the resize listener BEFORE the second recompute
	# so any size_changed event that fires synchronously between now
	# and the next frame still flows through.
	root.size_changed.connect(_recompute)
	# Step 4 — v0.15.1.1 fix: re-read viewport after the scale
	# factor took effect. Without this, the pre-step-2 stale
	# safe_area combined with the new viewport size produced phantom
	# right + bottom margins of (1 - 1/dpi_bucket) × design viewport,
	# visible as parchment-coloured bands in the screenshot the user
	# reported.
	_recompute()


## Force a full recomputation. Public so tests + the screenshot mode
## can call it directly without waiting for a `size_changed` event.
func recompute() -> void:
	_recompute()


func _recompute() -> void:
	var viewport_size: Vector2 = Vector2(get_viewport().get_visible_rect().size)

	# Safe area: `screen_get_usable_rect(0)` gives the screen area
	# minus system UI (status bar, gesture bar, taskbar). On desktop
	# / web stubs it returns the full screen. We translate it into
	# viewport coords assuming `canvas_items` stretch (which the
	# project uses) — the ratio of usable to full screen is preserved
	# under canvas_items scaling.
	var safe: Rect2 = _probe_safe_area(viewport_size)
	if safe.size.x <= 0.0 or safe.size.y <= 0.0:
		safe_area = Rect2(Vector2.ZERO, viewport_size)
	else:
		safe_area = safe

	dpi_bucket = _bucket_for_dpi(_screen_dpi())
	is_landscape = viewport_size.x > viewport_size.y
	# Tablet check uses the smaller dimension so a foldable open in
	# landscape still reads as tablet.
	is_tablet = min(viewport_size.x, viewport_size.y) > _TABLET_MIN_DP * dpi_bucket
	layout_changed.emit()


func _probe_safe_area(viewport_size: Vector2) -> Rect2:
	# Desktop / web: the entire window is usable. The earlier
	# `screen_get_usable_rect(0)` approach returned the *screen*'s
	# usable rect (monitor minus taskbar), which on multi-monitor
	# setups can be offset hundreds of pixels from the window
	# origin and projected a huge bogus left margin into the safe
	# area. v0.15.1 fix.
	if not OS.has_feature("mobile"):
		return Rect2(Vector2.ZERO, viewport_size)
	# Mobile: query the OS for the actual safe area inside the
	# window (status bar, gesture bar, notch insets). Each platform
	# call is guarded to fall back to a full-viewport safe area if
	# the DisplayServer is stubbed (headless tests, early boot).
	if DisplayServer.get_screen_count() <= 0:
		return Rect2(Vector2.ZERO, viewport_size)
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(0)
	if usable.size.x <= 0 or usable.size.y <= 0:
		return Rect2(Vector2.ZERO, viewport_size)
	# screen_get_usable_rect on a fullscreen mobile activity returns
	# the device screen minus status bar + gesture bar. Translate
	# into viewport coords via the canvas_items stretch ratio.
	var screen_size: Vector2i = DisplayServer.screen_get_size(0)
	if screen_size.x <= 0 or screen_size.y <= 0:
		return Rect2(Vector2.ZERO, viewport_size)
	var ratio_x: float = viewport_size.x / float(screen_size.x)
	var ratio_y: float = viewport_size.y / float(screen_size.y)
	# IMPORTANT: drop the position component. The activity is at
	# screen origin (0, 0) on Android — a non-zero `usable.position`
	# would mean a notch / status bar inset, which we want to
	# convert into a margin, not into a screen-space offset. So
	# `position.x * ratio_x` is the correct status-bar inset.
	return Rect2(
			Vector2(float(usable.position.x) * ratio_x, float(usable.position.y) * ratio_y),
			Vector2(float(usable.size.x) * ratio_x, float(usable.size.y) * ratio_y))


func _screen_dpi() -> float:
	# DisplayServer.screen_get_dpi may return 0 or -1 on web / desktop
	# stubs; we default to 160 (mdpi baseline) so the bucket lookup
	# falls into the 1.0 default.
	var dpi: int = DisplayServer.screen_get_dpi(0) if DisplayServer.get_screen_count() > 0 else 0
	if dpi <= 0:
		return 160.0
	return float(dpi)


func _bucket_for_dpi(dpi: float) -> float:
	for i in _DPI_CUTOFFS.size():
		if dpi < _DPI_CUTOFFS[i]:
			return _DPI_BUCKETS[i]
	return _DPI_BUCKETS[-1]


# region — test seams
# Pure setters that bypass DisplayServer probing, so tests can stage
# any device profile without needing the real screen. Each emits
# `layout_changed` so subscribed views can verify they reacted.

func _test_set_safe_area(r: Rect2) -> void:
	safe_area = r
	layout_changed.emit()


func _test_set_dpi_bucket(b: float) -> void:
	# Test seam: sets dpi_bucket directly. Does NOT mutate
	# content_scale_factor — that would trigger the viewport's
	# size_changed signal and re-fire _recompute, which would read
	# the headless DisplayServer's stub DPI (160) and reset our test
	# value. The live _ready does set content_scale_factor; tests
	# that need to verify that integration should do it explicitly.
	dpi_bucket = b
	layout_changed.emit()


func _test_set_orientation(landscape: bool) -> void:
	is_landscape = landscape
	layout_changed.emit()


func _test_set_tablet(tablet: bool) -> void:
	is_tablet = tablet
	layout_changed.emit()


## Maps an arbitrary DPI value to the bucket. Public for tests so
## the bucket math itself is verified independently of DisplayServer.
func bucket_for_dpi(dpi: float) -> float:
	return _bucket_for_dpi(dpi)

# endregion
