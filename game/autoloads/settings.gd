## User preferences (audio, accessibility). Loads first among autoloads.
extends Node

const SETTINGS_PATH := "user://settings.cfg"

var audio_master_db: float = 0.0
var sfx_db: float = 0.0
var music_db: float = -6.0
var reduce_motion: bool = false
var font_scale: float = 1.0


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
