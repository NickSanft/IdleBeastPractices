## User preferences (audio, accessibility). Loads first among autoloads.
extends Node

signal audio_settings_changed
## Phase 11b — emitted whenever an accessibility flag changes so live
## UI subscribers (theme font-size, reduce-motion-gated tweens) can
## refresh without a full scene reload.
signal accessibility_settings_changed

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

# Dev toggles — not persisted to disk. Bound to keyboard shortcuts in main.gd.
# Default off so production builds use the real catch threshold (25) and
# real variant_rate per pet. F2 flips it on for hand-testing.
var debug_fast_pets: bool = false   # F2: lower tier-complete threshold + force variant rolls


func set_music_db(db: float) -> void:
	music_db = clampf(db, MIN_DB, MAX_DB)
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


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_db", audio_master_db)
	cfg.set_value("audio", "sfx_db", sfx_db)
	cfg.set_value("audio", "music_db", music_db)
	cfg.set_value("accessibility", "reduce_motion", reduce_motion)
	cfg.set_value("accessibility", "font_scale", font_scale)
	cfg.set_value("accessibility", "haptics_enabled", haptics_enabled)
	cfg.save(SETTINGS_PATH)
