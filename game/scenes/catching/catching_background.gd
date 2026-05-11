## Phase 14d — Dusk map background.
##
## Reskinned per `docs/design_handoff_theming/reference_files/styles.css`
## `.map` block. Replaces the parchment dawn/dusk gradient + jagged
## silhouette polygons with a flat dusk repeating-stripe map, a horizontal
## scanline overlay (CRT pixel-art feel), and two radial dusk glows
## (teal at center-upper, magenta horizon at top, gold corner spark).
##
## The full layer stack lives inside a single fullscreen `ColorRect`
## driven by a fragment shader — cheaper than ParallaxBackground +
## three layers + two polygons, and the styles.css reference is a
## stack of `repeating-linear-gradient` + `radial-gradient` calls
## which map to shader math one-for-one.
##
## CRT pixel-art constraint: the shader samples by `FRAGCOORD.xy` (raw
## pixel coords) so the 16-px band, 17-px column-line, and 4-px
## scanline overlays stay at their handoff sizes regardless of
## viewport scale. UV-driven radial glows still scale across aspect
## ratios.
##
## Per-tier band: README mentions vignette props per tier (small
## ASCII labels at fixed % positions). Deferred to 14g polish along
## with the gold L-bracket corners, since the gameplay value is low
## next to the bg + scanline + monster card chrome that ships here.
##
## `reduce_motion` still applies — the parallax drift is gone, but
## the original 10c gentle scroll feel is preserved by a slow shader
## scroll offset (defaults off for `reduce_motion = true`).
extends ParallaxBackground

const _DUSK := preload("res://assets/themes/dusk/palette_dusk.gd")

# Slow horizontal drift on the stripe + scanline so the bg feels alive
# without the heavier parallax-mountain effect of the parchment era.
# Disabled when `reduce_motion` is on.
const _SCROLL_SPEED_PX_PER_SEC := 6.0

# Tier-band glow tint accents. Dusk handoff is palette-driven (not a
# per-band swap), but we keep a subtle accent so progressing tiers
# still reads as a visual change. Index = (tier-1) / 5.
#
# Band 0 (tiers 1-5):  teal-leaning (default — the "Bog Hollow" cool)
# Band 1 (tiers 6-10): teal+gold mix (cave-band warm)
# Band 2 (tiers 11-15): magenta horizon push
# Band 3 (tiers 16-20): rose/danger accent
const _BAND_ACCENT := [
	"teal",      # 1-5
	"gold",      # 6-10
	"magenta",   # 11-15
	"rose",      # 16-20
]

const _MAP_SHADER := """
shader_type canvas_item;

uniform vec4 bg_color : source_color = vec4(0.082, 0.063, 0.180, 1.0);
uniform vec4 bg2_color : source_color = vec4(0.114, 0.086, 0.251, 1.0);
uniform vec4 accent_color : source_color = vec4(0.373, 0.827, 0.761, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.851, 0.435, 0.722, 1.0);
uniform vec4 gold_color : source_color = vec4(0.961, 0.769, 0.420, 1.0);
uniform vec2 viewport_px = vec2(720.0, 1280.0);
uniform float scroll_x = 0.0;

void fragment() {
	// Pixel-space samples for the chunky CRT bands. Scaled relative to
	// a 720-wide design viewport so the 16-px / 4-px sizes stay visually
	// consistent at any window size.
	vec2 px = UV * viewport_px;
	vec2 px_scroll = vec2(px.x - scroll_x, px.y);

	// Horizontal band stripes — repeating-linear-gradient 0deg, 16px each.
	// `band` toggles 0/1 every 16 vertical pixels.
	float band = mod(floor(px.y / 16.0), 2.0);
	vec3 col = mix(bg_color.rgb, bg2_color.rgb, band);

	// Vertical column-line scanline — repeating-linear-gradient 90deg,
	// 16px transparent + 1px rgba(0,0,0,0.12). i.e. a faint black hairline
	// every 17 pixels. Scrolls horizontally so the bg drifts.
	float col_line = step(16.0, mod(px_scroll.x, 17.0));
	col = mix(col, vec3(0.0), 0.12 * col_line);

	// Radial dusk glow at center-upper (styles.css `.map` background) —
	// teal at 8% opacity, ellipse 50% / 30%.
	vec2 to_center = (UV - vec2(0.5, 0.3)) * vec2(1.0, 2.2);
	float teal_glow = clamp(1.0 - length(to_center) / 0.6, 0.0, 1.0);
	col = mix(col, accent_color.rgb, teal_glow * 0.10);

	// Far horizon glow — magenta ellipse at 50% 0% (top), 18% opacity.
	vec2 to_top = (UV - vec2(0.5, 0.0)) * vec2(0.8, 3.0);
	float horizon = clamp(1.0 - length(to_top) / 0.7, 0.0, 1.0);
	col = mix(col, horizon_color.rgb, horizon * 0.18);

	// Gold corner spark at 12% / 14%, 12% opacity.
	float gold = clamp(1.0 - distance(UV, vec2(0.12, 0.14)) / 0.30, 0.0, 1.0);
	col = mix(col, gold_color.rgb, gold * 0.12);

	// Horizontal scanline overlay — 4-px bands, top 2 px clear / bottom 2 px
	// 10% black, multiply blend at 0.35 strength. Produces the CRT feel.
	float scanline = step(2.0, mod(px.y, 4.0));
	col *= (1.0 - scanline * 0.10 * 0.35);

	COLOR = vec4(col, 1.0);
}
"""

var _map_material: ShaderMaterial
var _map_rect: ColorRect
var _scroll_x: float = 0.0


func _ready() -> void:
	# CanvasLayer.layer < 0 puts the parallax behind sibling Control nodes
	# living on the default layer (0). Catch view UI stays in front.
	layer = -2
	_build_map()
	_apply_tier_palette(_current_tier())
	if EventBus.has_signal("tier_unlocked"):
		EventBus.tier_unlocked.connect(_on_tier_unlocked)
	# Track viewport size so the shader's `viewport_px` uniform stays
	# in sync with the actual draw area. styles.css's pixel-scale
	# overlays (16-px band, 4-px scanline) need this to keep their
	# chunky feel regardless of orientation/density.
	var vp := get_viewport()
	if vp != null:
		vp.size_changed.connect(_on_viewport_resized)
		_on_viewport_resized()
	set_process(true)


func _process(delta: float) -> void:
	# v0.11.1 (Phase 11b): reduce_motion users get a static background.
	# Continuous drift at the bottom of the visual hierarchy is exactly
	# the kind of "nothing's wrong but my eyes are tracking motion"
	# effect motion-sensitive players ask to disable.
	if Settings.reduce_motion:
		return
	if _map_material == null:
		return
	_scroll_x += _SCROLL_SPEED_PX_PER_SEC * delta
	# Wrap manually so floating-point precision doesn't drift over a long
	# session. 1700 = lcm-friendly multiple of both stripe periods.
	if _scroll_x > 1700.0:
		_scroll_x = fmod(_scroll_x, 1700.0)
	_map_material.set_shader_parameter("scroll_x", _scroll_x)


func _build_map() -> void:
	var shader := Shader.new()
	shader.code = _MAP_SHADER
	_map_material = ShaderMaterial.new()
	_map_material.shader = shader

	# Single fullscreen ColorRect. ParallaxLayer is no longer needed — we
	# do the scrolling inside the shader via a uniform, and the silhouette
	# polygons are replaced by the stripe pattern itself.
	_map_rect = ColorRect.new()
	_map_rect.material = _map_material
	# Anchor full and pad slightly beyond viewport so any sub-pixel
	# rounding never reveals the edge.
	_map_rect.size = Vector2(2000, 2400)
	_map_rect.position = Vector2(-100, -100)
	_map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_map_rect)
	# `set_shader_parameter` for every uniform we care to read back —
	# Godot's `get_shader_parameter` returns null if the uniform was
	# never explicitly set, even when the shader declares a default
	# value. Initializing scroll_x here means tests + tooling can read
	# it as a `float` from the moment the rect is in the tree.
	_map_material.set_shader_parameter("scroll_x", 0.0)


func _on_viewport_resized() -> void:
	if _map_material == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var vp_size: Vector2 = Vector2(vp.get_visible_rect().size)
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return
	_map_material.set_shader_parameter("viewport_px", vp_size)


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
	if _map_material == null:
		return
	var palette: Dictionary = _DUSK.amethyst()
	# Pass the base bg / bg_2 verbatim — the stripe stays the same
	# Dusk amethyst regardless of tier; only the *accent* glow shifts
	# per tier band for a subtle visual progression cue.
	_map_material.set_shader_parameter("bg_color", palette["bg"])
	_map_material.set_shader_parameter("bg2_color", palette["bg_2"])
	# Tier-band index is deliberately integer division: tiers 1-5 → 0,
	# 6-10 → 1, etc. Decimal truncation is the desired behaviour.
	@warning_ignore("integer_division")
	var band: int = clamp((tier - 1) / 5, 0, _BAND_ACCENT.size() - 1)
	var accent_key: String = _BAND_ACCENT[band]
	_map_material.set_shader_parameter("accent_color", palette[accent_key])
	# Horizon stays magenta (styles.css explicit) and corner stays gold —
	# the per-tier shift is in `accent_color` alone so the dusk identity
	# survives across all 20 tiers.
	_map_material.set_shader_parameter("horizon_color", palette["magenta"])
	_map_material.set_shader_parameter("gold_color", palette["gold"])


## Test seam — lets test_catching_background introspect the current
## accent without forcing it to read shader uniforms (which require an
## active rendering pipeline). Returns the palette key in use.
func _test_current_accent_key() -> String:
	@warning_ignore("integer_division")
	var band: int = clamp((_current_tier() - 1) / 5, 0, _BAND_ACCENT.size() - 1)
	return _BAND_ACCENT[band]
