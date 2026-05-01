extends GutTest


func _make_persistent_upgrade(id: StringName) -> UpgradeResource:
	var u := UpgradeResource.new()
	u.id = id
	u.effect_id = &"gold_mult"
	u.magnitude = 0.5
	u.persists_through_prestige = true
	return u


func _make_temp_upgrade(id: StringName) -> UpgradeResource:
	var u := UpgradeResource.new()
	u.id = id
	u.effect_id = &"gold_mult"
	u.magnitude = 0.25
	u.persists_through_prestige = false
	return u


# region — compute_rp_gain

func test_compute_rp_zero_below_threshold():
	# 999_999 gold -> below 1M threshold -> 0 RP.
	var bn := BigNumber.from_float(999_999.0)
	assert_eq(PrestigeSystem.compute_rp_gain(bn.to_dict()), 0)


func test_compute_rp_one_at_threshold():
	# 1M gold -> sqrt(1) = 1 -> 1 RP.
	var bn := BigNumber.from_float(1_000_000.0)
	assert_eq(PrestigeSystem.compute_rp_gain(bn.to_dict()), 1)


func test_compute_rp_grows_as_sqrt():
	# 4M -> sqrt(4) = 2; 100M -> 10; 10B -> 100.
	assert_eq(PrestigeSystem.compute_rp_gain(BigNumber.from_float(4_000_000.0).to_dict()), 2)
	assert_eq(PrestigeSystem.compute_rp_gain(BigNumber.from_float(100_000_000.0).to_dict()), 10)
	assert_eq(PrestigeSystem.compute_rp_gain(BigNumber.from_float(1.0e10).to_dict()), 100)


func test_compute_rp_applies_multiplier():
	var bn := BigNumber.from_float(4_000_000.0)
	# Base 2 RP × 1.5 mult = 3 RP.
	assert_eq(PrestigeSystem.compute_rp_gain(bn.to_dict(), 1.5), 3)


func test_compute_rp_zero_for_zero_gold():
	assert_eq(PrestigeSystem.compute_rp_gain({"m": 0.0, "e": 0}), 0)


# endregion


# region — filter_persistent_upgrades

func test_filter_keeps_only_persistent():
	var u_keep := _make_persistent_upgrade(&"keep_me")
	var u_drop := _make_temp_upgrade(&"drop_me")
	var index: Dictionary = {&"keep_me": u_keep, &"drop_me": u_drop}
	var owned: Array = [
		{"id": &"keep_me", "level": 3},
		{"id": &"drop_me", "level": 1},
	]
	var kept := PrestigeSystem.filter_persistent_upgrades(owned, index)
	assert_eq(kept.size(), 1)
	assert_eq(String(kept[0]["id"]), "keep_me")
	assert_eq(int(kept[0]["level"]), 3)


func test_filter_handles_unknown_ids():
	var u_keep := _make_persistent_upgrade(&"keep_me")
	var index: Dictionary = {&"keep_me": u_keep}
	var owned: Array = [
		{"id": &"keep_me", "level": 1},
		{"id": &"who_is_this", "level": 99},
	]
	var kept := PrestigeSystem.filter_persistent_upgrades(owned, index)
	assert_eq(kept.size(), 1)


func test_filter_returns_empty_when_no_persistent():
	var u_drop := _make_temp_upgrade(&"drop_me")
	var index: Dictionary = {&"drop_me": u_drop}
	var owned: Array = [{"id": &"drop_me", "level": 5}]
	var kept := PrestigeSystem.filter_persistent_upgrades(owned, index)
	assert_eq(kept.size(), 0)

# endregion


# region — GameState.perform_prestige integration

func before_each() -> void:
	GameState.from_dict({})


func test_prestige_zeros_gold_and_inventory():
	GameState.add_gold(BigNumber.from_float(4_000_000.0))
	GameState.add_item(&"wisplet_ectoplasm", 50)
	GameState.current_max_tier = 3
	GameState.tiers_completed = [1, 2]
	GameState.perform_prestige()
	assert_true(GameState.current_gold().is_zero())
	assert_true(GameState.inventory.is_empty())
	assert_eq(GameState.current_max_tier, 1)
	assert_eq(GameState.tiers_completed.size(), 0)


func test_prestige_preserves_pets_and_bestiary():
	GameState.add_pet(&"green_wisplet_pet", false)
	GameState.record_catch(&"green_wisplet", false, "tap")
	GameState.add_gold(BigNumber.from_float(2_000_000.0))
	GameState.perform_prestige()
	assert_true(GameState.pets_owned.has("green_wisplet_pet"))
	assert_true(GameState.monsters_caught.has("green_wisplet"))


func test_prestige_increments_count_in_root_and_ledger():
	GameState.add_gold(BigNumber.from_float(2_000_000.0))
	GameState.perform_prestige()
	assert_eq(GameState.prestige_count, 1)
	assert_eq(int(GameState.ledger["prestige_count"]), 1)


func test_prestige_awards_rp_additively():
	GameState.add_rancher_points(5, "battle")
	GameState.add_gold(BigNumber.from_float(4_000_000.0))   # 2 RP
	GameState.perform_prestige()
	# 5 from battles + 2 from prestige = 7.
	assert_eq(GameState.current_rancher_points(), 7)


func test_prestige_zero_rp_when_gold_below_threshold():
	GameState.add_gold(BigNumber.from_float(500_000.0))
	var rp := GameState.perform_prestige()
	assert_eq(rp, 0)
	# But state should still reset.
	assert_true(GameState.current_gold().is_zero())
	assert_eq(GameState.prestige_count, 1)

# endregion


# region — save migration v1 -> v2

func test_v1_to_v2_migration_seeds_total_gold_from_currency():
	var v1: Dictionary = {
		"version": 1,
		"currencies": {"gold": {"m": 4.2, "e": 6}},
	}
	var v2: Dictionary = SaveMigrations.apply_chain(v1, 2)
	assert_eq(int(v2.get("version", -1)), 2)
	assert_true(v2.has("total_gold_earned_this_run"))
	# Should match current gold so existing saves can prestige immediately.
	assert_almost_eq(float(v2["total_gold_earned_this_run"]["m"]), 4.2, 1.0e-6)
	assert_eq(int(v2["total_gold_earned_this_run"]["e"]), 6)


func test_v0_to_v2_chain_gets_total_gold_default():
	var v0: Dictionary = {"version": 0}
	var v2: Dictionary = SaveMigrations.apply_chain(v0, 2)
	assert_eq(int(v2.get("version", -1)), 2)
	assert_true(v2.has("total_gold_earned_this_run"))
	assert_eq(float(v2["total_gold_earned_this_run"]["m"]), 0.0)

# endregion
