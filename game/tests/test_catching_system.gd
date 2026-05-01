extends GutTest


var item: ItemResource
var monsters: Array[MonsterResource]
var net: NetResource


func before_each() -> void:
	item = ItemResource.new()
	item.id = &"test_item"
	item.display_name = "Test Item"
	# Three monsters across two tiers to exercise the spawn filter.
	var m1 := _make_monster(&"m_t1_a", 1, 1.0, 1.0, 1, 0.0)
	var m2 := _make_monster(&"m_t1_b", 1, 0.5, 2.0, 5, 0.0)
	var m3 := _make_monster(&"m_t2_a", 2, 1.0, 4.0, 50, 0.0)
	monsters = [m1, m2, m3]
	net = NetResource.new()
	net.id = &"test_net"
	net.targets_tiers = [1]
	net.catches_per_second = 1.0
	net.spawn_max = 3


func _make_monster(
		id: StringName,
		tier: int,
		spawn_weight: float,
		catch_difficulty: float,
		gold_base: int,
		shiny_rate: float) -> MonsterResource:
	var m := MonsterResource.new()
	m.id = id
	m.tier = tier
	m.spawn_weight = spawn_weight
	m.base_catch_difficulty = catch_difficulty
	m.drop_item = item
	m.drop_amount_min = 1
	m.drop_amount_max = 1
	m.gold_base = gold_base
	m.shiny_rate = shiny_rate
	return m


func test_pick_spawn_respects_net_tier_filter():
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	# Net only targets tier 1, so tier-2 monster should never be picked.
	for i in 200:
		var picked := CatchingSystem.pick_spawn(monsters, 2, net, rng)
		assert_ne(picked.tier, 2, "Tier 2 monster picked despite net targeting tier 1 only")


func test_pick_spawn_respects_current_max_tier():
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	net.targets_tiers = [1, 2]
	# current_max_tier is 1; tier-2 monster should be ineligible.
	for i in 200:
		var picked := CatchingSystem.pick_spawn(monsters, 1, net, rng)
		assert_ne(picked.tier, 2, "Tier 2 monster picked despite current_max_tier=1")


func test_pick_spawn_returns_null_when_pool_empty_for_tier():
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	# Net targets tier 5; no monsters in pool match.
	net.targets_tiers = [5]
	var picked := CatchingSystem.pick_spawn(monsters, 5, net, rng)
	assert_null(picked, "Expected null when no candidate matches")


func test_resolve_tap_below_difficulty_does_not_catch():
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	# Monster with difficulty 5; one tap shouldn't suffice.
	var outcome := CatchingSystem.resolve_tap(monsters[1], 0.0, rng)
	assert_false(outcome["caught"], "Single tap should not catch a difficulty-2 monster")
	assert_almost_eq(outcome["tap_progress"], 1.0, 1.0e-9)


func test_resolve_tap_at_difficulty_catches():
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	# Monster m1 has difficulty 1.0; one tap catches.
	var outcome := CatchingSystem.resolve_tap(monsters[0], 0.0, rng)
	assert_true(outcome["caught"])
	assert_eq(outcome["monster_id"], &"m_t1_a")
	assert_true(outcome["gold"] is BigNumber)
	assert_almost_eq(outcome["gold"].to_float(), 1.0, 1.0e-6)


func test_resolve_tap_drop_in_range():
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	monsters[0].drop_amount_min = 2
	monsters[0].drop_amount_max = 7
	# Run many catches; every drop must land in [2, 7].
	for i in 100:
		rng.seed = i
		var outcome := CatchingSystem.resolve_tap(monsters[0], 0.0, rng)
		assert_true(outcome["caught"])
		var drop: int = outcome["drop_amount"]
		assert_true(drop >= 2 and drop <= 7, "Drop %d out of [2,7]" % drop)


func test_shiny_roll_seeded_deterministic():
	var rng_a := RandomNumberGenerator.new()
	var rng_b := RandomNumberGenerator.new()
	rng_a.seed = 1234
	rng_b.seed = 1234
	monsters[0].shiny_rate = 0.5
	var a := CatchingSystem.resolve_tap(monsters[0], 0.0, rng_a)
	var b := CatchingSystem.resolve_tap(monsters[0], 0.0, rng_b)
	assert_eq(a["is_shiny"], b["is_shiny"])
	assert_eq(a["drop_amount"], b["drop_amount"])


func test_auto_catch_count_accumulator():
	# 0.5 catches/sec, 3 second tick = 1.5 expected. One catch fires, 0.5 remains.
	var result := CatchingSystem.auto_catch_count(0.0, 3.0, 0.5)
	assert_eq(result["count"], 1)
	assert_almost_eq(result["accumulator"], 0.5, 1.0e-9)


func test_auto_catch_count_carries_remainder():
	# Start with 0.4 left over, +0.7 = 1.1 -> 1 catch, 0.1 remains.
	var result := CatchingSystem.auto_catch_count(0.4, 1.0, 0.7)
	assert_eq(result["count"], 1)
	assert_almost_eq(result["accumulator"], 0.1, 1.0e-9)


func test_auto_catch_count_zero_dt_no_catch():
	var result := CatchingSystem.auto_catch_count(0.9, 0.0, 1.0)
	assert_eq(result["count"], 0)
	assert_almost_eq(result["accumulator"], 0.9, 1.0e-9)


# region — tier_completion_status

func _make_t1_pool() -> Array[MonsterResource]:
	var a := MonsterResource.new()
	a.id = &"a"
	a.tier = 1
	var b := MonsterResource.new()
	b.id = &"b"
	b.tier = 1
	var c := MonsterResource.new()
	c.id = &"c"
	c.tier = 1
	var pool: Array[MonsterResource] = [a, b, c]
	return pool


func test_tier_status_all_seen_threshold_met():
	var pool := _make_t1_pool()
	var caught: Dictionary = {
		"a": {"normal": 5, "shiny": 0},
		"b": {"normal": 1, "shiny": 1},
		"c": {"normal": 1, "shiny": 0},
	}
	var status := CatchingSystem.tier_completion_status(pool, caught, 1, 2)
	assert_true(status["is_complete"], "expected complete")
	assert_eq(status["max_count"], 5)
	assert_true(status["missing_species"].is_empty())


func test_tier_status_missing_species_blocks():
	var pool := _make_t1_pool()
	# Caught a and b but never c.
	var caught: Dictionary = {
		"a": {"normal": 100, "shiny": 0},
		"b": {"normal": 100, "shiny": 0},
	}
	var status := CatchingSystem.tier_completion_status(pool, caught, 1, 2)
	assert_false(status["is_complete"], "should not be complete with missing species")
	assert_eq(status["missing_species"].size(), 1)
	assert_eq(status["missing_species"][0], &"c")


func test_tier_status_below_threshold_blocks():
	var pool := _make_t1_pool()
	var caught: Dictionary = {
		"a": {"normal": 1, "shiny": 0},
		"b": {"normal": 1, "shiny": 0},
		"c": {"normal": 1, "shiny": 0},
	}
	# Threshold 2; max_count is 1.
	var status := CatchingSystem.tier_completion_status(pool, caught, 1, 2)
	assert_false(status["is_complete"])
	assert_eq(status["max_count"], 1)


func test_tier_status_shiny_counts_toward_threshold():
	var pool := _make_t1_pool()
	# Shiny catches should also count toward the threshold.
	var caught: Dictionary = {
		"a": {"normal": 0, "shiny": 5},
		"b": {"normal": 1, "shiny": 0},
		"c": {"normal": 1, "shiny": 0},
	}
	var status := CatchingSystem.tier_completion_status(pool, caught, 1, 2)
	assert_true(status["is_complete"])
	assert_eq(status["max_count"], 5)


func test_tier_status_empty_pool_for_tier():
	var pool := _make_t1_pool()
	# Tier 2 has no monsters in this pool.
	var status := CatchingSystem.tier_completion_status(pool, {}, 2, 2)
	assert_false(status["is_complete"])
	assert_eq(status["tier_species"].size(), 0)


# endregion


# region — pets_to_award_for_tier

func test_pets_to_award_returns_each_pet_in_tier():
	var pet_a := PetResource.new()
	pet_a.id = &"pet_a"
	var pet_c := PetResource.new()
	pet_c.id = &"pet_c"
	var a := MonsterResource.new()
	a.id = &"a"
	a.tier = 1
	a.pet = pet_a
	var b := MonsterResource.new()
	b.id = &"b"
	b.tier = 1
	# b has no pet
	var c := MonsterResource.new()
	c.id = &"c"
	c.tier = 1
	c.pet = pet_c
	var d := MonsterResource.new()
	d.id = &"d"
	d.tier = 2
	# d is wrong tier, ignored
	var pool: Array[MonsterResource] = [a, b, c, d]
	var awarded := CatchingSystem.pets_to_award_for_tier(pool, 1)
	assert_eq(awarded.size(), 2, "expected 2 awarded pets (a + c)")
	var ids: Array = []
	for p in awarded:
		ids.append(p.id)
	assert_true(ids.has(&"pet_a"))
	assert_true(ids.has(&"pet_c"))


func test_pets_to_award_empty_when_no_tier_match():
	var a := MonsterResource.new()
	a.id = &"a"
	a.tier = 1
	var pool: Array[MonsterResource] = [a]
	var awarded := CatchingSystem.pets_to_award_for_tier(pool, 99)
	assert_eq(awarded.size(), 0)

# endregion


# region — statistical shiny-rate sanity

func test_shiny_rate_falls_within_95_pct_ci_at_5_pct():
	# Bernoulli(p=0.05) over 10000 trials: 500 ± 1.96·sqrt(10000·0.05·0.95) ≈
	# 500 ± 42.7 ⇒ [457, 543]. With a fixed seed this is deterministic, but the
	# test asserts the loose CI so a code change that drifts the rate trips it.
	var monster := MonsterResource.new()
	monster.id = &"stat_monster"
	monster.tier = 1
	monster.drop_item = item
	monster.drop_amount_min = 1
	monster.drop_amount_max = 1
	monster.gold_base = 1
	monster.shiny_rate = 0.05
	monster.base_catch_difficulty = 0.0  # always catches on first tap
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xC0FFEE
	var shinies: int = 0
	for i in 10000:
		var outcome := CatchingSystem.resolve_tap(monster, 0.0, rng)
		if bool(outcome.get("is_shiny", false)):
			shinies += 1
	assert_true(shinies >= 457 and shinies <= 543,
			"shiny count %d outside 95%% CI [457, 543] for p=0.05 n=10000" % shinies)

# endregion
