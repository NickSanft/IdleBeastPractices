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
