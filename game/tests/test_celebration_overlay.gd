## Phase 11a — celebration overlay smoke + dismissal contract.
extends GutTest

const _SCENE := preload("res://game/scenes/ui/celebration_overlay.tscn")


func _new_overlay() -> CanvasLayer:
	var o: CanvasLayer = _SCENE.instantiate()
	add_child_autofree(o)
	return o


func test_starts_hidden() -> void:
	var o := _new_overlay()
	await wait_frames(1)
	assert_false(o.visible, "overlay must start hidden — only show on demand")
	assert_false(o.is_showing())


func test_show_celebration_makes_overlay_visible() -> void:
	var o := _new_overlay()
	await wait_frames(1)
	o.show_celebration("Tier 1 Complete!", "Three pets joined the roster.")
	assert_true(o.visible)
	assert_true(o.is_showing())
	assert_eq(o._title_label.text, "Tier 1 Complete!")
	assert_string_contains(o._body_label.text, "pets joined")


func test_show_with_sprite_reveals_sprite_rect() -> void:
	var o := _new_overlay()
	await wait_frames(1)
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	o.show_celebration("First Shiny!", "Look at it shimmer.", tex)
	assert_true(o._sprite_rect.visible)
	assert_eq(o._sprite_rect.texture, tex)


func test_show_without_sprite_hides_sprite_rect() -> void:
	var o := _new_overlay()
	await wait_frames(1)
	o.show_celebration("Prestige #1", "+12 Rancher Points.")
	assert_false(o._sprite_rect.visible,
			"sprite rect must hide when celebration is sprite-less")


func test_dismiss_makes_overlay_hide() -> void:
	var o := _new_overlay()
	await wait_frames(1)
	o.show_celebration("Stage Cleared!", "+8 Rancher Points.")
	assert_true(o.visible)
	o.dismiss()
	# Fade-out tween is 0.18s; allow 0.4s margin.
	await wait_seconds(0.4)
	assert_false(o.visible, "overlay must hide after dismiss + fade-out")


func test_subsequent_show_replaces_previous() -> void:
	var o := _new_overlay()
	await wait_frames(1)
	o.show_celebration("Tier 1 Complete!", "First.")
	o.show_celebration("Tier 2 Complete!", "Replaced.")
	assert_eq(o._title_label.text, "Tier 2 Complete!")
	assert_string_contains(o._body_label.text, "Replaced")


func test_input_lock_blocks_immediate_dismissal() -> void:
	# Tap-to-dismiss must not fire within the input-lock window —
	# otherwise a player tapping rapidly would close the overlay
	# before they noticed it appeared.
	var o := _new_overlay()
	await wait_frames(1)
	o.show_celebration("Stage Cleared!", "+8 RP.")
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	o._on_backdrop_input(event)
	assert_true(o.is_showing(),
			"tap within input-lock window must not dismiss the overlay")


func test_emits_dismissed_signal() -> void:
	var o := _new_overlay()
	await wait_frames(1)
	o.show_celebration("Test", "Body")
	var fired: Array[bool] = [false]
	o.dismissed.connect(func() -> void: fired[0] = true)
	o.dismiss()
	await wait_seconds(0.3)
	assert_true(fired[0], "dismissed signal must fire after dismiss completes")
