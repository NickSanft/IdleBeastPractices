## Music + SFX dispatch.
##
## Looping music track on game start, tap SFX on every monster tap. SFX uses
## a small pool of AudioStreamPlayers so rapid taps don't cut each other off;
## oldest player is recycled if all are busy.
##
## Volumes pull from Settings.music_db / Settings.sfx_db on init and re-apply
## whenever Settings.audio_settings_changed fires (driven by the Settings UI).
extends Node

const _MUSIC_PATH := "res://assets/music/Divora - Bring The Guitar.ogg"
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
	var loaded: AudioStream = load(_MUSIC_PATH)
	if loaded == null:
		push_warning("AudioManager: music file not found at %s" % _MUSIC_PATH)
		return
	# Duplicate so loop_mode mutation doesn't pollute the shared cached resource
	# (and so a 0-length loop_end-derived bug in the cached copy is escaped).
	var stream: AudioStream = loaded.duplicate(true) as AudioStream
	if stream is AudioStreamWAV:
		var wav: AudioStreamWAV = stream
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		# Explicit loop range covering the whole stream. loop_end<=loop_begin is
		# the common cause of "playing=true → playing=false in <1s with pos=0".
		wav.loop_begin = 0
		var sr: int = max(1, wav.mix_rate)
		var total_frames: int = int(round(wav.get_length() * float(sr)))
		wav.loop_end = max(1, total_frames - 1)
		print("[audio] music wav: mix_rate=%d total_frames=%d loop=%d..%d" % [
			sr, total_frames, wav.loop_begin, wav.loop_end,
		])
	elif stream is AudioStreamOggVorbis:
		stream.loop = true

	_music_player = AudioStreamPlayer.new()
	_music_player.name = "Music"
	_music_player.stream = stream
	_music_player.bus = "Master"
	_music_player.volume_db = Settings.music_db
	_music_player.stream_paused = false
	add_child(_music_player)
	_music_player.finished.connect(_on_music_finished)
	# Defer to next frame so the audio server is fully alive before play().
	# Some Godot 4.6 editor builds drop early-init play() calls silently.
	call_deferred("_start_music_deferred")


func _start_music_deferred() -> void:
	if _music_player == null:
		return
	_music_player.play()
	var master_idx: int = AudioServer.get_bus_index("Master")
	var master_db: float = AudioServer.get_bus_volume_db(master_idx) if master_idx >= 0 else -INF
	var master_muted: bool = AudioServer.is_bus_mute(master_idx) if master_idx >= 0 else true
	print("[audio] music started: stream=%s len=%.1fs player_db=%.1f bus=%s master_db=%.1f master_muted=%s playing=%s" % [
		_music_player.stream.get_class(),
		_music_player.stream.get_length(),
		_music_player.volume_db,
		_music_player.bus,
		master_db,
		master_muted,
		_music_player.playing,
	])
	# Re-check 0.5s later in case the engine claimed playing=true at frame 0
	# but never actually fed the bus.
	get_tree().create_timer(0.5).timeout.connect(_log_music_state_late)


func _log_music_state_late() -> void:
	if _music_player == null:
		return
	print("[audio] music after 0.5s: playing=%s pos=%.2fs" % [
		_music_player.playing,
		_music_player.get_playback_position(),
	])
	# If position is still zero, retry a fresh play() — covers the race where
	# the deferred play() landed before AudioServer was actually listening.
	if not _music_player.playing or _music_player.get_playback_position() <= 0.0:
		_music_player.stop()
		_music_player.play()
		print("[audio] music retry play(); playing=%s" % _music_player.playing)


func _on_music_finished() -> void:
	# AudioStreamPlayer's `finished` fires when the stream reaches its end with
	# no looping (or when it's stopped). With LOOP_FORWARD this should never
	# fire under normal play. If it does, the stream's loop range is wrong.
	print("[audio] music finished signal fired (unexpected with looping enabled)")


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
