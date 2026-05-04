## Phase 10a — Theme & font foundation smoke tests.
##
## Validates that `res://game/resources/main_theme.tres` loads, has the
## fonts and StyleBoxes the rest of the polish phases assume, and that
## the Heading / Subhead theme variations resolve correctly.
extends GutTest

const _THEME_PATH := "res://game/resources/main_theme.tres"
const _PALETTE := preload("res://game/resources/palette_colors.gd")


func test_theme_resource_loads() -> void:
	var theme: Theme = load(_THEME_PATH)
	assert_not_null(theme, "main_theme.tres must load as a Theme resource")


func test_default_font_is_set() -> void:
	var theme: Theme = load(_THEME_PATH)
	var font := theme.default_font
	assert_not_null(font, "Theme must declare a default_font (body face)")
	assert_true(theme.default_font_size >= 12 and theme.default_font_size <= 24,
			"default_font_size %d should be a sensible body size" % theme.default_font_size)


func test_button_styles_resolve() -> void:
	var theme: Theme = load(_THEME_PATH)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := theme.get_stylebox(state, "Button")
		assert_true(sb is StyleBoxFlat,
				"Button/%s style should be a StyleBoxFlat" % state)


func test_panel_container_style_resolves() -> void:
	var theme: Theme = load(_THEME_PATH)
	var sb := theme.get_stylebox("panel", "PanelContainer")
	assert_true(sb is StyleBoxFlat, "PanelContainer/panel must be StyleBoxFlat")


func test_progressbar_styles_resolve() -> void:
	var theme: Theme = load(_THEME_PATH)
	assert_true(theme.get_stylebox("background", "ProgressBar") is StyleBoxFlat)
	assert_true(theme.get_stylebox("fill", "ProgressBar") is StyleBoxFlat)


func test_heading_variation_uses_display_font() -> void:
	# Heading is a Label-derived variation that uses the display face.
	# Verified via direct property lookup so tests don't depend on the
	# variation-registration map (set_type_variation), which is only
	# needed if scenes want fallback to Label keys — they don't.
	var theme: Theme = load(_THEME_PATH)
	assert_true(theme.has_font("font", "Heading"),
			"Heading variation must define a font")
	var heading_font := theme.get_font("font", "Heading")
	var body_font := theme.default_font
	assert_not_null(heading_font, "Heading variation must resolve a font")
	assert_true(heading_font != body_font,
			"Heading font should differ from the body default_font")
	assert_true(theme.has_font_size("font_size", "Heading"),
			"Heading variation must define a font_size")
	var size := theme.get_font_size("font_size", "Heading")
	assert_true(size > theme.default_font_size,
			"Heading font_size %d should be larger than body %d" % [size, theme.default_font_size])


func test_subhead_variation_exists() -> void:
	var theme: Theme = load(_THEME_PATH)
	assert_true(theme.has_font("font", "Subhead"),
			"Subhead variation must define a font")
	assert_true(theme.has_font_size("font_size", "Subhead"),
			"Subhead variation must define a font_size")
	# Subhead uses display face like Heading, but smaller.
	var subhead_size := theme.get_font_size("font_size", "Subhead")
	var heading_size := theme.get_font_size("font_size", "Heading")
	assert_true(subhead_size < heading_size,
			"Subhead size %d should be smaller than Heading size %d" % [subhead_size, heading_size])


func test_main_scene_applies_theme() -> void:
	var scene := load("res://game/scenes/main.tscn") as PackedScene
	var root: Control = scene.instantiate()
	add_child_autofree(root)
	await wait_frames(1)
	assert_not_null(root.theme, "main.tscn root must have theme assigned")
	var theme: Theme = load(_THEME_PATH)
	assert_eq(root.theme.resource_path, theme.resource_path,
			"main.tscn theme should be res://game/resources/main_theme.tres")


func test_palette_colors_constants_present() -> void:
	# Smoke-check a few representative constants — a typo here would
	# break any future scene that references the palette.
	assert_true(_PALETTE.PARCHMENT is Color)
	assert_true(_PALETTE.SEPIA_DARK is Color)
	assert_true(_PALETTE.BRASS_ACCENT is Color)
	assert_true(_PALETTE.BLOOD_RUBY is Color)
	assert_true(_PALETTE.INK_BLACK is Color)
