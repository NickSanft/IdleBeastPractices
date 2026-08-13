## Versioned JSON save with migration chain and pluggable backend.
##
## Phase 0: only LocalFileBackend exists. Phase 7 swaps in CloudBackend.
## CURRENT_VERSION must increment whenever the on-disk schema changes;
## a matching migration must be registered in save_migrations.gd.
extends Node

const CURRENT_VERSION := 5

var backend: SaveBackend = LocalFileBackend.new()

## True when a save EXISTED but could not be used — an unreadable/empty file,
## unparseable JSON, or a version newer than this build.
##
## load_save() returns {} for that case AND for a genuine first launch, and the
## two must not be confused: {} flows into GameState.from_dict, which seeds a
## brand-new ranch, and the periodic autosave then overwrites the original
## within seconds. Before this flag the loader failed OPEN — a corrupt file
## silently became "new player, no progress". Callers check this to tell the
## player; the save file itself is moved aside by `quarantine()`, never deleted.
var load_failed: bool = false
var load_failure_reason: String = ""
## Where the unusable save was preserved, or "" if it could not be moved.
var quarantined_path: String = ""

## True when the live state was SEEDED from defaults rather than loaded from a
## real save — a first launch, a quarantined save, or a deliberate wipe.
##
## Matters because `last_saved_unix` is now honest: the 10-second autosave
## stamps even a defaults-only ranch with `now`, so on a reinstall the seeded
## session would out-timestamp the Play Games snapshot it is about to download
## and win SaveConflictResolver's base pick — precisely inverting "restore my
## progress on a new phone". CloudSyncManager consults this to keep a seeded
## session from outranking real history. Cleared once a genuine save loads.
var state_is_seeded: bool = false


func load_save() -> Dictionary:
	load_failed = false
	load_failure_reason = ""
	quarantined_path = ""
	if not backend.exists():
		# First launch — return an empty dict; GameState seeds defaults.
		state_is_seeded = true
		return {}
	var raw := backend.read()
	if raw.is_empty():
		return _fail_load("save file was empty or unreadable")
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return _fail_load("save file is not a JSON object")
	var data: Dictionary = parsed
	var version: int = int(data.get("version", 0))
	if version > CURRENT_VERSION:
		return _fail_load("save version %d is newer than client version %d"
				% [version, CURRENT_VERSION])
	if version < CURRENT_VERSION:
		data = SaveMigrations.apply_chain(data, CURRENT_VERSION)
	state_is_seeded = false
	EventBus.game_loaded.emit()
	return data


## Record an unusable save and move it out of the way. Returns {} so callers
## still get first-launch defaults — but with `load_failed` set, so the reset
## is visible to the player instead of silent, and the original bytes survive
## on disk for recovery.
func _fail_load(reason: String) -> Dictionary:
	load_failed = true
	load_failure_reason = reason
	# The state that replaces it is defaults, carrying no history — it must not
	# outrank a real cloud snapshot on timestamp alone.
	state_is_seeded = true
	push_error("SaveManager.load_save: %s" % reason)
	quarantined_path = backend.quarantine()
	if quarantined_path != "":
		push_warning("SaveManager: previous save preserved at %s" % quarantined_path)
	else:
		push_warning("SaveManager: could not preserve the unusable save")
	return {}


## Returns true when the bytes were committed. The result matters: main's
## resume tick relies on this call advancing the "last credited at" marker, and
## that only happens on success — so a caller that discards the outcome will
## silently re-credit the same offline window on every resume while writes are
## failing. Deliberately no fake-advance on failure: the in-memory stamp must
## keep matching disk.
func save(state: Dictionary) -> bool:
	var to_write: Dictionary = state.duplicate(true)
	to_write["version"] = CURRENT_VERSION
	to_write["last_saved_unix"] = Time.get_unix_time_from_system()
	var json_str := JSON.stringify(to_write)
	if backend.write(json_str):
		# Keep the in-memory stamp in step with disk. Two things read it and
		# both were wrong without this: SaveConflictResolver picks the merge
		# BASE by last_saved_unix (and CloudSyncManager feeds it
		# GameState.to_dict()), so a stale field let an older cloud snapshot
		# beat a device that had just played — worst case a fresh install holds
		# 0 all session and its first sync discards everything; and main's
		# resume tick uses it as the "last credited at" marker for offline
		# progress.
		#
		# Deliberately Time.get_unix_time_from_system() and NOT
		# TimeManager.now_unix(): tests set future clock overrides, and this
		# value goes to disk.
		GameState.last_saved_unix = int(to_write["last_saved_unix"])
		EventBus.game_saved.emit()
		return true
	return false


## Reset save state to first-launch defaults.
##
## Steps:
##   1. Delete the persisted save (LocalFileBackend wipes both
##      user://save.json and the .tmp from any interrupted prior write).
##   2. Reset GameState in-memory to its defaults via from_dict({}).
##   3. Persist the empty defaults so a quit-without-saving doesn't
##      restore the prior data via OS swap.
##   4. Emit `game_loaded` so subscribers (currency_bar, bestiary view,
##      narrator overlay state, etc.) refresh from the new state.
##
## Returns true on success. The caller is responsible for confirming
## with the user — this method does not prompt.
func clear_save() -> bool:
	if not backend.clear():
		return false
	# A deliberate wipe is a seeded state too — the save that follows carries no
	# history and must not outrank a cloud snapshot purely on its timestamp.
	state_is_seeded = true
	GameState.from_dict({})
	# Persist the cleared state immediately so a hard quit before
	# the next save tick can't surface the prior save.
	save(GameState.to_dict())
	EventBus.game_loaded.emit()
	return true
