## Phase 14c — currency_chip behaviour (Dusk pixel-RPG variant).
##
## The chip should:
##   1. Snap immediately when set_*_value is called with animate=false.
##   2. Tween through intermediate values when animate=true.
##   3. Hide its progress bar when fraction is < 0.
##   4. Land on the target value once the tween completes.
##   5. Render the configured glyph character + label text from
##      configure(glyph, accent, label, tooltip).
##
## 14c rewrite notes: the old parchment-era chip exposed a single
## `_value_label` that contained the prefix + value (e.g. "Gold 123").
## The Dusk chip splits these into `_lbl_label` (UPPERCASE prefix in
## UiTiny) and `_value_label` (the numeric value alone). Tests now
## assert against both labels independently.
extends GutTest

const _SCENE := preload("res://game/scenes/ui/currency_chip.tscn")


func _new_chip() -> PanelContainer:
	var chip: PanelContainer = _SCENE.instantiate()
	add_child_autofree(chip)
	# 14c uses a glyph character (not a texture) for the colored cell.
	chip.configure("G", Color.GOLD, "Test", "tooltip")
	return chip


func test_int_value_snaps_when_animate_false() -> void:
	var chip := _new_chip()
	await wait_frames(1)
	chip.set_int_value(123, false)
	await wait_frames(1)
	assert_eq(chip._displayed_int, 123)
	assert_string_contains(chip._value_label.text, "123")


func test_int_value_tweens_through_intermediate() -> void:
	var chip := _new_chip()
	await wait_frames(1)
	chip.set_int_value(0, false)
	await wait_frames(1)
	chip.set_int_value(1000, true, 0.4)
	# Sample mid-tween: at ~0.1s the displayed value should be > 0 but
	# nowhere near 1000 yet (cubic ease-out is slow on the front end).
	await wait_frames(2)   # ~33ms
	var mid: int = chip._displayed_int
	assert_true(mid > 0 and mid < 1000,
			"int chip should tween through intermediate values; mid=%d" % mid)
	# Land cleanly on the target after the tween finishes.
	await wait_seconds(0.5)
	assert_eq(chip._displayed_int, 1000,
			"int chip should land exactly on the target value")


func test_big_value_snaps_on_first_set() -> void:
	# First-paint must NOT tween from a null prior value to the target,
	# even with animate=true. The bar uses this to avoid a 0→loaded
	# jackpot at startup.
	var chip := _new_chip()
	await wait_frames(1)
	var bn := BigNumber.from_float(42.0)
	chip.set_big_value(bn, true)
	await wait_frames(1)
	assert_eq(chip._displayed_big.format(), bn.format())


func test_big_value_lands_on_target_after_tween() -> void:
	var chip := _new_chip()
	await wait_frames(1)
	# Seed a starting value.
	chip.set_big_value(BigNumber.from_float(100.0), false)
	await wait_frames(1)
	# Drive a new value with animation. After the tween window closes
	# the displayed value should match the target's formatted string.
	var target: BigNumber = BigNumber.from_float(1000.0)
	chip.set_big_value(target, true, 0.2)
	await wait_seconds(0.35)
	assert_eq(chip._displayed_big.format(), target.format())


func test_progress_bar_hidden_when_fraction_negative() -> void:
	var chip := _new_chip()
	await wait_frames(1)
	chip.set_progress_fraction(-1.0)
	assert_false(chip._progress.visible)


func test_progress_bar_visible_and_clamped() -> void:
	var chip := _new_chip()
	await wait_frames(1)
	chip.set_progress_fraction(0.5)
	assert_true(chip._progress.visible)
	assert_almost_eq(chip._progress.value, 0.5, 0.001)
	# Out-of-range values clamp.
	chip.set_progress_fraction(2.0)
	assert_almost_eq(chip._progress.value, 1.0, 0.001)
	chip.set_progress_fraction(-2.0)
	assert_false(chip._progress.visible,
			"negative fractions hide the bar even after a prior visible call")


func test_configure_renders_glyph_and_label() -> void:
	# 14c rewrite: the chip splits the prefix label from the numeric
	# value. After configure("G", ..., "Test", ...), the glyph cell
	# should show "G" and the lbl above the value should show "TEST"
	# (UPPERCASE per styles.css `.currency .lbl`).
	var chip := _new_chip()
	await wait_frames(1)
	chip.set_int_value(7, false)
	await wait_frames(1)
	assert_eq(chip._glyph_label.text, "G",
			"glyph cell must render the configured character")
	assert_eq(chip._lbl_label.text, "TEST",
			"label must render UPPERCASE per styles.css `.currency .lbl`")
	assert_string_contains(chip._value_label.text, "7",
			"value label must contain the numeric value")


func test_configure_reapplies_glyph_and_label_at_runtime() -> void:
	# Calling configure() again should swap the glyph + label live.
	var chip := _new_chip()
	await wait_frames(1)
	chip.configure("R", Color.RED, "Renamed", "")
	await wait_frames(1)
	assert_eq(chip._glyph_label.text, "R")
	assert_eq(chip._lbl_label.text, "RENAMED")
	# The glyph stylebox's bg_color should now be the new accent.
	var sb: StyleBoxFlat = chip._glyph_panel.get_theme_stylebox("panel")
	assert_eq(sb.bg_color, Color.RED,
			"glyph cell stylebox bg should retint to the new accent color")


func test_configure_glyph_uses_dark_ink_for_legibility() -> void:
	# styles.css `.currency .glyph { color: #2b1a05 }` — dark ink on
	# the bright accent bg. The chip overrides font_color regardless
	# of the theme variation, since "DisplaySmall" defaults to gold.
	var chip := _new_chip()
	await wait_frames(1)
	var ink: Color = chip._glyph_label.get_theme_color("font_color")
	assert_eq(ink, Color("#2b1a05"),
			"glyph ink must be dark (#2b1a05) for legibility on the accent bg")
