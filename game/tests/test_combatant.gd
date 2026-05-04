## Phase 10e.1 — combatant state machine + lifecycle.
##
## Verifies the WALK_IN → IDLE_AT_ENGAGEMENT → ATTACK_LUNGE state
## transitions and the DEFEATED_FADE absorbing state. Doesn't assert
## visual pixels — focuses on the contract battle_view depends on.
extends GutTest

const _COMBATANT := preload("res://game/scenes/battle/combatant.tscn")
const _COMBATANT_SCRIPT := preload("res://game/scenes/battle/combatant.gd")


func _new_combatant(start: Vector2 = Vector2(-50, 200), engagement: Vector2 = Vector2(200, 200), team: String = "player", facing: int = 1) -> Node2D:
	var c: Node2D = _COMBATANT.instantiate()
	# IMPORTANT: setup() must be called BEFORE add_child — combatant's
	# _ready reads max_hp / facing / texture to build its sprite + HP
	# bar, so setting them after-the-fact would leave the visual nodes
	# at their defaults. battle_view.gd follows the same convention.
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	c.setup(team, 0, 100.0, engagement, start, facing, tex, Color.WHITE)
	add_child_autofree(c)
	return c


func test_initial_state_is_walk_in() -> void:
	var c := _new_combatant()
	await wait_frames(1)
	assert_eq(c.state, _COMBATANT_SCRIPT.State.WALK_IN)
	# Position drifts toward engagement_pos by ~4 px per frame at 60fps;
	# we just check the combatant hasn't teleported to engagement
	# already (which would mean WALK_IN was skipped).
	assert_lt(c.position.x, 0.0,
			"combatant should still be walking from start (x < 0) at frame 1, got %s" % c.position)


func test_walks_to_engagement_pos() -> void:
	# At 240 px/s the 250px walk takes ~1s. Wait 1.4s and confirm
	# the combatant has reached IDLE_AT_ENGAGEMENT.
	var c := _new_combatant()
	await wait_seconds(1.4)
	assert_eq(c.state, _COMBATANT_SCRIPT.State.IDLE_AT_ENGAGEMENT)
	# Position should be at engagement_pos (modulo a tiny bob offset).
	assert_almost_eq(c.position.x, 200.0, 1.5)


func test_attack_lunge_sets_state_then_returns_to_idle() -> void:
	var c := _new_combatant()
	await wait_seconds(1.3)   # arrive at engagement
	assert_eq(c.state, _COMBATANT_SCRIPT.State.IDLE_AT_ENGAGEMENT)
	c.play_attack_lunge(Vector2(400, 200))
	await wait_frames(2)
	assert_eq(c.state, _COMBATANT_SCRIPT.State.ATTACK_LUNGE)
	# Lunge total duration is 0.08 + 0.12 = 0.2s. Wait past it.
	await wait_seconds(0.3)
	assert_eq(c.state, _COMBATANT_SCRIPT.State.IDLE_AT_ENGAGEMENT,
			"state must return to IDLE_AT_ENGAGEMENT after the lunge tween completes")


func test_apply_damage_updates_hp_bar() -> void:
	var c := _new_combatant()
	await wait_frames(2)
	c.apply_damage(60)
	assert_almost_eq(c.hp, 60.0, 0.001)
	# HP bar value should track the public hp field.
	assert_almost_eq(float(c._hp_bar.value), 60.0, 0.001)


func test_zero_hp_marks_defeated() -> void:
	var c := _new_combatant()
	await wait_frames(2)
	c.apply_damage(0)
	assert_true(c.is_defeated())
	assert_eq(c.state, _COMBATANT_SCRIPT.State.DEFEATED_FADE)


func test_defeated_combatant_ignores_subsequent_damage() -> void:
	var c := _new_combatant()
	await wait_frames(2)
	c.apply_damage(0)
	# Apply more damage. Should not flip state out of DEFEATED_FADE.
	c.apply_damage(-50)
	c.play_attack_lunge(Vector2(400, 200))
	assert_eq(c.state, _COMBATANT_SCRIPT.State.DEFEATED_FADE)
	assert_almost_eq(c.hp, 0.0, 0.001)


func test_facing_negates_sprite_scale_x() -> void:
	# Enemy combatants face left (-1). The sprite's scale.x sign
	# encodes facing.
	var c := _new_combatant(Vector2(700, 200), Vector2(500, 200), "enemy", -1)
	await wait_frames(1)
	assert_lt(c._sprite.scale.x, 0.0,
			"enemy facing -1 should give the sprite a negative scale.x")
