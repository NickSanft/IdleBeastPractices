## Lazily scans game/data/ on first access and indexes Resources by id.
##
## Static-state class (call init() once at game start). Lookups are O(1).
## Phase 1 indexes monsters, items, and nets; later phases add upgrades,
## recipes, dialogue lines, pets.
class_name ContentRegistry
extends RefCounted

const _MONSTERS_DIR := "res://game/data/monsters"
const _ITEMS_DIR := "res://game/data/items"
const _NETS_DIR := "res://game/data/nets"

static var _monsters_by_id: Dictionary = {}   # StringName -> MonsterResource
static var _items_by_id: Dictionary = {}      # StringName -> ItemResource
static var _nets_by_id: Dictionary = {}       # StringName -> NetResource
static var _initialized: bool = false


static func ensure_loaded() -> void:
	if _initialized:
		return
	_load_dir(_MONSTERS_DIR, _monsters_by_id)
	_load_dir(_ITEMS_DIR, _items_by_id)
	_load_dir(_NETS_DIR, _nets_by_id)
	_initialized = true


static func _load_dir(dir_path: String, target: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("ContentRegistry: directory not found: %s" % dir_path)
		return
	dir.list_dir_begin()
	while true:
		var entry: String = dir.get_next()
		if entry == "":
			break
		if dir.current_is_dir():
			continue
		# Godot stores .tres source files alongside .tres.remap when exported;
		# both load via the same path. .import is editor metadata, skip.
		if not entry.ends_with(".tres") and not entry.ends_with(".tres.remap") and not entry.ends_with(".res"):
			continue
		# Strip .remap suffix so load() resolves correctly in exported builds.
		if entry.ends_with(".remap"):
			entry = entry.trim_suffix(".remap")
		var full_path: String = "%s/%s" % [dir_path, entry]
		var res: Resource = load(full_path)
		if res == null:
			continue
		var id_value: Variant = res.get("id")
		if id_value == null:
			continue
		target[StringName(id_value)] = res
	dir.list_dir_end()


static func monsters() -> Array[MonsterResource]:
	ensure_loaded()
	var out: Array[MonsterResource] = []
	for id in _monsters_by_id.keys():
		out.append(_monsters_by_id[id])
	return out


static func monster(id: StringName) -> MonsterResource:
	ensure_loaded()
	return _monsters_by_id.get(id)


static func items() -> Array[ItemResource]:
	ensure_loaded()
	var out: Array[ItemResource] = []
	for id in _items_by_id.keys():
		out.append(_items_by_id[id])
	return out


static func item(id: StringName) -> ItemResource:
	ensure_loaded()
	return _items_by_id.get(id)


static func nets() -> Array[NetResource]:
	ensure_loaded()
	var out: Array[NetResource] = []
	for id in _nets_by_id.keys():
		out.append(_nets_by_id[id])
	return out


static func net(id: StringName) -> NetResource:
	ensure_loaded()
	return _nets_by_id.get(id)
