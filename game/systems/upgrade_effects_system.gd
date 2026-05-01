## Aggregates active upgrade effects into per-effect_id multipliers.
##
## Composition rules:
##   additive_effects:        multiplier = 1.0 + sum(magnitude × level)
##   multiplicative_effects:  multiplier = product over each upgrade of (1 + magnitude)^level
##
## Final value clamped to [1.0, 1e9] so upstream BigNumber math stays sane.
class_name UpgradeEffectsSystem
extends RefCounted

const ADDITIVE_EFFECTS: Array[StringName] = [
	&"tap_speed",
	&"auto_speed",
	&"shiny_rate",
]

const MULTIPLICATIVE_EFFECTS: Array[StringName] = [
	&"gold_mult",
	&"drop_amount",
	&"rp_mult",
	&"offline_cap",
]

const CLAMP_MIN := 1.0
const CLAMP_MAX := 1.0e9


## Compute the multiplier for `effect_id` from the player's owned upgrades.
##
## owned_upgrades is the GameState.upgrades_purchased shape:
##   Array of {"id": StringName, "level": int}
## upgrade_index is a Dictionary[StringName -> UpgradeResource] (e.g. from
## ContentRegistry).
static func get_multiplier(
		effect_id: StringName,
		owned_upgrades: Array,
		upgrade_index: Dictionary) -> float:
	var is_additive: bool = ADDITIVE_EFFECTS.has(effect_id)
	var is_multiplicative: bool = MULTIPLICATIVE_EFFECTS.has(effect_id)
	if not is_additive and not is_multiplicative:
		return 1.0
	var additive_sum: float = 0.0
	var multiplicative_product: float = 1.0
	for entry in owned_upgrades:
		if not (entry is Dictionary):
			continue
		var id_value: Variant = entry.get("id")
		if id_value == null:
			continue
		var upgrade: UpgradeResource = upgrade_index.get(StringName(id_value))
		if upgrade == null:
			continue
		if upgrade.effect_id != effect_id:
			continue
		var level: int = int(entry.get("level", 0))
		if level <= 0:
			continue
		if is_additive:
			additive_sum += upgrade.magnitude * float(level)
		else:
			multiplicative_product *= pow(1.0 + upgrade.magnitude, float(level))
	var raw: float
	if is_additive:
		raw = 1.0 + additive_sum
	else:
		raw = multiplicative_product
	return clampf(raw, CLAMP_MIN, CLAMP_MAX)


## Compute the cost of the next level of `upgrade` given the current level.
## cost(L) = base_cost × cost_growth^L  (so first purchase is at base_cost).
static func cost_for_next_level(upgrade: UpgradeResource, current_level: int) -> BigNumber:
	if current_level >= upgrade.max_level:
		return BigNumber.zero()
	var base := BigNumber.from_dict(upgrade.cost)
	if current_level <= 0:
		return base
	var growth_factor: float = pow(upgrade.cost_growth, float(current_level))
	return base.multiply_float(growth_factor)
