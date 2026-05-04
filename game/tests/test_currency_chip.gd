## Phase 10c — currency_chip behaviour.
##
## The chip should:
##   1. Snap immediately when set_*_value is called with animate=false.
##   2. Tween through intermediate values when animate=true.
##   3. Hide its progress bar when fraction is < 0.
##   4. Land on the target value once the tween completes.
extends GutTest

const _SCENE := preload("res://game/scenes/ui/currency_chip.tscn")


func _new_chip() -> PanelContainer:
	var chip: PanelContainer = _SCENE.instantiate()
	add_child_autofree(chip)
	# Phase 10c chips assume the icon is non-null; supply a 4×4 stub so
	# texture_changed signals don't fire on null.
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	var tex := ImageTexture.create_from_image(img)
	chip.configure(tex, Color.GOLD, "Test", "tooltip")
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


func test_configure_updates_label_prefix() -> void:
	var chip := _new_chip()
	await wait_frames(1)
	chip.set_int_value(7, false)
	await wait_frames(1)
	assert_string_contains(chip._value_label.text, "Test")
	chip.configure(chip.icon_texture, Color.RED, "Renamed", "")
	chip.set_int_value(8, false)
	await wait_frames(1)
	assert_string_contains(chip._value_label.text, "Renamed")
