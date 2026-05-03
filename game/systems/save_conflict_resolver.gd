## Pure-function merge of two save dictionaries (e.g. local + cloud).
##
## Phase 7a ships this as scaffolding — Phase 7b will wire a real
## CloudSyncBackend that calls `resolve()` after pulling from cloud.
##
## Merge philosophy: take the **newer** save (higher `last_saved_unix`)
## as the base for "where the player is right now" (gold, inventory,
## active net, current battle, upgrades, etc.) and union/max in monotonic
## accumulating fields from BOTH saves so offline play on either device
## never loses ledger stats, pets, or bestiary entries.
##
## Field rules:
##   pets_owned, pet_variants_owned, recipes_crafted, nets_owned: UNION
##   monsters_caught: per-species per-{normal,shiny} MAX
##   ledger:          per-key MAX (monotonic counters), except
##                    first_launch_unix = MIN (earliest start wins)
##   narrator_state.lines_seen: per-line-id MAX
##   prestige_count, current_max_tier: MAX
##   version: MAX
##   last_saved_unix: MAX
##   currencies, total_gold_earned_this_run, inventory, active_net,
##   upgrades_purchased, tiers_completed, current_battle, session_id:
##                    take from NEWER save (last-write-wins by timestamp)
##
## The resolver is pure (no GameState / SaveManager dependencies) so it's
## fully testable in isolation. Pass two dicts as produced by
## `GameState.to_dict()`; receive a merged dict suitable for
## `GameState.from_dict()`.
class_name SaveConflictResolver


## Returns a merged save dict. If either input is empty, returns a deep
## copy of the other. Both inputs are treated as immutable — the result
## is a fresh allocation.
static func resolve(local: Dictionary, remote: Dictionary) -> Dictionary:
	if local.is_empty():
		return remote.duplicate(true)
	if remote.is_empty():
		return local.duplicate(true)

	var local_ts: int = int(local.get("last_saved_unix", 0))
	var remote_ts: int = int(remote.get("last_saved_unix", 0))
	# Tie -> prefer remote so two pristine devices reach the same fixpoint
	# regardless of which one resolves the conflict locally.
	var newer: Dictionary = remote if remote_ts >= local_ts else local

	# Start from a deep copy of the newer save so non-monotonic fields
	# (gold, inventory, active_net, etc.) inherit its values.
	var result: Dictionary = newer.duplicate(true)

	# Schema / identity
	result["version"] = max(int(local.get("version", 0)), int(remote.get("version", 0)))
	result["last_saved_unix"] = max(local_ts, remote_ts)

	# Monotonic accumulating fields — union/max so neither device loses
	# progress when offline-divergent saves merge.
	result["pets_owned"] = _union_strings(local.get("pets_owned", []), remote.get("pets_owned", []))
	result["pet_variants_owned"] = _union_strings(local.get("pet_variants_owned", []), remote.get("pet_variants_owned", []))
	result["recipes_crafted"] = _union_strings(local.get("recipes_crafted", []), remote.get("recipes_crafted", []))
	# nets_owned can technically reset via prestige in this codebase, but
	# the bought-net inventory is so cheap to re-buy that union (preserve
	# anything ever owned) is safer than dropping a net.
	result["nets_owned"] = _union_strings(local.get("nets_owned", []), remote.get("nets_owned", []))
	result["monsters_caught"] = _merge_bestiary(local.get("monsters_caught", {}), remote.get("monsters_caught", {}))
	result["ledger"] = _merge_ledger(local.get("ledger", {}), remote.get("ledger", {}))
	result["narrator_state"] = _merge_narrator_state(local.get("narrator_state", {}), remote.get("narrator_state", {}))
	result["prestige_count"] = max(int(local.get("prestige_count", 0)), int(remote.get("prestige_count", 0)))
	result["current_max_tier"] = max(int(local.get("current_max_tier", 1)), int(remote.get("current_max_tier", 1)))

	return result


static func _union_strings(a: Variant, b: Variant) -> Array:
	var seen: Dictionary = {}
	for s in a:
		seen[String(s)] = true
	for s in b:
		seen[String(s)] = true
	var out: Array = seen.keys()
	out.sort()
	return out


static func _merge_bestiary(a: Dictionary, b: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var keys: Dictionary = {}
	for k in a.keys():
		keys[k] = true
	for k in b.keys():
		keys[k] = true
	for k in keys.keys():
		var ae: Dictionary = a.get(k, {}) if a.get(k) is Dictionary else {}
		var be: Dictionary = b.get(k, {}) if b.get(k) is Dictionary else {}
		result[k] = {
			"normal": max(int(ae.get("normal", 0)), int(be.get("normal", 0))),
			"shiny": max(int(ae.get("shiny", 0)), int(be.get("shiny", 0))),
		}
	return result


static func _merge_ledger(a: Dictionary, b: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var keys: Dictionary = {}
	for k in a.keys():
		keys[k] = true
	for k in b.keys():
		keys[k] = true
	for k in keys.keys():
		if k == "first_launch_unix":
			# Take the earliest non-zero first-launch timestamp so the
			# player's "Days played: 47" stat preserves their oldest
			# device's start date even after a fresh install elsewhere.
			var av: int = int(a.get(k, 0))
			var bv: int = int(b.get(k, 0))
			if av == 0:
				result[k] = bv
			elif bv == 0:
				result[k] = av
			else:
				result[k] = mini(av, bv)
		else:
			result[k] = max(int(a.get(k, 0)), int(b.get(k, 0)))
	return result


static func _merge_narrator_state(a: Dictionary, b: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	result["last_line_unix"] = max(
			int(a.get("last_line_unix", 0)),
			int(b.get("last_line_unix", 0)))
	var a_lines: Dictionary = a.get("lines_seen", {})
	var b_lines: Dictionary = b.get("lines_seen", {})
	var lines: Dictionary = {}
	var keys: Dictionary = {}
	for k in a_lines.keys():
		keys[k] = true
	for k in b_lines.keys():
		keys[k] = true
	for k in keys.keys():
		lines[String(k)] = max(int(a_lines.get(k, 0)), int(b_lines.get(k, 0)))
	result["lines_seen"] = lines
	return result
