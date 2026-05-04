## Phase 11b — accessibility settings persistence + live re-apply.
##
## Tests the Settings setters, the accessibility_settings_changed
## signal, and a few of the runtime read sites that gate animations
## on `reduce_motion`. Doesn't try to assert pixel motion — focuses
## on the contract surfaces other code depends on.
extends GutTest


func before_each() -> void:
	# Restore defaults so tests don't leak state into each other.
	Settings.reduce_motion = false
	Settings.font_scale = 1.0
	Settings.haptics_enabled = true


func after_each() -> void:
	# Defensive: also reset after each test in this suite, so OTHER
	# test files (test_catching_background, test_combatant, etc.)
	# don't inherit reduce_motion=true state if this suite ran first.
	Settings.reduce_motion = false
	Settings.font_scale = 1.0
	Settings.haptics_enabled = true


# region — Setter contract

func test_set_reduce_motion_emits_signal() -> void:
	var fired: Array[bool] = [false]
	# Hold the lambda in a local so we can disconnect it cleanly. A
	# fresh Callable built at disconnect time wouldn't match the
	# connected one's hash and would error in Godot.
	var handler := func() -> void: fired[0] = true
	Settings.accessibility_settings_changed.connect(handler)
	Settings.set_reduce_motion(true)
	assert_true(fired[0], "set_reduce_motion(true) must emit accessibility_settings_changed")
	Settings.accessibility_settings_changed.disconnect(handler)


func test_set_reduce_motion_idempotent_on_unchanged_value() -> void:
	Settings.reduce_motion = true   # pre-set so the setter sees a no-op
	var fired: Array[int] = [0]
	Settings.accessibility_settings_changed.connect(func() -> void: fired[0] += 1)
	Settings.set_reduce_motion(true)
	assert_eq(fired[0], 0, "setting reduce_motion to its current value must not fire the signal")


func test_set_font_scale_clamps_to_range() -> void:
	Settings.set_font_scale(0.0)
	assert_eq(Settings.font_scale, Settings.FONT_SCALE_MIN,
			"font_scale below FONT_SCALE_MIN must clamp")
	Settings.set_font_scale(99.0)
	assert_eq(Settings.font_scale, Settings.FONT_SCALE_MAX,
			"font_scale above FONT_SCALE_MAX must clamp")


func test_set_haptics_enabled_persists() -> void:
	Settings.set_haptics_enabled(false)
	assert_false(Settings.haptics_enabled)
	# Round-trip through disk to confirm persistence shape — load_from_disk
	# should restore the saved value.
	Settings.haptics_enabled = true   # forget the in-memory value
	Settings.load_from_disk()
	assert_false(Settings.haptics_enabled,
			"haptics_enabled must round-trip through settings.cfg")


# endregion


# region — Runtime gating

func test_floating_number_skips_drift_when_reduce_motion() -> void:
	Settings.reduce_motion = true
	var label: Label = preload("res://game/scenes/ui/floating_number.tscn").instantiate()
	add_child_autofree(label)
	label.position = Vector2(100, 200)
	await wait_frames(2)
	# With reduce_motion the position.y should not have drifted upward.
	# Without the gate, the tween would have moved it ~6 px in 2 frames.
	assert_almost_eq(label.position.y, 200.0, 1.0,
			"floating_number must not drift when reduce_motion is on")


func test_floating_number_drifts_when_reduce_motion_off() -> void:
	Settings.reduce_motion = false
	var label: Label = preload("res://game/scenes/ui/floating_number.tscn").instantiate()
	add_child_autofree(label)
	label.position = Vector2(100, 200)
	await wait_frames(8)
	assert_lt(label.position.y, 200.0,
			"floating_number must drift up when reduce_motion is off")


func test_combatant_idle_bob_is_static_when_reduce_motion() -> void:
	Settings.reduce_motion = true
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	var c: Node2D = preload("res://game/scenes/battle/combatant.tscn").instantiate()
	c.setup("player", 0, 100.0, Vector2(200, 300), Vector2(200, 300), 1, tex, Color.WHITE)
	add_child_autofree(c)
	# Already at engagement_pos so state should immediately be IDLE_AT_ENGAGEMENT.
	c.state = c.State.IDLE_AT_ENGAGEMENT
	c.engagement_pos = Vector2(200, 300)
	await wait_frames(8)
	# With reduce_motion on, the y should stay at engagement_pos.y;
	# without it, the bob would have moved it by sin(*) * 2 px.
	assert_almost_eq(c.position.y, 300.0, 0.5,
			"combatant idle bob must not move position when reduce_motion is on")


func test_attack_lunge_returns_immediately_when_reduce_motion() -> void:
	Settings.reduce_motion = true
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	var c: Node2D = preload("res://game/scenes/battle/combatant.tscn").instantiate()
	c.setup("player", 0, 100.0, Vector2(200, 300), Vector2(200, 300), 1, tex, Color.WHITE)
	add_child_autofree(c)
	await wait_frames(1)
	c.play_attack_lunge(Vector2(400, 300))
	# With reduce_motion, lunge state should immediately flip back to
	# IDLE via _on_lunge_complete.
	await wait_frames(2)
	assert_eq(c.state, c.State.IDLE_AT_ENGAGEMENT,
			"reduce_motion lunge must not block the state machine in ATTACK_LUNGE")
	assert_eq(c.position, Vector2(200, 300),
			"reduce_motion lunge must leave position unchanged")

# endregion
