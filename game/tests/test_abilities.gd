## Phase 12d — coverage for the 5 new abilities + status effects.
##
## Each ability gets a focused test that verifies the combatant
## state mutation matches the design intent. Determinism stays
## intact: same RNG seed → byte-identical frame output.
extends GutTest

const _AR := preload("res://game/systems/ability_registry.gd")
const _BS := preload("res://game/systems/battle_system.gd")


func _make_combatant(team: String, idx: int, atk: float = 10.0, hp: float = 100.0, max_hp: float = 100.0, ddef: float = 0.0) -> Dictionary:
	return {
		"team": team,
		"index": idx,
		"id": "test_%d" % idx,
		"hp": hp,
		"max_hp": max_hp,
		"atk": atk,
		"def": ddef,
		"ability_id": StringName(""),
		"ability_cooldown": 0,
		"status_effects": [],
	}


func _rng(seed_: int = 42) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_
	return r


# ============= Taunt =============

func test_taunt_applies_status() -> void:
	var caster := _make_combatant("player", 0)
	var frames: Array[Dictionary] = _AR._ability_taunt(0, caster, [], [], _rng())
	assert_eq(frames.size(), 1)
	assert_eq(frames[0]["action"], "ability:taunt")
	assert_eq(caster["status_effects"].size(), 1)
	assert_eq(caster["status_effects"][0]["type"], "taunted")


func test_taunt_redirects_targeting() -> void:
	# Two enemies. Taunt one, verify pick_target_with_taunt selects
	# the taunted target even though it's not the lowest-HP option.
	var bystander := _make_combatant("enemy", 0, 5.0, 50.0)
	var taunter := _make_combatant("enemy", 1, 5.0, 100.0)
	taunter["status_effects"].append({"type": "taunted", "ticks_remaining": 5})
	var picked: Dictionary = _AR.pick_target_with_taunt([bystander, taunter])
	assert_eq(int(picked["index"]), 1, "taunted enemy must be picked even at higher HP")


func test_pick_target_falls_back_to_lowest_hp_without_taunt() -> void:
	var low := _make_combatant("enemy", 0, 5.0, 30.0)
	var high := _make_combatant("enemy", 1, 5.0, 100.0)
	var picked: Dictionary = _AR.pick_target_with_taunt([high, low])
	assert_eq(int(picked["index"]), 0, "no taunt → pick lowest HP")


# ============= Rend (bleed DOT) =============

func test_rend_applies_bleed_status() -> void:
	var caster := _make_combatant("player", 0)
	var target := _make_combatant("enemy", 0)
	_AR._ability_rend(0, caster, [], [target], _rng())
	assert_eq(target["status_effects"].size(), 1)
	assert_eq(target["status_effects"][0]["type"], "bleed")
	assert_eq(int(target["status_effects"][0]["ticks_remaining"]), _AR.REND_DURATION)


func test_bleed_deals_damage_each_tick() -> void:
	# Apply bleed manually, then tick statuses 4 times. Total damage
	# should equal REND_DAMAGE_PER_TICK * REND_DURATION.
	var target := _make_combatant("enemy", 0, 5.0, 100.0)
	target["status_effects"].append({
		"type": "bleed",
		"magnitude": _AR.REND_DAMAGE_PER_TICK,
		"ticks_remaining": _AR.REND_DURATION,
	})
	var team: Array = [target]
	var initial_hp: float = float(target["hp"])
	for i in _AR.REND_DURATION:
		_BS._tick_statuses(team)
	var expected_total: int = _AR.REND_DAMAGE_PER_TICK * _AR.REND_DURATION
	var actual_loss: int = int(initial_hp - float(target["hp"]))
	assert_eq(actual_loss, expected_total,
			"4 ticks of bleed at 5/tick should deal 20 total damage")
	# bleed should have expired after REND_DURATION ticks.
	assert_eq(target["status_effects"].size(), 0,
			"bleed must drop off after duration elapses")


# ============= Smite =============

func test_smite_picks_highest_hp_enemy() -> void:
	var caster := _make_combatant("player", 0, 20.0)
	var low := _make_combatant("enemy", 0, 5.0, 30.0)
	var high := _make_combatant("enemy", 1, 5.0, 100.0)
	var frames: Array[Dictionary] = _AR._ability_smite(0, caster, [], [high, low], _rng())
	assert_eq(frames.size(), 1)
	assert_eq(frames[0]["target"], "enemy_1",
			"smite must hit the highest-HP enemy, not the lowest")


func test_smite_damage_uses_2_5x_multiplier() -> void:
	# With caster.atk=10, target.def=0, variance=1.0, expected damage
	# is 25. Variance is RNG so we just bound-check.
	var caster := _make_combatant("player", 0, 10.0)
	var target := _make_combatant("enemy", 0, 5.0, 100.0)
	_AR._ability_smite(0, caster, [], [target], _rng())
	var damage_taken: float = 100.0 - float(target["hp"])
	# 10 * 2.5 = 25 expected. With variance [0.85..1.15], range is ~[21..29].
	assert_gt(damage_taken, 19.0)
	assert_lt(damage_taken, 31.0)


# ============= Cleanse =============

func test_cleanse_strips_bleed_from_allies() -> void:
	var caster := _make_combatant("player", 0)
	var ally1 := _make_combatant("player", 1)
	var ally2 := _make_combatant("player", 2)
	ally1["status_effects"].append({"type": "bleed", "magnitude": 5, "ticks_remaining": 3})
	ally2["status_effects"].append({"type": "bleed", "magnitude": 5, "ticks_remaining": 2})
	# Add a positive status that should NOT be cleansed.
	ally1["status_effects"].append({"type": "def_buff", "magnitude": 0.5, "ticks_remaining": 4})
	_AR._ability_cleanse(0, caster, [caster, ally1, ally2], [], _rng())
	# Bleeds gone, def_buff retained.
	assert_eq(ally1["status_effects"].size(), 1)
	assert_eq(ally1["status_effects"][0]["type"], "def_buff")
	assert_eq(ally2["status_effects"].size(), 0)


# ============= Burst =============

func test_burst_damages_all_living_enemies() -> void:
	var caster := _make_combatant("player", 0, 20.0)
	var e1 := _make_combatant("enemy", 0, 5.0, 100.0)
	var e2 := _make_combatant("enemy", 1, 5.0, 100.0)
	var dead := _make_combatant("enemy", 2, 5.0, 0.0, 100.0)   # already dead
	var frames: Array[Dictionary] = _AR._ability_burst(0, caster, [], [e1, e2, dead], _rng())
	# Should hit only living enemies (2 frames, not 3).
	assert_eq(frames.size(), 2)
	assert_lt(float(e1["hp"]), 100.0)
	assert_lt(float(e2["hp"]), 100.0)
	assert_eq(float(dead["hp"]), 0.0,
			"burst must not damage already-dead enemies")


# ============= Determinism =============

func test_smite_deterministic_with_same_seed() -> void:
	# Same seed, same caster/target → byte-identical frame output.
	var c1 := _make_combatant("player", 0, 10.0)
	var t1 := _make_combatant("enemy", 0, 5.0, 100.0)
	var f1: Array[Dictionary] = _AR._ability_smite(0, c1, [], [t1], _rng(123))

	var c2 := _make_combatant("player", 0, 10.0)
	var t2 := _make_combatant("enemy", 0, 5.0, 100.0)
	var f2: Array[Dictionary] = _AR._ability_smite(0, c2, [], [t2], _rng(123))
	assert_eq(int(f1[0]["damage"]), int(f2[0]["damage"]),
			"same seed → same damage roll")


func test_burst_deterministic_with_same_seed() -> void:
	var c1 := _make_combatant("player", 0, 10.0)
	var enemies1: Array = [
		_make_combatant("enemy", 0, 5.0, 100.0),
		_make_combatant("enemy", 1, 5.0, 100.0),
	]
	var f1: Array[Dictionary] = _AR._ability_burst(0, c1, [], enemies1, _rng(456))

	var c2 := _make_combatant("player", 0, 10.0)
	var enemies2: Array = [
		_make_combatant("enemy", 0, 5.0, 100.0),
		_make_combatant("enemy", 1, 5.0, 100.0),
	]
	var f2: Array[Dictionary] = _AR._ability_burst(0, c2, [], enemies2, _rng(456))
	assert_eq(f1.size(), f2.size())
	for i in f1.size():
		assert_eq(int(f1[i]["damage"]), int(f2[i]["damage"]))
