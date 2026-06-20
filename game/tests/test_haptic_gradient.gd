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


func test_normal_tap_catch_fires_pulse_catch() -> void:
	# v0.15.10 — a completed TAP catch now fires its own 50 ms sting
	# (between the 40 ms tap and the 60 ms first-catch) so the catch
	# feels heavier than a plain non-completing tap. Pre-v0.15.10 a
	# normal catch fired nothing here.
	EventBus.monster_caught.emit("red_wisplet", 1, false, "tap")
	assert_eq(HapticManager.vibrate_count, 1,
		"a normal tap catch must fire exactly one pulse")
	assert_eq(HapticManager.last_pulse_ms, HapticManager.PULSE_CATCH)


func test_normal_net_catch_fires_no_pulse() -> void:
	# v0.15.10 — idle/net auto-catches must NOT buzz: a phone vibrating
	# in a pocket on every passive catch is exactly what we avoid. Only
	# the source differs from the tap-catch case above.
	EventBus.monster_caught.emit("red_wisplet", 1, false, "net")
	assert_eq(HapticManager.vibrate_count, 0,
		"a non-shiny NET/auto catch must NOT fire any pulse")


func test_shiny_net_catch_still_buzzes() -> void:
	# A shiny is rare enough to warrant the buzz even when auto-caught —
	# the heavier sting is the catch marker for shinies regardless of
	# source. Only the per-catch NORMAL pulse is source-gated.
	EventBus.monster_caught.emit("red_wisplet", 1, true, "net")
	assert_eq(HapticManager.vibrate_count, 1)
	assert_eq(HapticManager.last_pulse_ms, HapticManager.PULSE_HEAVY)

# endregion


# region — layered pulses (a shiny catch)

func test_normal_tap_catch_layers_tap_plus_catch() -> void:
	# v0.15.10 — a normal tap catch is the 40 ms tap followed by the
	# 50 ms catch sting: 2 pulses, 90 ms total. Documents the escalation
	# a completed catch now feels vs a tap that didn't land (40 ms only).
	EventBus.monster_tapped.emit("red_wisplet", 1)
	EventBus.monster_caught.emit("red_wisplet", 1, false, "tap")
	assert_eq(HapticManager.vibrate_count, 2)
	assert_eq(HapticManager.total_pulse_ms,
			HapticManager.PULSE_MEDIUM + HapticManager.PULSE_CATCH)


func test_subsequent_shiny_layers_tap_plus_heavy() -> void:
	# Subsequent shiny (not first ever): monster_tapped fires
	# PULSE_MEDIUM, then monster_caught fires PULSE_HEAVY (shiny's sting
	# is its catch marker — no extra PULSE_CATCH on top). 40 + 80 = 120 ms.
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
	# v0.15.10 — PULSE_CATCH sits between the tap (MEDIUM) and the
	# first-catch (NOTABLE) so a landed catch is heavier than a tap but
	# lighter than the Pokédex moment.
	assert_lt(HapticManager.PULSE_MEDIUM, HapticManager.PULSE_CATCH)
	assert_lt(HapticManager.PULSE_CATCH, HapticManager.PULSE_NOTABLE)
	assert_lt(HapticManager.PULSE_NOTABLE, HapticManager.PULSE_HEAVY)
	assert_lt(HapticManager.PULSE_HEAVY, HapticManager.PULSE_MAJOR)
	assert_lt(HapticManager.PULSE_MAJOR, HapticManager.PULSE_PRESTIGE)

# endregion
