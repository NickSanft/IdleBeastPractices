## Save format migration registry.
##
## Each entry is {from: int, fn: Callable}. fn takes a Dictionary
## of save data at version `from` and returns a Dictionary at version `from + 1`.
##
## Loading runs every applicable migration in order, advancing `version` each time,
## until the data reaches CURRENT_VERSION. Adding a new format version means:
##   1. Bump CURRENT_VERSION in save_manager.gd
##   2. Append a migration here from (new - 1) -> new
##   3. Add a fixture-based test in test_save_migration.gd
class_name SaveMigrations
extends RefCounted


static func migrations() -> Array[Dictionary]:
	return [
		{"from": 0, "fn": Callable(SaveMigrations, "_migrate_v0_to_v1")},
	]


## Existing legacy v0 saves (none in the wild — fixture-only) get an empty
## scaffold filled in.
static func _migrate_v0_to_v1(data: Dictionary) -> Dictionary:
	var out := data.duplicate(true)
	out["version"] = 1
	# Ensure all v1 top-level keys exist with safe defaults.
	out.merge({
		"last_saved_unix": 0,
		"session_id": "",
		"currencies": {},
		"inventory": {},
		"monsters_caught": {},
		"pets_owned": [],
		"pet_variants_owned": [],
		"nets_owned": [],
		"active_net": "",
		"upgrades_purchased": [],
		"current_max_tier": 1,
		"tiers_completed": [],
		"current_battle": null,
		"prestige_count": 0,
		"ledger": {
			"total_catches": 0,
			"total_taps": 0,
			"total_shinies": 0,
			"session_count": 0,
			"total_play_seconds": 0,
			"total_offline_seconds_credited": 0,
			"prestige_count": 0,
			"first_launch_unix": 0,
			"peniber_quotes_seen": 0,
		},
		"narrator_state": {
			"lines_seen": {},
			"last_line_unix": 0,
		},
	}, false)  # `false` = do not overwrite existing keys
	return out


## Apply every migration whose `from` is >= the data's current version,
## advancing version one step at a time.
static func apply_chain(data: Dictionary, target_version: int) -> Dictionary:
	var current := data.duplicate(true)
	var current_version: int = int(current.get("version", 0))
	while current_version < target_version:
		var step: Dictionary = _find_migration_from(current_version)
		if step.is_empty():
			push_error("SaveMigrations: no migration registered from version %d" % current_version)
			break
		var fn: Callable = step["fn"]
		current = fn.call(current)
		var new_version: int = int(current.get("version", current_version))
		if new_version <= current_version:
			push_error("SaveMigrations: migration from %d did not advance version" % current_version)
			break
		current_version = new_version
	return current


static func _find_migration_from(from_version: int) -> Dictionary:
	for m in migrations():
		if int(m.get("from", -1)) == from_version:
			return m
	return {}
