## Phase 10b — parallax background for the catching screen.
##
## Three ParallaxLayers (sky / mid silhouette / near ground) plus a
## constant slow scroll so the world feels alive even when no monsters
## are on screen. Sky color shifts by tier band:
##   tiers 1-5   warm dawn (parchment-pink top, vellum bottom)
##   tiers 6-10  cave (dim sepia top, deep brown bottom)
##   tiers 11-15 dusk (purple-brass top, parchment bottom)
##   tiers 16-20 abyss (near-black top, deep ruby bottom)
##
## Built script-side (consistent with the rest of the project's UI).
extends ParallaxBackground

const _PALETTE := preload("res://game/resources/palette_colors.gd")
const _SCROLL_SPEED_PX_PER_SEC := 6.0  # gentle ambient drift

# Tier-band sky colors. Index by tier-1 / 5 to get the band.
const _SKY_TOP_BY_BAND := [
	Color(0.95, 0.78, 0.62, 1.0),   # 1-5  dawn
	Color(0.42, 0.30, 0.22, 1.0),   # 6-10 cave
	Color(0.55, 0.40, 0.62, 1.0),   # 11-15 dusk
	Color(0.10, 0.06, 0.10, 1.0),   # 16-20 abyss
]
const _SKY_BOTTOM_BY_BAND := [
	Color(0.93, 0.88, 0.74, 1.0),   # parchment
	Color(0.18, 0.12, 0.08, 1.0),   # cave floor
	Color(0.93, 0.78, 0.66, 1.0),   # warm parchment dusk
	Color(0.45, 0.10, 0.16, 1.0),   # ruby deep
]

const _SKY_SHADER := """
shader_type canvas_item;
uniform vec4 top_color : source_color = vec4(0.95, 0.78, 0.62, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.93, 0.88, 0.74, 1.0);
void fragment() {
	COLOR = mix(top_color, bottom_color, UV.y);
}
"""

var _sky_material: ShaderMaterial
var _sky_rect: ColorRect
var _scroll_x: float = 0.0


func _ready() -> void:
	# CanvasLayer.layer < 0 puts the parallax behind sibling Control nodes
	# living on the default layer (0). Catch view UI stays in front.
	layer = -2
	_build_sky()
	_build_mid_silhouette()
	_build_near_ground()
	_apply_tier_palette(_current_tier())
	if EventBus.has_signal("tier_unlocked"):
		EventBus.tier_unlocked.connect(_on_tier_unlocked)
	set_process(true)


func _process(delta: float) -> void:
	_scroll_x += _SCROLL_SPEED_PX_PER_SEC * delta
	# Wrap manually so floating-point precision doesn't drift over a long
	# session. ParallaxLayer's motion_mirroring handles the visual wrap;
	# we just feed it a steady scroll offset.
	scroll_offset = Vector2(_scroll_x, 0.0)


func _build_sky() -> void:
	var layer_node := ParallaxLayer.new()
	layer_node.name = "Sky"
	layer_node.motion_scale = Vector2(0.0, 0.0)   # static back wall
	add_child(layer_node)

	var shader := Shader.new()
	shader.code = _SKY_SHADER
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = shader

	_sky_rect = ColorRect.new()
	_sky_rect.material = _sky_material
	# Cover comfortably more than the viewport so the rect never reveals
	# its edge under any phone/tablet aspect.
	_sky_rect.size = Vector2(1500, 2200)
	_sky_rect.position = Vector2(-100, -100)
	layer_node.add_child(_sky_rect)


func _build_mid_silhouette() -> void:
	# Distant mountains. Polygon2D with a jagged top over a 1500px width;
	# motion_mirroring so it tiles seamlessly as scroll_offset advances.
	var layer_node := ParallaxLayer.new()
	layer_node.name = "Mid"
	layer_node.motion_scale = Vector2(0.3, 0.0)
	layer_node.motion_mirroring = Vector2(1500, 0)
	add_child(layer_node)

	var poly := Polygon2D.new()
	poly.color = _PALETTE.SEPIA_MID
	poly.modulate.a = 0.55
	# Build jagged ridge at y≈900 across 1500px. The viewport is 720x1280
	# so this places the silhouette in the lower-third of the screen.
	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(Vector2(0, 1280))
	var step: float = 75.0
	var x: float = 0.0
	var bumps: Array[float] = [820.0, 760.0, 880.0, 740.0, 900.0, 800.0, 860.0, 770.0, 830.0, 790.0, 870.0, 810.0, 850.0, 780.0, 890.0, 820.0, 760.0, 840.0, 790.0, 880.0, 770.0]
	var i: int = 0
	while x <= 1500.0:
		pts.append(Vector2(x, bumps[i % bumps.size()]))
		x += step
		i += 1
	pts.append(Vector2(1500, 1280))
	poly.polygon = pts
	layer_node.add_child(poly)


func _build_near_ground() -> void:
	var layer_node := ParallaxLayer.new()
	layer_node.name = "Near"
	layer_node.motion_scale = Vector2(0.7, 0.0)
	layer_node.motion_mirroring = Vector2(1500, 0)
	add_child(layer_node)

	# Foreground rolling hills at y≈1080. Same construction pattern as Mid
	# but with a different bump sequence and a darker, more saturated tone.
	var poly := Polygon2D.new()
	poly.color = _PALETTE.SEPIA_DARK
	poly.modulate.a = 0.85
	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(Vector2(0, 1280))
	var step: float = 60.0
	var x: float = 0.0
	var bumps: Array[float] = [1110.0, 1080.0, 1130.0, 1070.0, 1120.0, 1090.0, 1140.0, 1100.0, 1080.0, 1130.0, 1100.0, 1070.0, 1140.0, 1090.0, 1120.0, 1080.0, 1110.0, 1100.0, 1130.0, 1090.0, 1070.0, 1140.0, 1100.0, 1080.0, 1120.0, 1110.0]
	var i: int = 0
	while x <= 1500.0:
		pts.append(Vector2(x, bumps[i % bumps.size()]))
		x += step
		i += 1
	pts.append(Vector2(1500, 1280))
	poly.polygon = pts
	layer_node.add_child(poly)


func _on_tier_unlocked(_tier: int) -> void:
	_apply_tier_palette(_current_tier())


func _current_tier() -> int:
	if Engine.is_editor_hint():
		return 1
	if not has_node("/root/GameState"):
		return 1
	var gs := get_node("/root/GameState")
	if gs == null:
		return 1
	# GameState.current_max_tier is 1-indexed.
	var t: int = int(gs.current_max_tier)
	return clamp(t, 1, 20)


func _apply_tier_palette(tier: int) -> void:
	if _sky_material == null:
		return
	var band: int = clamp((tier - 1) / 5, 0, _SKY_TOP_BY_BAND.size() - 1)
	_sky_material.set_shader_parameter("top_color", _SKY_TOP_BY_BAND[band])
	_sky_material.set_shader_parameter("bottom_color", _SKY_BOTTOM_BY_BAND[band])
