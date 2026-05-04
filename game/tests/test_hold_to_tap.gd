## Phase 12b — hold-to-tap setter contract.
##
## Verifies the Settings setters for hold_to_tap_enabled +
## hold_tap_rate_hz clamp, dedupe, persist, and emit
## accessibility_settings_changed. The catching_view integration is
## a straightforward _process loop that consults Settings each frame;
## driving it through GUT involves instantiating the catching scene
## (with its parallax background, drops-2x button, etc.) and the
## resulting tree leaks into subsequent tests in unpredictable ways.
## A behavioral test for hold-to-tap is better deferred to a Maestro
## emulator flow.
extends GutTest


func before_each() -> void:
	Settings.hold_to_tap_enabled = false
	Settings.hold_tap_rate_hz = 8.0


func after_each() -> void:
	Settings.hold_to_tap_enabled = false
	Settings.hold_tap_rate_hz = 8.0


func test_setter_clamps_rate() -> void:
	Settings.set_hold_tap_rate_hz(0.0)
	assert_eq(Settings.hold_tap_rate_hz, Settings.HOLD_TAP_RATE_MIN,
			"rate below minimum must clamp to HOLD_TAP_RATE_MIN")
	Settings.set_hold_tap_rate_hz(99.0)
	assert_eq(Settings.hold_tap_rate_hz, Settings.HOLD_TAP_RATE_MAX,
			"rate above maximum must clamp to HOLD_TAP_RATE_MAX")


func test_enabled_setter_emits_signal() -> void:
	var fired: Array[bool] = [false]
	var handler := func() -> void: fired[0] = true
	Settings.accessibility_settings_changed.connect(handler)
	Settings.set_hold_to_tap_enabled(true)
	assert_true(fired[0])
	Settings.accessibility_settings_changed.disconnect(handler)


func test_enabled_setter_idempotent() -> void:
	Settings.hold_to_tap_enabled = true
	var fired: Array[int] = [0]
	var handler := func() -> void: fired[0] += 1
	Settings.accessibility_settings_changed.connect(handler)
	Settings.set_hold_to_tap_enabled(true)
	assert_eq(fired[0], 0,
			"setting hold_to_tap_enabled to its current value must not fire signal")
	Settings.accessibility_settings_changed.disconnect(handler)


func test_round_trip_through_disk() -> void:
	Settings.set_hold_to_tap_enabled(true)
	Settings.set_hold_tap_rate_hz(12.0)
	Settings.hold_to_tap_enabled = false
	Settings.hold_tap_rate_hz = 8.0
	Settings.load_from_disk()
	assert_true(Settings.hold_to_tap_enabled,
			"hold_to_tap_enabled must round-trip via settings.cfg")
	assert_almost_eq(Settings.hold_tap_rate_hz, 12.0, 0.01,
			"hold_tap_rate_hz must round-trip via settings.cfg")
