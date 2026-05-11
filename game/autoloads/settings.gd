## User preferences (audio, accessibility). Loads first among autoloads.
extends Node

signal audio_settings_changed
## Phase 11b — emitted whenever an accessibility flag changes so live
## UI subscribers (theme font-size, reduce-motion-gated tweens) can
## refresh without a full scene reload.
signal accessibility_settings_changed
## Phase 14f — emitted whenever the active Dusk palette changes
## (Amethyst / Twilight / Ember). Subscribers re-resolve their cached
## palette colors and rebuild any inline stylebox overrides.
signal theme_changed

const SETTINGS_PATH := "user://settings.cfg"

# Volume range for the UI sliders. Below MIN_DB the corresponding bus is muted.
const MIN_DB := -40.0
const MAX_DB := 0.0

# Font-scale clamp — chosen so all themed Labels stay readable without
# overflowing their containers at the upper end. 0.85 is the smallest
# size where the nav glyphs stay legible; 1.5 is roughly the largest
# before currency_chip text starts clipping its 110-px panel.
const FONT_SCALE_MIN := 0.85
const FONT_SCALE_MAX := 1.5

var audio_master_db: float = 0.0
var sfx_db: float = 0.0
var music_db: float = -6.0
var reduce_motion: bool = false
var font_scale: float = 1.0
## Phase 11b — global haptic on/off. When false, the main.gd button
## haptic hook + catching_view's per-tap haptic both skip the
## `Input.vibrate_handheld` call. Defaults true so existing players
## see no change.
var haptics_enabled: bool = true

## Phase 11e — persisted battle speed selector index. Idle players
## tend to set 4x once and want it to stick across sessions; before
## persistence, every Battle entry reset to 1x (the audit's F42
## medium-severity finding). Range: [0..2] mapping to [1x, 2x, 4x]
## per battle_view._SPEED_OPTIONS.
var battle_speed_index: int = 0

## Phase 12b — hold-to-tap accessibility. When `hold_to_tap_enabled`
## is true and the player holds finger on a monster, the catching
## view fires repeat tap events at `hold_tap_rate_hz`. Per Game
## Accessibility Guidelines, hold-to-tap is the highest-leverage
## clicker accessibility addition: it serves players with RSI, motor
## sensitivities, and players whose phones can't keep up with rapid
## taps. Defaults off so existing players see no behavior change.
var hold_to_tap_enabled: bool = false
var hold_tap_rate_hz: float = 8.0
const HOLD_TAP_RATE_MIN := 4.0
const HOLD_TAP_RATE_MAX := 16.0

## Phase 12b — color-blind redundancy. When on, bestiary slot pills +
## shiny floating-number cues add shape/icon variation alongside
## color so players who can't distinguish certain colors still parse
## the state. Defaults off — color-blind users opt in via Settings.
var colorblind_mode: bool = false

## Phase 14f — Dusk palette identifier. One of "amethyst" / "twilight"
## / "ember" per PaletteDusk.by_id(). Drives both the Theme.tres
## assignment at the window root and the live `PaletteDusk.active()`
## lookup that scenes use for inline color overrides. Persisted.
const THEME_AMETHYST := "amethyst"
const THEME_TWILIGHT := "twilight"
const THEME_EMBER := "ember"
const VALID_THEME_IDS: Array[String] = [THEME_AMETHYST, THEME_TWILIGHT, THEME_EMBER]
var theme_id: String = THEME_AMETHYST

# Dev toggles — not persisted to disk. Bound to keyboard shortcuts in main.gd.
# Default off so production builds use the real catch threshold (25) and
# real variant_rate per pet. F2 flips it on for hand-testing.
var debug_fast_pets: bool = false   # F2: lower tier-complete threshold + force variant rolls


func set_music_db(db: float) -> void:
	music_db = clampf(db, MIN_DB, MAX_DB)
	audio_settings_changed.emit()
	save_to_disk()


## Phase 12a — master volume slider, finally wired into the UI. Was
## persisted but had no setter or UI control. AudioServer's Master bus
## reads `audio_master_db` directly via the audio_settings_changed
## listener in [AudioManager].
func set_master_db(db: float) -> void:
	audio_master_db = clampf(db, MIN_DB, MAX_DB)
	audio_settings_changed.emit()
	save_to_disk()


func set_sfx_db(db: float) -> void:
	sfx_db = clampf(db, MIN_DB, MAX_DB)
	audio_settings_changed.emit()
	save_to_disk()


func set_reduce_motion(value: bool) -> void:
	if reduce_motion == value:
		return
	reduce_motion = value
	accessibility_settings_changed.emit()
	save_to_disk()


func set_font_scale(value: float) -> void:
	var clamped: float = clampf(value, FONT_SCALE_MIN, FONT_SCALE_MAX)
	if is_equal_approx(font_scale, clamped):
		return
	font_scale = clamped
	accessibility_settings_changed.emit()
	save_to_disk()


func set_haptics_enabled(value: bool) -> void:
	if haptics_enabled == value:
		return
	haptics_enabled = value
	accessibility_settings_changed.emit()
	save_to_disk()


func set_battle_speed_index(value: int) -> void:
	# Clamp to the valid range. battle_view._SPEED_OPTIONS has 3
	# entries; if it grows, this clamp grows with it.
	var clamped: int = clampi(value, 0, 2)
	if battle_speed_index == clamped:
		return
	battle_speed_index = clamped
	save_to_disk()


func set_hold_to_tap_enabled(value: bool) -> void:
	if hold_to_tap_enabled == value:
		return
	hold_to_tap_enabled = value
	accessibility_settings_changed.emit()
	save_to_disk()


func set_hold_tap_rate_hz(value: float) -> void:
	var clamped: float = clampf(value, HOLD_TAP_RATE_MIN, HOLD_TAP_RATE_MAX)
	if is_equal_approx(hold_tap_rate_hz, clamped):
		return
	hold_tap_rate_hz = clamped
	accessibility_settings_changed.emit()
	save_to_disk()


func set_colorblind_mode(value: bool) -> void:
	if colorblind_mode == value:
		return
	colorblind_mode = value
	accessibility_settings_changed.emit()
	save_to_disk()


## Phase 14f — switch the active Dusk palette. Unknown ids fall back
## to Amethyst (matching PaletteDusk.by_id behaviour) so persisted
## values from a future palette set that's been removed don't break
## startup. Emits `theme_changed` so main.gd + live UI subscribers
## reload the matching `.tres` and re-resolve cached palette colors.
func set_theme_id(value: String) -> void:
	var clamped: String = value if VALID_THEME_IDS.has(value) else THEME_AMETHYST
	if theme_id == clamped:
		return
	theme_id = clamped
	theme_changed.emit()
	save_to_disk()


func _ready() -> void:
	load_from_disk()


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err != OK:
		# First run; defaults already set.
		return
	audio_master_db = cfg.get_value("audio", "master_db", audio_master_db)
	sfx_db = cfg.get_value("audio", "sfx_db", sfx_db)
	music_db = cfg.get_value("audio", "music_db", music_db)
	reduce_motion = cfg.get_value("accessibility", "reduce_motion", reduce_motion)
	font_scale = cfg.get_value("accessibility", "font_scale", font_scale)
	haptics_enabled = cfg.get_value("accessibility", "haptics_enabled", haptics_enabled)
	hold_to_tap_enabled = cfg.get_value("accessibility", "hold_to_tap_enabled", hold_to_tap_enabled)
	hold_tap_rate_hz = cfg.get_value("accessibility", "hold_tap_rate_hz", hold_tap_rate_hz)
	colorblind_mode = cfg.get_value("accessibility", "colorblind_mode", colorblind_mode)
	battle_speed_index = cfg.get_value("gameplay", "battle_speed_index", battle_speed_index)
	# Phase 14f: load Dusk palette id with a safety net for unknown
	# values (a future palette removal shouldn't crash startup).
	var loaded_theme: String = cfg.get_value("theme", "id", theme_id)
	theme_id = loaded_theme if VALID_THEME_IDS.has(loaded_theme) else THEME_AMETHYST


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_db", audio_master_db)
	cfg.set_value("audio", "sfx_db", sfx_db)
	cfg.set_value("audio", "music_db", music_db)
	cfg.set_value("accessibility", "reduce_motion", reduce_motion)
	cfg.set_value("accessibility", "font_scale", font_scale)
	cfg.set_value("accessibility", "haptics_enabled", haptics_enabled)
	cfg.set_value("accessibility", "hold_to_tap_enabled", hold_to_tap_enabled)
	cfg.set_value("accessibility", "hold_tap_rate_hz", hold_tap_rate_hz)
	cfg.set_value("accessibility", "colorblind_mode", colorblind_mode)
	cfg.set_value("gameplay", "battle_speed_index", battle_speed_index)
	cfg.set_value("theme", "id", theme_id)
	cfg.save(SETTINGS_PATH)
