## Phase 10b — verify the catch white-flash plays in front of the
## existing despawn fade, and that the despawn still runs cleanly so
## monster instances don't leak into the spawn root after a catch.
##
## Doesn't try to assert exact pixel modulate (visual). Asserts only
## the observable contract: the sprite's modulate is briefly mutated
## past the per-monster tint, and queue_free still happens.
extends GutTest

const _SCENE := preload("res://game/scenes/catching/monster_instance.tscn")


func _new_instance(tint: Color = Color.WHITE) -> Node2D:
	var inst: Node2D = _SCENE.instantiate()
	var m := MonsterResource.new()
	m.id = &"flash_monster"
	m.tier = 1
	m.tint = tint
	inst.monster = m
	add_child_autofree(inst)
	return inst


func test_catch_flash_modulates_past_tint() -> void:
	var inst := _new_instance(Color(0.3, 0.7, 0.4, 1.0))   # green-ish tint
	await wait_frames(1)
	var sprite: Sprite2D = inst._sprite
	assert_not_null(sprite)
	# Pre-catch: modulate equals the monster tint.
	assert_eq(sprite.modulate, Color(0.3, 0.7, 0.4, 1.0))
	inst.play_catch_and_despawn()
	# Flash tween runs ~0.05s but tween advancement under headless GUT
	# is flaky inside a single wait_seconds. Poll each frame for up to
	# 12 frames (~0.2s at 60fps) — if at ANY point modulate brightens
	# past the tint, the flash plumbing is working.
	var saw_flash: bool = false
	for i in 12:
		await wait_frames(1)
		if not is_instance_valid(sprite):
			break
		if sprite.modulate.r > 0.9 or sprite.modulate.g > 0.9 or sprite.modulate.b > 0.9:
			saw_flash = true
			break
	assert_true(saw_flash,
			"sprite modulate should brighten past the tint at some point during the flash window")


func test_catch_eventually_despawns() -> void:
	# After flash + scale + alpha tween, the instance must queue_free.
	# Total expected timeline: 0.05 (flash) + 0.18 (despawn) ≈ 0.25s.
	var inst := _new_instance()
	await wait_frames(1)
	inst.play_catch_and_despawn()
	await wait_seconds(0.4)
	assert_false(is_instance_valid(inst),
			"monster instance must queue_free after catch tween completes")


func test_repeated_catches_do_not_leak_nodes() -> void:
	# 10 successive catch/despawn cycles — within ~3 seconds of real time.
	# All instances must drop out of the tree.
	var spawned: Array[Node2D] = []
	for i in 10:
		var inst := _new_instance()
		spawned.append(inst)
	await wait_frames(1)
	for inst in spawned:
		inst.play_catch_and_despawn()
	await wait_seconds(0.5)
	for inst in spawned:
		assert_false(is_instance_valid(inst),
				"every catch should despawn cleanly; one or more leaked")
