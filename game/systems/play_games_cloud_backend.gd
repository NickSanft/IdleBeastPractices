## CloudSyncBackend impl backed by Google Play Games Services Saved Games.
## Wraps the godot-sdk-integrations/godot-play-game-services plugin
## (vendored at addons/GodotPlayGameServices/, exposes the
## `GodotPlayGameServices` autoload + `PlayGamesSignInClient` /
## `PlayGamesSnapshotsClient` Node classes).
##
## Selected over StubCloudSyncBackend when:
##   OS.get_name() == "Android" AND Engine.has_singleton("GodotPlayGameServices")
##
## Save format: GameState.to_dict() -> JSON string -> UTF-8 bytes ->
## passed as PackedByteArray to Snapshots.save_game().
class_name PlayGamesCloudBackend
extends CloudSyncBackend

const _SAVE_NAME := "main_save"
const _SAVE_DESCRIPTION := "IdleBeastPractices progress"
const _PLUGIN_SINGLETON := "GodotPlayGameServices"

var _sign_in_client: PlayGamesSignInClient
var _snapshots_client: PlayGamesSnapshotsClient
var _plugin_initialized: bool = false
## Set to true once the auto-attempted authentication on plugin init has
## reported back. Until then is_signed_in() returns false even if the
## user happened to be authenticated in a prior session, because we
## don't know yet.
var _initial_auth_check_complete: bool = false
var _is_authenticated: bool = false


static func is_plugin_loaded() -> bool:
	return Engine.has_singleton(_PLUGIN_SINGLETON)


func _init() -> void:
	if not is_plugin_loaded():
		return
	# Initialize the plugin (idempotent — the autoload's initialize() is
	# safe to call multiple times). Do this before constructing the
	# clients so they can wire their signal forwards.
	GodotPlayGameServices.initialize()
	_plugin_initialized = true

	_sign_in_client = PlayGamesSignInClient.new()
	_snapshots_client = PlayGamesSnapshotsClient.new()

	_sign_in_client.user_authenticated.connect(_on_user_authenticated)
	_snapshots_client.game_saved.connect(_on_game_saved)
	_snapshots_client.game_loaded.connect(_on_game_loaded)
	_snapshots_client.conflict_emitted.connect(_on_conflict_emitted)

	# Plugin auto-checks auth on startup; the result lands as a
	# user_authenticated signal we forward via _on_user_authenticated.
	_sign_in_client.is_authenticated()


func is_available() -> bool:
	return _plugin_initialized


func is_signed_in() -> bool:
	return _is_authenticated


func sign_in() -> void:
	if not _plugin_initialized:
		sign_in_complete.emit.call_deferred(false, "no_plugin")
		return
	# Plugin's sign_in() pops the native account picker (or silently
	# completes if a previously-authorized account exists). Result lands
	# as user_authenticated.
	_sign_in_client.sign_in()


func sign_out() -> void:
	# The plugin doesn't expose an explicit sign-out — Google Play Games
	# only offers sign-out via the Play Games app UI. We just flip our
	# local flag so the orchestrator stops attempting uploads/downloads.
	_is_authenticated = false
	sign_out_complete.emit.call_deferred()


func upload(state: Dictionary) -> void:
	if not _plugin_initialized:
		upload_complete.emit.call_deferred(false, "no_plugin")
		return
	if not _is_authenticated:
		upload_complete.emit.call_deferred(false, "not_signed_in")
		return
	var json_str: String = JSON.stringify(state)
	var bytes: PackedByteArray = json_str.to_utf8_buffer()
	# played_time_millis = 0 since we don't track wall-clock per save;
	# progress_value 0 same reason. The plugin uses these for its native
	# saved-games picker UI, which we don't surface in our flow.
	_snapshots_client.save_game(_SAVE_NAME, _SAVE_DESCRIPTION, bytes, 0, 0)


func download() -> void:
	if not _plugin_initialized:
		download_complete.emit.call_deferred({}, false, "no_plugin")
		return
	if not _is_authenticated:
		download_complete.emit.call_deferred({}, false, "not_signed_in")
		return
	# create_if_not_found=true so a fresh device with no cloud save yet
	# doesn't trigger an error — the plugin returns an empty snapshot
	# which we deserialize as an empty dict.
	_snapshots_client.load_game(_SAVE_NAME, true)


func _on_user_authenticated(authenticated: bool) -> void:
	_is_authenticated = authenticated
	if not _initial_auth_check_complete:
		_initial_auth_check_complete = true
		# Plugin auto-checks auth at startup. If the user is already
		# signed in (cached from a previous session), trigger the
		# initial sync. If they're NOT signed in, swallow the result
		# silently — the Settings UI will show "Sign in to Google Play
		# Games" and the user can opt in. Otherwise every cold start
		# without an account would surface as a "sign-in failed" error.
		if authenticated:
			sign_in_complete.emit(true, "")
		return
	# Explicit sign_in() call — surface the result either way.
	sign_in_complete.emit(authenticated, "" if authenticated else "auth_failed")


func _on_game_saved(is_saved: bool, _save_name: String, _description: String) -> void:
	upload_complete.emit(is_saved, "" if is_saved else "save_failed")


func _on_game_loaded(snapshot: PlayGamesSnapshot) -> void:
	if snapshot == null:
		# No snapshot found — fresh device. Emit empty success so the
		# orchestrator treats it as "no remote save yet".
		download_complete.emit({}, true, "")
		return
	var bytes: PackedByteArray = snapshot.content
	if bytes.is_empty():
		download_complete.emit({}, true, "")
		return
	var json_str: String = bytes.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(json_str)
	if not (parsed is Dictionary):
		push_warning("PlayGamesCloudBackend: snapshot content didn't parse as JSON dict")
		download_complete.emit({}, false, "invalid_payload")
		return
	download_complete.emit(parsed, true, "")


func _on_conflict_emitted(_conflict: PlayGamesSnapshotConflict) -> void:
	# A conflict means the cloud has TWO snapshots for the same name and
	# the plugin couldn't auto-resolve. We don't expose dual-snapshot
	# reconciliation yet (Phase 7c could). Surface as a download failure
	# so the orchestrator skips this sync window; local progress stays.
	push_warning("PlayGamesCloudBackend: snapshot conflict — leaving for next sync")
	download_complete.emit({}, false, "conflict")
	upload_complete.emit(false, "conflict")
