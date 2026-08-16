## Phase 15a — pet progression across tiers 2-20.
##
## Before this phase the game shipped 60 monsters and THREE pets, all
## tier 1. Because BattleSystem derives enemy stats from tier
## (hp 20t+10, atk 4t+4, def 2t) and damage is a flat `max(1, atk - def)`,
## a tier-1 pet (atk 9-16) cannot scratch a tier-20 enemy (def 40) — which
## is why scripts/generate_battle_stages.py recorded "tier 7+ is unwinnable
## in ANY shape ... more stages need pet progression first".
##
## These tests pin the two halves of the fix: every tier awards pets, and
## the fielded team is the STRONGEST three rather than the first three
## acquired (without which all 57 new pets would be dead content, since
## BattleView used to slice acquisition order).
extends GutTest

const _EXPECTED_TIERS := 20
const _SPECIES_PER_TIER := 3


func before_each() -> void:
	GameState._reset_to_defaults()
	ContentRegistry.ensure_loaded()


func after_each() -> void:
	GameState._reset_to_defaults()


func _pet_tier(p: PetResource) -> int:
	var m: MonsterResource = ContentRegistry.monster(p.source_monster_id)
	return m.tier if m != null else -1


# region — content coverage


func test_every_tier_awards_a_pet_for_every_species() -> void:
	var by_tier: Dictionary = {}
	for m in ContentRegistry.monsters():
		by_tier[m.tier] = int(by_tier.get(m.tier, 0)) + (1 if m.pet != null else 0)
	for tier in range(1, _EXPECTED_TIERS + 1):
		assert_eq(int(by_tier.get(tier, 0)), _SPECIES_PER_TIER,
				"tier %d must award %d pets — a tier with no pet strands the roster"
						% [tier, _SPECIES_PER_TIER])


func test_pet_ids_are_unique_and_resolve_to_their_source_monster() -> void:
	var seen: Dictionary = {}
	for p in ContentRegistry.pets():
		var key: String = String(p.id)
		assert_false(seen.has(key), "duplicate pet id '%s'" % key)
		seen[key] = true
		assert_gt(_pet_tier(p), 0,
				"pet '%s' has an unresolvable source_monster_id '%s'"
						% [key, String(p.source_monster_id)])


func test_every_pet_ability_is_registered() -> void:
	for p in ContentRegistry.pets():
		var cb: Callable = AbilityRegistry.get_ability(p.ability_id)
		assert_true(cb.is_valid(),
				"pet '%s' has unregistered ability '%s' — it would silently basic-attack forever"
						% [String(p.id), String(p.ability_id)])


# endregion
# region — stat curve


## The curve must be monotonic in tier, otherwise completing a tier could
## hand the player a downgrade and battle_team would keep the old trio.
func test_pet_power_increases_with_tier() -> void:
	var best_per_tier: Dictionary = {}
	for p in ContentRegistry.pets():
		var t: int = _pet_tier(p)
		var power: float = GameState.pet_power(p)
		best_per_tier[t] = max(float(best_per_tier.get(t, 0.0)), power)
	for tier in range(2, _EXPECTED_TIERS + 1):
		assert_gt(float(best_per_tier[tier]), float(best_per_tier[tier - 1]),
				"tier %d's best pet must out-power tier %d's" % [tier, tier - 1])


## A same-tier pet must be able to hurt a same-tier enemy. Damage is
## `max(1, atk - def)`, so an atk at or below the enemy's def floors every
## hit at 1 and turns the fight into a tick-cap draw.
func test_each_tier_can_meaningfully_damage_its_own_tier_enemies() -> void:
	for p in ContentRegistry.pets():
		var tier: int = _pet_tier(p)
		var enemy_def: float = float(2 * tier)
		assert_gt(p.base_attack, enemy_def * 2.0,
				"pet '%s' (atk %.1f) barely dents a tier-%d enemy (def %.1f)"
						% [String(p.id), p.base_attack, tier, enemy_def])


# endregion
# region — fielded team


func test_battle_team_picks_the_strongest_and_caps_at_three() -> void:
	for p in ContentRegistry.pets():
		GameState.pets_owned.append(String(p.id))
	var team: Array[PetResource] = GameState.battle_team(3)
	assert_eq(team.size(), 3, "battle_team must cap the fight at 3 pets")
	var all_powers: Array[float] = []
	for p in ContentRegistry.pets():
		all_powers.append(GameState.pet_power(p))
	all_powers.sort()
	all_powers.reverse()
	for i in team.size():
		assert_almost_eq(GameState.pet_power(team[i]), all_powers[i], 0.001,
				"battle_team entry %d is not the %dth strongest pet" % [i, i])


## The regression this whole phase turns on: BattleView used to field
## `owned_pets().slice(0, 3)` — acquisition order — so a player who owned
## every pet would fight tier 20 with the three tier-1 wisplets.
func test_late_roster_does_not_field_the_starting_wisplets() -> void:
	for p in ContentRegistry.pets():
		GameState.pets_owned.append(String(p.id))
	for p in GameState.battle_team(3):
		assert_gt(_pet_tier(p), 1,
				"tier-1 pet '%s' should not be fielded once the full roster is owned"
						% String(p.id))


func test_battle_team_is_deterministic() -> void:
	for p in ContentRegistry.pets():
		GameState.pets_owned.append(String(p.id))
	var first: Array[PetResource] = GameState.battle_team(3)
	# Re-derive from a shuffled ownership order: the ranking, not the
	# acquisition order, must decide the team (seeded replays depend on it).
	GameState.pets_owned.reverse()
	var second: Array[PetResource] = GameState.battle_team(3)
	assert_eq(first.size(), second.size())
	for i in first.size():
		assert_eq(String(first[i].id), String(second[i].id),
				"battle_team entry %d changed with acquisition order" % i)


func test_battle_team_handles_rosters_smaller_than_the_cap() -> void:
	GameState.pets_owned.append("green_wisplet_pet")
	var team: Array[PetResource] = GameState.battle_team(3)
	assert_eq(team.size(), 1, "a one-pet roster must field one pet, not crash")


# endregion
