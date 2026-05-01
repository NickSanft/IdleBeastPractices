## Prestige math.
##
## Pure helpers for computing RP gain and filtering which upgrades survive a
## prestige reset. The actual state mutation lives in GameState.perform_prestige
## so the autoload remains the source of truth for save/load.
class_name PrestigeSystem
extends RefCounted

const RP_DIVISOR := 1.0e6   # 1 RP per √(1M gold) earned this run.


## Compute Rancher Points awarded by a prestige right now.
##
## RP = floor( sqrt( total_gold_earned_this_run / 1e6 ) × rp_mult )
##
## Examples (rp_mult = 1.0):
##   1M gold        → 1 RP
##   4M gold        → 2 RP
##   100M gold      → 10 RP
##   10B gold       → 100 RP
##
## Below 1M earned this run, returns 0; the player gates themselves into
## prestige economy by accumulating to threshold.
static func compute_rp_gain(gold_earned_dict: Dictionary, rp_mult: float = 1.0) -> int:
	var earned: BigNumber = BigNumber.from_dict(gold_earned_dict)
	if earned.is_zero() or earned.lt(BigNumber.from_float(RP_DIVISOR)):
		return 0
	# divisor = 1e6
	var divisor: BigNumber = BigNumber.from_float(RP_DIVISOR)
	var ratio_bn: BigNumber = earned.divide(divisor)
	var ratio: float = ratio_bn.to_float()
	if ratio <= 0.0 or is_inf(ratio) or is_nan(ratio):
		return 0
	var rp: float = floor(sqrt(ratio) * rp_mult)
	return max(0, int(rp))


## Returns the upgrades_purchased entries that survive a prestige reset
## (those whose UpgradeResource.persists_through_prestige is true).
##
## upgrades_purchased: Array of {"id": StringName, "level": int} (GameState shape).
## upgrade_index: Dictionary[StringName -> UpgradeResource] (e.g. ContentRegistry.upgrade_index()).
static func filter_persistent_upgrades(
		upgrades_purchased: Array,
		upgrade_index: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in upgrades_purchased:
		if not (entry is Dictionary):
			continue
		var id_value: Variant = entry.get("id")
		if id_value == null:
			continue
		var upgrade: UpgradeResource = upgrade_index.get(StringName(id_value))
		if upgrade == null:
			continue
		if upgrade.persists_through_prestige:
			out.append((entry as Dictionary).duplicate(true))
	return out
