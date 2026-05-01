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
