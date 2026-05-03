## Phase 7a stub: in-memory only, no network. Useful for editor / dev
## builds where Play Games Services isn't available, and for tests
## that need to drive the orchestration layer end-to-end without
## stubbing the abstract directly.
##
## Behavior:
##   - is_available() = true
##   - sign_in() succeeds synchronously on the next idle frame
##   - upload(state) records the dict and emits success
##   - download() returns the last uploaded dict (or empty if none),
##     simulating a fresh device pulling the cloud's view
##
## Phase 7b will land PlayGamesCloudBackend that hits the real
## Saved Games API; this stub stays in the codebase as a fallback for
## dev builds.
class_name StubCloudSyncBackend
extends CloudSyncBackend

var _signed_in: bool = false
var _stored_state: Dictionary = {}


func is_available() -> bool:
	return true


func is_signed_in() -> bool:
	return _signed_in


func sign_in() -> void:
	_signed_in = true
	sign_in_complete.emit.call_deferred(true, "")


func sign_out() -> void:
	_signed_in = false
	sign_out_complete.emit.call_deferred()


func upload(state: Dictionary) -> void:
	if not _signed_in:
		upload_complete.emit.call_deferred(false, "not_signed_in")
		return
	_stored_state = state.duplicate(true)
	upload_complete.emit.call_deferred(true, "")


func download() -> void:
	if not _signed_in:
		download_complete.emit.call_deferred({}, false, "not_signed_in")
		return
	# Empty stored state -> first-time sync; return empty (success=true,
	# data={}) so the orchestrator treats it as "no remote save yet" and
	# the local state wins by default in resolve().
	download_complete.emit.call_deferred(_stored_state.duplicate(true), true, "")
