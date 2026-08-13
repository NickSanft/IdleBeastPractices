## Abstract storage backend for the save system.
##
## Implementations:
##   - LocalFileBackend  (Phase 0): writes to user://save.json
##   - CloudBackend      (Phase 7): Play Games Services / iCloud
##
## SaveManager swaps backends in one line.
class_name SaveBackend
extends RefCounted


func read() -> String:
	push_error("SaveBackend.read() not implemented")
	return ""


func write(_data: String) -> bool:
	push_error("SaveBackend.write() not implemented")
	return false


func exists() -> bool:
	push_error("SaveBackend.exists() not implemented")
	return false


## Permanently remove the persisted save. Returns true if the backend
## successfully cleared its store (or there was nothing to clear).
## Implementations: LocalFileBackend deletes the on-disk JSON;
## CloudBackend (Phase 7) is expected to clear the remote object too.
func clear() -> bool:
	push_error("SaveBackend.clear() not implemented")
	return false


## Move the persisted save aside so a file that exists but cannot be used
## (corrupt, or written by a newer build) is preserved for recovery rather
## than silently overwritten by the fresh state that replaces it. Returns the
## new location, or "" when nothing was moved. Defaults to a no-op so backends
## with no cheap "move aside" primitive simply opt out — SaveManager treats ""
## as "not preserved" and still refuses to trust the unusable data.
func quarantine() -> String:
	return ""
