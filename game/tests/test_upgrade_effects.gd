extends GutTest


func _make_upgrade(id: StringName, effect: StringName, magnitude: float, max_level: int = 5) -> UpgradeResource:
	var u := UpgradeResource.new()
	u.id = id
	u.effect_id = effect
	u.magnitude = magnitude
	u.max_level = max_level
	u.cost = {"m": 1.0, "e": 0}
	u.cost_growth = 1.5
	return u


func test_unknown_effect_returns_one():
	var index: Dictionary = {}
	var owned: Array = []
	assert_eq(UpgradeEffectsSystem.get_multiplier(&"definitely_not_a_real_effect", owned, index), 1.0)


func test_additive_no_upgrades_returns_one():
	var index: Dictionary = {}
	var owned: Array = []
	assert_eq(UpgradeEffectsSystem.get_multiplier(&"tap_speed", owned, index), 1.0)


func test_additive_one_level():
	var u := _make_upgrade(&"u1", &"tap_speed", 0.2)
	var index: Dictionary = {&"u1": u}
	var owned: Array = [{"id": &"u1", "level": 1}]
	# 1.0 + 0.2 * 1 = 1.2
	assert_almost_eq(UpgradeEffectsSystem.get_multiplier(&"tap_speed", owned, index), 1.2, 1.0e-6)


func test_additive_multi_level():
	var u := _make_upgrade(&"u1", &"tap_speed", 0.2)
	var index: Dictionary = {&"u1": u}
	var owned: Array = [{"id": &"u1", "level": 3}]
	# 1.0 + 0.2 * 3 = 1.6
	assert_almost_eq(UpgradeEffectsSystem.get_multiplier(&"tap_speed", owned, index), 1.6, 1.0e-6)


func test_multiplicative_one_level():
	var u := _make_upgrade(&"u1", &"gold_mult", 0.25)
	var index: Dictionary = {&"u1": u}
	var owned: Array = [{"id": &"u1", "level": 1}]
	# (1 + 0.25)^1 = 1.25
	assert_almost_eq(UpgradeEffectsSystem.get_multiplier(&"gold_mult", owned, index), 1.25, 1.0e-6)


func test_multiplicative_compounds_per_level():
	var u := _make_upgrade(&"u1", &"gold_mult", 0.25)
	var index: Dictionary = {&"u1": u}
	var owned: Array = [{"id": &"u1", "level": 3}]
	# 1.25^3 = 1.953125
	assert_almost_eq(UpgradeEffectsSystem.get_multiplier(&"gold_mult", owned, index), 1.953125, 1.0e-6)


func test_multiple_upgrades_for_same_effect_compose():
	var u1 := _make_upgrade(&"u1", &"gold_mult", 0.25)
	var u2 := _make_upgrade(&"u2", &"gold_mult", 0.10)
	var index: Dictionary = {&"u1": u1, &"u2": u2}
	var owned: Array = [
		{"id": &"u1", "level": 1},
		{"id": &"u2", "level": 2},
	]
	# 1.25 * 1.10^2 = 1.25 * 1.21 = 1.5125
	assert_almost_eq(UpgradeEffectsSystem.get_multiplier(&"gold_mult", owned, index), 1.5125, 1.0e-6)


func test_zero_level_upgrade_ignored():
	var u := _make_upgrade(&"u1", &"tap_speed", 0.5)
	var index: Dictionary = {&"u1": u}
	var owned: Array = [{"id": &"u1", "level": 0}]
	assert_eq(UpgradeEffectsSystem.get_multiplier(&"tap_speed", owned, index), 1.0)


func test_clamp_max():
	# Force absurd magnitude × level. Should clamp to 1e9.
	var u := _make_upgrade(&"u1", &"gold_mult", 9.0, 1000)
	var index: Dictionary = {&"u1": u}
	var owned: Array = [{"id": &"u1", "level": 100}]
	var m := UpgradeEffectsSystem.get_multiplier(&"gold_mult", owned, index)
	assert_eq(m, 1.0e9)


func test_cost_for_next_level_at_zero():
	var u := _make_upgrade(&"u1", &"gold_mult", 0.25)
	u.cost = {"m": 1.0, "e": 2}  # 100
	var c := UpgradeEffectsSystem.cost_for_next_level(u, 0)
	assert_almost_eq(c.to_float(), 100.0, 1.0e-6)


func test_cost_for_next_level_grows():
	var u := _make_upgrade(&"u1", &"gold_mult", 0.25)
	u.cost = {"m": 1.0, "e": 2}  # 100
	u.cost_growth = 2.0
	# Level 2 -> 100 * 2^2 = 400
	var c := UpgradeEffectsSystem.cost_for_next_level(u, 2)
	assert_almost_eq(c.to_float(), 400.0, 1.0e-6)


func test_cost_at_max_level_is_zero():
	var u := _make_upgrade(&"u1", &"gold_mult", 0.25, 3)
	var c := UpgradeEffectsSystem.cost_for_next_level(u, 3)
	assert_true(c.is_zero())
