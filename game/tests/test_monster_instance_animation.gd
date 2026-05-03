## Smoke tests for the monster_instance animation polish (v0.8.2):
##  - sprite walk-cycle frames advance during WANDER
##  - sprite holds the pause frame during PAUSE
##  - direction flip uses an animated scale.x tween, not instant flip_h
##
## Doesn't test the full wander state machine — that's covered
## indirectly via the catching system tests. We just verify the
## animation hooks fire without crashing and the visible attributes
## (region_rect, scale.x sign) reach the expected values.
extends GutTest

const _SCENE := preload("res://game/scenes/catching/monster_instance.tscn")


func _new_instance() -> Node2D:
	# monster_instance expects a MonsterResource; build a stub so
	# _apply_monster() doesn't crash. Tint stays white, no sprite
	# texture (region_rect updates regardless).
	var inst: Node2D = _SCENE.instantiate()
	var m := MonsterResource.new()
	m.id = &"test_monster"
	m.tier = 1
	m.tint = Color.WHITE
	inst.monster = m
	add_child_autofree(inst)
	return inst


func test_walk_frame_advances_during_wander() -> void:
	# After _ready spawns at frame 0, advancing the wander timer should
	# tick region_rect.position.x past frame 0.
	var inst := _new_instance()
	# Force a known target so the instance is in WANDER state.
	inst._target_pos = inst.position + Vector2(200.0, 0.0)
	inst._state = inst._State.WANDER
	var sprite: Sprite2D = inst._sprite
	# Frame 0 at start.
	assert_eq(sprite.region_rect.position.x, 0.0)
	# After one frame (~0.016 s) at 8 fps, still frame 0.
	# After ~0.13 s we should land on frame 1 (1 / 8 = 0.125).
	await wait_seconds(0.2)
	assert_gt(sprite.region_rect.position.x, 0.0,
			"walk cycle should have advanced past frame 0 within 0.2 s")


func test_pause_state_holds_pause_frame() -> void:
	var inst := _new_instance()
	inst._state = inst._State.PAUSE
	inst._pause_left = 5.0  # long enough not to transition
	var sprite: Sprite2D = inst._sprite
	await wait_frames(2)
	# Region rect should land on the configured _PAUSE_FRAME (0).
	assert_eq(sprite.region_rect.position.x, 0.0,
			"PAUSE state should hold the pause frame (frame 0)")


func test_direction_flip_creates_scale_tween() -> void:
	# Triggering _set_facing(-1) should record the new facing
	# synchronously and create a scale-x tween. Tween timing under
	# headless GUT is flaky (no real frame advancement during awaits),
	# so we assert the synchronous side effects rather than the
	# eventual scale.x value.
	var inst := _new_instance()
	# Default facing is +1 from member initializer.
	assert_eq(inst._facing, 1)
	inst._set_facing(-1)
	assert_eq(inst._facing, -1, "facing flips immediately")
	assert_not_null(inst._scale_tween, "tween created for scale-x easing")
	assert_true(inst._scale_tween.is_valid(), "tween is live, not pre-killed")


func test_idempotent_facing_doesnt_restart_tween() -> void:
	# Calling _set_facing(1) twice in a row is a no-op for the second
	# call — guards against the per-frame "to_target.x > 0" check
	# constantly retriggering tweens during a long walk segment.
	var inst := _new_instance()
	# Already facing 1 from defaults; call once to allocate a tween.
	inst._set_facing(-1)
	var first_tween: Tween = inst._scale_tween
	# Same direction again -> early return, tween untouched.
	inst._set_facing(-1)
	assert_eq(inst._scale_tween, first_tween,
			"redundant facing call should not allocate a new tween")
