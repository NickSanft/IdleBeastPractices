## Phase 14d — smoke tests for the Dusk map background.
##
## The Phase-10b implementation built three ParallaxLayers (Sky / Mid /
## Near) with two polygons for the parchment dawn/dusk vista. Phase 14d
## replaces all of that with a single fullscreen `ColorRect` driven by
## a fragment shader that paints the styles.css `.map` stack (stripes +
## scanline + radial glows). Tests pin the new structure:
##
##   - root still a ParallaxBackground at layer < 0 (catch UI sits in front)
##   - one `ColorRect` child with a `ShaderMaterial`
##   - shader uniforms reflect the Dusk palette
##   - tier-band index drives the accent glow (1→teal, 11→magenta)
##   - shader `scroll_x` uniform advances on each frame when motion is on
##   - `reduce_motion` freezes the scroll uniform
extends GutTest

const _SCENE := preload("res://game/scenes/catching/catching_background.tscn")
const _DUSK := preload("res://assets/themes/dusk/palette_dusk.gd")


func before_each() -> void:
	# Reset Settings.reduce_motion so state leaked from
	# test_accessibility_settings doesn't disable scroll here.
	Settings.reduce_motion = false


func test_instantiates_with_map_shader_layer() -> void:
	var bg: ParallaxBackground = _SCENE.instantiate()
	add_child_autofree(bg)
	await wait_frames(1)
	assert_true(bg is ParallaxBackground,
			"root keeps the ParallaxBackground type for save-compat + tier-event hookup")
	assert_eq(bg.layer, -2, "background must render behind sibling Controls (layer < 0)")
	assert_not_null(bg._map_rect, "map ColorRect must be built in _ready")
	assert_true(bg._map_rect is ColorRect,
			"Phase 14d uses a single fullscreen ColorRect, not three parallax layers")


func test_map_rect_has_shader_material() -> void:
	var bg: ParallaxBackground = _SCENE.instantiate()
	add_child_autofree(bg)
	await wait_frames(1)
	assert_true(bg._map_rect.material is ShaderMaterial,
			"map ColorRect must have a ShaderMaterial that paints the styles.css `.map` stack")
	assert_not_null(bg._map_material,
			"_map_material reference must be live for tier-palette swaps")


func test_tier_palette_routes_through_band_accent() -> void:
	# Tier 1 → band 0 (teal accent), tier 11 → band 2 (magenta horizon-leaning).
	# Pin the band lookup behaviour by checking the public test seam
	# rather than reading shader uniforms (which need a render frame).
	var bg = _SCENE.instantiate()
	add_child_autofree(bg)
	await wait_frames(1)

	GameState.current_max_tier = 1
	bg._apply_tier_palette(1)
	assert_eq(bg._test_current_accent_key(), "teal",
			"tier 1 must use the teal accent (band 0 — early Bog Hollow cool)")

	GameState.current_max_tier = 11
	bg._apply_tier_palette(11)
	assert_eq(bg._test_current_accent_key(), "magenta",
			"tier 11 must use the magenta accent (band 2 — late horizon-leaning)")


func test_shader_bg_color_matches_dusk_palette() -> void:
	# After _apply_tier_palette, the shader's `bg_color` uniform must
	# carry the Dusk `bg` token. This catches a regression where the
	# parchment fallback color sneaks back into the shader uniforms.
	var bg = _SCENE.instantiate()
	add_child_autofree(bg)
	await wait_frames(1)
	bg._apply_tier_palette(1)
	var bg_color: Color = bg._map_material.get_shader_parameter("bg_color")
	var expected: Color = _DUSK.amethyst()["bg"]
	assert_almost_eq(bg_color.r, expected.r, 0.001)
	assert_almost_eq(bg_color.g, expected.g, 0.001)
	assert_almost_eq(bg_color.b, expected.b, 0.001)


func test_scroll_uniform_advances_in_process() -> void:
	# The shader-side scroll uniform replaces the old
	# `ParallaxBackground.scroll_offset.x` ambient drift. After a real-time
	# wait the `scroll_x` uniform should have advanced past zero.
	var bg = _SCENE.instantiate()
	add_child_autofree(bg)
	await wait_frames(1)
	var initial: float = bg._map_material.get_shader_parameter("scroll_x")
	await wait_seconds(0.4)
	var after: float = bg._map_material.get_shader_parameter("scroll_x")
	assert_gt(after, initial,
			"ambient scroll should advance shader uniform `scroll_x` within 0.4s")


func test_reduce_motion_freezes_scroll() -> void:
	# Accessibility: reduce_motion users must NOT see any background
	# drift. The shader `scroll_x` uniform stays at whatever value it
	# was when reduce_motion flipped on.
	var bg = _SCENE.instantiate()
	add_child_autofree(bg)
	await wait_frames(1)
	Settings.reduce_motion = true
	var initial: float = bg._map_material.get_shader_parameter("scroll_x")
	await wait_seconds(0.4)
	var after: float = bg._map_material.get_shader_parameter("scroll_x")
	assert_almost_eq(after, initial, 0.001,
			"reduce_motion must freeze the shader scroll_x uniform")
