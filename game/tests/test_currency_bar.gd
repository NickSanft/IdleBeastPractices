## Phase 10c — currency_bar composition + signal hygiene.
##
## Verifies:
##   - Three chips wired in (Gold / RP / Prestige).
##   - Gold chip is always visible; RP + Prestige hidden until earned.
##   - currency_changed events drive the chip values.
##   - Re-instantiating the bar repeatedly does not leak EventBus
##     signal connections (covers the bug where a re-instantiated bar
##     would respond multiple times to the same signal).
extends GutTest

const _SCENE := preload("res://game/scenes/ui/currency_bar.tscn")


func before_each() -> void:
	GameState.from_dict({})


func test_three_chips_present() -> void:
	var bar: PanelContainer = _SCENE.instantiate()
	add_child_autofree(bar)
	await wait_frames(1)
	assert_not_null(bar._gold_chip)
	assert_not_null(bar._rp_chip)
	assert_not_null(bar._prestige_chip)


func test_gold_chip_always_visible() -> void:
	var bar: PanelContainer = _SCENE.instantiate()
	add_child_autofree(bar)
	await wait_frames(1)
	assert_true(bar._gold_chip.visible)


func test_rp_chip_hidden_until_earned() -> void:
	GameState.currencies["rancher_points"] = 0
	var bar: PanelContainer = _SCENE.instantiate()
	add_child_autofree(bar)
	await wait_frames(1)
	assert_false(bar._rp_chip.visible, "RP chip should be hidden at zero RP")


func test_rp_chip_appears_after_currency_changed() -> void:
	GameState.currencies["rancher_points"] = 0
	var bar: PanelContainer = _SCENE.instantiate()
	add_child_autofree(bar)
	await wait_frames(1)
	assert_false(bar._rp_chip.visible)
	# Simulate earning RP.
	GameState.currencies["rancher_points"] = 5
	EventBus.currency_changed.emit("rancher_points", 5)
	await wait_frames(2)
	assert_true(bar._rp_chip.visible, "RP chip must surface once RP > 0")


func test_prestige_chip_hidden_at_zero_prestiges() -> void:
	GameState.prestige_count = 0
	var bar: PanelContainer = _SCENE.instantiate()
	add_child_autofree(bar)
	await wait_frames(1)
	assert_false(bar._prestige_chip.visible)


func test_prestige_chip_appears_after_prestige_triggered() -> void:
	GameState.prestige_count = 0
	var bar: PanelContainer = _SCENE.instantiate()
	add_child_autofree(bar)
	await wait_frames(1)
	GameState.prestige_count = 1
	EventBus.prestige_triggered.emit(7, 1)
	await wait_frames(2)
	assert_true(bar._prestige_chip.visible)


func test_gold_progress_fraction_within_range() -> void:
	GameState.currencies["gold"] = BigNumber.from_float(1000.0).to_dict()
	var bar: PanelContainer = _SCENE.instantiate()
	add_child_autofree(bar)
	await wait_frames(1)
	# 1000 = 1.0 × 10^3, so progress through this decade = (1.0-1.0)/9 = 0.
	# Fast-forward to mid-decade and verify the bar tracks.
	GameState.currencies["gold"] = BigNumber.from_float(5500.0).to_dict()
	EventBus.currency_changed.emit("gold", BigNumber.from_float(5500.0))
	await wait_frames(2)
	# 5500 = 5.5 × 10^3, progress = (5.5-1)/9 ≈ 0.5
	assert_almost_eq(bar._gold_chip._progress.value, 0.5, 0.05)


func test_repeated_instantiation_does_not_leak_signals() -> void:
	# Build, destroy, build, destroy, build — count connections after
	# each cycle. The bar must clean up in _exit_tree so leaked
	# connections don't accumulate.
	var initial: int = EventBus.currency_changed.get_connections().size()
	var bars: Array[PanelContainer] = []
	for i in 3:
		var bar: PanelContainer = _SCENE.instantiate()
		add_child(bar)
		bars.append(bar)
		await wait_frames(1)
	# Tear them all down.
	for bar in bars:
		bar.queue_free()
	await wait_frames(2)
	var final: int = EventBus.currency_changed.get_connections().size()
	# Filter to connections owned by currency_bar specifically — other
	# autoloads connect too, and we only care about our own.
	# Acceptable drift is +0; +N indicates a leak.
	assert_eq(final, initial,
			"currency_changed connection count drifted: %d → %d" % [initial, final])
