extends GutTest


var item: ItemResource
var monsters: Array[MonsterResource]
var net: NetResource


func before_each() -> void:
	item = ItemResource.new()
	item.id = &"test_item"
	# Two tier-1 monsters, equal spawn weight.
	var m1 := _make_monster(&"a", 1, 1.0, 1, 0.05)
	var m2 := _make_monster(&"b", 1, 1.0, 2, 0.05)
	monsters = [m1, m2]
	net = NetResource.new()
	net.id = &"basic"
	net.targets_tiers = [1]
	net.catches_per_second = 1.0


func _make_monster(
		id: StringName,
		tier: int,
		spawn_weight: float,
		gold_base: int,
		shiny_rate: float) -> MonsterResource:
	var m := MonsterResource.new()
	m.id = id
	m.tier = tier
	m.spawn_weight = spawn_weight
	m.drop_item = item
	m.drop_amount_min = 1
	m.drop_amount_max = 3
	m.gold_base = gold_base
	m.shiny_rate = shiny_rate
	return m


func test_zero_elapsed_returns_empty_summary():
	var rng := RandomNumberGenerator.new()
	rng.seed = 0
	var summary := OfflineProgressSystem.compute(monsters, net, 1, 0.0, rng)
	assert_eq(summary["seconds"], 0.0)
	assert_true(summary["catches_by_species"].is_empty())
	assert_true((summary["gold_gained"] as BigNumber).is_zero())


func test_cap_enforced():
	var rng := RandomNumberGenerator.new()
	rng.seed = 0
	# 7200s elapsed; default cap 3600. Result should report 3600 and capped=true.
	var summary := OfflineProgressSystem.compute(monsters, net, 1, 7200.0, rng)
	assert_eq(summary["seconds"], 3600.0)
	assert_true(summary["capped"])


func test_cap_multiplier_extends_cap():
	var rng := RandomNumberGenerator.new()
	rng.seed = 0
	# Cap multiplier 2.0 -> 7200s ceiling.
	var summary := OfflineProgressSystem.compute(
			monsters, net, 1, 5400.0, rng, 2.0)
	assert_eq(summary["seconds"], 5400.0)
	assert_false(summary["capped"])


func test_distribution_by_spawn_weight():
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	# Equal spawn_weight -> roughly equal catches_by_species. 1 catch/sec * 60s = ~60 catches total.
	var summary := OfflineProgressSystem.compute(monsters, net, 1, 60.0, rng)
	var a_total: int = summary["catches_by_species"][&"a"]["normal"] + summary["catches_by_species"][&"a"]["shiny"]
	var b_total: int = summary["catches_by_species"][&"b"]["normal"] + summary["catches_by_species"][&"b"]["shiny"]
	# Each should be ~30; allow a wide tolerance because rounding distributes
	# half-catches deterministically per species.
	assert_almost_eq(float(a_total), 30.0, 5.0, "Species 'a' total off expected")
	assert_almost_eq(float(b_total), 30.0, 5.0, "Species 'b' total off expected")


func test_gold_accumulates_via_bignumber():
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# 60 catches * (gold_base 1 for half + 2 for half) ≈ 90 gold.
	var summary := OfflineProgressSystem.compute(monsters, net, 1, 60.0, rng)
	var gold: BigNumber = summary["gold_gained"]
	assert_true(gold is BigNumber)
	# Loose bounds: 60 catches * average gold 1.5 = 90, allow ±20.
	assert_true(gold.to_float() >= 70.0 and gold.to_float() <= 110.0,
			"gold=%s out of expected band" % gold.format())


func test_filters_by_tier_gate():
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	# current_max_tier=0 means no eligible monsters.
	var summary := OfflineProgressSystem.compute(monsters, net, 0, 60.0, rng)
	assert_true(summary["catches_by_species"].is_empty())
	assert_true((summary["gold_gained"] as BigNumber).is_zero())


func test_no_catches_when_per_second_is_zero():
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	net.catches_per_second = 0.0
	var summary := OfflineProgressSystem.compute(monsters, net, 1, 600.0, rng)
	assert_true(summary["catches_by_species"].is_empty())


func test_handles_null_net_gracefully():
	var rng := RandomNumberGenerator.new()
	var summary := OfflineProgressSystem.compute(monsters, null, 1, 60.0, rng)
	assert_eq(summary["seconds"], 0.0)
	assert_true(summary["catches_by_species"].is_empty())
