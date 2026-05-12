## A single on-screen catchable monster.
##
## Owns its own wander state machine and tap_progress accumulator. The
## containing CatchingView listens to `tapped` and `caught_self` to
## resolve catches via CatchingSystem and update GameState.
##
## Phase 14d — Dusk pixel-card chrome. Per
## `docs/design_handoff_theming/reference_files/styles.css` `.mon`:
## a 92-px-wide sprite-card with the 32×32 monster sprite on top
## (kept as-is — handoff explicit about reusing existing pixel art)
## and an 8-px Silkscreen "NAME · T2" label below, on a 70%-black bg
## with a 1-px border. The whole monster (sprite + label) participates
## in the wander state machine: the sprite walks/bobs/flips while the
## label tracks the parent's translation.
extends Node2D

signal tapped(instance: Node2D)
signal caught_self(instance: Node2D)

const _DUSK := preload("res://assets/themes/dusk/palette_dusk.gd")
const _WANDER_SPEED_PX_PER_SEC := 60.0
const _PAUSE_TIME_RANGE := Vector2(0.4, 1.4)
const _SPRITE_FRAME_SIZE := Vector2(32, 32)
const _RENDER_SCALE := 3.0
## Sprite sheet is 256x32 = 8 frames laid out horizontally. Animation
## walks through all 8 frames at _WALK_FPS during WANDER state and
## holds frame 0 during PAUSE (with a subtle vertical bob).
const _SPRITE_FRAME_COUNT := 8
const _WALK_FPS := 8.0
const _PAUSE_FRAME := 0
const _PAUSE_BOB_AMPLITUDE_PX := 2.0
const _PAUSE_BOB_HZ := 1.6
## Direction-flip easing time in seconds. Anything under ~0.25 still
## reads as a quick "turnaround" rather than a slow rotation.
const _FLIP_DURATION := 0.18
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
## Phase 14d: pixel-card label below the sprite — Silkscreen 8 px on
## a 70%-black bg with a 1-px Dusk border. Built once in _ready and
## retargeted in `_apply_monster()` when the bound MonsterResource
## changes. `Label2D` is the right primitive: it lives in 2D space
## next to the sprite and inherits the parent's transform.
var _name_card: Label
var _name_card_panel: PanelContainer

var _state: int = _State.WANDER
var _target_pos: Vector2
var _pause_left: float = 0.0
var _alive: bool = true

## +1 = facing right, -1 = facing left. Encoded as a sign on the
## sprite's x scale so the tap-bump tween can multiply through it
## without losing direction.
var _facing: int = 1
## Frame index running through 0.._SPRITE_FRAME_COUNT-1 during WANDER.
var _anim_time: float = 0.0
var _bob_time: float = 0.0
## Single shared tween for all sprite-scale animations (direction flip
## + tap bump). Kept on a member so we can kill it before starting a
## new one; otherwise concurrent tweens fight for the same property.
var _scale_tween: Tween

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

	_build_name_card()

	if monster != null:
		_apply_monster()
	_pick_new_target()

	# Phase 14h — repaint the name card border + ink when the player
	# swaps palette in Settings. Both colors were cached at build time
	# in `_build_name_card`, so a palette swap requires a stylebox
	# rebuild + an ink override refresh.
	Settings.theme_changed.connect(_on_theme_changed)


## Phase 14h — Settings.theme_changed handler. Re-applies the name
## card border + ink with the new palette's tokens. Both colors are
## set in `_build_name_card` once and otherwise never change, so a
## targeted re-paint is cheaper than rebuilding the whole label.
func _on_theme_changed() -> void:
	if _name_card_panel == null:
		return
	var palette: Dictionary = _DUSK.active()
	var sb: StyleBoxFlat = _name_card_panel.get_theme_stylebox("panel")
	if sb != null:
		var new_sb: StyleBoxFlat = sb.duplicate()
		new_sb.border_color = palette["border"]
		_name_card_panel.add_theme_stylebox_override("panel", new_sb)
	if _name_card != null:
		_name_card.add_theme_color_override("font_color", palette["ink"])


## Phase 14d: builds the small "NAME · T2" pixel-card label below the
## sprite, per styles.css `.mon .label` (Silkscreen 8 px on rgba(0,0,0,0.7)
## with a 1-px Dusk border). The panel auto-centers horizontally relative
## to the monster's origin once its size settles (via `resized` signal).
func _build_name_card() -> void:
	_name_card_panel = PanelContainer.new()
	_name_card_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	sb.border_color = _DUSK.active()["border"]
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 4.0
	sb.content_margin_right = 4.0
	sb.content_margin_top = 2.0
	sb.content_margin_bottom = 2.0
	_name_card_panel.add_theme_stylebox_override("panel", sb)
	# Position below the sprite. Sprite center is at (0,0) and renders
	# 96 px tall (32 × _RENDER_SCALE), so its bottom edge is at y = +48.
	# Add a 6-px gap, then re-center horizontally once layout settles.
	_name_card_panel.position = Vector2(0, 54)
	_name_card_panel.resized.connect(_recenter_name_card)
	add_child(_name_card_panel)

	_name_card = Label.new()
	_name_card.theme_type_variation = "UiTiny"   # Silkscreen 7 px
	_name_card.add_theme_color_override("font_color", _DUSK.active()["ink"])
	_name_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Default text until _apply_monster() runs.
	_name_card.text = "—"
	_name_card_panel.add_child(_name_card)


## Recenters the name card panel so its horizontal middle aligns with
## the monster's origin (which is also where the 96 px sprite is
## centered). `Control.resized` fires after the panel's size settles,
## which is exactly when we can read `_name_card_panel.size.x`.
func _recenter_name_card() -> void:
	if _name_card_panel == null:
		return
	_name_card_panel.position.x = -_name_card_panel.size.x * 0.5


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
	# Phase 14d: drive the pixel-card label. styles.css uses uppercase
	# letter-spaced text — match with .to_upper(). Format mirrors the
	# handoff's "WISPLET · T2" example.
	if _name_card != null:
		_name_card.text = "%s · T%d" % [monster.display_name.to_upper(), monster.tier]


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
			_bob_time = 0.0
			_sprite.position.y = 0.0   # zero out residual walk offset
		else:
			position += to_target / dist * step
		# Smooth direction-change: tween scale.x through 0 to flip,
		# instead of a hard `flip_h` swap. Reads as a quick turnaround.
		if to_target.x != 0.0:
			_set_facing(-1 if to_target.x < 0.0 else 1)
		# Walk-cycle frame.
		_anim_time += delta
		var frame: int = int(_anim_time * _WALK_FPS) % _SPRITE_FRAME_COUNT
		_sprite.region_rect = Rect2(
				Vector2(frame * _SPRITE_FRAME_SIZE.x, 0.0),
				_SPRITE_FRAME_SIZE)
	elif _state == _State.PAUSE:
		_pause_left -= delta
		# Hold the pause frame.
		_sprite.region_rect = Rect2(
				Vector2(_PAUSE_FRAME * _SPRITE_FRAME_SIZE.x, 0.0),
				_SPRITE_FRAME_SIZE)
		# Subtle vertical bob — feels like the monster is breathing.
		_bob_time += delta
		_sprite.position.y = sin(_bob_time * TAU * _PAUSE_BOB_HZ) * _PAUSE_BOB_AMPLITUDE_PX
		if _pause_left <= 0.0:
			_pick_new_target()
			_anim_time = 0.0   # restart walk cycle from frame 0


func _set_facing(facing: int) -> void:
	if _facing == facing:
		return
	_facing = facing
	if _scale_tween != null and _scale_tween.is_valid():
		_scale_tween.kill()
	_scale_tween = create_tween()
	_scale_tween.tween_property(
			_sprite, "scale:x", float(facing) * _RENDER_SCALE, _FLIP_DURATION,
	).set_trans(Tween.TRANS_QUAD)


func _pick_new_target() -> void:
	var x: float = randf_range(bounds.position.x + 32, bounds.position.x + bounds.size.x - 32)
	var y: float = randf_range(bounds.position.y + 32, bounds.position.y + bounds.size.y - 32)
	_target_pos = Vector2(x, y)
	_state = _State.WANDER
	# Reset bob residual so the next walk cycle starts at sprite-y=0.
	if _sprite != null:
		_sprite.position.y = 0.0


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
	# feel the tap registered. Multiplies through `_facing` so a monster
	# facing left stays facing left through the bump.
	if _sprite == null:
		return
	# v0.11.1 (Phase 11b): reduce_motion users get particles only — the
	# scale punch fires on every tap and is the highest-frequency
	# animation in the game.
	if Settings.reduce_motion:
		return
	if _scale_tween != null and _scale_tween.is_valid():
		_scale_tween.kill()
	var base: Vector2 = Vector2(float(_facing) * _RENDER_SCALE, _RENDER_SCALE)
	var bump: Vector2 = base * 1.18
	_scale_tween = create_tween()
	_scale_tween.tween_property(_sprite, "scale", bump, 0.06)
	_scale_tween.tween_property(_sprite, "scale", base, 0.10)


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
	# Phase 14d: hide the name card immediately on catch so it doesn't
	# linger past the sprite's fade-and-shrink. The sprite tween below
	# handles modulate.a; doing the same on a PanelContainer means
	# tweening the panel's `modulate.a`, which is cheaper to just
	# hide outright since the catch despawn is a one-way trip.
	if _name_card_panel != null:
		_name_card_panel.visible = false
	# Kill any in-flight scale animation (tap bump or direction flip)
	# so the catch despawn isn't fighting them for the same property.
	if _scale_tween != null and _scale_tween.is_valid():
		_scale_tween.kill()
	# Phase 10b: white-out flash before the despawn fade. Modulate is
	# pushed past 1.0 (HDR-style) for a brief blow-out, then the existing
	# scale punch + alpha fade plays on top. We're decommissioning the
	# sprite anyway, so we don't need to restore the original tint.
	var flash_tween: Tween = create_tween()
	flash_tween.tween_property(_sprite, "modulate", Color(2.4, 2.4, 2.4, 1.0), 0.05)
	flash_tween.tween_callback(_start_catch_despawn_tween)


## Phase 14g — styles.css `mon-catch` keyframes:
##   0%:   scale(1)   rotate(0°)    opacity(1)
##   60%:  scale(1.2) rotate(+8°)
##   100%: scale(0.1) rotate(-20°)  opacity(0)   translateY(+24)
##
## Total duration 360 ms ease-in. Reads like a startled-snatch + drop:
## the monster expands and turns one way, then shrinks-and-twists the
## opposite way as it disappears downward. Replaces the parchment-era
## flat fade.
##
## `reduce_motion` keeps the original 18-frame fade behaviour — no
## scale punch, no rotation, just a clean alpha-out.
func _start_catch_despawn_tween() -> void:
	if Settings.reduce_motion:
		_play_reduced_catch_despawn()
		return

	# Phase 1 (0→60%, 0..216 ms): scale up to 1.2 + tilt +8°. The
	# sprite's scale magnitude was `_facing * _RENDER_SCALE` (e.g.
	# +3.0 or -3.0); multiply by 1.2 for the punch, preserving the
	# facing sign so a left-facing monster stays left-facing.
	var base_scale_x: float = float(_facing) * _RENDER_SCALE
	var t: Tween = create_tween()
	t.set_ease(Tween.EASE_IN)
	var phase1_secs: float = 0.216   # 60% of 360 ms
	t.set_parallel(true)
	t.tween_property(_sprite, "scale", Vector2(base_scale_x * 1.2, _RENDER_SCALE * 1.2), phase1_secs)
	t.tween_property(_sprite, "rotation_degrees", 8.0, phase1_secs)

	# Phase 2 (60→100%, 216..360 ms): scale crashes to 0.1, rotation
	# swings to -20°, sprite drops +24 px, alpha fades to 0.
	var phase2_secs: float = 0.144   # 40% of 360 ms
	var start_y: float = _sprite.position.y
	t.chain().set_parallel(true)
	t.tween_property(_sprite, "scale", Vector2(base_scale_x * 0.1, _RENDER_SCALE * 0.1), phase2_secs)
	t.tween_property(_sprite, "rotation_degrees", -20.0, phase2_secs)
	t.tween_property(_sprite, "position:y", start_y + 24.0, phase2_secs)
	t.tween_property(_sprite, "modulate:a", 0.0, phase2_secs)

	t.chain().tween_callback(func() -> void:
		caught_self.emit(self)
		queue_free())


## reduce_motion fallback: matches the pre-14g flat fade so motion-
## sensitive players don't see the new scale/rotate punch.
func _play_reduced_catch_despawn() -> void:
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_sprite, "scale", Vector2(float(_facing) * _RENDER_SCALE * 1.4, _RENDER_SCALE * 1.4), 0.15)
	tween.tween_property(_sprite, "modulate:a", 0.0, 0.18)
	tween.chain().tween_callback(func() -> void:
		caught_self.emit(self)
		queue_free())
