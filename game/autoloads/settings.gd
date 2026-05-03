## User preferences (audio, accessibility). Loads first among autoloads.
extends Node

signal audio_settings_changed

const SETTINGS_PATH := "user://settings.cfg"

# Volume range for the UI sliders. Below MIN_DB the corresponding bus is muted.
const MIN_DB := -40.0
const MAX_DB := 0.0

var audio_master_db: float = 0.0
var sfx_db: float = 0.0
var music_db: float = -6.0
var reduce_motion: bool = false
var font_scale: float = 1.0

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


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_db", audio_master_db)
	cfg.set_value("audio", "sfx_db", sfx_db)
	cfg.set_value("audio", "music_db", music_db)
	cfg.set_value("accessibility", "reduce_motion", reduce_motion)
	cfg.set_value("accessibility", "font_scale", font_scale)
	cfg.save(SETTINGS_PATH)
