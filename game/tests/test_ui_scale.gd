## v0.14.0 (Phase 13a) — UiScale resolver tests.
##
## Asserts the contract every label in the codebase now depends on:
##   - `size(N) = N * Settings.font_scale` — purely the accessibility
##     slider's user preference.
##   - Density (dpi_bucket) is handled at the engine level via
##     Window.content_scale_factor (set in DeviceLayout._ready) and
##     intentionally NOT applied a second time here. v0.14.2 had this
##     wrong: UiScale also multiplied by dpi_bucket, which double-
##     scaled fonts on dense screens once content_scale_factor
##     carried the density adjustment.
##   - Edge cases (zero, negative) clamp safely.
##
## Tests stage values via `Settings.set_font_scale()` so they're
## deterministic and don't depend on the host's actual screen DPI.
extends GutTest


func before_each() -> void:
	Settings.set_font_scale(1.0)
	DeviceLayout._test_set_dpi_bucket(1.0)


func after_each() -> void:
	Settings.set_font_scale(1.0)
	DeviceLayout._test_set_dpi_bucket(1.0)


# region — size()

func test_size_at_unit_scale_returns_input() -> void:
	assert_eq(UiScale.size(16), 16)
	assert_eq(UiScale.size(26), 26)
	assert_eq(UiScale.size(12), 12)


func test_size_scales_with_font_scale() -> void:
	Settings.set_font_scale(1.5)
	assert_eq(UiScale.size(16), 24, "16 px at 1.5× should be 24 px")
	Settings.set_font_scale(0.85)
	# 16 * 0.85 = 13.6 → rounds to 14
	assert_eq(UiScale.size(16), 14)


func test_size_ignores_dpi_bucket() -> void:
	# v0.14.3: density is handled via Window.content_scale_factor
	# (set in DeviceLayout._ready). UiScale.size() is purely the
	# user's font_scale preference. Setting dpi_bucket here must NOT
	# affect the returned design px.
	DeviceLayout._test_set_dpi_bucket(1.30)
	assert_eq(UiScale.size(16), 16,
		"UiScale.size must NOT apply dpi_bucket — content_scale_factor handles density")
	DeviceLayout._test_set_dpi_bucket(0.85)
	assert_eq(UiScale.size(16), 16)


func test_size_clamps_zero_and_negative() -> void:
	assert_eq(UiScale.size(0), 1, "size(0) must clamp to 1 to avoid invisible labels")
	assert_eq(UiScale.size(-5), 1, "size(<0) must clamp to 1 — defensive")


func test_tap_target_returns_material_floor() -> void:
	# v0.14.3: tap_target() returns 48 design dp. The device's
	# content_scale_factor (from DeviceLayout) scales this to
	# physical pixels at engine level — same single-source-of-truth
	# pattern as size().
	assert_eq(UiScale.tap_target(), 48)
	# Independent of dpi_bucket setting.
	DeviceLayout._test_set_dpi_bucket(1.30)
	assert_eq(UiScale.tap_target(), 48)

# endregion


# region — DeviceLayout dpi bucketing

func test_dpi_bucket_lookup_cutoffs() -> void:
	# Cutoffs documented in device_layout.gd:
	#   < 140 → 0.85
	#   140-200 → 1.0
	#   200-280 → 1.15
	#   ≥ 280 → 1.30
	assert_eq(DeviceLayout.bucket_for_dpi(120.0), 0.85)
	assert_eq(DeviceLayout.bucket_for_dpi(160.0), 1.0)
	assert_eq(DeviceLayout.bucket_for_dpi(240.0), 1.15)
	assert_eq(DeviceLayout.bucket_for_dpi(420.0), 1.30)


func test_dpi_bucket_at_boundaries() -> void:
	# Exactly at 140 falls into the 1.0 bucket (open lower bound).
	assert_eq(DeviceLayout.bucket_for_dpi(140.0), 1.0)
	assert_eq(DeviceLayout.bucket_for_dpi(199.99), 1.0)
	assert_eq(DeviceLayout.bucket_for_dpi(200.0), 1.15)

# endregion


# region — DeviceLayout signal contract

func test_layout_changed_fires_on_safe_area_set() -> void:
	var fired: Array[bool] = [false]
	var handler := func() -> void: fired[0] = true
	DeviceLayout.layout_changed.connect(handler)
	DeviceLayout._test_set_safe_area(Rect2(0, 24, 720, 1232))
	assert_true(fired[0], "_test_set_safe_area must emit layout_changed")
	DeviceLayout.layout_changed.disconnect(handler)


func test_layout_changed_fires_on_dpi_bucket_set() -> void:
	var fired: Array[bool] = [false]
	var handler := func() -> void: fired[0] = true
	DeviceLayout.layout_changed.connect(handler)
	DeviceLayout._test_set_dpi_bucket(1.30)
	assert_true(fired[0])
	DeviceLayout.layout_changed.disconnect(handler)


func test_test_setters_update_public_fields() -> void:
	DeviceLayout._test_set_safe_area(Rect2(8, 24, 700, 1200))
	assert_eq(DeviceLayout.safe_area, Rect2(8, 24, 700, 1200))
	DeviceLayout._test_set_dpi_bucket(1.15)
	assert_eq(DeviceLayout.dpi_bucket, 1.15)
	DeviceLayout._test_set_orientation(true)
	assert_true(DeviceLayout.is_landscape)
	DeviceLayout._test_set_tablet(true)
	assert_true(DeviceLayout.is_tablet)
	# Reset for downstream tests.
	DeviceLayout._test_set_orientation(false)
	DeviceLayout._test_set_tablet(false)

# endregion


# region — no-hardcoded-font_size lint
#
# This test scans the live source tree for `add_theme_font_size_override("font_size", N)`
# call sites whose N is a literal integer. After Phase 13a's sweep,
# every such call should route through UiScale.size(N) instead.
# A future maintainer who adds a hardcoded font_size and forgets to
# wrap it will fail this test by name.

func test_no_hardcoded_font_size_overrides_remain() -> void:
	var roots: Array[String] = ["res://game/scenes", "res://game/autoloads"]
	var literal_pattern := RegEx.new()
	# Match `add_theme_font_size_override("font_size", 14)` but NOT
	# `add_theme_font_size_override("font_size", UiScale.size(14))`.
	literal_pattern.compile('add_theme_font_size_override\\("font_size",\\s*\\d+\\)')

	var offending: Array[String] = []
	for root in roots:
		_collect_offenses(root, literal_pattern, offending)

	assert_true(
		offending.is_empty(),
		"Every add_theme_font_size_override must use UiScale.size(N). Offending:\n%s"
				% "\n".join(offending))


func _collect_offenses(dir_path: String, pattern: RegEx, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var entry: String = dir.get_next()
		if entry == "":
			break
		if entry.begins_with("."):
			continue
		var full_path: String = "%s/%s" % [dir_path, entry]
		if dir.current_is_dir():
			_collect_offenses(full_path, pattern, out)
			continue
		if not entry.ends_with(".gd"):
			continue
		var f := FileAccess.open(full_path, FileAccess.READ)
		if f == null:
			continue
		var content: String = f.get_as_text()
		f.close()
		var line_no: int = 0
		for line in content.split("\n"):
			line_no += 1
			if pattern.search(line) != null:
				out.append("  %s:%d  %s" % [full_path, line_no, line.strip_edges()])
	dir.list_dir_end()

# endregion
