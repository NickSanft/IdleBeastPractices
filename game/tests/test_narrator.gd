## Tests for Narrator selection: filtering, max_uses, sliding-window
## anti-clustering, condition gates.
extends GutTest

const _NARRATOR := preload("res://game/autoloads/narrator.gd")


func before_each() -> void:
	GameState.from_dict({})
	ContentRegistry.ensure_loaded()
	Narrator.reset_recent_window()


func test_first_launch_fires_once_and_never_again() -> void:
	var first := Narrator.try_speak(&"on_first_launch")
	assert_not_null(first, "first call should produce the on_first_launch line")
	# After max_uses is hit, subsequent calls return null.
	var second := Narrator.try_speak(&"on_first_launch")
	assert_null(second, "second call should be filtered out by max_uses")


func test_unknown_trigger_returns_null() -> void:
	var line := Narrator.try_speak(&"on_definitely_not_a_real_trigger")
	assert_null(line)


func _count_pool(trigger_id: StringName) -> int:
	var n: int = 0
	for line in ContentRegistry.dialogue_lines():
		if line.trigger_id == trigger_id:
			n += 1
	return n


func test_pool_trigger_returns_lines_repeatedly() -> void:
	# on_battle_loss is a pool (max_uses=0). Successive calls should not
	# return the same line back-to-back thanks to the recent-window.
	var first := Narrator.try_speak(&"on_battle_loss")
	var second := Narrator.try_speak(&"on_battle_loss")
	assert_not_null(first)
	assert_not_null(second)
	assert_ne(String(first.id), String(second.id), "anti-clustering should pick a different line")


func test_recent_window_suppresses_repeats_for_pool() -> void:
	# Exhaust the recent-window's worth of picks. If the pool size is ≤
	# the window size, every candidate ends up filtered and the next call
	# must return null. Larger pools can still serve a non-recent pick.
	var pool_size: int = _count_pool(&"on_battle_loss")
	var iterations: int = min(pool_size, Narrator.RECENT_WINDOW_SIZE)
	assert_true(iterations >= 1, "expected at least 1 line in on_battle_loss pool")
	for i in iterations:
		Narrator.try_speak(&"on_battle_loss")
	if pool_size <= Narrator.RECENT_WINDOW_SIZE:
		var blocked := Narrator.try_speak(&"on_battle_loss")
		assert_null(blocked, "all pool entries in recent window; should fail to pick")
	Narrator.reset_recent_window()
	var after_reset := Narrator.try_speak(&"on_battle_loss")
	assert_not_null(after_reset, "reset_recent_window unblocks the pool")


func test_lines_seen_persists_across_save_round_trip() -> void:
	Narrator.try_speak(&"on_first_launch")
	# Confirm the speak counter went up.
	assert_eq(int(GameState.narrator_state["lines_seen"]["first_launch"]), 1)
	# Save and reload — narrator state must survive.
	var snapshot: Dictionary = GameState.to_dict()
	GameState.from_dict({})
	GameState.from_dict(snapshot)
	assert_eq(int(GameState.narrator_state["lines_seen"]["first_launch"]), 1)
	# Re-attempt now and the line should still be filtered out.
	Narrator.reset_recent_window()
	var line := Narrator.try_speak(&"on_first_launch")
	assert_null(line, "max_uses respects the persisted lines_seen")


func test_milestone_lines_load() -> void:
	# Confirm the four milestone lines are findable.
	for milestone in [10, 100, 1000, 10000]:
		var line := Narrator.try_speak(StringName("on_milestone_%d" % milestone))
		assert_not_null(line, "milestone_%d should have a line" % milestone)


func test_per_species_first_catch_lines_load() -> void:
	for species in ["green_wisplet", "red_wisplet", "blue_wisplet"]:
		Narrator.reset_recent_window()
		var line := Narrator.try_speak(StringName("on_first_catch_" + species))
		assert_not_null(line, "expected first-catch line for %s" % species)


func test_speaking_increments_peniber_quotes_seen() -> void:
	var before: int = int(GameState.ledger.get("peniber_quotes_seen", 0))
	Narrator.try_speak(&"on_first_launch")
	var after: int = int(GameState.ledger.get("peniber_quotes_seen", 0))
	assert_eq(after, before + 1)
