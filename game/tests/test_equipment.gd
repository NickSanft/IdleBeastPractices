## Phase 12e — equipment system + auto-equip + battle stat application
## + save migration + prestige preservation.
extends GutTest


func before_each() -> void:
	GameState.from_dict({})
	ContentRegistry.ensure_loaded()


func test_equipment_loads_via_content_registry() -> void:
	var brass: EquipmentResource = ContentRegistry.equipment(&"brass_collar")
	assert_not_null(brass)
	assert_eq(brass.display_name, "Brass Collar")
	# Body slot enum value is 1 in EquipmentResource.Slot.
	assert_eq(int(brass.slot), 1)


func test_grant_equipment_auto_equips_first_eligible_pet() -> void:
	GameState.add_pet(&"green_wisplet_pet", false)
	GameState.add_pet(&"red_wisplet_pet", false)
	var brass: EquipmentResource = ContentRegistry.equipment(&"brass_collar")
	GameState._grant_equipment(brass)
	# brass goes in body slot. First eligible pet (alphabetical or
	# insertion order) should have it equipped.
	var equipped_on_first: String = GameState.equipment_in_slot("green_wisplet_pet", "body")
	var equipped_on_second: String = GameState.equipment_in_slot("red_wisplet_pet", "body")
	assert_true(equipped_on_first == "brass_collar" or equipped_on_second == "brass_collar",
			"first crafted brass collar must auto-equip on one of the owned pets")
	# Second grant goes to the OTHER pet's body slot.
	GameState._grant_equipment(brass)
	var first_again: String = GameState.equipment_in_slot("green_wisplet_pet", "body")
	var second_again: String = GameState.equipment_in_slot("red_wisplet_pet", "body")
	assert_true(first_again == "brass_collar" and second_again == "brass_collar",
			"second crafted brass collar must equip on the other pet")


func test_grant_equipment_falls_back_to_owned_when_full() -> void:
	GameState.add_pet(&"green_wisplet_pet", false)
	# Pre-equip brass on green's body slot.
	GameState.pet_equipment["green_wisplet_pet"] = {"body": "brass_collar"}
	var brass: EquipmentResource = ContentRegistry.equipment(&"brass_collar")
	# A second brass collar should fall through to owned_equipment.
	GameState._grant_equipment(brass)
	assert_eq(GameState.owned_equipment.size(), 1)
	assert_eq(GameState.owned_equipment[0], "brass_collar")


# region — v0.15.19: Pareto upgrade-on-craft (unbricks pre-tier-3 craft
# histories; without it an early tier-1 craft locked the slot forever)

func test_grant_upgrades_dominated_gear_and_stashes_old() -> void:
	GameState.add_pet(&"green_wisplet_pet", false)
	GameState._grant_equipment(ContentRegistry.equipment(&"brass_collar"))
	assert_eq(GameState.equipment_in_slot("green_wisplet_pet", "body"), "brass_collar")
	# silver_collar Pareto-dominates brass_collar (>= every stat, > some).
	GameState._grant_equipment(ContentRegistry.equipment(&"silver_collar"))
	assert_eq(GameState.equipment_in_slot("green_wisplet_pet", "body"), "silver_collar",
			"a dominating craft upgrades the occupied slot")
	assert_true(GameState.owned_equipment.has("brass_collar"),
			"displaced gear is stashed, not lost")


func test_grant_never_downgrades_an_occupied_slot() -> void:
	GameState.add_pet(&"green_wisplet_pet", false)
	GameState._grant_equipment(ContentRegistry.equipment(&"silver_collar"))
	# brass is dominated by silver — must NOT replace it.
	GameState._grant_equipment(ContentRegistry.equipment(&"brass_collar"))
	assert_eq(GameState.equipment_in_slot("green_wisplet_pet", "body"), "silver_collar")
	assert_true(GameState.owned_equipment.has("brass_collar"),
			"the weaker craft goes to the stash")


func test_grant_prefers_empty_slot_over_upgrade() -> void:
	GameState.add_pet(&"green_wisplet_pet", false)
	GameState.add_pet(&"red_wisplet_pet", false)
	GameState._grant_equipment(ContentRegistry.equipment(&"brass_collar"))
	# Red's body slot is still EMPTY — fill it before upgrading green's.
	GameState._grant_equipment(ContentRegistry.equipment(&"silver_collar"))
	assert_eq(GameState.equipment_in_slot("red_wisplet_pet", "body"), "silver_collar")
	assert_eq(GameState.equipment_in_slot("green_wisplet_pet", "body"), "brass_collar")

# endregion


func test_battle_combatant_applies_equipment_stats() -> void:
	# Pre-equip brass collar (+2 def, +10 hp) on green wisplet.
	GameState.add_pet(&"green_wisplet_pet", false)
	GameState.pet_equipment["green_wisplet_pet"] = {"body": "brass_collar"}
	var pet: PetResource = ContentRegistry.pet(&"green_wisplet_pet")
	# Build the combatant via BattleSystem's static method.
	# Using the public path through simulate is heavier than needed;
	# call the underlying _make_combatant_from_pet directly.
	var combatant: Dictionary = BattleSystem._make_combatant_from_pet(pet, 0, "player")
	# Green wisplet base: HP 60, DEF 6. Brass adds +10 hp, +2 def.
	assert_almost_eq(float(combatant["hp"]), 70.0, 0.01,
			"hp must reflect base + equipment hp_add")
	assert_almost_eq(float(combatant["def"]), 8.0, 0.01,
			"def must reflect base + equipment defense_add")


func test_no_equipment_gives_base_stats() -> void:
	GameState.add_pet(&"green_wisplet_pet", false)
	# pet_equipment is empty → no modifiers applied.
	var pet: PetResource = ContentRegistry.pet(&"green_wisplet_pet")
	var combatant: Dictionary = BattleSystem._make_combatant_from_pet(pet, 0, "player")
	assert_almost_eq(float(combatant["hp"]), float(pet.base_hp), 0.01)
	assert_almost_eq(float(combatant["def"]), float(pet.base_defense), 0.01)


func test_equipment_stats_for_returns_totals() -> void:
	GameState.add_pet(&"green_wisplet_pet", false)
	GameState.pet_equipment["green_wisplet_pet"] = {
		"body": "brass_collar",
		"trinket": "agitator_charm",
	}
	var totals: Dictionary = GameState.equipment_stats_for("green_wisplet_pet")
	# brass: +2 def +10 hp; agitator: +4 atk
	assert_almost_eq(float(totals["atk"]), 4.0, 0.01)
	assert_almost_eq(float(totals["def"]), 2.0, 0.01)
	assert_almost_eq(float(totals["hp"]), 10.0, 0.01)


func test_save_migration_v2_to_v3_adds_equipment_fields() -> void:
	var v2_data := {
		"version": 2,
		"pets_owned": ["green_wisplet_pet"],
	}
	var migrated: Dictionary = SaveMigrations._migrate_v2_to_v3(v2_data)
	assert_eq(int(migrated["version"]), 3)
	assert_true(migrated.has("pet_equipment"))
	assert_true(migrated.has("owned_equipment"))
	assert_true(migrated.has("best_rp_at_prestige"))
	assert_eq(migrated["pet_equipment"], {})
	assert_eq(migrated["owned_equipment"], [])
	assert_eq(int(migrated["best_rp_at_prestige"]), 0)


func test_prestige_preserves_equipment() -> void:
	GameState.add_pet(&"green_wisplet_pet", false)
	GameState.pet_equipment["green_wisplet_pet"] = {"body": "brass_collar"}
	# Force enough gold for a prestige to fire (1M+).
	GameState.total_gold_earned_this_run = BigNumber.from_float(2_000_000.0).to_dict()
	GameState.currencies["gold"] = BigNumber.from_float(2_000_000.0).to_dict()
	GameState.perform_prestige()
	# Equipment should survive.
	var still_equipped: String = GameState.equipment_in_slot("green_wisplet_pet", "body")
	assert_eq(still_equipped, "brass_collar",
			"equipment must persist across prestige")


func test_prestige_updates_best_rp_when_higher() -> void:
	GameState.add_pet(&"green_wisplet_pet", false)
	GameState.total_gold_earned_this_run = BigNumber.from_float(2_000_000.0).to_dict()
	GameState.currencies["gold"] = BigNumber.from_float(2_000_000.0).to_dict()
	var rp_gain: int = GameState.perform_prestige()
	assert_eq(GameState.best_rp_at_prestige, rp_gain,
			"best_rp_at_prestige must update on a higher run")
	# A second prestige with LOWER rp should not lower the best.
	GameState.total_gold_earned_this_run = BigNumber.from_float(1_000_000.0).to_dict()
	GameState.currencies["gold"] = BigNumber.from_float(1_000_000.0).to_dict()
	GameState.perform_prestige()
	assert_eq(GameState.best_rp_at_prestige, rp_gain,
			"best_rp_at_prestige must not decrease when a lower run prestiges")


func test_recipe_with_output_equipment_can_craft() -> void:
	# can_craft requires at least one output type. recipe_brass_collar
	# specifies output_equipment.
	var recipe: CraftingRecipeResource = ContentRegistry.recipe(&"recipe_brass_collar")
	assert_not_null(recipe)
	GameState.inventory["wisplet_ectoplasm"] = 25
	GameState.currencies["gold"] = BigNumber.from_float(2000.0).to_dict()
	GameState.current_max_tier = 1
	GameState.add_pet(&"green_wisplet_pet", false)
	var status: Dictionary = CraftingSystem.can_craft(
			recipe,
			GameState.inventory,
			GameState.current_gold(),
			GameState.current_max_tier,
			GameState.recipes_crafted)
	assert_true(bool(status["can"]),
			"recipe with output_equipment must validate via can_craft")
	# Actually craft and confirm equipment landed on the pet.
	var result: Dictionary = GameState.try_craft(recipe)
	assert_true(bool(result["success"]))
	var equipped: String = GameState.equipment_in_slot("green_wisplet_pet", "body")
	assert_eq(equipped, "brass_collar")
