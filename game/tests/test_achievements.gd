## Phase 12f — achievement evaluator, idempotency, save round-trip.
##
## Tests use the live ContentRegistry achievements (the 20 starter set)
## by id. They mutate GameState fields directly and call
## Achievements.evaluate_all() — bypassing the EventBus signal hookup
## so the tests are deterministic regardless of connection ordering.
extends GutTest


func before_each() -> void:
	# Tests need a clean GameState slice; we don't reset everything because
	# perform_prestige + currency mutations have downstream tests. Just clear
	# the fields the trigger evaluator reads + the achievements ledger.
	GameState.achievements_unlocked = {}
	GameState.ledger["total_catches"] = 0
	GameState.ledger["total_taps"] = 0
	GameState.ledger["total_shinies"] = 0
	GameState.prestige_count = 0
	GameState.pets_owned = []
	GameState.nets_owned = []
	GameState.recipes_crafted = []
	GameState.current_max_tier = 1


func after_each() -> void:
	GameState.achievements_unlocked = {}


# region — trigger evaluator

func test_ledger_field_unlock_fires_when_threshold_crossed() -> void:
	GameState.ledger["total_catches"] = 100
	Achievements.evaluate_all()
	assert_true(
		GameState.achievements_unlocked.has("catch_100"),
		"catch_100 should unlock at 100 total_catches")


func test_ledger_field_below_threshold_does_not_fire() -> void:
	GameState.ledger["total_catches"] = 99
	Achievements.evaluate_all()
	assert_false(
		GameState.achievements_unlocked.has("catch_100"),
		"catch_100 must not unlock at 99 catches")


func test_prestige_count_unlock() -> void:
	GameState.prestige_count = 1
	Achievements.evaluate_all()
	assert_true(GameState.achievements_unlocked.has("prestige_1"))


func test_pets_owned_count_unlock() -> void:
	GameState.pets_owned = ["a", "b", "c"]
	Achievements.evaluate_all()
	assert_true(GameState.achievements_unlocked.has("pet_3"))
	assert_true(GameState.achievements_unlocked.has("pet_1"))


func test_nets_owned_count_unlock() -> void:
	GameState.nets_owned = ["basic", "tier2"]
	Achievements.evaluate_all()
	assert_true(GameState.achievements_unlocked.has("net_2"))


func test_recipes_crafted_count_unlock() -> void:
	GameState.recipes_crafted = ["r1"]
	Achievements.evaluate_all()
	assert_true(GameState.achievements_unlocked.has("recipe_1"))


func test_current_max_tier_unlock() -> void:
	GameState.current_max_tier = 5
	Achievements.evaluate_all()
	assert_true(GameState.achievements_unlocked.has("tier_5"))
	assert_false(
		GameState.achievements_unlocked.has("tier_10"),
		"tier_10 must not unlock at tier 5")

# endregion


# region — idempotency / signal contract

func test_unlock_emits_event_only_once() -> void:
	var fired: Array[int] = [0]
	var handler := func(_id: String) -> void: fired[0] += 1
	EventBus.achievement_unlocked.connect(handler)

	GameState.ledger["total_catches"] = 100
	Achievements.evaluate_all()
	Achievements.evaluate_all()   # second pass — must NOT re-fire
	GameState.ledger["total_catches"] = 200
	Achievements.evaluate_all()

	EventBus.achievement_unlocked.disconnect(handler)
	assert_eq(fired[0], 1, "achievement_unlocked must fire exactly once per id")


func test_unlock_grants_rp_reward() -> void:
	var rp_before: int = GameState.current_rancher_points()
	GameState.ledger["total_catches"] = 100
	Achievements.evaluate_all()
	var rp_after: int = GameState.current_rancher_points()
	# catch_100 awards +5 RP per generate_achievements.sh
	assert_eq(rp_after - rp_before, 5, "catch_100 unlock should grant +5 RP")

# endregion


# region — save round-trip

func test_achievements_unlocked_round_trips_through_save() -> void:
	GameState.achievements_unlocked = {"catch_100": true, "shiny_1": true}
	var dict: Dictionary = GameState.to_dict()
	# Wipe and reload.
	GameState.achievements_unlocked = {}
	GameState.from_dict(dict)
	assert_true(GameState.achievements_unlocked.has("catch_100"))
	assert_true(GameState.achievements_unlocked.has("shiny_1"))


func test_v3_to_v4_migration_seeds_empty_dict() -> void:
	var v3: Dictionary = {"version": 3, "current_max_tier": 4}
	var migrated: Dictionary = SaveMigrations.apply_chain(v3, 4)
	assert_eq(migrated.get("version"), 4)
	assert_true(migrated.has("achievements_unlocked"))
	assert_true(
		(migrated["achievements_unlocked"] as Dictionary).is_empty(),
		"v4 migration must seed an empty achievements_unlocked dict")


func test_v3_to_v4_migration_preserves_existing_unlocks() -> void:
	var v3: Dictionary = {
		"version": 3,
		"achievements_unlocked": {"catch_100": true},
	}
	var migrated: Dictionary = SaveMigrations.apply_chain(v3, 4)
	assert_true(
		(migrated["achievements_unlocked"] as Dictionary).has("catch_100"),
		"existing achievement entries must survive migration")

# endregion


# region — prestige preserves achievements

func test_perform_prestige_preserves_unlocks() -> void:
	GameState.achievements_unlocked = {"catch_100": true, "prestige_1": true}
	# Make sure prestige produces a non-zero RP payout (otherwise the
	# perform_prestige fast-path may not exercise the keepers loop).
	GameState.total_gold_earned_this_run = {"m": 1.0, "e": 6}
	GameState.perform_prestige()
	assert_true(
		GameState.achievements_unlocked.has("catch_100"),
		"achievement_unlocked dict must persist across prestige")
	assert_true(GameState.achievements_unlocked.has("prestige_1"))

# endregion
