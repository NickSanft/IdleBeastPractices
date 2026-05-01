## Music + SFX dispatch.
##
## Phase 3: looping music track on game start, tap SFX on every monster tap.
## SFX uses a small pool of AudioStreamPlayers so rapid taps don't cut each
## other off; oldest player is recycled if all are busy.
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
	# Wire EventBus subscriptions. Catching signals existed in Phase 0 but
	# only now route to actual playback.
	EventBus.monster_tapped.connect(_on_monster_tapped)
	EventBus.monster_caught.connect(_on_monster_caught)
	EventBus.first_shiny_caught.connect(_on_first_shiny_caught)
	EventBus.tier_completed.connect(_on_tier_completed)
	EventBus.upgrade_purchased.connect(_on_upgrade_purchased)


func _setup_music() -> void:
	var stream: AudioStream = load(_MUSIC_PATH)
	if stream == null:
		push_warning("AudioManager: music file not found at %s" % _MUSIC_PATH)
		return
	# Force loop on the WAV stream so the track restarts at end. Godot
	# imports loop_mode from .wav.import; force it here for safety.
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif stream is AudioStreamOggVorbis:
		stream.loop = true
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "Music"
	_music_player.stream = stream
	_music_player.volume_db = Settings.music_db
	_music_player.autoplay = true
	add_child(_music_player)


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
	# Try to find an idle player first.
	for p in _sfx_pool:
		if not p.playing:
			p.play()
			return
	# All busy — round-robin steal the oldest.
	var victim: AudioStreamPlayer = _sfx_pool[_sfx_pool_cursor]
	victim.stop()
	victim.play()
	_sfx_pool_cursor = (_sfx_pool_cursor + 1) % _sfx_pool.size()


# region — EventBus handlers

func _on_monster_tapped(_monster_id: String, _instance_id: int) -> void:
	play_tap_sfx()


func _on_monster_caught(_monster_id: String, _instance_id: int, _is_shiny: bool, _source: String) -> void:
	pass  # Phase 5: catch sting; for now the tap SFX from the final tap is enough.


func _on_first_shiny_caught(_monster_id: String) -> void:
	pass  # Phase 5: shiny sting


func _on_tier_completed(_tier: int) -> void:
	pass  # Phase 5: tier-up jingle


func _on_upgrade_purchased(_upgrade_id: String) -> void:
	pass  # Phase 5: purchase confirm SFX

# endregion
