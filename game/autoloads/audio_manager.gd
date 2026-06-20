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
## v0.15.10 — minimum gap between idle/net auto-catch chimes. A fast net
## can resolve several catches in one frame; without a throttle they'd
## machine-gun the speaker. 150 ms (~7/s) clears the fastest shipped net
## (nadir_net, 5.6 catches/s) one-to-one so the chime tracks the catch
## flurry, while still collapsing same-frame bursts into one "caught".
const _AUTO_CATCH_CHIME_MIN_MS := 150

var _music_player: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_pool_cursor: int = 0
var _shiny_player: AudioStreamPlayer
var _tier_up_player: AudioStreamPlayer
var _miss_tap_player: AudioStreamPlayer
## v0.15.10 — the "caught!" chimes. Reuse tap.wav at distinct pitches
## (the codebase convention for differentiating a moment without shipping
## a new asset, same as the shiny / tier-up / miss-tap players). Pre-fix
## a normal catch made NO distinct sound — it was indistinguishable from
## a non-completing tap, leaving the loop's main payoff unmarked.
##
## Two separate players so an active tap-catch and a passive net catch
## are distinct VOICES that don't stop()/play() over each other's tail:
##   _catch_player      — active tap catch: full volume, brighter 1.15 pitch
##   _auto_catch_player — passive net catch: quieter, mellower 0.9 pitch
var _catch_player: AudioStreamPlayer
var _auto_catch_player: AudioStreamPlayer
## Seed one interval in the past so the very first net catch always chimes
## regardless of process uptime (avoids a cold-start drop in the first
## _AUTO_CATCH_CHIME_MIN_MS of the session).
var _last_auto_chime_ms: int = -_AUTO_CATCH_CHIME_MIN_MS

## Test seams (mirrors HapticManager). Always updated, even headless, so
## the catch-audio routing + throttle are assertable without real output.
var catch_sfx_count: int = 0        # full-volume tap-catch chimes
var auto_catch_sfx_count: int = 0   # reduced-volume net-catch chimes that PLAYED
var auto_catch_throttled_count: int = 0  # net chimes suppressed by the throttle


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
	# Shiny + tier-up stings: same WAV, different pitch_scale. Crude but it
	# differentiates the moment without shipping new audio assets.
	_shiny_player = AudioStreamPlayer.new()
	_shiny_player.name = "ShinyPlayer"
	_shiny_player.stream = stream
	_shiny_player.volume_db = Settings.sfx_db + 4.0
	_shiny_player.pitch_scale = 1.6
	add_child(_shiny_player)
	_tier_up_player = AudioStreamPlayer.new()
	_tier_up_player.name = "TierUpPlayer"
	_tier_up_player.stream = stream
	_tier_up_player.volume_db = Settings.sfx_db + 6.0
	_tier_up_player.pitch_scale = 0.7
	add_child(_tier_up_player)
	# Phase 10b: miss-tap soft acknowledge — same source WAV, lower volume,
	# slightly higher pitch so it reads as "registered, but no reward".
	_miss_tap_player = AudioStreamPlayer.new()
	_miss_tap_player.name = "MissTapPlayer"
	_miss_tap_player.stream = stream
	_miss_tap_player.volume_db = Settings.sfx_db - 8.0
	_miss_tap_player.pitch_scale = 1.3
	add_child(_miss_tap_player)
	# v0.15.10: the active "caught!" chime — brighter 1.15 pitch (≈+2.4
	# semitones) so the success transient reads distinctly from the tap
	# (1.0) that completed it. Pitch map: tier-up 0.7 · net-catch 0.9 ·
	# tap 1.0 · catch 1.15 · miss 1.3 · shiny 1.6 — all distinct.
	_catch_player = AudioStreamPlayer.new()
	_catch_player.name = "CatchPlayer"
	_catch_player.stream = stream
	_catch_player.volume_db = Settings.sfx_db + 1.0
	_catch_player.pitch_scale = 1.15
	add_child(_catch_player)
	# v0.15.10: the passive idle/net catch chime — a separate player (so a
	# background net catch can't stop()/play() over an in-flight tap-catch)
	# at a mellower 0.9 pitch + reduced volume, so passive earning reads as
	# softer/lower than an active tap-catch rather than relying on volume
	# alone. Throttled in play_auto_catch_sfx so a fast net doesn't
	# machine-gun the speaker.
	_auto_catch_player = AudioStreamPlayer.new()
	_auto_catch_player.name = "AutoCatchPlayer"
	_auto_catch_player.stream = stream
	_auto_catch_player.volume_db = Settings.sfx_db - 6.0
	_auto_catch_player.pitch_scale = 0.9
	add_child(_auto_catch_player)


func play_tap_sfx() -> void:
	if _sfx_muted():
		return
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
##
## v0.12.0 (Phase 12a): also applies `Settings.audio_master_db` to
## the AudioServer's Master bus so the master-volume slider in
## Settings actually does something.
func _apply_volumes() -> void:
	var master_idx: int = AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_volume_db(master_idx, Settings.audio_master_db)
	if _music_player != null:
		_music_player.volume_db = Settings.music_db
	for p in _sfx_pool:
		p.volume_db = Settings.sfx_db
	if _shiny_player != null:
		_shiny_player.volume_db = Settings.sfx_db + 4.0
	if _tier_up_player != null:
		_tier_up_player.volume_db = Settings.sfx_db + 6.0
	if _miss_tap_player != null:
		_miss_tap_player.volume_db = Settings.sfx_db - 8.0
	if _catch_player != null:
		_catch_player.volume_db = Settings.sfx_db + 1.0
	if _auto_catch_player != null:
		_auto_catch_player.volume_db = Settings.sfx_db - 6.0


## v0.15.10 — full-volume "caught!" chime for an active (tap) catch.
## Player-rate-limited by catch frequency, so no throttle. Restart-on-play
## (like the shiny sting) keeps rapid tap-catches responsive.
func play_catch_sfx() -> void:
	if _sfx_muted():
		return
	catch_sfx_count += 1
	if _catch_player == null:
		return
	_catch_player.stop()
	_catch_player.play()


## v0.15.10 — quieter, lower-pitched "caught" for an idle/net auto-catch,
## throttled to `_AUTO_CATCH_CHIME_MIN_MS` so a fast net (which can resolve
## several catches in a single frame) batches into one audible chime
## instead of machine-gunning. Uses its own player so it never clips an
## in-flight tap-catch.
func play_auto_catch_sfx() -> void:
	if _sfx_muted():
		return
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_auto_chime_ms < _AUTO_CATCH_CHIME_MIN_MS:
		auto_catch_throttled_count += 1
		return
	_last_auto_chime_ms = now_ms
	auto_catch_sfx_count += 1
	if _auto_catch_player == null:
		return
	_auto_catch_player.stop()
	_auto_catch_player.play()


## v0.15.10 — true SFX mute. Settings labels sfx_db at the MIN_DB floor as
## "Muted", but there is no SFX bus to mute — players are volume-only — so
## pre-fix every SFX still leaked at ≈-40 dB. Gate every play() on this so
## "Muted" actually silences SFX (music has its own slider).
func _sfx_muted() -> bool:
	return Settings.sfx_db <= Settings.MIN_DB + 0.01


## Reset the catch-audio test counters + throttle clock. Called from
## before_each in the catch-audio tests so each starts clean. Live
## gameplay never calls this.
func reset_test_counters() -> void:
	catch_sfx_count = 0
	auto_catch_sfx_count = 0
	auto_catch_throttled_count = 0
	# Match the live cold-start seed so the first net catch after a reset
	# always passes the throttle (tests run well past 150 ms of uptime).
	_last_auto_chime_ms = -_AUTO_CATCH_CHIME_MIN_MS


func play_shiny_sting() -> void:
	if _sfx_muted():
		return
	if _shiny_player != null:
		_shiny_player.stop()
		_shiny_player.play()


func play_tier_up_sting() -> void:
	if _sfx_muted():
		return
	if _tier_up_player != null:
		_tier_up_player.stop()
		_tier_up_player.play()


## Phase 10b: tap that hit empty space. Soft so it doesn't compete with
## the real catch SFX, but audible so the player knows the tap registered.
func play_miss_tap_sfx() -> void:
	if _sfx_muted():
		return
	if _miss_tap_player == null:
		return
	# Don't pre-empt itself — rapid miss-taps should layer naturally rather
	# than each one cutting the previous off.
	if _miss_tap_player.playing:
		return
	_miss_tap_player.play()


# region — EventBus handlers

func _on_monster_tapped(_monster_id: String, _instance_id: int) -> void:
	play_tap_sfx()


func _on_monster_caught(_monster_id: String, _instance_id: int, is_shiny: bool, source: String) -> void:
	# v0.15.10 — mark the catch (the loop's main payoff). Pre-fix only a
	# shiny made a sound here, so a normal catch was indistinguishable
	# from a non-completing tap. Now:
	#   - shiny (any source): the brighter shiny sting IS the catch sound
	#   - normal TAP catch:   full-volume "caught!" chime
	#   - normal NET catch:   quieter, throttled chime so idle play is
	#                         audible without machine-gunning
	if is_shiny:
		play_shiny_sting()
	elif source == "tap":
		play_catch_sfx()
	else:
		play_auto_catch_sfx()


func _on_first_shiny_caught(_monster_id: String) -> void:
	# First shiny is also covered by monster_caught above; keep the hook here
	# for future Phase 5 polish (e.g. chord stack on the very first one).
	pass


func _on_tier_completed(_tier: int) -> void:
	play_tier_up_sting()


func _on_upgrade_purchased(_upgrade_id: String) -> void:
	pass

# endregion
