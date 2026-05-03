## Tests for SaveConflictResolver.resolve(local, remote).
##
## Covers each field's merge rule documented in save_conflict_resolver.gd.
## Resolver is pure / static, no autoload state to set up.
extends GutTest


func test_empty_local_returns_remote() -> void:
	var remote := {"last_saved_unix": 1000, "version": 2, "pets_owned": ["a"]}
	var merged := SaveConflictResolver.resolve({}, remote)
	assert_eq(merged["last_saved_unix"], 1000)
	assert_eq(merged["pets_owned"], ["a"])


func test_empty_remote_returns_local() -> void:
	var local := {"last_saved_unix": 1000, "version": 2, "pets_owned": ["a"]}
	var merged := SaveConflictResolver.resolve(local, {})
	assert_eq(merged["last_saved_unix"], 1000)


func test_both_empty_returns_empty() -> void:
	assert_eq(SaveConflictResolver.resolve({}, {}), {})


func test_newer_save_wins_for_non_monotonic_fields() -> void:
	# Inventory, gold, active_net, current_battle should come from whichever
	# save has the higher last_saved_unix.
	var older := {
		"last_saved_unix": 1000,
		"currencies": {"gold": {"m": 5.0, "e": 0}, "rancher_points": 0},
		"inventory": {"wisplet_ectoplasm": 50},
		"active_net": "basic_net",
		"current_battle": null,
	}
	var newer := {
		"last_saved_unix": 2000,
		"currencies": {"gold": {"m": 1.0, "e": 6}, "rancher_points": 5},
		"inventory": {"centiphantom_jelly": 20},
		"active_net": "wraith_net",
		"current_battle": {"seed": "abc"},
	}
	var merged := SaveConflictResolver.resolve(older, newer)
	assert_eq(merged["currencies"], newer["currencies"])
	assert_eq(merged["inventory"], newer["inventory"])
	assert_eq(merged["active_net"], "wraith_net")
	assert_eq(merged["current_battle"], {"seed": "abc"})
	# last_saved_unix is the max, version is the max
	assert_eq(merged["last_saved_unix"], 2000)


func test_pets_owned_unioned_across_saves() -> void:
	# Player owned pet A on phone X (older save), pet B on phone Y (newer
	# save, after divergent offline play). Merge should preserve both.
	var older := {
		"last_saved_unix": 1000,
		"pets_owned": ["green_wisplet_pet", "red_wisplet_pet"],
		"pet_variants_owned": [],
	}
	var newer := {
		"last_saved_unix": 2000,
		"pets_owned": ["green_wisplet_pet", "centiphantom_pet"],
		"pet_variants_owned": ["green_wisplet_pet_variant"],
	}
	var merged := SaveConflictResolver.resolve(older, newer)
	# All three pets present, sorted, no duplicates.
	assert_eq(merged["pets_owned"], [
		"centiphantom_pet", "green_wisplet_pet", "red_wisplet_pet",
	])
	assert_eq(merged["pet_variants_owned"], ["green_wisplet_pet_variant"])


func test_monsters_caught_per_species_max() -> void:
	# Bestiary entries are monotonic; merge takes max per (species, type).
	var older := {
		"last_saved_unix": 1000,
		"monsters_caught": {
			"green_wisplet": {"normal": 100, "shiny": 5},
			"red_wisplet": {"normal": 30, "shiny": 0},
		},
	}
	var newer := {
		"last_saved_unix": 2000,
		"monsters_caught": {
			"green_wisplet": {"normal": 80, "shiny": 7},
			"centiphantom": {"normal": 12, "shiny": 0},
		},
	}
	var merged := SaveConflictResolver.resolve(older, newer)
	var bestiary: Dictionary = merged["monsters_caught"]
	# green_wisplet: max(100, 80)=100 normal, max(5, 7)=7 shiny
	assert_eq(bestiary["green_wisplet"], {"normal": 100, "shiny": 7})
	# red_wisplet only in older: kept
	assert_eq(bestiary["red_wisplet"], {"normal": 30, "shiny": 0})
	# centiphantom only in newer: kept
	assert_eq(bestiary["centiphantom"], {"normal": 12, "shiny": 0})


func test_ledger_takes_max_per_counter() -> void:
	# Ledger counters are monotonic. Two devices played offline; whichever
	# played MORE on each axis is the "true" total.
	var older := {
		"last_saved_unix": 1000,
		"ledger": {
			"total_catches": 1000,
			"total_taps": 5000,
			"total_shinies": 12,
			"first_launch_unix": 1700000000,
		},
	}
	var newer := {
		"last_saved_unix": 2000,
		"ledger": {
			"total_catches": 800,        # phone B caught fewer
			"total_taps": 7500,           # but tapped more
			"total_shinies": 14,          # and got more shinies
			"first_launch_unix": 1710000000,  # later first launch
		},
	}
	var merged := SaveConflictResolver.resolve(older, newer)
	var ledger: Dictionary = merged["ledger"]
	assert_eq(ledger["total_catches"], 1000)
	assert_eq(ledger["total_taps"], 7500)
	assert_eq(ledger["total_shinies"], 14)
	# first_launch_unix takes the EARLIER value (preserves "I started in 2026").
	assert_eq(ledger["first_launch_unix"], 1700000000)


func test_first_launch_unix_handles_zero() -> void:
	# A pristine save has first_launch_unix=0 (never set). Merging it with
	# a real save should adopt the real save's value, not pick 0.
	var pristine := {"last_saved_unix": 1000, "ledger": {"first_launch_unix": 0, "total_catches": 0}}
	var real := {"last_saved_unix": 2000, "ledger": {"first_launch_unix": 1700000000, "total_catches": 50}}
	var merged := SaveConflictResolver.resolve(pristine, real)
	assert_eq(merged["ledger"]["first_launch_unix"], 1700000000)
	assert_eq(merged["ledger"]["total_catches"], 50)


func test_recipes_crafted_unioned() -> void:
	var older := {"last_saved_unix": 1000, "recipes_crafted": ["recipe_a", "recipe_b"]}
	var newer := {"last_saved_unix": 2000, "recipes_crafted": ["recipe_b", "recipe_c"]}
	var merged := SaveConflictResolver.resolve(older, newer)
	assert_eq(merged["recipes_crafted"], ["recipe_a", "recipe_b", "recipe_c"])


func test_nets_owned_unioned() -> void:
	var older := {"last_saved_unix": 1000, "nets_owned": ["basic_net"]}
	var newer := {"last_saved_unix": 2000, "nets_owned": ["basic_net", "wraith_net"]}
	var merged := SaveConflictResolver.resolve(older, newer)
	assert_eq(merged["nets_owned"], ["basic_net", "wraith_net"])


func test_current_max_tier_takes_max() -> void:
	# One device prestiged (tier reset to 1), other was at tier 5. Take
	# 5, since the prestiging device will quickly re-climb.
	var older := {"last_saved_unix": 1000, "current_max_tier": 5}
	var newer := {"last_saved_unix": 2000, "current_max_tier": 1}
	var merged := SaveConflictResolver.resolve(older, newer)
	assert_eq(merged["current_max_tier"], 5)


func test_prestige_count_takes_max() -> void:
	var older := {"last_saved_unix": 1000, "prestige_count": 3}
	var newer := {"last_saved_unix": 2000, "prestige_count": 1}
	var merged := SaveConflictResolver.resolve(older, newer)
	assert_eq(merged["prestige_count"], 3)


func test_narrator_state_per_line_max() -> void:
	# Peniber's "lines_seen" is per-line monotonic. Merge takes max so a
	# line shown 3 times on phone A and 1 on phone B reads as 3 total.
	var older := {
		"last_saved_unix": 1000,
		"narrator_state": {
			"last_line_unix": 1000,
			"lines_seen": {
				"on_first_launch": 1,
				"on_first_catch_ever": 1,
				"on_battle_loss": 3,
			},
		},
	}
	var newer := {
		"last_saved_unix": 2000,
		"narrator_state": {
			"last_line_unix": 2000,
			"lines_seen": {
				"on_first_launch": 1,
				"on_battle_loss": 1,
				"on_first_shiny": 1,
			},
		},
	}
	var merged := SaveConflictResolver.resolve(older, newer)
	var lines: Dictionary = merged["narrator_state"]["lines_seen"]
	assert_eq(lines["on_first_launch"], 1)
	assert_eq(lines["on_first_catch_ever"], 1)  # only in older
	assert_eq(lines["on_battle_loss"], 3)        # max(3, 1)
	assert_eq(lines["on_first_shiny"], 1)        # only in newer
	assert_eq(merged["narrator_state"]["last_line_unix"], 2000)


func test_version_takes_max() -> void:
	var older := {"last_saved_unix": 1000, "version": 1}
	var newer := {"last_saved_unix": 2000, "version": 2}
	var merged := SaveConflictResolver.resolve(older, newer)
	assert_eq(merged["version"], 2)
	# And vice-versa: newer save with older schema still picks the higher version.
	merged = SaveConflictResolver.resolve({"last_saved_unix": 2000, "version": 1}, {"last_saved_unix": 1000, "version": 2})
	assert_eq(merged["version"], 2)


func test_last_saved_unix_tie_prefers_remote() -> void:
	# Tiebreak rule: when timestamps are equal, prefer remote. Lets two
	# pristine devices converge to the same fixpoint regardless of which
	# one runs the resolver.
	var local := {"last_saved_unix": 1000, "active_net": "local_net"}
	var remote := {"last_saved_unix": 1000, "active_net": "remote_net"}
	var merged := SaveConflictResolver.resolve(local, remote)
	assert_eq(merged["active_net"], "remote_net")


func test_resolver_is_pure_input_unmodified() -> void:
	# Defense against accidentally mutating inputs.
	var local := {"last_saved_unix": 1000, "pets_owned": ["a"]}
	var remote := {"last_saved_unix": 2000, "pets_owned": ["b"]}
	var local_snapshot := local.duplicate(true)
	var remote_snapshot := remote.duplicate(true)
	SaveConflictResolver.resolve(local, remote)
	assert_eq(local, local_snapshot, "local must not be mutated")
	assert_eq(remote, remote_snapshot, "remote must not be mutated")
