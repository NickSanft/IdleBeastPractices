## Offline progress: given an elapsed window and the current spawnable pool,
## compute aggregate catches/items/gold without iterating per-catch.
##
## Caps elapsed at 1 hour (extendable via upgrade in Phase 2). Anti-cheat
## clock-back is handled upstream in TimeManager; this system just trusts
## the elapsed value it receives.
##
## Returns a summary suitable for the welcome-back dialog:
##   {
##     seconds:            float,
##     catches_by_species: Dictionary[StringName -> {normal, shiny}],
##     items_gained:       Dictionary[StringName -> int],
##     gold_gained:        BigNumber,
##     shinies_caught:     int,
##     capped:             bool,  # true if input elapsed exceeded the cap
##   }
class_name OfflineProgressSystem
extends RefCounted

const DEFAULT_CAP_SECONDS := 3600.0


static func compute(
		spawnable_pool: Array[MonsterResource],
		net: NetResource,
		current_max_tier: int,
		elapsed_seconds: float,
		rng: RandomNumberGenerator,
		offline_cap_mult: float = 1.0,
		auto_speed_mult: float = 1.0,
		drop_amount_mult: float = 1.0,
		gold_mult: float = 1.0,
		shiny_rate_mult: float = 1.0) -> Dictionary:
	var summary: Dictionary = {
		"seconds": 0.0,
		"catches_by_species": {},
		"items_gained": {},
		"gold_gained": BigNumber.zero(),
		"shinies_caught": 0,
		"capped": false,
	}
	if elapsed_seconds <= 0.0 or net == null:
		return summary
	var cap: float = DEFAULT_CAP_SECONDS * max(0.0, offline_cap_mult)
	var raw_elapsed: float = elapsed_seconds
	var elapsed: float = clampf(raw_elapsed, 0.0, cap)
	summary["seconds"] = elapsed
	summary["capped"] = raw_elapsed > cap
	var per_second: float = net.catches_per_second * auto_speed_mult
	if per_second <= 0.0:
		return summary
	var expected_catches: float = per_second * elapsed

	# Filter eligible monsters (active tier × net targets) and total spawn weight.
	var eligible: Array[MonsterResource] = []
	var weights: Array[float] = []
	var total_weight: float = 0.0
	for m in spawnable_pool:
		if m.tier > current_max_tier:
			continue
		if not net.targets_tiers.has(m.tier):
			continue
		var w: float = max(0.0001, m.spawn_weight) / float(max(1, m.tier))
		eligible.append(m)
		weights.append(w)
		total_weight += w
	if eligible.is_empty() or total_weight <= 0.0:
		return summary

	for i in eligible.size():
		var m: MonsterResource = eligible[i]
		var share: float = weights[i] / total_weight
		var expected_per_species: float = expected_catches * share
		if expected_per_species <= 0.0:
			continue
		var shiny_rate_eff: float = clampf(m.shiny_rate * shiny_rate_mult, 0.0, 1.0)
		var lambda: float = expected_per_species * shiny_rate_eff
		# Normal approximation to Poisson for shiny count.
		var shinies: int = 0
		if lambda > 0.0:
			var sampled: float = lambda + sqrt(lambda) * rng.randfn()
			shinies = max(0, int(round(sampled)))
			# Don't exceed total expected catches (defends against >100% rate edge cases).
			shinies = min(shinies, int(round(expected_per_species)))
		var normals: int = max(0, int(round(expected_per_species)) - shinies)

		summary["catches_by_species"][m.id] = {
			"normal": normals,
			"shiny": shinies,
		}

		var avg_drop: float = (float(m.drop_amount_min) + float(m.drop_amount_max)) * 0.5
		var per_catch_drop: float = avg_drop * drop_amount_mult
		var item_gain: int = int(round(per_catch_drop * float(normals + shinies)))
		if m.drop_item != null and item_gain > 0:
			var existing: int = int(summary["items_gained"].get(m.drop_item.id, 0))
			summary["items_gained"][m.drop_item.id] = existing + item_gain

		var per_catch_gold: float = float(m.gold_base) * gold_mult
		var gold_for_species: BigNumber = BigNumber.from_float(per_catch_gold * float(normals + shinies))
		summary["gold_gained"] = (summary["gold_gained"] as BigNumber).add(gold_for_species)

		summary["shinies_caught"] = int(summary["shinies_caught"]) + shinies

	return summary
