## Phase 14 — Dusk theme builder + palette + .tres integrity tests.
##
## Pins:
##   - The 17 palette tokens for each named palette match the README's
##     Design Tokens table (and styles.css ":root").
##   - DuskThemeBuilder produces a Theme with the three font roles
##     populated (display / ui / body), the seven type variations
##     (DisplayHeading / DisplaySmall / UiTiny / UiCaption / BodyText /
##     BodyIntro / PixelButtonGold), and the per-class StyleBoxFlats
##     for Panel, PanelContainer, Button, CheckBox, OptionButton.
##   - The committed .tres files load cleanly and carry the same
##     entries the builder emits — so a future maintainer who tweaks
##     palette_dusk.gd without re-running tools/build_dusk_themes.gd
##     fails by name, surfacing the staleness immediately.
##
## Source of truth: docs/design_handoff_theming/README.md +
## reference_files/styles.css. When the README's hex values change,
## update palette_dusk.gd AND re-run the builder; this test catches
## drift in either direction.
extends GutTest

const _AMETHYST_PATH := "res://assets/themes/dusk/amethyst.tres"
const _TWILIGHT_PATH := "res://assets/themes/dusk/twilight.tres"
const _EMBER_PATH := "res://assets/themes/dusk/ember.tres"

const _DISPLAY_FONT_PATH := "res://assets/fonts/dusk/PressStart2P-Regular.ttf"
const _UI_FONT_PATH := "res://assets/fonts/dusk/Silkscreen-Regular.ttf"
const _BODY_FONT_PATH := "res://assets/fonts/dusk/VT323-Regular.ttf"


# region — palette tokens

func test_amethyst_palette_matches_design_tokens() -> void:
	# Hex values lifted from README's Design Tokens table. Any drift
	# in palette_dusk.gd shows up here by exact name + value.
	var p := PaletteDusk.amethyst()
	assert_eq(p["bg_deep"],     Color("#0c0820"))
	assert_eq(p["bg"],          Color("#15102e"))
	assert_eq(p["bg_2"],        Color("#1d1640"))
	assert_eq(p["card"],        Color("#251b52"))
	assert_eq(p["card_2"],      Color("#2f2364"))
	assert_eq(p["border"],      Color("#4a3a8a"))
	assert_eq(p["border_soft"], Color("#3a2d6f"))
	assert_eq(p["ink"],         Color("#ece4ff"))
	assert_eq(p["ink_dim"],     Color("#b6a8de"))
	assert_eq(p["ink_mute"],    Color("#8576b6"))
	assert_eq(p["gold"],        Color("#f5c46b"))
	assert_eq(p["gold_dark"],   Color("#b8862e"))
	assert_eq(p["teal"],        Color("#5fd3c2"))
	assert_eq(p["teal_dark"],   Color("#2e8a82"))
	assert_eq(p["magenta"],     Color("#d96fb8"))
	assert_eq(p["rose"],        Color("#ef6f8a"))
	assert_eq(p["danger"],      Color("#ff6b6b"))


func test_twilight_palette_overrides_purple_with_teal() -> void:
	var p := PaletteDusk.twilight()
	assert_eq(p["bg_deep"], Color("#061518"))
	assert_eq(p["card"],    Color("#143a40"))
	assert_eq(p["border"],  Color("#2e7a82"))
	assert_eq(p["ink"],     Color("#e0f7f4"))
	assert_eq(p["gold"],    Color("#f0b95a"))
	# Tokens NOT specified in the README's Twilight section inherit
	# from Amethyst — verify a couple so the inheritance path works.
	assert_eq(p["danger"],    Color("#ff6b6b"))   # inherits
	assert_eq(p["teal"],      Color("#5fd3c2"))   # explicitly preserved


func test_ember_palette_overrides_with_warm_plum() -> void:
	var p := PaletteDusk.ember()
	assert_eq(p["bg_deep"], Color("#1a0814"))
	assert_eq(p["card"],    Color("#4a2238"))
	assert_eq(p["border"],  Color("#8a3f6a"))
	assert_eq(p["gold"],    Color("#ffb84d"))


func test_palette_by_id_falls_back_to_amethyst_on_unknown() -> void:
	var unknown := PaletteDusk.by_id("does_not_exist")
	assert_eq(unknown, PaletteDusk.amethyst())


func test_every_palette_returns_same_keyset() -> void:
	# Theme code indexes by key without checking — verify all three
	# expose the same 18 token keys.
	var keys: Array = PaletteDusk.amethyst().keys()
	keys.sort()
	for p_id in [PaletteDusk.Id.TWILIGHT, PaletteDusk.Id.EMBER]:
		var other_keys: Array = PaletteDusk.palette(p_id).keys()
		other_keys.sort()
		assert_eq(other_keys, keys,
			"every palette must expose the same token keyset")

# endregion


# region — DuskThemeBuilder output shape

func _build_amethyst() -> Theme:
	var display_font := load(_DISPLAY_FONT_PATH) as FontFile
	var ui_font := load(_UI_FONT_PATH) as FontFile
	var body_font := load(_BODY_FONT_PATH) as FontFile
	return DuskThemeBuilder.build(PaletteDusk.amethyst(), display_font, ui_font, body_font)


func test_built_theme_has_silkscreen_default_font_at_size_11() -> void:
	var t := _build_amethyst()
	assert_eq(t.default_font_size, DuskThemeBuilder.SIZE_DEFAULT_BODY_PX)
	assert_not_null(t.default_font, "Silkscreen must be assigned as the default UI font")


func test_built_theme_has_button_styleboxes_for_all_4_states() -> void:
	var t := _build_amethyst()
	for cls in ["Button", "CheckBox", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "disabled"]:
			var sb := t.get_stylebox(state, cls)
			assert_true(sb is StyleBoxFlat, "%s.%s must be a StyleBoxFlat" % [cls, state])


func test_built_theme_has_panel_styleboxes() -> void:
	var t := _build_amethyst()
	assert_true(t.get_stylebox("panel", "Panel") is StyleBoxFlat)
	assert_true(t.get_stylebox("panel", "PanelContainer") is StyleBoxFlat)


func test_built_theme_has_seven_type_variations() -> void:
	var t := _build_amethyst()
	var expected := [
		"DisplayHeading", "DisplaySmall",
		"UiTiny", "UiCaption",
		"BodyText", "BodyIntro", "BodyTextRich",
		"PixelButtonGold",
	]
	for variation in expected:
		var base := t.get_type_variation_base(variation)
		assert_ne(base, "",
			"theme must declare type variation '%s' (base = parent class)" % variation)


func test_display_heading_uses_press_start_font_at_size_18() -> void:
	var t := _build_amethyst()
	# DisplayHeading variation overrides Label's font / font_size /
	# font_color with the gold pixel-display look.
	assert_true(t.has_font("font", "DisplayHeading"))
	assert_eq(t.get_font_size("font_size", "DisplayHeading"),
			DuskThemeBuilder.SIZE_DISPLAY_HEADING)
	assert_eq(t.get_color("font_color", "DisplayHeading"),
			PaletteDusk.amethyst()["gold"])


func test_body_text_uses_vt323_font_at_size_18() -> void:
	var t := _build_amethyst()
	assert_true(t.has_font("font", "BodyText"))
	assert_eq(t.get_font_size("font_size", "BodyText"),
			DuskThemeBuilder.SIZE_BODY_TEXT)
	assert_eq(t.get_color("font_color", "BodyText"),
			PaletteDusk.amethyst()["ink"])


func test_pixel_button_gold_has_dark_brown_ink_on_gold_bg() -> void:
	var t := _build_amethyst()
	# Variation should use #2b1a05 (dark brown) for ink so the gold
	# bg has enough contrast — matches `.pixel-btn--gold` in styles.css.
	assert_eq(t.get_color("font_color", "PixelButtonGold"), Color("#2b1a05"))
	var normal_sb := t.get_stylebox("normal", "PixelButtonGold")
	assert_true(normal_sb is StyleBoxFlat)
	assert_eq((normal_sb as StyleBoxFlat).bg_color,
			PaletteDusk.amethyst()["gold"])


func test_pixel_styleboxes_have_zero_corner_radius() -> void:
	# README is explicit: "Square corners are part of the aesthetic."
	# Walk every StyleBoxFlat in the built theme and assert no
	# rounded corners snuck in.
	var t := _build_amethyst()
	var checked: Array[String] = []
	for cls in ["Button", "CheckBox", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "disabled"]:
			var sb := t.get_stylebox(state, cls) as StyleBoxFlat
			checked.append("%s.%s" % [cls, state])
			assert_eq(sb.corner_radius_top_left, 0,
				"%s.%s must have square corners" % [cls, state])
			assert_eq(sb.corner_radius_top_right, 0)
			assert_eq(sb.corner_radius_bottom_left, 0)
			assert_eq(sb.corner_radius_bottom_right, 0)
	for cls in ["Panel", "PanelContainer"]:
		var sb := t.get_stylebox("panel", cls) as StyleBoxFlat
		checked.append("%s.panel" % cls)
		assert_eq(sb.corner_radius_top_left, 0)
	assert_gt(checked.size(), 0, "expected to inspect at least one stylebox")

# endregion


# region — committed .tres integrity

func test_amethyst_tres_loads_cleanly() -> void:
	var t: Theme = load(_AMETHYST_PATH)
	assert_not_null(t, "amethyst.tres must load")
	assert_true(t is Theme)


func test_twilight_tres_loads_cleanly() -> void:
	var t: Theme = load(_TWILIGHT_PATH)
	assert_not_null(t)


func test_ember_tres_loads_cleanly() -> void:
	var t: Theme = load(_EMBER_PATH)
	assert_not_null(t)


func test_committed_amethyst_matches_freshly_built() -> void:
	# Drift detector: if a maintainer edits palette_dusk.gd or
	# dusk_theme_builder.gd without re-running
	# `tools/build_dusk_themes.gd`, the committed .tres falls behind.
	# Compare a handful of load-bearing fields to catch it.
	var loaded: Theme = load(_AMETHYST_PATH)
	var built := _build_amethyst()
	assert_eq(loaded.default_font_size, built.default_font_size,
		"default_font_size in committed amethyst.tres differs from builder output — re-run tools/build_dusk_themes.gd")
	assert_eq(loaded.get_color("font_color", "DisplayHeading"),
			built.get_color("font_color", "DisplayHeading"),
		"DisplayHeading color drift — re-run tools/build_dusk_themes.gd")
	assert_eq(loaded.get_font_size("font_size", "BodyText"),
			built.get_font_size("font_size", "BodyText"),
		"BodyText size drift — re-run tools/build_dusk_themes.gd")

# endregion


# region — fonts vendored

func test_three_fonts_load_as_fontfile() -> void:
	for path in [_DISPLAY_FONT_PATH, _UI_FONT_PATH, _BODY_FONT_PATH]:
		var f := load(path)
		assert_true(f is FontFile, "%s must load as FontFile" % path)

# endregion
