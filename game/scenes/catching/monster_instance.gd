## A single on-screen catchable monster.
##
## Owns its own wander state machine and tap_progress accumulator. The
## containing CatchingView listens to `tapped` and `caught_self` to
## resolve catches via CatchingSystem and update GameState.
extends Node2D

signal tapped(instance: Node2D)
signal caught_self(instance: Node2D)

const _WANDER_SPEED_PX_PER_SEC := 60.0
const _PAUSE_TIME_RANGE := Vector2(0.4, 1.4)
const _SPRITE_FRAME_SIZE := Vector2(32, 32)
const _RENDER_SCALE := 3.0
## Print one line per tap and per catch to the Godot console. Phase 2 dev aid;
## flip to false (or remove) once the catch loop is verified end-to-end.
const _DEBUG_LOG := true

@export var monster: MonsterResource
@export var instance_id: int = 0
@export var bounds: Rect2 = Rect2(0, 0, 720, 1100)

var tap_progress: float = 0.0

var _sprite: Sprite2D
var _area: Area2D
var _collision: CollisionShape2D
var _tap_particles: CPUParticles2D
var _catch_particles: CPUParticles2D

var _state: int = _State.WANDER
var _target_pos: Vector2
var _pause_left: float = 0.0
var _alive: bool = true

enum _State { WANDER, PAUSE, CAUGHT }


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2(Vector2.ZERO, _SPRITE_FRAME_SIZE)
	_sprite.scale = Vector2(_RENDER_SCALE, _RENDER_SCALE)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)

	_area = Area2D.new()
	_area.input_pickable = true
	_collision = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = _SPRITE_FRAME_SIZE * _RENDER_SCALE
	_collision.shape = shape
	_area.add_child(_collision)
	add_child(_area)
	_area.input_event.connect(_on_area_input_event)

	_tap_particles = _make_particles(Color(1.0, 0.95, 0.5), 10, 0.35, 60.0, 120.0, 1.5, 2.5)
	add_child(_tap_particles)
	_catch_particles = _make_particles(Color(0.6, 1.0, 0.85), 24, 0.55, 100.0, 220.0, 2.0, 4.0)
	add_child(_catch_particles)

	if monster != null:
		_apply_monster()
	_pick_new_target()


func _make_particles(
		color: Color,
		amount: int,
		lifetime: float,
		speed_min: float,
		speed_max: float,
		scale_min: float,
		scale_max: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = 0.95
	p.spread = 180.0
	p.initial_velocity_min = speed_min
	p.initial_velocity_max = speed_max
	p.gravity = Vector2(0.0, 220.0)
	p.scale_amount_min = scale_min
	p.scale_amount_max = scale_max
	p.color = color
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return p


func set_monster(m: MonsterResource) -> void:
	monster = m
	if is_inside_tree():
		_apply_monster()


func _apply_monster() -> void:
	if monster == null or _sprite == null:
		return
	_sprite.texture = monster.sprite
	_sprite.modulate = monster.tint


func _process(delta: float) -> void:
	if not _alive:
		return
	if _state == _State.WANDER:
		var to_target: Vector2 = _target_pos - position
		var dist: float = to_target.length()
		var step: float = _WANDER_SPEED_PX_PER_SEC * delta
		if dist <= step:
			position = _target_pos
			_state = _State.PAUSE
			_pause_left = randf_range(_PAUSE_TIME_RANGE.x, _PAUSE_TIME_RANGE.y)
		else:
			position += to_target / dist * step
		# Flip sprite to face direction of motion.
		if to_target.x != 0.0:
			_sprite.flip_h = to_target.x < 0.0
	elif _state == _State.PAUSE:
		_pause_left -= delta
		if _pause_left <= 0.0:
			_pick_new_target()


func _pick_new_target() -> void:
	var x: float = randf_range(bounds.position.x + 32, bounds.position.x + bounds.size.x - 32)
	var y: float = randf_range(bounds.position.y + 32, bounds.position.y + bounds.size.y - 32)
	_target_pos = Vector2(x, y)
	_state = _State.WANDER


func _on_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	# Phase 2: kept as a fallback; the primary input path is CatchingView's
	# _gui_input + _find_monster_at. Area2D physics picking under a
	# TabContainer is unreliable, so we drive taps from the parent Control.
	if not _alive:
		return
	var consumed: bool = false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		consumed = true
	elif event is InputEventScreenTouch and event.pressed:
		consumed = true
	if not consumed:
		return
	play_tap_feedback()
	tapped.emit(self)


## Public API: play the visual feedback for a tap. Used by both Area2D physics
## picking (when it works) and CatchingView._gui_input forwarding.
func play_tap_feedback() -> void:
	if _DEBUG_LOG:
		var monster_id: String = String(monster.id) if monster != null else "<null>"
		print("[catch] tap registered: monster=%s instance=%d progress=%.2f" % [monster_id, instance_id, tap_progress])
	if _tap_particles != null:
		_tap_particles.restart()
	_play_tap_bump()


func _play_tap_bump() -> void:
	# Quick squash-and-rebound on the sprite so even without particles you
	# feel the tap registered.
	if _sprite == null:
		return
	var base: Vector2 = Vector2(_RENDER_SCALE, _RENDER_SCALE)
	var bump: Vector2 = base * 1.18
	var t: Tween = create_tween()
	t.tween_property(_sprite, "scale", bump, 0.06)
	t.tween_property(_sprite, "scale", base, 0.10)


## Called by CatchingView once a catch resolves.
func play_catch_and_despawn() -> void:
	if not _alive:
		return
	if _DEBUG_LOG:
		var monster_id: String = String(monster.id) if monster != null else "<null>"
		print("[catch] CATCH despawn: monster=%s instance=%d" % [monster_id, instance_id])
	_alive = true   # keep alive flag true until tween completes; just block input
	_state = _State.CAUGHT
	_area.input_pickable = false
	_catch_particles.restart()
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_sprite, "scale", Vector2(_RENDER_SCALE * 1.4, _RENDER_SCALE * 1.4), 0.15)
	tween.tween_property(_sprite, "modulate:a", 0.0, 0.18)
	tween.chain().tween_callback(func() -> void:
		caught_self.emit(self)
		queue_free()
	)
