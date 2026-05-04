## Phase 10b — smoke tests for the catching screen parallax background.
##
## Doesn't try to exercise visual scroll (that needs a viewport + render
## frames). Verifies the scene structure: a ParallaxBackground root with
## a Sky / Mid / Near layer, and that the sky shader's color uniforms
## switch when the tier palette is reapplied.
extends GutTest

const _SCENE := preload("res://game/scenes/catching/catching_background.tscn")


func test_instantiates_with_three_parallax_layers() -> void:
	var bg: ParallaxBackground = _SCENE.instantiate()
	add_child_autofree(bg)
	await wait_frames(1)
	assert_true(bg is ParallaxBackground, "root must be a ParallaxBackground")
	assert_eq(bg.layer, -2, "background must render behind sibling Controls (layer < 0)")
	assert_not_null(bg.get_node_or_null("Sky"))
	assert_not_null(bg.get_node_or_null("Mid"))
	assert_not_null(bg.get_node_or_null("Near"))


func test_sky_layer_has_shader_material() -> void:
	var bg: ParallaxBackground = _SCENE.instantiate()
	add_child_autofree(bg)
	await wait_frames(1)
	var sky_layer := bg.get_node("Sky")
	# The sky ColorRect lives one level under the layer.
	var color_rect: ColorRect = null
	for child in sky_layer.get_children():
		if child is ColorRect:
			color_rect = child
			break
	assert_not_null(color_rect, "Sky ParallaxLayer must contain a ColorRect")
	assert_true(color_rect.material is ShaderMaterial,
			"sky ColorRect must have a ShaderMaterial for the gradient")


func test_tier_palette_updates_sky_uniforms() -> void:
	var bg = _SCENE.instantiate()
	add_child_autofree(bg)
	await wait_frames(1)
	var sky_mat: ShaderMaterial = bg._sky_material
	assert_not_null(sky_mat, "_sky_material must be set after _ready")
	# Tier 1 uses band 0 (dawn).
	bg._apply_tier_palette(1)
	var dawn_top: Color = sky_mat.get_shader_parameter("top_color")
	# Tier 11 lands in band 2 (dusk) — should differ from dawn.
	bg._apply_tier_palette(11)
	var dusk_top: Color = sky_mat.get_shader_parameter("top_color")
	assert_true(dawn_top != dusk_top,
			"sky top_color must shift between tier bands (dawn != dusk)")


func test_scroll_offset_advances_in_process() -> void:
	# The background owns a slow ambient scroll. After a real-time wait
	# the scroll_offset.x should have advanced past zero.
	var bg = _SCENE.instantiate()
	add_child_autofree(bg)
	await wait_frames(1)
	var initial: float = bg.scroll_offset.x
	await wait_seconds(0.4)
	assert_gt(bg.scroll_offset.x, initial,
			"ambient scroll should advance scroll_offset.x within 0.4s")
