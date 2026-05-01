## Tests GameState mutators that aren't pure-system territory.
## Resets the live autoload between tests via from_dict({}).
extends GutTest


func before_each() -> void:
	GameState.from_dict({})


func test_add_pet_base_only():
	var added: bool = GameState.add_pet(&"green_wisplet_pet", false)
	assert_true(added)
	assert_eq(GameState.pets_owned.size(), 1)
	assert_eq(GameState.pets_owned[0], "green_wisplet_pet")
	assert_true(GameState.pet_variants_owned.is_empty())


func test_add_pet_variant_implies_base():
	var added: bool = GameState.add_pet(&"red_wisplet_pet", true)
	assert_true(added)
	# Variant flag must add to BOTH lists — variant ownership implies base ownership.
	assert_true(GameState.pets_owned.has("red_wisplet_pet"))
	assert_true(GameState.pet_variants_owned.has("red_wisplet_pet"))


func test_add_pet_idempotent_for_base():
	var first: bool = GameState.add_pet(&"green_wisplet_pet", false)
	var second: bool = GameState.add_pet(&"green_wisplet_pet", false)
	assert_true(first)
	assert_false(second, "second add of same base should be no-op")
	assert_eq(GameState.pets_owned.size(), 1)


func test_add_pet_variant_after_base_adds_only_variant():
	GameState.add_pet(&"green_wisplet_pet", false)
	var second: bool = GameState.add_pet(&"green_wisplet_pet", true)
	assert_true(second, "variant flag should still add to pet_variants_owned")
	assert_eq(GameState.pets_owned.size(), 1, "should not duplicate in pets_owned")
	assert_eq(GameState.pet_variants_owned.size(), 1)


func test_add_pet_variant_idempotent():
	GameState.add_pet(&"green_wisplet_pet", true)
	var second: bool = GameState.add_pet(&"green_wisplet_pet", true)
	assert_false(second)
	assert_eq(GameState.pets_owned.size(), 1)
	assert_eq(GameState.pet_variants_owned.size(), 1)


func test_reconcile_pet_awards_fills_missing_pets():
	# Simulate the user's broken save shape: tier 1 marked complete but only
	# one of the three pets is in pets_owned.
	GameState.tiers_completed = [1]
	GameState.pets_owned = ["green_wisplet_pet"]
	GameState.reconcile_pet_awards()
	# After reconciliation all 3 tier-1 pets should be present (red + blue
	# wisplet pets reconstituted from the monster .tres files via
	# ContentRegistry).
	assert_true(GameState.pets_owned.has("green_wisplet_pet"))
	assert_true(GameState.pets_owned.has("red_wisplet_pet"))
	assert_true(GameState.pets_owned.has("blue_wisplet_pet"))


func test_reconcile_pet_awards_idempotent():
	GameState.tiers_completed = [1]
	GameState.reconcile_pet_awards()
	var size_after_first := GameState.pets_owned.size()
	GameState.reconcile_pet_awards()
	assert_eq(GameState.pets_owned.size(), size_after_first, "second reconcile should be a no-op")


func test_reconcile_pet_awards_skips_completed_tiers_without_pets():
	# tier 99 doesn't exist as content; reconcile must not crash or add anything.
	GameState.tiers_completed = [99]
	GameState.reconcile_pet_awards()
	assert_eq(GameState.pets_owned.size(), 0)


func test_try_purchase_upgrade_deducts_gold_and_increments_level():
	var u := UpgradeResource.new()
	u.id = &"test_upgrade"
	u.effect_id = &"gold_mult"
	u.magnitude = 0.25
	u.max_level = 3
	u.cost = {"m": 1.0, "e": 0}  # 1 gold base
	u.cost_growth = 2.0
	u.cost_currency = UpgradeResource.Currency.GOLD
	GameState.add_gold(BigNumber.from_float(100.0))
	var result: Dictionary = GameState.try_purchase_upgrade(u)
	assert_true(bool(result["success"]))
	assert_eq(int(result["new_level"]), 1)
	assert_eq(GameState.get_upgrade_level(&"test_upgrade"), 1)
	# Level 2 should cost 1 * 2^1 = 2.
	var second: Dictionary = GameState.try_purchase_upgrade(u)
	assert_true(bool(second["success"]))
	assert_eq(int(second["new_level"]), 2)


func test_try_purchase_upgrade_blocks_at_max_level():
	var u := UpgradeResource.new()
	u.id = &"capped"
	u.effect_id = &"gold_mult"
	u.magnitude = 0.25
	u.max_level = 1
	u.cost = {"m": 1.0, "e": 0}
	u.cost_currency = UpgradeResource.Currency.GOLD
	GameState.add_gold(BigNumber.from_float(100.0))
	GameState.try_purchase_upgrade(u)
	var second: Dictionary = GameState.try_purchase_upgrade(u)
	assert_false(bool(second["success"]))
	assert_eq(String(second["reason"]), "max_level")


func test_try_purchase_upgrade_blocks_on_insufficient_gold():
	var u := UpgradeResource.new()
	u.id = &"expensive"
	u.effect_id = &"gold_mult"
	u.magnitude = 0.25
	u.max_level = 1
	u.cost = {"m": 1.0, "e": 6}  # 1,000,000
	u.cost_currency = UpgradeResource.Currency.GOLD
	# State starts with 0 gold.
	var result: Dictionary = GameState.try_purchase_upgrade(u)
	assert_false(bool(result["success"]))
	assert_eq(String(result["reason"]), "insufficient_gold")
	assert_eq(GameState.get_upgrade_level(&"expensive"), 0)


func test_record_catch_first_seen_initializes_entry():
	GameState.record_catch(&"new_species", false, "tap")
	assert_true(GameState.monsters_caught.has("new_species"))
	assert_eq(int(GameState.monsters_caught["new_species"]["normal"]), 1)
	assert_eq(int(GameState.monsters_caught["new_species"]["shiny"]), 0)


func test_record_catch_shiny_increments_shiny_counter():
	GameState.record_catch(&"green_wisplet", true, "tap")
	assert_eq(int(GameState.monsters_caught["green_wisplet"]["shiny"]), 1)
	assert_eq(int(GameState.ledger["total_shinies"]), 1)


# region — total_gold_earned_this_run reconciliation

func test_reconcile_total_gold_snaps_up_when_tracker_low() -> void:
	# Simulate a stale save: lots of gold but a tiny tracker — impossible
	# under the live invariant because spending never decrements the tracker.
	GameState.from_dict({})
	GameState.currencies["gold"] = {"m": 4.18, "e": 7}            # ~41.8M
	GameState.total_gold_earned_this_run = {"m": 4.1, "e": 4}     # ~41K
	GameState.reconcile_total_gold_earned_this_run()
	var tracked := BigNumber.from_dict(GameState.total_gold_earned_this_run)
	var current := GameState.current_gold()
	assert_true(tracked.gte(current),
			"tracker (%s) should be >= current gold (%s) after reconciliation" % [
				tracked.format(), current.format(),
			])


func test_reconcile_total_gold_noop_when_already_consistent() -> void:
	GameState.from_dict({})
	GameState.currencies["gold"] = {"m": 1.0, "e": 3}             # 1000
	GameState.total_gold_earned_this_run = {"m": 5.0, "e": 3}     # 5000 (legitimate: spent 4000)
	GameState.reconcile_total_gold_earned_this_run()
	assert_almost_eq(
			BigNumber.from_dict(GameState.total_gold_earned_this_run).to_float(),
			5000.0,
			1.0e-6,
			"reconcile must not lower a legitimately-higher tracker")


func test_reconcile_total_gold_unblocks_prestige_for_stale_save() -> void:
	# 41.8M tracker → projected RP ≈ floor(sqrt(41.8)) = 6.
	GameState.from_dict({})
	GameState.currencies["gold"] = {"m": 4.18, "e": 7}
	GameState.total_gold_earned_this_run = {"m": 4.1, "e": 4}
	assert_eq(GameState.projected_rp_gain(), 0,
			"before reconciliation, projected RP should reflect the bogus tracker")
	GameState.reconcile_total_gold_earned_this_run()
	assert_eq(GameState.projected_rp_gain(), 6,
			"after reconciliation, prestige math should kick in based on actual gold")

# endregion
