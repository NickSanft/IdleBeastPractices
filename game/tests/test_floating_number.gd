## Phase 14g — FloatingNumber feedback popup tests.
##
## Pre-14g: a simple drift-up + delayed fade. The "starts visible"
## assumption held because the tween only fired the fade after a
## 40 % delay.
##
## v0.15.6 (14g) — reskinned per styles.css `.float-gain`. The
## animation now has THREE phases that pin specific scene-tree state:
##   0%   (t=0):    scale 0.7, opacity 0   (starts invisible!)
##   20%  (~220ms): scale 1.1, opacity 1   (peak punch)
##   100% (~1100ms): scale 1.0, opacity 0, y -56 (drift-out)
##
## Tests below pin the new keyframes' early states + the configure
## API (which supports an `is_item` teal variant in addition to
## `is_shiny`).
extends GutTest

const _SCENE := preload("res://game/scenes/ui/floating_number.tscn")


func before_each() -> void:
	# reduce_motion paths take a different branch — pin to false here
	# so the full-motion keyframes are what we test.
	Settings.reduce_motion = false


func test_instantiates_and_configures() -> void:
	var label: Label = _SCENE.instantiate()
	add_child_autofree(label)
	var configured: Variant = label.call("configure", "1.23K", false)
	assert_eq(configured, label, "configure should return self for chaining")
	assert_eq(label.text, "+1.23K g")


func test_shiny_variant_prepends_sparkle() -> void:
	var label: Label = _SCENE.instantiate()
	add_child_autofree(label)
	label.call("configure", "5", true)
	assert_true(String(label.text).contains("✨"))
	assert_true(String(label.text).contains("+5 g"))


## Phase 14g: starts at opacity 0 + scale 0.7 (the 0% keyframe of
## styles.css `float-up`). The full animation is 1.1 s; pinning each
## sample frame's exact opacity is timing-flaky under headless GUT
## (tween-driven property tweens advance per process frame and don't
## guarantee a specific delta_t budget), so we assert just the
## structural contract: initial opacity is 0 (not 1) and initial
## scale is 0.7 (not 1.0). Both catch the regression where a future
## refactor re-introduces the parchment-era flat-show-then-fade.
func test_starts_at_zero_opacity_and_small_scale() -> void:
	var label: Label = _SCENE.instantiate()
	label.call("configure", "1", false)
	add_child_autofree(label)
	# Synchronously after add_child_autofree (which fires _ready), the
	# 0% keyframe state must be visible: opacity 0, scale 0.7.
	assert_almost_eq(label.modulate.a, 0.0, 0.05,
		"float-gain must start at opacity 0 (per styles.css 0%% keyframe)")
	assert_almost_eq(label.scale.x, 0.7, 0.05,
		"float-gain must start at scale 0.7 (per styles.css 0%% keyframe)")


## Phase 14g: `is_item` paints teal instead of gold for drop floaters
## (styles.css `.float-gain.item { color: var(--teal) }`).
func test_is_item_paints_teal_not_gold() -> void:
	var label: Label = _SCENE.instantiate()
	add_child_autofree(label)
	label.call("configure", "+1 Mushroom", false, true)
	var teal: Color = preload("res://assets/themes/dusk/palette_dusk.gd").active()["teal"]
	var color: Color = label.get_theme_color("font_color")
	assert_eq(color, teal,
		"is_item=true must paint the Dusk teal token per styles.css `.float-gain.item`")
	# Text passes through verbatim — caller pre-formats item drops.
	assert_eq(label.text, "+1 Mushroom",
		"is_item=true must NOT append the trailing 'g' suffix")


## Phase 14g: gold currency floaters use the Dusk `gold` token.
func test_currency_float_paints_gold() -> void:
	var label: Label = _SCENE.instantiate()
	add_child_autofree(label)
	label.call("configure", "42", false, false)
	var gold: Color = preload("res://assets/themes/dusk/palette_dusk.gd").active()["gold"]
	var color: Color = label.get_theme_color("font_color")
	assert_eq(color, gold,
		"currency floaters must paint the Dusk gold token per styles.css `.float-gain`")


## reduce_motion path: skip the scale punch + drift, but still show
## the number briefly and fade out. Same total duration as the full
## motion path so call-site timing assumptions hold.
func test_reduce_motion_holds_then_fades() -> void:
	Settings.reduce_motion = true
	var label: Label = _SCENE.instantiate()
	label.call("configure", "1", false)
	add_child_autofree(label)
	await wait_frames(1)
	# In reduce_motion the label starts at full alpha (no punch).
	assert_almost_eq(label.modulate.a, 1.0, 0.01,
		"reduce_motion path must start at full alpha — no scale punch")
	Settings.reduce_motion = false
