## v0.15.1.1 — visual-regression structural assertions.
##
## Catches the two bug classes the user reported just before this
## test landed:
##
##   1. **Theme not propagating** — main.tscn had a scene-level
##      `theme = main_theme.tres` export that shadowed the Dusk
##      theme assigned at runtime. Dusk reached the window but
##      never reached Main's subtree, so the live UI stayed
##      parchment-colored even though `_apply_mobile_default_theme`
##      had loaded amethyst.tres.
##
##   2. **Phantom safe-area margins** — DeviceLayout._ready called
##      `_recompute()` BEFORE setting `Window.content_scale_factor`,
##      so the cached `safe_area` was sized at the raw
##      viewport_width × viewport_height (720×1280). When
##      content_scale_factor (0.85) later expanded the effective
##      viewport to 847×1505 design dp, the
##      `_apply_safe_area_margins` math:
##         right = view_size.x - (safe.position.x + safe.size.x)
##                = 847 - (0 + 720) = 127 px phantom margin
##      produced 127×225 px parchment bands on the right + bottom.
##
## Both bugs are visible the moment you boot the app — but neither
## had a GUT-level test guarding them. These tests instantiate
## main.tscn and assert STRUCTURAL invariants that would fail if
## either regression slipped back:
##
##   - `Main.theme.resource_path` points at the Dusk theme file.
##   - All four `_safe_margin` constants are 0 on a non-mobile
##     test runner (gated; mobile may legitimately have insets).
##   - `_orientation_root.size` matches the safe_margin's inner
##     content rect (no leftover blank band).
##   - The persistent Background ColorRect is fully covered by the
##     orientation root (i.e., parchment won't bleed through).
##
## These are cheaper than render-snapshot diffs but catch the same
## class of bug. PHASED_RESKIN_PLAN.md describes the heavier
## PNG-diff approach for per-phase cosmetic verification.
extends GutTest

const _MAIN_SCENE := preload("res://game/scenes/main.tscn")
const _DUSK_AMETHYST_PATH := "res://assets/themes/dusk/amethyst.tres"


func before_each() -> void:
	# Other tests in the suite call DeviceLayout._test_set_safe_area
	# and don't always reset. Recompute from the live viewport here
	# so the next `_instantiate_main()` reads the correct, current
	# safe-area (full viewport on this non-mobile test runner).
	DeviceLayout.recompute()


func _instantiate_main() -> Node:
	var main: Node = _MAIN_SCENE.instantiate()
	add_child_autofree(main)
	return main


# region — bug 1: theme propagation

func test_main_node_carries_dusk_theme_after_ready() -> void:
	var main: Node = _instantiate_main()
	# `theme` on Main is the load-bearing assignment — Main's whole
	# subtree (currency_bar, tabs, all 10 tab views) inherits from
	# Main's `theme` property, not the window root's.
	var t: Theme = (main as Control).theme
	assert_not_null(t, "Main must have a theme assigned after _ready")
	assert_eq(t.resource_path, _DUSK_AMETHYST_PATH,
		"Main.theme must point at the Dusk Amethyst theme — got %s" % t.resource_path)


func test_main_scene_tscn_does_not_export_legacy_theme() -> void:
	# Belt-and-braces: the .tscn used to declare `theme = main_theme.tres`
	# at scene-export time, which shadowed whatever we set at runtime.
	# Read the .tscn file directly and assert no parchment theme ext_resource
	# remains. If a future maintainer re-adds an inline theme= line on
	# Main, this test fails by name.
	var f := FileAccess.open("res://game/scenes/main.tscn", FileAccess.READ)
	assert_not_null(f, "main.tscn must be readable")
	var content: String = f.get_as_text()
	f.close()
	assert_false(content.contains("main_theme.tres"),
		"main.tscn must NOT reference the legacy parchment main_theme.tres — strip the theme export from the .tscn")
	assert_false(content.contains("theme = ExtResource"),
		"main.tscn must NOT export a scene-level theme — runtime assignment is the source of truth")


func test_window_root_also_carries_dusk_theme() -> void:
	# `get_tree().root.theme` is what popup Windows (welcome-back,
	# language picker, etc.) inherit from — they're siblings of Main,
	# not children. Setting only Main.theme would leave popups
	# parchment-styled. Verify both are set.
	var _main: Node = _instantiate_main()
	var root_theme: Theme = get_tree().root.theme
	assert_not_null(root_theme, "window root must also receive the Dusk theme so popups inherit it")
	assert_eq(root_theme.resource_path, _DUSK_AMETHYST_PATH)

# endregion


# region — bug 2: no phantom safe-area bands on desktop

func test_safe_margin_has_zero_margins_on_desktop() -> void:
	# After _ready, on a non-mobile test environment, the safe area
	# equals the full viewport (no notch / status bar) so every
	# margin must be 0. If any is non-zero, content gets pushed into
	# a smaller rect with a parchment-colored band on the edge — the
	# exact user-visible bug.
	assert_false(OS.has_feature("mobile"),
		"GUT runs in headless / non-mobile mode where this assertion applies")
	var main: Node = _instantiate_main()
	# Drain any deferred layout apply.
	main._process(0.0)
	var margin: MarginContainer = main.get("_safe_margin")
	assert_not_null(margin)
	for side in ["margin_top", "margin_bottom", "margin_left", "margin_right"]:
		var v: int = margin.get_theme_constant(side)
		assert_eq(v, 0,
			"_safe_margin.%s must be 0 on desktop (got %d → would be a %d-px parchment band on that edge)" % [side, v, v])


func test_device_layout_safe_area_matches_post_scale_factor_viewport() -> void:
	# The init-order bug had DeviceLayout._recompute running BEFORE
	# Window.content_scale_factor was set. Result: cached safe_area
	# was sized against the raw viewport (720×1280), then the actual
	# viewport grew to 847×1505 design dp post-scale-factor, leaving
	# the safe_area stale.
	#
	# Pin the post-fix invariant: safe_area.size == viewport_size,
	# and safe_area.position is at origin.
	# (On mobile the position can be non-zero — status bar inset —
	# but this is a non-mobile test so origin is the contract.)
	var _main: Node = _instantiate_main()
	var view_size: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	assert_eq(DeviceLayout.safe_area.position, Vector2.ZERO,
		"safe_area.position must be (0,0) on desktop after _ready")
	assert_eq(DeviceLayout.safe_area.size, view_size,
		"safe_area.size must equal the post-scale-factor viewport size (got %v, expected %v)" % [
			DeviceLayout.safe_area.size, view_size,
		])

# endregion


# region — popups + window-subtypes use the Dusk theme, not parchment
#
# v0.15.1.2 — 9 popup / dialog / overlay scripts explicitly preloaded
# `res://game/resources/main_theme.tres` (the parchment theme) and
# assigned it via `theme = preload(...)`. This was the v0.10.4 fix —
# Window subtypes don't inherit Control theme cascade, so each popup
# had to set its own theme. v0.15.1.2 swept all 9 references to the
# Dusk theme. A future maintainer who re-introduces parchment in a
# popup fails this lint test by file:line.

func test_no_scene_script_loads_legacy_parchment_theme() -> void:
	# Walks every `.gd` under `game/scenes/` for the literal
	# `main_theme.tres` substring. Comment mentions are filtered out
	# by checking for the `preload(` / `load(` prefix on the same line.
	var roots: Array[String] = ["res://game/scenes"]
	var offending: Array[String] = []
	for r in roots:
		_walk_for_legacy_theme(r, offending)
	assert_true(offending.is_empty(),
		"Found scripts still loading res://game/resources/main_theme.tres — sweep to res://assets/themes/dusk/amethyst.tres:\n%s" % "\n".join(offending))


func _walk_for_legacy_theme(dir_path: String, out: Array[String]) -> void:
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
		var full: String = "%s/%s" % [dir_path, entry]
		if dir.current_is_dir():
			_walk_for_legacy_theme(full, out)
			continue
		if not entry.ends_with(".gd"):
			continue
		var f := FileAccess.open(full, FileAccess.READ)
		if f == null:
			continue
		var line_no: int = 0
		while not f.eof_reached():
			line_no += 1
			var line: String = f.get_line()
			# We only care about LOAD/PRELOAD references — comment
			# mentions are fine for historical context.
			if (line.contains("preload(") or line.contains("load(")) and line.contains("main_theme.tres"):
				out.append("  %s:%d  %s" % [full, line_no, line.strip_edges()])
		f.close()
	dir.list_dir_end()

# endregion


# region — orientation root fills safe margin

func test_orientation_root_fills_safe_margin_horizontally() -> void:
	# The composition root (HBox in landscape, VBox in portrait) sits
	# inside _safe_margin. If anything inside has a fixed width that
	# doesn't honor SIZE_EXPAND_FILL, the orientation_root won't fill
	# its parent — a parchment-coloured Background ColorRect would
	# show through on the right edge.
	#
	# Assert the orientation_root's WIDTH matches the safe_margin's
	# width to within a 1-px tolerance (rounding).
	var main: Node = _instantiate_main()
	# Force a layout pass so anchors / EXPAND_FILL settle.
	main._process(0.0)
	await wait_frames(2)
	var safe_margin: MarginContainer = main.get("_safe_margin")
	var orientation_root: Control = main.get("_orientation_root")
	assert_not_null(safe_margin)
	assert_not_null(orientation_root)
	# safe_margin's inner content rect is safe_margin.size minus its
	# four margin theme constants. With desktop margins == 0 (proven
	# by the test above) that equals safe_margin.size.
	var expected_inner_width: float = safe_margin.size.x
	var actual_width: float = orientation_root.size.x
	assert_almost_eq(actual_width, expected_inner_width, 1.0,
		"orientation_root must fill _safe_margin horizontally (parchment Background would bleed through otherwise)")


func test_orientation_root_fills_safe_margin_vertically() -> void:
	var main: Node = _instantiate_main()
	main._process(0.0)
	await wait_frames(2)
	var safe_margin: MarginContainer = main.get("_safe_margin")
	var orientation_root: Control = main.get("_orientation_root")
	var expected_inner_height: float = safe_margin.size.y
	var actual_height: float = orientation_root.size.y
	assert_almost_eq(actual_height, expected_inner_height, 1.0,
		"orientation_root must fill _safe_margin vertically (parchment band on bottom otherwise)")

# endregion
