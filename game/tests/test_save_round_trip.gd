## Verifies a populated GameState can survive save -> reset -> load equality.
##
## Uses LocalFileBackend with the real user:// path; Godot's per-test
## sandboxing keeps these files isolated from user data.
extends GutTest


func before_each() -> void:
	# Ensure clean slate.
	if FileAccess.file_exists(LocalFileBackend.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LocalFileBackend.SAVE_PATH))


func test_round_trip_preserves_state():
	# Populate.
	GameState.currencies = {"gold": {"m": 4.2, "e": 7}, "rancher_points": 42}
	GameState.inventory = {"wisplet_ectoplasm": 247, "centiphantom_jelly": 13}
	GameState.monsters_caught = {"green_wisplet": {"normal": 247, "shiny": 3}}
	GameState.pets_owned = ["green_wisplet_pet"]
	GameState.nets_owned = ["basic_net"]
	GameState.active_net = "basic_net"
	GameState.current_max_tier = 2
	GameState.tiers_completed = [1]
	GameState.prestige_count = 0
	GameState.ledger["total_catches"] = 247

	# Save and reset.
	var state_before := GameState.to_dict()
	SaveManager.save(state_before)
	GameState.from_dict({})  # reset to first-launch defaults

	# Sanity: post-reset != pre-save.
	assert_ne(GameState.current_max_tier, 2, "Reset should clear current_max_tier")

	# Load and reapply.
	var loaded: Dictionary = SaveManager.load_save()
	GameState.from_dict(loaded)

	# Compare.
	assert_eq(GameState.current_max_tier, 2)
	assert_eq(GameState.active_net, "basic_net")
	assert_eq(GameState.inventory["wisplet_ectoplasm"], 247)
	assert_eq(GameState.monsters_caught["green_wisplet"]["shiny"], 3)
	assert_eq(int(GameState.currencies["rancher_points"]), 42)
	assert_eq(float(GameState.currencies["gold"]["m"]), 4.2)
	assert_eq(int(GameState.currencies["gold"]["e"]), 7)
	assert_eq(GameState.ledger["total_catches"], 247)
