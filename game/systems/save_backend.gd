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
