## Phase 10e.1 — battle map.
##
## Hosts a parallax background, a tiled ground strip, a Camera2D, and
## a `Combatants` Node2D where the BattleView spawns up to 6
## `combatant` instances (3 per side). Layout is fixed-size (intended
## viewport: 720x520) so positions are stable across replays.
##
## Shape:
##   ┌──────────────────────── 720 ────────────────────────┐
##   │                          (sky)                       │
##   │                                                      │
##   │  ┌── player team ──┐         ┌── enemy team ──┐     │
##   │  │ p0 (180, 280)   │   ←→    │ e0 (540, 280)   │     │
##   │  │ p1 (180, 340)   │         │ e1 (540, 340)   │     │
##   │  │ p2 (180, 400)   │         │ e2 (540, 400)   │     │
##   │  └─────────────────┘         └─────────────────┘     │
##   │ ════ ground ════════════════════════════════════════ │
##   └─────────────────── 520 ──────────────────────────────┘
##
## Player team walks in from x = -60; enemy team from x = 780.
extends Node2D

const _PALETTE := preload("res://game/resources/palette_colors.gd")

const VIEWPORT_SIZE := Vector2(720, 520)
const GROUND_Y: float = 460.0
const PLAYER_ENGAGEMENT_X: float = 230.0
const ENEMY_ENGAGEMENT_X: float = 490.0
const PLAYER_START_X: float = -60.0
const ENEMY_START_X: float = 780.0
const SLOT_Y_BASE: float = 280.0
const SLOT_Y_STEP: float = 60.0

const _SKY_SHADER := """
shader_type canvas_item;
uniform vec4 top_color : source_color = vec4(0.95, 0.78, 0.62, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.93, 0.88, 0.74, 1.0);
void fragment() {
	COLOR = mix(top_color, bottom_color, UV.y);
}
"""

# Tier-band sky colors mirroring catching_background's palette so the
# two screens read as the same world.
const _SKY_TOP_BY_BAND := [
	Color(0.95, 0.78, 0.62, 1.0),
	Color(0.42, 0.30, 0.22, 1.0),
	Color(0.55, 0.40, 0.62, 1.0),
	Color(0.10, 0.06, 0.10, 1.0),
]
const _SKY_BOTTOM_BY_BAND := [
	Color(0.93, 0.88, 0.74, 1.0),
	Color(0.18, 0.12, 0.08, 1.0),
	Color(0.93, 0.78, 0.66, 1.0),
	Color(0.45, 0.10, 0.16, 1.0),
]

var _sky_material: ShaderMaterial
var _camera: Camera2D
var _combatants_layer: Node2D


func _ready() -> void:
	_build_background()
	_build_ground()
	_build_camera()
	_combatants_layer = Node2D.new()
	_combatants_layer.name = "Combatants"
	add_child(_combatants_layer)
	apply_tier_palette(_current_tier())


## Returns the engagement position for slot `index` on the given team.
func engagement_pos(team: String, index: int) -> Vector2:
	var x: float = PLAYER_ENGAGEMENT_X if team == "player" else ENEMY_ENGAGEMENT_X
	return Vector2(x, SLOT_Y_BASE + float(index) * SLOT_Y_STEP)


## Returns the off-screen start position so a combatant can walk in.
func start_pos(team: String, index: int) -> Vector2:
	var x: float = PLAYER_START_X if team == "player" else ENEMY_START_X
	return Vector2(x, SLOT_Y_BASE + float(index) * SLOT_Y_STEP)


## True if this team faces right (player) or left (enemy).
func facing_for_team(team: String) -> int:
	return 1 if team == "player" else -1


## BattleView calls this on every new battle to clear stale combatants
## and re-host fresh ones. Returns the Combatants layer for the caller
## to add_child into.
func combatants_layer() -> Node2D:
	return _combatants_layer


func clear_combatants() -> void:
	if _combatants_layer == null:
		return
	for c in _combatants_layer.get_children():
		c.queue_free()


# Sky modulation by tier band. Public so battle_view can drive it on
# new battles instead of waiting for an EventBus signal.
func apply_tier_palette(tier: int) -> void:
	if _sky_material == null:
		return
	var band: int = clamp((tier - 1) / 5, 0, _SKY_TOP_BY_BAND.size() - 1)
	_sky_material.set_shader_parameter("top_color", _SKY_TOP_BY_BAND[band])
	_sky_material.set_shader_parameter("bottom_color", _SKY_BOTTOM_BY_BAND[band])


func _build_background() -> void:
	var bg := ColorRect.new()
	bg.size = VIEWPORT_SIZE
	bg.position = Vector2.ZERO
	var shader := Shader.new()
	shader.code = _SKY_SHADER
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = shader
	bg.material = _sky_material
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Distant silhouette ridge for depth.
	var ridge := Polygon2D.new()
	ridge.color = _PALETTE.SEPIA_MID
	ridge.modulate.a = 0.45
	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(Vector2(0, GROUND_Y))
	var bumps: Array[float] = [380.0, 350.0, 410.0, 360.0, 400.0, 370.0, 390.0, 360.0, 410.0, 380.0, 360.0, 400.0]
	var x: float = 0.0
	var step: float = 60.0
	var i: int = 0
	while x <= VIEWPORT_SIZE.x:
		pts.append(Vector2(x, bumps[i % bumps.size()]))
		x += step
		i += 1
	pts.append(Vector2(VIEWPORT_SIZE.x, GROUND_Y))
	ridge.polygon = pts
	add_child(ridge)


func _build_ground() -> void:
	var ground := Polygon2D.new()
	ground.color = _PALETTE.SEPIA_DARK
	ground.modulate.a = 0.85
	var w: float = VIEWPORT_SIZE.x
	var h: float = VIEWPORT_SIZE.y
	ground.polygon = PackedVector2Array([
			Vector2(0, GROUND_Y),
			Vector2(w, GROUND_Y),
			Vector2(w, h),
			Vector2(0, h),
	])
	add_child(ground)

	# A lighter highlight strip just above ground level so the engagement
	# line reads more clearly than a flat sepia block would.
	var highlight := Polygon2D.new()
	highlight.color = _PALETTE.BRASS_ACCENT
	highlight.modulate.a = 0.25
	highlight.polygon = PackedVector2Array([
			Vector2(0, GROUND_Y - 2),
			Vector2(w, GROUND_Y - 2),
			Vector2(w, GROUND_Y + 2),
			Vector2(0, GROUND_Y + 2),
	])
	add_child(highlight)


func _build_camera() -> void:
	_camera = Camera2D.new()
	# Camera anchors to the centre of the viewport. The SubViewport
	# itself is sized to VIEWPORT_SIZE, so this just centres the world.
	_camera.position = VIEWPORT_SIZE * 0.5
	_camera.enabled = true
	add_child(_camera)


func _current_tier() -> int:
	if Engine.is_editor_hint():
		return 1
	if not has_node("/root/GameState"):
		return 1
	var gs := get_node("/root/GameState")
	if gs == null:
		return 1
	return clamp(int(gs.current_max_tier), 1, 20)
