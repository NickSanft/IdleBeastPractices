## Phase 10e.1 — single combatant on the battle map.
##
## Reads its visual state from BattleLog frames; does NOT compute
## combat. The deterministic [BattleSystem] runs first, the resulting
## frames are replayed via `apply_frame()` and `walk_to_engagement()`.
##
## State machine:
##   WALK_IN              — sliding from off-screen toward engagement_pos
##   IDLE_AT_ENGAGEMENT   — gentle bob in place, ready to attack/be hit
##   ATTACK_LUNGE         — tween toward target, then back
##   HURT_FLASH           — modulate-driven white flash on take-damage
##   DEFEATED_FADE        — alpha + rotation fade-out, no more updates
##
## A defeated combatant ignores subsequent frame applies (the BattleLog
## may still address it via `target` strings; we silently no-op).
extends Node2D

const _PALETTE := preload("res://game/resources/palette_colors.gd")
const _SPRITE_FRAME_SIZE := Vector2(32, 32)
const _RENDER_SCALE := 2.5
const _WALK_SPEED_PX_PER_SEC := 240.0
const _IDLE_BOB_AMPLITUDE := 2.0
const _IDLE_BOB_HZ := 1.4
const _LUNGE_REACH := 28.0   # px of forward motion during attack
const _LUNGE_OUT_SECS := 0.08
const _LUNGE_BACK_SECS := 0.12

enum State { WALK_IN, IDLE_AT_ENGAGEMENT, ATTACK_LUNGE, HURT_FLASH, DEFEATED_FADE }

# Public configuration set via `setup()` before the combatant is added
# to the scene tree.
var team: String = ""
var combatant_index: int = 0
var max_hp: float = 0.0
var hp: float = 0.0
var engagement_pos: Vector2 = Vector2.ZERO
## +1 for player (faces right), -1 for enemy (faces left).
var facing: int = 1
## Texture and tint plumbed through from PetResource / MonsterResource.
var sprite_texture: Texture2D
var sprite_tint: Color = Color.WHITE
## Public so tests + battle_view can read state without touching internals.
var state: int = State.WALK_IN

var _sprite: Sprite2D
var _hp_bar: ProgressBar
var _bob_phase: float = 0.0
var _lunge_tween: Tween
var _flash_tween: Tween
var _defeated: bool = false


func setup(
		p_team: String,
		p_index: int,
		p_max_hp: float,
		p_engagement: Vector2,
		p_start: Vector2,
		p_facing: int,
		p_texture: Texture2D,
		p_tint: Color = Color.WHITE) -> void:
	team = p_team
	combatant_index = p_index
	max_hp = max(1.0, p_max_hp)
	hp = max_hp
	engagement_pos = p_engagement
	position = p_start
	facing = -1 if p_facing < 0 else 1
	sprite_texture = p_texture
	sprite_tint = p_tint


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2(Vector2.ZERO, _SPRITE_FRAME_SIZE)
	_sprite.scale = Vector2(float(facing) * _RENDER_SCALE, _RENDER_SCALE)
	_sprite.texture = sprite_texture
	_sprite.modulate = sprite_tint
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)

	_hp_bar = ProgressBar.new()
	_hp_bar.show_percentage = false
	_hp_bar.size = Vector2(64, 6)
	_hp_bar.position = Vector2(-32, -52)
	_hp_bar.min_value = 0.0
	_hp_bar.max_value = max_hp
	_hp_bar.value = hp
	_hp_bar.modulate = _PALETTE.SAGE_GREEN if team == "player" else _PALETTE.BLOOD_RUBY
	add_child(_hp_bar)
	set_process(true)


func _process(delta: float) -> void:
	if state == State.WALK_IN:
		_step_walk_in(delta)
	elif state == State.IDLE_AT_ENGAGEMENT:
		_step_idle_bob(delta)


func _step_walk_in(delta: float) -> void:
	var to_target: Vector2 = engagement_pos - position
	var step: float = _WALK_SPEED_PX_PER_SEC * delta
	if to_target.length() <= step:
		position = engagement_pos
		state = State.IDLE_AT_ENGAGEMENT
		_bob_phase = 0.0
	else:
		position += to_target.normalized() * step


func _step_idle_bob(delta: float) -> void:
	# v0.11.1 (Phase 11b): reduce_motion users see static combatants
	# at engagement_pos. They're still visually distinct from
	# defeated combatants (which are faded + tilted).
	if Settings.reduce_motion:
		position = engagement_pos
		return
	_bob_phase += delta * _IDLE_BOB_HZ
	# A trig bob keeps idle combatants visually distinct from defeated
	# ones (which are static + faded).
	position = engagement_pos + Vector2(0.0, sin(_bob_phase * TAU) * _IDLE_BOB_AMPLITUDE)


## Public: BattleMap calls this when a frame names this combatant as
## the actor. Plays a quick lunge toward the target's screen position
## then returns to engagement_pos. No-op if already defeated.
##
## v0.11.1 (Phase 11b): reduce_motion players skip the position
## tween. The brief hurt-flash on the target still fires, so the
## "X attacked Y" beat reads through color rather than position.
func play_attack_lunge(target_pos: Vector2) -> void:
	if state == State.DEFEATED_FADE or _defeated:
		return
	if Settings.reduce_motion:
		# Still set state briefly so the state machine reflects "this
		# combatant just acted" — useful for debug + tests — but skip
		# the visible motion.
		state = State.ATTACK_LUNGE
		_on_lunge_complete()
		return
	var dir: Vector2 = (target_pos - engagement_pos).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2(float(facing), 0.0)
	if _lunge_tween != null and _lunge_tween.is_valid():
		_lunge_tween.kill()
	state = State.ATTACK_LUNGE
	_lunge_tween = create_tween()
	_lunge_tween.tween_property(self, "position", engagement_pos + dir * _LUNGE_REACH, _LUNGE_OUT_SECS)
	_lunge_tween.tween_property(self, "position", engagement_pos, _LUNGE_BACK_SECS)
	_lunge_tween.tween_callback(_on_lunge_complete)


func _on_lunge_complete() -> void:
	if state == State.ATTACK_LUNGE:
		state = State.IDLE_AT_ENGAGEMENT
		_bob_phase = 0.0


## Public: BattleMap calls this when a frame names this combatant as
## the target. Updates HP, plays the hurt flash, and triggers the
## defeated fade if HP just hit zero. `new_hp` is in BattleLog units
## (int from the frame).
func apply_damage(new_hp: int) -> void:
	if _defeated:
		return
	hp = max(0.0, float(new_hp))
	_hp_bar.value = hp
	_play_hurt_flash()
	if hp <= 0.0:
		_defeated = true
		_play_defeated_fade()


func _play_hurt_flash() -> void:
	if _sprite == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	# Brief HDR-style overbright flash, then back to the sprite tint.
	_flash_tween.tween_property(_sprite, "modulate", Color(2.4, 1.6, 1.6, 1.0), 0.04)
	_flash_tween.tween_property(_sprite, "modulate", sprite_tint, 0.10)


func _play_defeated_fade() -> void:
	state = State.DEFEATED_FADE
	if _lunge_tween != null and _lunge_tween.is_valid():
		_lunge_tween.kill()
	if _hp_bar != null:
		_hp_bar.visible = false
	if _sprite == null:
		return
	# v0.11.1 (Phase 11b): reduce_motion skips the topple rotation.
	# Pure alpha fade still conveys defeat without the rotational
	# motion that triggers vestibular issues for some players.
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_sprite, "modulate:a", 0.0, 0.45)
	if not Settings.reduce_motion:
		var tilt: float = deg_to_rad(70.0) * float(-facing)
		t.tween_property(_sprite, "rotation", tilt, 0.45)


## True once the defeated-fade tween starts. Tests + battle_view
## inspect this without scraping state internals.
func is_defeated() -> bool:
	return _defeated
