## Static dictionary mapping ability_id -> Callable.
##
## Each ability is a static function with signature:
##   fn(tick, caster, allies, enemies, rng) -> Array[Dictionary]
## where the return value is a list of frames produced by the ability
## and side-effects are applied directly to the combatant dicts.
##
## Phase 2 ships strike/shield/heal so the framework is exercised.
## Per-pet abilities are added as content in Phase 5+.
class_name AbilityRegistry
extends RefCounted

const STRIKE_DAMAGE_MULT := 1.5
const STRIKE_COOLDOWN := 4
const SHIELD_DEF_MAGNITUDE := 0.5
const SHIELD_DURATION := 8
const SHIELD_COOLDOWN := 12
const HEAL_FRACTION := 0.25
const HEAL_COOLDOWN := 16

# Phase 12d — five new abilities. Tunings chosen so each occupies a
# distinct role in team comps without any one dominating:
#   taunt   redirects enemy targeting to the caster for 5 ticks
#   rend    applies a 4-tick bleed; small per-tick but stacks badly
#   smite   2.5x burst on highest-HP enemy; long cooldown
#   cleanse strips bleed/burn from all allies
#   burst   0.6x AOE damage; medium cooldown
const TAUNT_DURATION := 5
const TAUNT_COOLDOWN := 10
const REND_DAMAGE_PER_TICK := 5
const REND_DURATION := 4
const REND_COOLDOWN := 8
const SMITE_DAMAGE_MULT := 2.5
const SMITE_COOLDOWN := 12
const CLEANSE_COOLDOWN := 14
const BURST_DAMAGE_MULT := 0.6
const BURST_COOLDOWN := 10

const DAMAGE_VARIANCE_MIN := 0.85
const DAMAGE_VARIANCE_MAX := 1.15


static func get_ability(ability_id: StringName) -> Callable:
	match ability_id:
		&"strike":
			return Callable(AbilityRegistry, "_ability_strike")
		&"shield":
			return Callable(AbilityRegistry, "_ability_shield")
		&"heal":
			return Callable(AbilityRegistry, "_ability_heal")
		&"taunt":
			return Callable(AbilityRegistry, "_ability_taunt")
		&"rend":
			return Callable(AbilityRegistry, "_ability_rend")
		&"smite":
			return Callable(AbilityRegistry, "_ability_smite")
		&"cleanse":
			return Callable(AbilityRegistry, "_ability_cleanse")
		&"burst":
			return Callable(AbilityRegistry, "_ability_burst")
		_:
			return Callable()


## Strike: 1.5× damage to lowest-HP enemy.
static func _ability_strike(
		tick: int,
		caster: Dictionary,
		_allies: Array,
		enemies: Array,
		rng: RandomNumberGenerator) -> Array[Dictionary]:
	var target: Dictionary = _pick_lowest_hp(enemies)
	if target.is_empty():
		return []
	var variance: float = rng.randf_range(DAMAGE_VARIANCE_MIN, DAMAGE_VARIANCE_MAX)
	var raw_damage: float = caster["atk"] * STRIKE_DAMAGE_MULT - _effective_def(target)
	var damage: int = int(max(1.0, raw_damage * variance))
	target["hp"] = max(0.0, float(target["hp"]) - float(damage))
	caster["ability_cooldown"] = STRIKE_COOLDOWN
	return [{
		"tick": tick,
		"actor": _id_for(caster),
		"target": _id_for(target),
		"action": "ability:strike",
		"damage": damage,
		"hp_remaining": int(target["hp"]),
		"status_changes": [],
	}]


## Shield: +50% def for 8 ticks on caster.
static func _ability_shield(
		tick: int,
		caster: Dictionary,
		_allies: Array,
		_enemies: Array,
		_rng: RandomNumberGenerator) -> Array[Dictionary]:
	var existing: Array = caster["status_effects"]
	existing.append({
		"type": "def_buff",
		"magnitude": SHIELD_DEF_MAGNITUDE,
		"ticks_remaining": SHIELD_DURATION,
	})
	caster["status_effects"] = existing
	caster["ability_cooldown"] = SHIELD_COOLDOWN
	return [{
		"tick": tick,
		"actor": _id_for(caster),
		"target": _id_for(caster),
		"action": "ability:shield",
		"damage": 0,
		"hp_remaining": int(caster["hp"]),
		"status_changes": ["def_buff_applied"],
	}]


## Heal: +25% max_hp on lowest-HP ally (including self).
static func _ability_heal(
		tick: int,
		caster: Dictionary,
		allies: Array,
		_enemies: Array,
		_rng: RandomNumberGenerator) -> Array[Dictionary]:
	var target: Dictionary = _pick_lowest_hp(allies)
	if target.is_empty():
		return []
	var heal_amount: int = int(round(float(target["max_hp"]) * HEAL_FRACTION))
	var new_hp: float = min(float(target["max_hp"]), float(target["hp"]) + float(heal_amount))
	target["hp"] = new_hp
	caster["ability_cooldown"] = HEAL_COOLDOWN
	return [{
		"tick": tick,
		"actor": _id_for(caster),
		"target": _id_for(target),
		"action": "ability:heal",
		"damage": -heal_amount,
		"hp_remaining": int(new_hp),
		"status_changes": [],
	}]


## Taunt: caster takes 5 ticks of `taunted` status. While taunted,
## enemies preferentially target the caster on basic attacks.
## BattleSystem._pick_lowest_hp + AbilityRegistry._pick_lowest_hp
## both honour the taunt by checking for taunted enemies first via
## the `pick_target_with_taunt` helper.
static func _ability_taunt(
		tick: int,
		caster: Dictionary,
		_allies: Array,
		_enemies: Array,
		_rng: RandomNumberGenerator) -> Array[Dictionary]:
	var existing: Array = caster["status_effects"]
	existing.append({
		"type": "taunted",
		"ticks_remaining": TAUNT_DURATION,
	})
	caster["status_effects"] = existing
	caster["ability_cooldown"] = TAUNT_COOLDOWN
	return [{
		"tick": tick,
		"actor": _id_for(caster),
		"target": _id_for(caster),
		"action": "ability:taunt",
		"damage": 0,
		"hp_remaining": int(caster["hp"]),
		"status_changes": ["taunted_applied"],
	}]


## Rend: apply a `bleed` DOT (5 dmg/tick × 4 ticks) to lowest-HP enemy.
## BattleSystem._tick_statuses applies the bleed damage on each tick.
static func _ability_rend(
		tick: int,
		caster: Dictionary,
		_allies: Array,
		enemies: Array,
		_rng: RandomNumberGenerator) -> Array[Dictionary]:
	var target: Dictionary = _pick_lowest_hp(enemies)
	if target.is_empty():
		return []
	var existing: Array = target["status_effects"]
	existing.append({
		"type": "bleed",
		"magnitude": REND_DAMAGE_PER_TICK,
		"ticks_remaining": REND_DURATION,
	})
	target["status_effects"] = existing
	caster["ability_cooldown"] = REND_COOLDOWN
	return [{
		"tick": tick,
		"actor": _id_for(caster),
		"target": _id_for(target),
		"action": "ability:rend",
		"damage": 0,
		"hp_remaining": int(target["hp"]),
		"status_changes": ["bleed_applied"],
	}]


## Smite: 2.5x damage on the HIGHEST-HP enemy. Inverted target
## selection vs strike so the ability has a different niche
## (focus-fire on the tankiest enemy rather than the squishiest).
static func _ability_smite(
		tick: int,
		caster: Dictionary,
		_allies: Array,
		enemies: Array,
		rng: RandomNumberGenerator) -> Array[Dictionary]:
	var target: Dictionary = _pick_highest_hp(enemies)
	if target.is_empty():
		return []
	var variance: float = rng.randf_range(DAMAGE_VARIANCE_MIN, DAMAGE_VARIANCE_MAX)
	var raw_damage: float = caster["atk"] * SMITE_DAMAGE_MULT - _effective_def(target)
	var damage: int = int(max(1.0, raw_damage * variance))
	target["hp"] = max(0.0, float(target["hp"]) - float(damage))
	caster["ability_cooldown"] = SMITE_COOLDOWN
	return [{
		"tick": tick,
		"actor": _id_for(caster),
		"target": _id_for(target),
		"action": "ability:smite",
		"damage": damage,
		"hp_remaining": int(target["hp"]),
		"status_changes": [],
	}]


## Cleanse: strip negative statuses (currently `bleed`) from all
## allies. Positive statuses (def_buff, taunted) survive.
static func _ability_cleanse(
		tick: int,
		caster: Dictionary,
		allies: Array,
		_enemies: Array,
		_rng: RandomNumberGenerator) -> Array[Dictionary]:
	var cleansed_count: int = 0
	for ally in allies:
		if not (ally is Dictionary):
			continue
		var kept: Array = []
		for s in ally.get("status_effects", []):
			if s is Dictionary and s.get("type", "") == "bleed":
				cleansed_count += 1
				continue
			kept.append(s)
		ally["status_effects"] = kept
	caster["ability_cooldown"] = CLEANSE_COOLDOWN
	return [{
		"tick": tick,
		"actor": _id_for(caster),
		"target": _id_for(caster),
		"action": "ability:cleanse",
		"damage": 0,
		"hp_remaining": int(caster["hp"]),
		"status_changes": ["cleansed_%d" % cleansed_count],
	}]


## Burst: 0.6x damage to ALL living enemies. AOE alternative to
## strike — lower per-target damage but wider coverage.
static func _ability_burst(
		tick: int,
		caster: Dictionary,
		_allies: Array,
		enemies: Array,
		rng: RandomNumberGenerator) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	for target in enemies:
		if not (target is Dictionary):
			continue
		if float(target["hp"]) <= 0.0:
			continue
		var variance: float = rng.randf_range(DAMAGE_VARIANCE_MIN, DAMAGE_VARIANCE_MAX)
		var raw_damage: float = caster["atk"] * BURST_DAMAGE_MULT - _effective_def(target)
		var damage: int = int(max(1.0, raw_damage * variance))
		target["hp"] = max(0.0, float(target["hp"]) - float(damage))
		frames.append({
			"tick": tick,
			"actor": _id_for(caster),
			"target": _id_for(target),
			"action": "ability:burst",
			"damage": damage,
			"hp_remaining": int(target["hp"]),
			"status_changes": [],
		})
	caster["ability_cooldown"] = BURST_COOLDOWN
	return frames


## Phase 12d helper: select an attack target while respecting taunt.
## If any enemy carries the `taunted` status, prefer them (lowest-HP
## taunted target). Otherwise fall back to plain lowest-HP. Used by
## both BattleSystem._act and any future ability that picks targets.
static func pick_target_with_taunt(enemies: Array) -> Dictionary:
	var taunted_targets: Array = []
	for c in enemies:
		if not (c is Dictionary):
			continue
		if float(c["hp"]) <= 0.0:
			continue
		for s in c.get("status_effects", []):
			if s is Dictionary and s.get("type", "") == "taunted":
				taunted_targets.append(c)
				break
	if not taunted_targets.is_empty():
		return _pick_lowest_hp(taunted_targets)
	return _pick_lowest_hp(enemies)


# region — internals

static func _pick_lowest_hp(combatants: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_hp: float = INF
	for c in combatants:
		if not (c is Dictionary):
			continue
		if float(c["hp"]) <= 0.0:
			continue
		if float(c["hp"]) < best_hp:
			best = c
			best_hp = float(c["hp"])
	return best


static func _pick_highest_hp(combatants: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_hp: float = -INF
	for c in combatants:
		if not (c is Dictionary):
			continue
		if float(c["hp"]) <= 0.0:
			continue
		if float(c["hp"]) > best_hp:
			best = c
			best_hp = float(c["hp"])
	return best


static func _effective_def(combatant: Dictionary) -> float:
	var base: float = float(combatant["def"])
	var bonus: float = 0.0
	for s in combatant.get("status_effects", []):
		if s is Dictionary and s.get("type", "") == "def_buff":
			bonus += base * float(s.get("magnitude", 0.0))
	return base + bonus


static func _id_for(combatant: Dictionary) -> String:
	return "%s_%d" % [combatant.get("team", "?"), int(combatant.get("index", -1))]

# endregion
