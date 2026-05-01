## Music + SFX dispatch.
##
## Looping music track on game start, tap SFX on every monster tap. SFX uses
## a small pool of AudioStreamPlayers so rapid taps don't cut each other off;
## oldest player is recycled if all are busy.
##
## Volumes pull from Settings.music_db / Settings.sfx_db on init and re-apply
## whenever Settings.audio_settings_changed fires (driven by the Settings UI).
extends Node

const _MUSIC_PATH := "res://assets/music/Divora - New Beginnings - DND 4 - 05 Bring The Guitar, It's Going Down.wav"
const _TAP_SFX_PATH := "res://assets/sounds/tap.wav"
const _SFX_POOL_SIZE := 4

var _music_player: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_pool_cursor: int = 0


func _ready() -> void:
	_setup_music()
	_setup_sfx_pool()
	EventBus.monster_tapped.connect(_on_monster_tapped)
	EventBus.monster_caught.connect(_on_monster_caught)
	EventBus.first_shiny_caught.connect(_on_first_shiny_caught)
	EventBus.tier_completed.connect(_on_tier_completed)
	EventBus.upgrade_purchased.connect(_on_upgrade_purchased)
	Settings.audio_settings_changed.connect(_apply_volumes)


func _setup_music() -> void:
	var stream: AudioStream = load(_MUSIC_PATH)
	if stream == null:
		push_warning("AudioManager: music file not found at %s" % _MUSIC_PATH)
		return
	# Force loop in case the .import didn't bake it in.
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif stream is AudioStreamOggVorbis:
		stream.loop = true
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "Music"
	_music_player.stream = stream
	_music_player.volume_db = Settings.music_db
	add_child(_music_player)
	# Don't rely on autoplay — Godot autoloads can race the audio system on init.
	# Explicit play() after add_child is reliable.
	_music_player.play()
	print("[audio] music started: stream=%s len=%.1fs db=%.1f" % [
		_music_player.stream.get_class(),
		_music_player.stream.get_length(),
		_music_player.volume_db,
	])


func _setup_sfx_pool() -> void:
	var stream: AudioStream = load(_TAP_SFX_PATH)
	if stream == null:
		push_warning("AudioManager: tap SFX not found at %s" % _TAP_SFX_PATH)
		return
	for i in _SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "SFX_%d" % i
		p.stream = stream
		p.volume_db = Settings.sfx_db
		add_child(p)
		_sfx_pool.append(p)


func play_tap_sfx() -> void:
	if _sfx_pool.is_empty():
		return
	for p in _sfx_pool:
		if not p.playing:
			p.play()
			return
	var victim: AudioStreamPlayer = _sfx_pool[_sfx_pool_cursor]
	victim.stop()
	victim.play()
	_sfx_pool_cursor = (_sfx_pool_cursor + 1) % _sfx_pool.size()


## Re-applies the current Settings.* dB values to every player. Called when
## sliders change, but also safe to call any time.
func _apply_volumes() -> void:
	if _music_player != null:
		_music_player.volume_db = Settings.music_db
	for p in _sfx_pool:
		p.volume_db = Settings.sfx_db


# region — EventBus handlers

func _on_monster_tapped(_monster_id: String, _instance_id: int) -> void:
	play_tap_sfx()


func _on_monster_caught(_monster_id: String, _instance_id: int, _is_shiny: bool, _source: String) -> void:
	pass


func _on_first_shiny_caught(_monster_id: String) -> void:
	pass


func _on_tier_completed(_tier: int) -> void:
	pass


func _on_upgrade_purchased(_upgrade_id: String) -> void:
	pass

# endregion
