## v0.14.6 (Phase 13f) — haptic gradient tests.
##
## Asserts the contract every gameplay event depends on:
##   - Each EventBus signal HapticManager subscribes to fires
##     exactly one `_vibrate` call with the documented intensity.
##   - `Settings.haptics_enabled = false` makes everything a no-op.
##   - Shiny catches layer correctly (monster_tapped + monster_caught
##     fires both pulses; first-ever shiny also fires
##     first_shiny_caught for the third pulse).
##   - Pulse intensities are monotonically heavier from light → prestige.
##
## Tests use HapticManager.reset_test_counters and read
## `vibrate_count` / `total_pulse_ms` / `last_pulse_ms` to verify.
## No real device needed.
extends GutTest


func before_each() -> void:
	Settings.haptics_enabled = true
	HapticManager.reset_test_counters()


func after_each() -> void:
	Settings.haptics_enabled = true
	HapticManager.reset_test_counters()


# region — single-event pulses

func test_monster_tapped_fires_pulse_medium() -> void:
	EventBus.monster_tapped.emit("red_wisplet", 1)
	assert_eq(HapticManager.vibrate_count, 1)
	assert_eq(HapticManager.last_pulse_ms, HapticManager.PULSE_MEDIUM)


func test_first_catch_of_species_fires_pulse_notable() -> void:
	EventBus.first_catch_of_species.emit("red_wisplet")
	assert_eq(HapticManager.vibrate_count, 1)
	assert_eq(HapticManager.last_pulse_ms, HapticManager.PULSE_NOTABLE)


func test_first_shiny_caught_fires_pulse_major() -> void:
	EventBus.first_shiny_caught.emit("red_wisplet")
	assert_eq(HapticManager.last_pulse_ms, HapticManager.PULSE_MAJOR)


func test_tier_completed_fires_pulse_major() -> void:
	EventBus.tier_completed.emit(3)
	assert_eq(HapticManager.last_pulse_ms, HapticManager.PULSE_MAJOR)


func test_pet_acquired_fires_pulse_heavy() -> void:
	EventBus.pet_acquired.emit("red_wisplet", false)
	assert_eq(HapticManager.last_pulse_ms, HapticManager.PULSE_HEAVY)


func test_prestige_triggered_fires_pulse_prestige() -> void:
	EventBus.prestige_triggered.emit(100, 1)
	assert_eq(HapticManager.last_pulse_ms, HapticManager.PULSE_PRESTIGE)


func test_normal_catch_does_not_fire_extra_pulse() -> void:
	# Non-shiny monster_caught alone (without first_catch_of_species)
	# should not add a pulse — the catching_view's monster_tapped
	# already fired earlier in the catch flow.
	EventBus.monster_caught.emit("red_wisplet", 1, false, "tap")
	assert_eq(HapticManager.vibrate_count, 0,
		"non-shiny monster_caught alone must NOT fire a pulse")

# endregion


# region — layered pulses (a shiny catch)

func test_subsequent_shiny_layers_tap_plus_heavy() -> void:
	# Subsequent shiny (not first ever): monster_tapped fires
	# PULSE_MEDIUM, then monster_caught fires PULSE_HEAVY. Total 2
	# pulses summing to 40 + 80 = 120 ms.
	EventBus.monster_tapped.emit("red_wisplet", 1)
	EventBus.monster_caught.emit("red_wisplet", 1, true, "tap")
	assert_eq(HapticManager.vibrate_count, 2)
	assert_eq(HapticManager.total_pulse_ms,
			HapticManager.PULSE_MEDIUM + HapticManager.PULSE_HEAVY)


func test_first_ever_shiny_layers_three_pulses() -> void:
	# First-ever shiny: monster_tapped + monster_caught(shiny) +
	# first_shiny_caught. 40 + 80 + 100 = 220 ms across 3 pulses.
	EventBus.monster_tapped.emit("red_wisplet", 1)
	EventBus.monster_caught.emit("red_wisplet", 1, true, "tap")
	EventBus.first_shiny_caught.emit("red_wisplet")
	assert_eq(HapticManager.vibrate_count, 3)
	assert_eq(HapticManager.total_pulse_ms,
			HapticManager.PULSE_MEDIUM + HapticManager.PULSE_HEAVY + HapticManager.PULSE_MAJOR)

# endregion


# region — Settings.haptics_enabled gate

func test_disabled_haptics_suppresses_all_pulses() -> void:
	Settings.haptics_enabled = false
	EventBus.monster_tapped.emit("red_wisplet", 1)
	EventBus.first_shiny_caught.emit("red_wisplet")
	EventBus.tier_completed.emit(5)
	EventBus.prestige_triggered.emit(500, 1)
	assert_eq(HapticManager.vibrate_count, 0,
		"Settings.haptics_enabled = false must zero every pulse")
	assert_eq(HapticManager.total_pulse_ms, 0)

# endregion


# region — gradient ordering

func test_pulse_intensities_are_monotonic() -> void:
	# Each tier strictly heavier than the previous. Future tweaks
	# must preserve the gradient shape.
	assert_lt(HapticManager.PULSE_LIGHT, HapticManager.PULSE_MEDIUM)
	assert_lt(HapticManager.PULSE_MEDIUM, HapticManager.PULSE_NOTABLE)
	assert_lt(HapticManager.PULSE_NOTABLE, HapticManager.PULSE_HEAVY)
	assert_lt(HapticManager.PULSE_HEAVY, HapticManager.PULSE_MAJOR)
	assert_lt(HapticManager.PULSE_MAJOR, HapticManager.PULSE_PRESTIGE)

# endregion
