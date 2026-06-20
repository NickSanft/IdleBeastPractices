## v0.15.10 — catch-audio routing + throttle tests.
##
## Pre-v0.15.10 a normal catch made no distinct sound (only shiny did),
## so the loop's main payoff was unmarked. AudioManager now plays a
## "caught!" chime on every catch, routed by source:
##   - shiny (any source) → the shiny sting is the catch sound (unchanged)
##   - normal TAP catch    → full-volume catch chime
##   - normal NET catch    → quieter chime, throttled so a fast net
##                           doesn't machine-gun the speaker
##
## Like HapticManager, AudioManager exposes test-seam counters that
## update even headlessly (no real audio output needed):
##   catch_sfx_count · auto_catch_sfx_count · auto_catch_throttled_count
extends GutTest


func before_each() -> void:
	# Ensure SFX aren't at the "Muted" floor (a prior test could have left
	# sfx_db there) — the routing/throttle tests below assume audible SFX.
	Settings.sfx_db = 0.0
	AudioManager.reset_test_counters()


func after_each() -> void:
	Settings.sfx_db = 0.0
	AudioManager.reset_test_counters()


func test_tap_catch_plays_full_catch_chime() -> void:
	EventBus.monster_caught.emit("red_wisplet", 1, false, "tap")
	assert_eq(AudioManager.catch_sfx_count, 1,
		"a normal tap catch must play exactly one full-volume catch chime")
	assert_eq(AudioManager.auto_catch_sfx_count, 0,
		"a tap catch must NOT route through the auto-catch (net) path")


func test_net_catch_plays_throttled_auto_chime() -> void:
	EventBus.monster_caught.emit("red_wisplet", 1, false, "net")
	assert_eq(AudioManager.auto_catch_sfx_count, 1,
		"a net catch must play one (reduced-volume) auto-catch chime")
	assert_eq(AudioManager.catch_sfx_count, 0,
		"a net catch must NOT route through the full tap-catch path")


func test_shiny_catch_does_not_play_normal_catch_chime() -> void:
	# Shiny's brighter sting IS the catch sound for shinies; it must not
	# also fire the normal catch chime (tap or net path).
	EventBus.monster_caught.emit("red_wisplet", 1, true, "tap")
	assert_eq(AudioManager.catch_sfx_count, 0,
		"a shiny tap catch must not also play the normal catch chime")
	EventBus.monster_caught.emit("red_wisplet", 1, true, "net")
	assert_eq(AudioManager.auto_catch_sfx_count, 0,
		"a shiny net catch must not also play the auto-catch chime")


func test_burst_of_net_catches_is_throttled_to_one() -> void:
	# Several net catches in the same frame (a fast net resolving many at
	# once) must batch into a single audible chime; the rest are counted
	# as throttled, not played.
	for i in 5:
		EventBus.monster_caught.emit("red_wisplet", i, false, "net")
	assert_eq(AudioManager.auto_catch_sfx_count, 1,
		"a same-frame burst of net catches must play exactly one chime")
	assert_eq(AudioManager.auto_catch_throttled_count, 4,
		"the other 4 net catches in the burst must be throttled, not played")


func test_throttle_window_reopens_after_the_interval() -> void:
	# After the throttle interval elapses, the next net catch chimes again.
	EventBus.monster_caught.emit("red_wisplet", 1, false, "net")
	assert_eq(AudioManager.auto_catch_sfx_count, 1)
	# Simulate the throttle window elapsing by rewinding the last-chime
	# clock a full second into the past. This is deterministic — a real
	# `await wait_seconds(...)` flakes in the full suite, where a lingering
	# CatchingView from a prior test can process a frame mid-wait and emit
	# a stray "net" catch that resets the throttle clock before our second
	# emit. No await here → no frames process → no stray emit can race it.
	AudioManager._last_auto_chime_ms -= 1000
	EventBus.monster_caught.emit("red_wisplet", 2, false, "net")
	assert_eq(AudioManager.auto_catch_sfx_count, 2,
		"a net catch after the throttle window must chime again")


func test_tap_catches_are_not_throttled() -> void:
	# Tap catches are player-rate-limited, so every one chimes (no batch).
	for i in 4:
		EventBus.monster_caught.emit("red_wisplet", i, false, "tap")
	assert_eq(AudioManager.catch_sfx_count, 4,
		"every tap catch must chime — only the net path is throttled")


func test_muted_sfx_suppresses_catch_chimes() -> void:
	# v0.15.10 — at the "Muted" SFX floor (sfx_db == MIN_DB) the catch
	# chimes must be fully silent, not just quiet. Pre-fix SFX leaked at
	# ≈-40 dB because there's no SFX bus to mute.
	Settings.sfx_db = Settings.MIN_DB
	EventBus.monster_caught.emit("red_wisplet", 1, false, "tap")
	EventBus.monster_caught.emit("red_wisplet", 2, false, "net")
	assert_eq(AudioManager.catch_sfx_count, 0,
		"muted SFX must suppress the tap-catch chime entirely")
	assert_eq(AudioManager.auto_catch_sfx_count, 0,
		"muted SFX must suppress the net-catch chime entirely")
	Settings.sfx_db = 0.0
