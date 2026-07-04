## v0.15.19 — generated battle stages (tiers 3–6) + gear reachability.
##
## Pins the simulator-derived contract (tools/simulate_stage_winrates.gd):
## one stage per tier 1..6, thinning wave shapes, every monster id
## resolvable, and — the load-bearing one — every generated stage is
## WINNABLE with equipment the player can ACTUALLY OBTAIN, built through
## the real crafting grant path (not a hand-assembled dict: the first
## draft of this file pinned a loadout with no acquisition path, and the
## adversarial review proved tiers 5-6 would have shipped unwinnable).
## BattleView auto-picks the highest unlocked stage (no picker), so an
## unwinnable top stage bricks the battler for late players.
extends GutTest

const _SEEDS := [1000, 1001, 1002, 1003, 1004]
## The tier-2 gear trio — craftable via the v0.15.19 recipes; the Pareto
## upgrade rule in _grant_equipment lets it replace earlier tier-1 gear.
const _TIER2_GEAR := [&"seer_circlet", &"silver_collar", &"rending_fang"]
const _ALL_EQUIPMENT_IDS := [
	&"copper_circlet", &"brass_collar", &"agitator_charm",
	&"seer_circlet", &"silver_collar", &"rending_fang",
]


func before_each() -> void:
	GameState._reset_to_defaults()
	ContentRegistry.ensure_loaded()


func after_each() -> void:
	GameState._reset_to_defaults()


## Mirrors BattleView._start_stage's team construction (owned_pets order).
func _owned_pets() -> Array[PetResource]:
	return GameState.owned_pets()


## Grant the full roster + best obtainable gear THROUGH the real path:
## every pet owned, then each tier-2 item granted once per pet via
## GameState._grant_equipment — exactly what crafting the recipe does.
func _acquire_roster_and_best_gear() -> void:
	for pet in ContentRegistry.pets():
		if not GameState.pets_owned.has(String(pet.id)):
			GameState.pets_owned.append(String(pet.id))
	for item_id in _TIER2_GEAR:
		for i in GameState.pets_owned.size():
			GameState._grant_equipment(ContentRegistry.equipment(item_id))


func test_exactly_one_stage_per_tier_one_through_six() -> void:
	var by_tier: Dictionary = {}
	for stage in ContentRegistry.battle_stages():
		by_tier[stage.tier] = int(by_tier.get(stage.tier, 0)) + 1
	for tier in range(1, 7):
		assert_eq(int(by_tier.get(tier, 0)), 1, "tier %d has exactly one stage" % tier)
	assert_eq(ContentRegistry.battle_stages().size(), 6,
			"no stages beyond the winnable band (tier 7+ needs pet progression first)")


func test_every_encounter_monster_resolves() -> void:
	for stage in ContentRegistry.battle_stages():
		assert_gt(stage.encounters.size(), 0, "%s has waves" % stage.id)
		for enc in stage.encounters:
			assert_gt(enc.monster_ids.size(), 0)
			for mid in enc.monster_ids:
				assert_not_null(ContentRegistry.monster(mid),
						"%s references unknown monster %s" % [stage.id, mid])


func test_wave_sizes_never_shrink_within_a_stage() -> void:
	for stage in ContentRegistry.battle_stages():
		var prev: int = 0
		for enc in stage.encounters:
			assert_true(enc.monster_ids.size() >= prev,
					"%s waves must not shrink" % stage.id)
			prev = enc.monster_ids.size()


func test_default_stage_tracks_highest_unlocked() -> void:
	assert_eq(String(ContentRegistry.default_stage_for_tier(3).id), "hush_thicket")
	assert_eq(String(ContentRegistry.default_stage_for_tier(6).id), "surge_shallows")
	# Late players stay on the band's top stage rather than an unwinnable one.
	assert_eq(String(ContentRegistry.default_stage_for_tier(20).id), "surge_shallows")


func test_every_equipment_item_has_a_recipe() -> void:
	# Orphan-gear guard: equipment with no acquisition path is dead data at
	# best — at worst it silently distorts balance tooling (the v0.15.19
	# review caught the band being tuned against unobtainable gear).
	var craftable: Dictionary = {}
	for recipe in ContentRegistry.recipes():
		if recipe.output_equipment != null:
			craftable[recipe.output_equipment.id] = true
	for item_id in _ALL_EQUIPMENT_IDS:
		assert_true(craftable.has(item_id),
				"%s has no recipe — orphaned equipment" % item_id)


func test_generated_stages_winnable_with_obtainable_gear() -> void:
	_acquire_roster_and_best_gear()
	var pets := _owned_pets()
	for stage in ContentRegistry.battle_stages():
		if stage.tier < 3:
			continue  # hand-authored tiers are covered by test_battle_stage
		for s in _SEEDS:
			var log: Dictionary = BattleSystem.simulate_stage(s, pets, stage)
			assert_eq(String(log.get("winner", "")), "player",
					"%s seed %d must be winnable with obtainable gear" % [stage.id, s])


func test_tier_three_is_the_equipment_gate() -> void:
	# Bare roster loses Hush Thicket (simulator: 0% bare) — the moment
	# crafting/equipment becomes REQUIRED, not optional.
	for pet in ContentRegistry.pets():
		GameState.pets_owned.append(String(pet.id))
	GameState.pet_equipment = {}
	var stage: BattleStageResource = ContentRegistry.battle_stage(&"hush_thicket")
	var log: Dictionary = BattleSystem.simulate_stage(1000, _owned_pets(), stage)
	assert_ne(String(log.get("winner", "")), "player",
			"bare roster should not clear the tier-3 stage")
