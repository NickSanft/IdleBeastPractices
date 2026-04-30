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
