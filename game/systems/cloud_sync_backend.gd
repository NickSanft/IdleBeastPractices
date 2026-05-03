## Abstract backend for cloud-save sync. Mirrors the AdsBackend pattern.
##
## Concrete impls:
##   - StubCloudSyncBackend  (Phase 7a) — records calls, no network.
##   - PlayGamesCloudBackend (Phase 7b) — wraps the Google Play Games
##     Services Saved Games API on Android.
##
## Sync flow (orchestrator's responsibility, not the backend's):
##   1. on_login_complete:        download() -> resolve(local, remote) -> apply
##   2. on_state_change_committed: upload(state)
##   3. on_signed_out:            no-op (local-only mode)
##
## All operations are async — callers listen to the signals.
class_name CloudSyncBackend
extends RefCounted

## Sign-in lifecycle: emitted by the platform-specific impl when the
## auth flow completes (success/failure).
signal sign_in_complete(success: bool, error: String)
signal sign_out_complete()

## Upload result for the last `upload(...)` call. `success=false` with a
## non-empty `error` means the orchestrator should retry on the next
## sync window. `error=""` on success.
signal upload_complete(success: bool, error: String)

## Download result. `data` is a save-shaped Dictionary identical in
## structure to GameState.to_dict() output (suitable for passing to
## SaveConflictResolver.resolve()) when `success=true`. When `success=false`
## (e.g. no remote save exists yet), `data` is empty.
signal download_complete(data: Dictionary, success: bool, error: String)


## Returns true if the backend is functional on this platform/build
## (e.g. Play Games Services plugin is loaded). Stub returns true.
func is_available() -> bool:
	return false


## Returns true if the user is authenticated and uploads/downloads can
## proceed. Default false until `sign_in()` succeeds.
func is_signed_in() -> bool:
	return false


## Trigger the platform's sign-in flow. Async — listen to
## `sign_in_complete`.
func sign_in() -> void:
	push_error("CloudSyncBackend.sign_in: not implemented")
	sign_in_complete.emit(false, "not_implemented")


func sign_out() -> void:
	push_error("CloudSyncBackend.sign_out: not implemented")
	sign_out_complete.emit()


## Push the given state dict to the cloud. Async — listen to
## `upload_complete`. The orchestrator calls this after a save commits
## locally; the backend MUST NOT mutate `state`.
func upload(state: Dictionary) -> void:
	push_error("CloudSyncBackend.upload: not implemented")
	upload_complete.emit(false, "not_implemented")


## Fetch the latest cloud-side state. Async — listen to
## `download_complete`. The orchestrator passes the result through
## SaveConflictResolver.resolve(local, remote) and applies the merged dict.
func download() -> void:
	push_error("CloudSyncBackend.download: not implemented")
	download_complete.emit({}, false, "not_implemented")
