## Phase 13f — graded haptic feedback for events of varying weight.
##
## Pre-13f, haptics were scattered:
##   - main.gd's _install_global_haptic_feedback fires 20 ms on every
##     button press
##   - catching_view fires 40 ms on every monster_tapped
##   - everything else (catches, first shiny, tier completion, pet
##     acquired, prestige) had NO haptic at all — these are exactly
##     the moments where a tactile sting feels best
##
## This autoload subscribes to the noteworthy events and fires
## graded pulses, so a shiny catch feels distinctly heavier than a
## normal catch and a prestige feels heavier still. The catching
## view's 40 ms inline tap is REMOVED — the manager fires it on
## `monster_tapped` so the dispatch lives in one place.
##
## All pulses respect:
##   - Settings.haptics_enabled (off → no-op)
##   - OS.has_feature("mobile") (desktop / web → no-op)
##
## Test seam: `_vibrate()` increments `vibrate_count` and adds to
## `total_pulse_ms` regardless of platform, so headless tests can
## assert pulse counts and intensities without a real device.
extends Node

# Intensity gradient. Picked so each tier feels noticeably heavier
# than the previous without crossing into "phone won't stop buzzing"
# territory. 150 ms is the longest single sting.
const PULSE_LIGHT := 20      # button press (handled by main.gd)
const PULSE_MEDIUM := 40     # monster_tapped — every tap
const PULSE_NOTABLE := 60    # first catch of species (Pokédex moment)
const PULSE_HEAVY := 80      # shiny catch (subsequent, not first ever)
const PULSE_MAJOR := 100     # tier complete, first-ever shiny
const PULSE_PRESTIGE := 150  # prestige triggered

# Test counters — exposed for the haptic regression test. Never
# touched by gameplay code.
var vibrate_count: int = 0
var total_pulse_ms: int = 0
var last_pulse_ms: int = 0


func _ready() -> void:
	EventBus.monster_tapped.connect(_on_monster_tapped)
	EventBus.monster_caught.connect(_on_monster_caught)
	EventBus.first_catch_of_species.connect(_on_first_catch_of_species)
	EventBus.first_shiny_caught.connect(_on_first_shiny_caught)
	EventBus.tier_completed.connect(_on_tier_completed)
	EventBus.pet_acquired.connect(_on_pet_acquired)
	EventBus.prestige_triggered.connect(_on_prestige_triggered)


# region — public

## Reset the test counters. Called from before_each in haptic tests
## so each test starts from zero. Live gameplay never calls this.
func reset_test_counters() -> void:
	vibrate_count = 0
	total_pulse_ms = 0
	last_pulse_ms = 0

# endregion


# region — internal

func _vibrate(ms: int) -> void:
	if ms <= 0:
		return
	if not Settings.haptics_enabled:
		return
	# Counters always update, even on non-mobile, so tests work
	# headlessly. Real device call is gated separately.
	vibrate_count += 1
	last_pulse_ms = ms
	total_pulse_ms += ms
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


func _on_monster_tapped(_id: String, _ix: int) -> void:
	_vibrate(PULSE_MEDIUM)


func _on_monster_caught(_id: String, _ix: int, is_shiny: bool, _src: String) -> void:
	# Subsequent shinies (after the first ever) get an 80 ms sting
	# layered on top of the already-fired monster_tapped 40 ms,
	# distinguishing them from normal catches. The very-first shiny
	# also fires `first_shiny_caught` which adds PULSE_MAJOR on top.
	if is_shiny:
		_vibrate(PULSE_HEAVY)


func _on_first_catch_of_species(_id: String) -> void:
	_vibrate(PULSE_NOTABLE)


func _on_first_shiny_caught(_id: String) -> void:
	_vibrate(PULSE_MAJOR)


func _on_tier_completed(_tier: int) -> void:
	_vibrate(PULSE_MAJOR)


func _on_pet_acquired(_pet_id: String, _is_variant: bool) -> void:
	_vibrate(PULSE_HEAVY)


func _on_prestige_triggered(_rp: int, _count: int) -> void:
	_vibrate(PULSE_PRESTIGE)

# endregion
