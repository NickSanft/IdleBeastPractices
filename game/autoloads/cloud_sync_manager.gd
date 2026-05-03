## Orchestrates cloud-side save sync via a CloudSyncBackend.
##
## On Android with the godot-play-game-services plugin loaded, picks
## PlayGamesCloudBackend; everywhere else (editor, Windows, Web,
## headless CI) the backend is `null` and every method short-circuits.
##
## Lifecycle:
##   1. _ready: create backend; plugin auto-attempts auth in the
##      background, so user_authenticated may fire shortly after.
##   2. On first successful sign-in: download remote state, merge with
##      local via SaveConflictResolver, write merged back to local.
##   3. Subscribed to EventBus.game_saved: each save triggers a
##      debounced cloud upload (rapid saves only push once).
##
## Status is exposed via `status` + `status_changed(status)` signal so
## the Settings UI can show "Syncing… / Idle / Error" feedback.
extends Node

signal status_changed(status: String)

const STATUS_DISABLED := "disabled"        # Backend null (non-Android, no plugin)
const STATUS_SIGNED_OUT := "signed_out"    # Backend present, not authenticated
const STATUS_DOWNLOADING := "downloading"  # Initial sync pulling remote
const STATUS_UPLOADING := "uploading"      # Pushing local after a save
const STATUS_IDLE := "idle"                # Authenticated, no sync in flight
const STATUS_ERROR := "error"              # Last op failed; see last_error

const _UPLOAD_DEBOUNCE_SECONDS := 5.0

var backend: CloudSyncBackend
var status: String = STATUS_DISABLED
var last_error: String = ""

var _initial_sync_done: bool = false
var _upload_timer: SceneTreeTimer
var _upload_pending: bool = false


func _ready() -> void:
	# Backend selection mirrors AdsManager / Phase 6b: pick the real
	# Android backend when the PGS plugin is loaded, else stay disabled.
	# Editor / desktop / web exports never instantiate the real backend
	# because PGS isn't available outside Android.
	if PlayGamesCloudBackend.is_plugin_loaded():
		backend = PlayGamesCloudBackend.new()
	else:
		backend = null
		return
	backend.sign_in_complete.connect(_on_sign_in_complete)
	backend.sign_out_complete.connect(_on_sign_out_complete)
	backend.upload_complete.connect(_on_upload_complete)
	backend.download_complete.connect(_on_download_complete)
	# Each successful local save -> debounced cloud upload.
	EventBus.game_saved.connect(_on_local_save_committed)
	_set_status(STATUS_SIGNED_OUT)


## Returns true if we have a real backend that can be signed into.
## False on platforms without the PGS plugin (editor, desktop, web).
func is_available() -> bool:
	return backend != null and backend.is_available()


## True iff user is currently signed in to Google Play Games.
func is_signed_in() -> bool:
	return backend != null and backend.is_signed_in()


## Trigger sign-in. Idempotent — if already signed in, no-op. Bound to
## the Settings tab "Sign in" button.
func sign_in() -> void:
	if backend == null:
		return
	if backend.is_signed_in():
		return
	backend.sign_in()


## Sign out (just flips local flag — the PGS plugin doesn't expose a
## true sign-out, that's done from the Play Games app).
func sign_out() -> void:
	if backend == null:
		return
	backend.sign_out()


func _on_sign_in_complete(success: bool, error: String) -> void:
	if not success:
		last_error = error
		_set_status(STATUS_ERROR)
		return
	last_error = ""
	# First successful sign-in this session triggers the initial pull.
	# Subsequent sign_in calls (idempotent) skip the merge step.
	if not _initial_sync_done:
		_set_status(STATUS_DOWNLOADING)
		backend.download()
	else:
		_set_status(STATUS_IDLE)


func _on_sign_out_complete() -> void:
	_initial_sync_done = false
	_set_status(STATUS_SIGNED_OUT)


func _on_download_complete(remote: Dictionary, success: bool, error: String) -> void:
	if not success:
		last_error = error
		# A "no_snapshot" or empty download is success=true with empty
		# data; only real failures land here.
		_set_status(STATUS_ERROR)
		return
	# Merge remote with local. Empty remote (fresh device) returns local
	# unchanged via SaveConflictResolver's empty-input handling.
	var local: Dictionary = GameState.to_dict()
	var merged: Dictionary = SaveConflictResolver.resolve(local, remote)
	GameState.from_dict(merged)
	SaveManager.save(merged)
	_initial_sync_done = true
	last_error = ""
	_set_status(STATUS_IDLE)


func _on_upload_complete(success: bool, error: String) -> void:
	if success:
		last_error = ""
		_set_status(STATUS_IDLE)
	else:
		last_error = error
		_set_status(STATUS_ERROR)


## Hooked to EventBus.game_saved (fires inside SaveManager.save()).
## Schedules a debounced upload — rapid back-to-back saves coalesce
## into one cloud push after _UPLOAD_DEBOUNCE_SECONDS of quiet.
func _on_local_save_committed() -> void:
	if backend == null or not backend.is_signed_in():
		return
	if not _initial_sync_done:
		# Don't upload before the initial pull-merge — we'd be pushing
		# a pre-merge local state and risk overwriting a richer cloud.
		return
	_upload_pending = true
	if _upload_timer != null and _upload_timer.time_left > 0:
		return  # Existing timer will trigger; coalesce.
	_upload_timer = get_tree().create_timer(_UPLOAD_DEBOUNCE_SECONDS)
	_upload_timer.timeout.connect(_flush_pending_upload)


func _flush_pending_upload() -> void:
	if not _upload_pending:
		return
	_upload_pending = false
	if backend == null or not backend.is_signed_in():
		return
	_set_status(STATUS_UPLOADING)
	backend.upload(GameState.to_dict())


func _set_status(new_status: String) -> void:
	if status == new_status:
		return
	status = new_status
	status_changed.emit(new_status)
