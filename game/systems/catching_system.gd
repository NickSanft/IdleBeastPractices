## Pure logic for the catch loop.
##
## No scene or autoload deps: callers pass the spawnable monster pool, the
## active net, and an RNG. Returns CatchOutcome dicts; the calling scene
## emits EventBus signals and mutates GameState.
##
## Multiplier hooks (UpgradeEffectsSystem in Phase 2) all default to 1.0 here.
class_name CatchingSystem
extends RefCounted


## Pick the next monster to spawn given the active tiers and net's targets.
## Weight per candidate = monster.spawn_weight * (1.0 / monster.tier) so
## lower tiers naturally appear more often unless explicitly weighted up.
##
## `pool` is the full set of monsters currently authorable. `state` provides
## current_max_tier; `net` constrains targets_tiers.
##
## Returns null if no candidate matches (e.g. wrong net for current tiers).
static func pick_spawn(
		pool: Array[MonsterResource],
		current_max_tier: int,
		net: NetResource,
		rng: RandomNumberGenerator) -> MonsterResource:
	var candidates: Array[MonsterResource] = []
	var weights: Array[float] = []
	var total: float = 0.0
	for m in pool:
		if m.tier > current_max_tier:
			continue
		if not net.targets_tiers.has(m.tier):
			continue
		var w: float = max(0.0001, m.spawn_weight) / float(max(1, m.tier))
		candidates.append(m)
		weights.append(w)
		total += w
	if candidates.is_empty():
		return null
	var r: float = rng.randf() * total
	var acc: float = 0.0
	for i in candidates.size():
		acc += weights[i]
		if r <= acc:
			return candidates[i]
	return candidates[candidates.size() - 1]


## Resolve a player tap on a monster. Returns the outcome dict:
##   {caught: bool, drop_item_id: StringName, drop_amount: int,
##    gold: BigNumber, is_shiny: bool, monster_id: StringName}
##
## tap_progress is mutated by the caller; this fn returns whether the catch
## fires this tap. The caller decides what to do with the outcome.
##
## tap_speed_mult / drop_amount_mult / gold_mult / shiny_rate_mult come
## from UpgradeEffectsSystem in Phase 2; default to 1.0.
static func resolve_tap(
		monster: MonsterResource,
		tap_progress_in: float,
		rng: RandomNumberGenerator,
		tap_speed_mult: float = 1.0,
		drop_amount_mult: float = 1.0,
		gold_mult: float = 1.0,
		shiny_rate_mult: float = 1.0) -> Dictionary:
	var tap_progress: float = tap_progress_in + 1.0 * tap_speed_mult
	if tap_progress < monster.base_catch_difficulty:
		return {
			"caught": false,
			"tap_progress": tap_progress,
		}
	# Caught.
	var drop_amount: int = rng.randi_range(monster.drop_amount_min, monster.drop_amount_max)
	drop_amount = max(1, int(round(float(drop_amount) * drop_amount_mult)))
	var gold: BigNumber = BigNumber.from_float(float(monster.gold_base) * gold_mult)
	var is_shiny: bool = rng.randf() < (monster.shiny_rate * shiny_rate_mult)
	return {
		"caught": true,
		"tap_progress": 0.0,
		"monster_id": monster.id,
		"drop_item_id": monster.drop_item.id if monster.drop_item != null else &"",
		"drop_amount": drop_amount,
		"gold": gold,
		"is_shiny": is_shiny,
	}


## Resolve a single auto-catch event. The caller is responsible for
## scheduling these via accumulated dt against net.catches_per_second.
## Returns the same outcome dict as resolve_tap but always with caught=true
## (auto-catches don't have a difficulty gate; that's the per-tap flavor).
static func resolve_auto(
		monster: MonsterResource,
		rng: RandomNumberGenerator,
		drop_amount_mult: float = 1.0,
		gold_mult: float = 1.0,
		shiny_rate_mult: float = 1.0) -> Dictionary:
	var drop_amount: int = rng.randi_range(monster.drop_amount_min, monster.drop_amount_max)
	drop_amount = max(1, int(round(float(drop_amount) * drop_amount_mult)))
	var gold: BigNumber = BigNumber.from_float(float(monster.gold_base) * gold_mult)
	var is_shiny: bool = rng.randf() < (monster.shiny_rate * shiny_rate_mult)
	return {
		"caught": true,
		"tap_progress": 0.0,
		"monster_id": monster.id,
		"drop_item_id": monster.drop_item.id if monster.drop_item != null else &"",
		"drop_amount": drop_amount,
		"gold": gold,
		"is_shiny": is_shiny,
	}


## Compute auto-catches from accumulated time. Returns the number of catches
## that should fire and the new accumulator value (for the caller to store).
static func auto_catch_count(
		accumulator_in: float,
		dt: float,
		catches_per_second: float,
		auto_speed_mult: float = 1.0) -> Dictionary:
	var per_second: float = catches_per_second * auto_speed_mult
	var acc: float = accumulator_in + dt * per_second
	var catches: int = int(floor(acc))
	return {
		"count": catches,
		"accumulator": acc - float(catches),
	}


## Pure check for tier completion. Returns:
##   {
##     is_complete:     bool,
##     tier:            int,
##     tier_species:    Array[StringName],   # all monsters in this tier
##     missing_species: Array[StringName],   # species in tier with zero catches
##     max_count:       int,                 # highest catches across species in tier
##   }
##
## A tier is considered complete when every species in it has been caught at
## least once AND any one species has reached `threshold` catches.
##
## monsters_caught is the GameState shape: {String -> {"normal": int, "shiny": int}}.
static func tier_completion_status(
		monster_pool: Array[MonsterResource],
		monsters_caught: Dictionary,
		catch_tier: int,
		threshold: int) -> Dictionary:
	var tier_species: Array[StringName] = []
	for m in monster_pool:
		if m.tier == catch_tier:
			tier_species.append(m.id)
	if tier_species.is_empty():
		return {
			"is_complete": false,
			"tier": catch_tier,
			"tier_species": [] as Array[StringName],
			"missing_species": [] as Array[StringName],
			"max_count": 0,
		}
	var missing: Array[StringName] = []
	var max_count: int = 0
	for sid in tier_species:
		var key: String = String(sid)
		if not monsters_caught.has(key):
			missing.append(sid)
			continue
		var entry: Dictionary = monsters_caught[key]
		var count: int = int(entry.get("normal", 0)) + int(entry.get("shiny", 0))
		max_count = max(max_count, count)
	var is_complete: bool = missing.is_empty() and max_count >= threshold
	return {
		"is_complete": is_complete,
		"tier": catch_tier,
		"tier_species": tier_species,
		"missing_species": missing,
		"max_count": max_count,
	}


## Returns the pet PetResources awarded when `catch_tier` completes — every
## monster in that tier with a non-null `pet` reference contributes one.
## Empty array if no monsters in that tier have pets.
static func pets_to_award_for_tier(
		monster_pool: Array[MonsterResource],
		catch_tier: int) -> Array[PetResource]:
	var out: Array[PetResource] = []
	for m in monster_pool:
		if m.tier != catch_tier:
			continue
		if m.pet == null:
			continue
		out.append(m.pet)
	return out
