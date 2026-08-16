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
## Phase 15a: the fielded team, not the whole roster. BattleView caps the
## fight at GameState.battle_team(3); before pets existed for tiers 2-20
## the roster WAS three pets so the distinction did not exist, and passing
## every owned pet here quietly simulated a 60-strong army that no player
## can field.
func _owned_pets() -> Array[PetResource]:
	return GameState.battle_team(3)


## The tier a pet is awarded at — its source monster's tier.
func _pet_tier(p: PetResource) -> int:
	var m: MonsterResource = ContentRegistry.monster(p.source_monster_id)
	return m.tier if m != null else 1


## Grant the roster + best obtainable gear THROUGH the real path: pets
## owned, then each tier-2 item granted once per pet via
## GameState._grant_equipment — exactly what crafting the recipe does.
##
## Phase 15a: bounded by `max_tier`, because pets now exist for all 20
## tiers. Granting the whole roster would field tier-20 companions against
## a tier-3 stage — a save state no player can reach, since pets are only
## awarded by completing their own tier.
func _acquire_roster_and_best_gear(max_tier: int = 20) -> void:
	for pet in ContentRegistry.pets():
		if _pet_tier(pet) > max_tier:
			continue
		if not GameState.pets_owned.has(String(pet.id)):
			GameState.pets_owned.append(String(pet.id))
	for item_id in _TIER2_GEAR:
		for i in GameState.pets_owned.size():
			GameState._grant_equipment(ContentRegistry.equipment(item_id))


func test_exactly_one_stage_per_tier_one_through_twenty() -> void:
	var by_tier: Dictionary = {}
	for stage in ContentRegistry.battle_stages():
		by_tier[stage.tier] = int(by_tier.get(stage.tier, 0)) + 1
	for tier in range(1, 21):
		assert_eq(int(by_tier.get(tier, 0)), 1, "tier %d has exactly one stage" % tier)
	# Phase 15a: the band used to stop at 6 because a static tier-1 roster
	# could not win past it. Pets now scale with the tier, so it runs to
	# the tier cap — a player who catches to 20 can battle to 20.
	assert_eq(ContentRegistry.battle_stages().size(), 20,
			"one stage per catching tier, all the way to the cap")


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
	# Phase 15a: the band reaches the tier cap, so a tier-20 player gets
	# the tier-20 stage. Before pet progression they were parked on
	# surge_shallows (tier 6) — the top of a band that stopped early
	# because no deeper stage was winnable with a static roster.
	assert_eq(String(ContentRegistry.default_stage_for_tier(20).id), "nadir_spire")


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
	for stage in ContentRegistry.battle_stages():
		if stage.tier < 3:
			continue  # hand-authored tiers are covered by test_battle_stage
		# Phase 15a: rebuild the roster per stage, capped at that stage's
		# tier — the strongest team a player standing in front of it owns.
		GameState._reset_to_defaults()
		_acquire_roster_and_best_gear(stage.tier)
		var pets := _owned_pets()
		for s in _SEEDS:
			var log: Dictionary = BattleSystem.simulate_stage(s, pets, stage)
			assert_eq(String(log.get("winner", "")), "player",
					"%s seed %d must be winnable with obtainable gear" % [stage.id, s])


## Phase 15a retired `test_tier_three_is_the_equipment_gate`.
##
## That test asserted a BARE roster LOSES the tier-3 stage — equipment as a
## hard gate. It held only because the roster was frozen at three tier-1
## pets while enemies scaled with tier. Now that each tier awards its own
## companions, a player arriving at tier 3 fields tier-3 pets, and
## tools/simulate_stage_winrates.gd reports 100% bare at every tier 1-20.
## Gear is a genuine upgrade, not an entry toll.
##
## What replaces it is the contract that survived: a player who reached a
## tier can clear its stage with the roster that tier gave them, WITHOUT
## having crafted anything. BattleView auto-picks the highest unlocked
## stage with no picker, so a stage that demands gear the player skipped
## would soft-lock the battler.
func test_every_stage_is_clearable_bare_by_its_own_tiers_roster() -> void:
	for stage in ContentRegistry.battle_stages():
		GameState._reset_to_defaults()
		for pet in ContentRegistry.pets():
			if _pet_tier(pet) <= stage.tier:
				GameState.pets_owned.append(String(pet.id))
		GameState.pet_equipment = {}
		var log: Dictionary = BattleSystem.simulate_stage(1000, _owned_pets(), stage)
		assert_eq(String(log.get("winner", "")), "player",
				"%s must be clearable bare — BattleView auto-picks it with no gear check"
						% stage.id)
