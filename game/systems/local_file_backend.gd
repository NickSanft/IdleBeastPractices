## SaveBackend that persists to user://save.json with atomic writes.
##
## Atomicity: write to user://save.json.tmp, then rename. A crash mid-write
## leaves the prior save intact.
class_name LocalFileBackend
extends SaveBackend

const SAVE_PATH := "user://save.json"
const TMP_PATH := "user://save.json.tmp"


func read() -> String:
	if not exists():
		return ""
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_error("LocalFileBackend.read: failed to open %s" % SAVE_PATH)
		return ""
	var contents := f.get_as_text()
	f.close()
	return contents


func write(data: String) -> bool:
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		push_error("LocalFileBackend.write: failed to open %s for writing" % TMP_PATH)
		return false
	f.store_string(data)
	f.close()
	# Atomic rename. DirAccess.rename_absolute requires absolute OS paths;
	# use the user:// equivalent helpers.
	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("LocalFileBackend.write: failed to open user:// directory")
		return false
	if dir.file_exists(SAVE_PATH.get_file()):
		dir.remove(SAVE_PATH.get_file())
	var err := dir.rename(TMP_PATH.get_file(), SAVE_PATH.get_file())
	if err != OK:
		push_error("LocalFileBackend.write: rename failed (err=%d)" % err)
		return false
	return true


func exists() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Delete user://save.json (and any stale .tmp from an interrupted
## prior write). Idempotent: returns true if the file is gone after
## the call, regardless of whether anything was deleted.
func clear() -> bool:
	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("LocalFileBackend.clear: failed to open user:// directory")
		return false
	# Wipe the temp file too — a crash mid-write could have left one
	# behind, and re-saving would surprise-restore it via the rename
	# step in write().
	var tmp_name: String = TMP_PATH.get_file()
	if dir.file_exists(tmp_name):
		dir.remove(tmp_name)
	var save_name: String = SAVE_PATH.get_file()
	if dir.file_exists(save_name):
		var err := dir.remove(save_name)
		if err != OK:
			push_error("LocalFileBackend.clear: remove failed (err=%d)" % err)
			return false
	return not exists()
