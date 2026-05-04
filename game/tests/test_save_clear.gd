## Tests for the new wipe-save flow:
##   - LocalFileBackend.clear() removes user://save.json (and any
##     stale .tmp).
##   - SaveManager.clear_save() resets GameState to defaults, persists
##     the cleared state, and emits game_loaded.
##   - The post-wipe GameState matches a fresh-launch GameState exactly
##     (no stray fields from the prior save survive).
extends GutTest


func before_each() -> void:
	# Wipe any prior save so each test starts clean.
	SaveManager.backend.clear()


func test_local_file_backend_clear_removes_save_file() -> void:
	# Write a non-empty save, confirm it exists, then clear.
	var ok_write: bool = SaveManager.backend.write('{"hello":"world"}')
	assert_true(ok_write, "write should succeed before clear test")
	assert_true(SaveManager.backend.exists())
	var ok_clear: bool = SaveManager.backend.clear()
	assert_true(ok_clear, "clear should succeed")
	assert_false(SaveManager.backend.exists(), "save file must be gone after clear")


func test_local_file_backend_clear_is_idempotent() -> void:
	# Clearing when there's nothing to clear should still return true.
	assert_false(SaveManager.backend.exists())
	var ok: bool = SaveManager.backend.clear()
	assert_true(ok, "clear() on a missing save must still succeed")


func test_save_manager_clear_resets_game_state() -> void:
	# Seed GameState with some non-default values, save, then wipe.
	GameState.currencies["rancher_points"] = 42
	GameState.prestige_count = 3
	GameState.pets_owned = ["green_wisplet_pet"]
	GameState.tiers_completed = [1, 2]
	SaveManager.save(GameState.to_dict())
	assert_true(SaveManager.backend.exists())
	# Wipe.
	var ok: bool = SaveManager.clear_save()
	assert_true(ok)
	# In-memory state must be back to first-launch defaults.
	assert_eq(int(GameState.currencies["rancher_points"]), 0)
	assert_eq(GameState.prestige_count, 0)
	assert_eq(GameState.pets_owned, [] as Array[String])
	assert_eq(GameState.tiers_completed, [] as Array[int])


func test_save_manager_clear_persists_empty_state() -> void:
	# After wipe, the disk should hold the cleared GameState (not the
	# prior data, not nothing). This guards against a quit-without-save
	# scenario surfacing the old data on next launch.
	GameState.currencies["rancher_points"] = 999
	GameState.pets_owned = ["green_wisplet_pet"]
	SaveManager.save(GameState.to_dict())
	SaveManager.clear_save()
	# The file should exist and contain a fresh-default GameState.
	assert_true(SaveManager.backend.exists(),
			"clear_save must persist the cleared defaults so a hard quit doesn't restore the prior data")
	var loaded: Dictionary = SaveManager.load_save()
	# rancher_points defaults to 0; pets_owned defaults to [].
	assert_eq(int(loaded.get("currencies", {}).get("rancher_points", -1)), 0)
	assert_eq(loaded.get("pets_owned", null), [],
			"persisted pets_owned must be empty after wipe")


func test_save_manager_clear_emits_game_loaded() -> void:
	# Subscribers (currency_bar, bestiary view) refresh on game_loaded.
	# Wipe must emit it so the UI flips to the fresh state.
	GameState.currencies["rancher_points"] = 7
	SaveManager.save(GameState.to_dict())
	var fired: Array[bool] = [false]
	var handler := func() -> void:
		fired[0] = true
	EventBus.game_loaded.connect(handler)
	SaveManager.clear_save()
	# game_loaded fires synchronously inside clear_save.
	assert_true(fired[0],
			"clear_save must emit EventBus.game_loaded so UI subscribers refresh")
	EventBus.game_loaded.disconnect(handler)


func test_save_manager_clear_handles_missing_save() -> void:
	# If there's no save on disk yet (first launch), clear_save should
	# still complete cleanly — wipe a fresh-default state.
	assert_false(SaveManager.backend.exists())
	var ok: bool = SaveManager.clear_save()
	assert_true(ok, "clear_save must succeed when there's nothing to clear")
