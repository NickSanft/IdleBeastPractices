## Versioned JSON save with migration chain and pluggable backend.
##
## Phase 0: only LocalFileBackend exists. Phase 7 swaps in CloudBackend.
## CURRENT_VERSION must increment whenever the on-disk schema changes;
## a matching migration must be registered in save_migrations.gd.
extends Node

const CURRENT_VERSION := 2

var backend: SaveBackend = LocalFileBackend.new()


func load_save() -> Dictionary:
	if not backend.exists():
		# First launch — return an empty dict; GameState seeds defaults.
		return {}
	var raw := backend.read()
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		push_error("SaveManager.load_save: save file is not a JSON object")
		return {}
	var data: Dictionary = parsed
	var version: int = int(data.get("version", 0))
	if version > CURRENT_VERSION:
		push_error("SaveManager.load_save: save version %d is newer than client version %d" % [version, CURRENT_VERSION])
		return {}
	if version < CURRENT_VERSION:
		data = SaveMigrations.apply_chain(data, CURRENT_VERSION)
	EventBus.game_loaded.emit()
	return data


func save(state: Dictionary) -> void:
	var to_write: Dictionary = state.duplicate(true)
	to_write["version"] = CURRENT_VERSION
	to_write["last_saved_unix"] = Time.get_unix_time_from_system()
	var json_str := JSON.stringify(to_write)
	if backend.write(json_str):
		EventBus.game_saved.emit()


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
	GameState.from_dict({})
	# Persist the cleared state immediately so a hard quit before
	# the next save tick can't surface the prior save.
	save(GameState.to_dict())
	EventBus.game_loaded.emit()
	return true
