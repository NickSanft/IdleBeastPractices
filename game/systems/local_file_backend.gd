## SaveBackend that persists to user://save.json with atomic writes.
##
## Atomicity: write to user://save.json.tmp, VERIFY it, then rename over
## save.json. The verification is load-bearing, not belt-and-braces —
## `store_string` reports nothing, so a full disk or a failing card produced a
## silently truncated .tmp that the rename then promoted over the good save,
## with `write()` still returning true. That is the one code path in the game
## that can manufacture total progress loss, so it fails closed: on any doubt
## the .tmp is discarded and save.json is never touched.
class_name LocalFileBackend
extends SaveBackend

const SAVE_PATH := "user://save.json"
const TMP_PATH := "user://save.json.tmp"


func read() -> String:
	if FileAccess.file_exists(SAVE_PATH):
		return _read_path(SAVE_PATH)
	# save.json is gone but a .tmp survives — a crash inside write()'s rename
	# window (or on a platform that needed the remove-then-rename fallback).
	# Recovering it beats reporting "no save": SaveManager parses the result,
	# so a truncated .tmp is caught and quarantined rather than trusted.
	if FileAccess.file_exists(TMP_PATH):
		push_warning("LocalFileBackend.read: %s missing; recovering %s" % [SAVE_PATH, TMP_PATH])
		return _read_path(TMP_PATH)
	return ""


func write(data: String) -> bool:
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		push_error("LocalFileBackend.write: failed to open %s for writing" % TMP_PATH)
		return false
	f.store_string(data)
	# flush() forces the buffered bytes out so get_error() reflects the real
	# write rather than a not-yet-attempted one.
	f.flush()
	var write_err: Error = f.get_error()
	f.close()
	if write_err != OK:
		push_error("LocalFileBackend.write: store failed (err=%d); keeping the previous save" % write_err)
		_discard_tmp()
		return false
	# This is the LOAD-BEARING guard on Android, not a nicety: FileAccessUnix's
	# flush() is a bare fflush and close() a bare fclose, and neither folds its
	# result into last_error — so a full disk frequently reports get_error() ==
	# OK. Compare bytes on disk against bytes intended. Never optimise away.
	var expected: int = data.to_utf8_buffer().size()
	var actual: int = _file_size(TMP_PATH)
	if actual != expected:
		push_error("LocalFileBackend.write: short write (%d of %d bytes); keeping the previous save"
				% [actual, expected])
		_discard_tmp()
		return false
	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("LocalFileBackend.write: failed to open user:// directory")
		_discard_tmp()
		return false
	var tmp_name: String = TMP_PATH.get_file()
	var save_name: String = SAVE_PATH.get_file()
	# Rename straight over the target. On POSIX/Android that is a single atomic
	# step with no window in which neither file exists. On WINDOWS it is not:
	# DirAccessWindows::rename removes the destination first, so a rename that
	# then fails with the source locked leaves save.json missing and the .tmp
	# intact — which is exactly why read()/exists() recover a lone .tmp, and why
	# that state self-heals on the next autosave instead of losing the save.
	# The fallback below earns its keep only on Windows with a locked
	# DESTINATION; on POSIX it is unreachable in practice.
	#
	# "Atomic" here means atomic against process kill (the real Android risk),
	# NOT against power loss — Godot exposes no fsync.
	var err := dir.rename(tmp_name, save_name)
	if err != OK:
		if dir.file_exists(save_name):
			dir.remove(save_name)
		err = dir.rename(tmp_name, save_name)
	if err != OK:
		push_error("LocalFileBackend.write: rename failed (err=%d)" % err)
		return false
	return true


## Move the current save aside instead of letting it be overwritten. Used by
## SaveManager when a file exists but cannot be used (corrupt, or written by a
## newer build). Returns the new path, or "" if nothing was moved.
func quarantine() -> String:
	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("LocalFileBackend.quarantine: failed to open user:// directory")
		return ""
	var save_name: String = SAVE_PATH.get_file()
	var tmp_name: String = TMP_PATH.get_file()
	var target: String = "%s.bak-%d" % [save_name, int(Time.get_unix_time_from_system())]
	var moved: String = ""
	if dir.file_exists(save_name) and dir.rename(save_name, target) == OK:
		moved = "user://%s" % target
	# Whatever happens, a .tmp must not survive. An UNCOMMITTED .tmp is never
	# trustworthy — write() truncates it at open, so any kill before the
	# verification steps leaves a partial file — and quarantine() has no parser
	# to tell partial from whole. (It also stops read() "recovering" the same
	# unusable bytes on every subsequent boot.)
	if dir.file_exists(tmp_name):
		if moved == "" and dir.rename(tmp_name, target) == OK:
			moved = "user://%s" % target
		elif dir.file_exists(tmp_name):
			dir.remove(tmp_name)
	return moved


func _read_path(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("LocalFileBackend.read: failed to open %s" % path)
		return ""
	var contents := f.get_as_text()
	f.close()
	return contents


func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var n: int = f.get_length()
	f.close()
	return n


func _discard_tmp() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	var tmp_name: String = TMP_PATH.get_file()
	if dir.file_exists(tmp_name):
		dir.remove(tmp_name)


## True when anything restorable is on disk — including a lone .tmp, which
## read() knows how to recover. Reporting false there would send SaveManager
## down the first-launch path and strand a recoverable save.
func exists() -> bool:
	return FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(TMP_PATH)


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
