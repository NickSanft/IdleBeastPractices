extends GutTest


func test_v0_save_migrates_to_v1_with_required_keys():
	var v0: Dictionary = {"version": 0, "currencies": {"gold": {"m": 1.5, "e": 2}}}
	var migrated: Dictionary = SaveMigrations.apply_chain(v0, 1)
	assert_eq(migrated.get("version"), 1, "version should be 1 after migration")
	# Existing data preserved.
	assert_eq(migrated["currencies"]["gold"]["m"], 1.5)
	# Required v1 keys filled in.
	for key in ["last_saved_unix", "session_id", "inventory", "monsters_caught",
			"pets_owned", "pet_variants_owned", "nets_owned", "active_net",
			"upgrades_purchased", "current_max_tier", "tiers_completed",
			"current_battle", "prestige_count", "ledger", "narrator_state"]:
		assert_true(migrated.has(key), "v1 save should have key '%s'" % key)


func test_migration_preserves_existing_keys():
	var v0: Dictionary = {
		"version": 0,
		"current_max_tier": 5,
		"prestige_count": 2,
	}
	var migrated: Dictionary = SaveMigrations.apply_chain(v0, 1)
	assert_eq(migrated["current_max_tier"], 5)
	assert_eq(migrated["prestige_count"], 2)


func test_chain_at_target_version_is_noop():
	var v1: Dictionary = {"version": 1, "current_max_tier": 3}
	var result: Dictionary = SaveMigrations.apply_chain(v1, 1)
	assert_eq(result["version"], 1)
	assert_eq(result["current_max_tier"], 3)
