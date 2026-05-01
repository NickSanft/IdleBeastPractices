## Peniber. Listens to EventBus, picks a DialogueLineResource matching the
## trigger, and emits narrator_line_chosen for the overlay UI.
##
## Selection algorithm:
##   1. Filter all loaded lines by trigger_id.
##   2. Drop lines whose conditions don't match (min_total_catches,
##      min_prestige_count).
##   3. Drop lines that have hit max_uses (counted from
##      GameState.narrator_state.lines_seen).
##   4. Drop lines whose id is in the recent-window (last RECENT_WINDOW_SIZE
##      line ids spoken). Anti-clustering for pool triggers.
##   5. Weighted-random pick over the remainder by `weight`.
##
## State the player accumulates (lines_seen) is held on GameState.narrator_state
## and persists across prestige.
extends Node

const RECENT_WINDOW_SIZE := 5
const _IDLE_TRIGGER_SECONDS := 5 * 60.0   # idle-too-long fires after 5 min no input
const _IDLE_COOLDOWN_SECONDS := 90.0      # don't re-fire idle within this window

var _lines_by_trigger: Dictionary = {}    # StringName -> Array[DialogueLineResource]
var _recent: Array[String] = []
var _last_input_time_ms: int = 0
var _last_idle_fire_ms: int = 0
var _initialized: bool = false


func _ready() -> void:
	# Lines are loaded lazily so ContentRegistry has a chance to scan disk.
	EventBus.first_catch_of_species.connect(_on_first_catch_of_species)
	EventBus.monster_caught.connect(_on_monster_caught)
	EventBus.first_shiny_caught.connect(_on_first_shiny_caught)
	EventBus.tier_completed.connect(_on_tier_completed)
	EventBus.pet_acquired.connect(_on_pet_acquired)
	EventBus.battle_ended.connect(_on_battle_ended)
	EventBus.prestige_triggered.connect(_on_prestige_triggered)
	EventBus.offline_progress_calculated.connect(_on_offline_progress_calculated)
	EventBus.upgrade_purchased.connect(_on_upgrade_purchased)
	EventBus.item_crafted.connect(_on_item_crafted)
	EventBus.recipe_unlocked.connect(_on_recipe_unlocked)
	EventBus.game_loaded.connect(_on_game_loaded)
	EventBus.narrator_line_chosen.connect(_on_line_chosen)   # for our own bookkeeping
	_last_input_time_ms = Time.get_ticks_msec()
	set_process_unhandled_input(true)


func _ensure_loaded() -> void:
	if _initialized:
		return
	for line in ContentRegistry.dialogue_lines():
		var key: StringName = line.trigger_id
		if not _lines_by_trigger.has(key):
			_lines_by_trigger[key] = []
		_lines_by_trigger[key].append(line)
	_initialized = true


# region — public selection

## Try to speak a line for `trigger_id`. Returns the line spoken, or null
## if no line is available right now. Mutates GameState.narrator_state.lines_seen
## and the recent-window so subsequent selections respect it.
func try_speak(trigger_id: StringName) -> DialogueLineResource:
	_ensure_loaded()
	var pool: Array = _lines_by_trigger.get(trigger_id, [])
	if pool.is_empty():
		return null
	var lines_seen: Dictionary = GameState.narrator_state.get("lines_seen", {})
	var candidates: Array[DialogueLineResource] = []
	for line in pool:
		if not _conditions_pass(line, lines_seen):
			continue
		if _recent.has(String(line.id)):
			continue
		candidates.append(line)
	if candidates.is_empty():
		return null
	var chosen: DialogueLineResource = _weighted_pick(candidates)
	if chosen != null:
		_record_spoken(chosen)
		EventBus.narrator_line_chosen.emit(String(chosen.id), chosen.text, String(chosen.mood))
	return chosen


func reset_recent_window() -> void:
	_recent.clear()


# endregion


# region — internals

func _conditions_pass(line: DialogueLineResource, lines_seen: Dictionary) -> bool:
	if line.min_total_catches > 0 and GameState.total_catches() < line.min_total_catches:
		return false
	if line.min_prestige_count > 0 and GameState.prestige_count < line.min_prestige_count:
		return false
	if line.max_uses > 0:
		var times_seen: int = int(lines_seen.get(String(line.id), 0))
		if times_seen >= line.max_uses:
			return false
	return true


func _weighted_pick(candidates: Array[DialogueLineResource]) -> DialogueLineResource:
	var total: float = 0.0
	for line in candidates:
		total += max(0.0001, line.weight)
	if total <= 0.0:
		return candidates[0]
	var roll: float = randf() * total
	var acc: float = 0.0
	for line in candidates:
		acc += max(0.0001, line.weight)
		if roll <= acc:
			return line
	return candidates[candidates.size() - 1]


func _record_spoken(line: DialogueLineResource) -> void:
	var lines_seen: Dictionary = GameState.narrator_state.get("lines_seen", {})
	var id_str: String = String(line.id)
	lines_seen[id_str] = int(lines_seen.get(id_str, 0)) + 1
	GameState.narrator_state["lines_seen"] = lines_seen
	GameState.narrator_state["last_line_unix"] = TimeManager.now_unix()
	GameState.ledger["peniber_quotes_seen"] = int(GameState.ledger.get("peniber_quotes_seen", 0)) + 1
	# Sliding window of the last few line ids.
	_recent.append(id_str)
	while _recent.size() > RECENT_WINDOW_SIZE:
		_recent.pop_front()


func _on_line_chosen(_id: String, _text: String, _mood: String) -> void:
	# Hook for telemetry; bookkeeping already done by _record_spoken.
	pass

# endregion


# region — EventBus handlers

func _on_first_catch_of_species(monster_id: String) -> void:
	# First catch of any species also triggers the "first catch ever" gate.
	if int(GameState.ledger.get("total_catches", 0)) <= 1:
		try_speak(&"on_first_catch_ever")
	try_speak(StringName("on_first_catch_" + monster_id))


func _on_monster_caught(_monster_id: String, _instance_id: int, is_shiny: bool, _source: String) -> void:
	_last_input_time_ms = Time.get_ticks_msec()
	# Catch milestones at 10 / 100 / 1000 / 10000 total catches.
	var total: int = GameState.total_catches()
	for milestone in [10, 100, 1000, 10000]:
		if total == milestone:
			try_speak(StringName("on_milestone_%d" % milestone))
			break
	if is_shiny and int(GameState.ledger.get("total_shinies", 0)) > 1:
		try_speak(&"on_shiny")


func _on_first_shiny_caught(_monster_id: String) -> void:
	try_speak(&"on_first_shiny")


func _on_tier_completed(tier: int) -> void:
	try_speak(StringName("on_tier_complete_%d" % tier))


func _on_pet_acquired(_pet_id: String, _is_variant: bool) -> void:
	if GameState.pets_owned.size() == 1:
		try_speak(&"on_first_pet_acquired")
	else:
		try_speak(&"on_pet_acquired")


func _on_battle_ended(_battle_id: String, won: bool, _rewards: Dictionary) -> void:
	if won:
		try_speak(&"on_first_battle_win")
		try_speak(&"on_battle_win")
	else:
		try_speak(&"on_battle_loss")


func _on_prestige_triggered(_rp_gained: int, prestige_count: int) -> void:
	if prestige_count == 1:
		try_speak(&"on_first_prestige")
	try_speak(&"on_prestige")


func _on_offline_progress_calculated(summary: Dictionary) -> void:
	var seconds: float = float(summary.get("seconds", 0))
	if seconds <= 0.0:
		return
	if seconds < 600.0:
		try_speak(&"on_offline_return_short")
	else:
		try_speak(&"on_offline_return_long")


func _on_upgrade_purchased(_upgrade_id: String) -> void:
	_last_input_time_ms = Time.get_ticks_msec()


func _on_item_crafted(_recipe_id: String, _output_id: String) -> void:
	if int(GameState.ledger.get("peniber_quotes_seen", 0)) == 0 or not _has_seen_trigger(&"on_first_craft"):
		try_speak(&"on_first_craft")


func _on_recipe_unlocked(_recipe_or_net_id: String) -> void:
	# Currently piggybacks on first_craft; future content can split this.
	pass


func _on_game_loaded() -> void:
	_ensure_loaded()
	if int(GameState.ledger.get("first_launch_unix", 0)) > 0 and int(GameState.ledger.get("peniber_quotes_seen", 0)) == 0:
		try_speak(&"on_first_launch")


func _has_seen_trigger(trigger_id: StringName) -> bool:
	# Returns true if any line with this trigger has been spoken before.
	var lines_seen: Dictionary = GameState.narrator_state.get("lines_seen", {})
	for line_id in lines_seen.keys():
		if int(lines_seen[line_id]) > 0:
			# Map back to trigger via registry lookup.
			# Simpler: just check string prefix of the trigger.
			if String(line_id).begins_with(String(trigger_id)):
				return true
	return false


func _process(_delta: float) -> void:
	# Idle detection.
	var now_ms: int = Time.get_ticks_msec()
	var idle_seconds: float = float(now_ms - _last_input_time_ms) / 1000.0
	var since_last_fire: float = float(now_ms - _last_idle_fire_ms) / 1000.0
	if idle_seconds >= _IDLE_TRIGGER_SECONDS and since_last_fire >= _IDLE_COOLDOWN_SECONDS:
		_last_idle_fire_ms = now_ms
		EventBus.idle_too_long.emit(idle_seconds)
		try_speak(&"on_idle_too_long")


func _unhandled_input(event: InputEvent) -> void:
	# Any user input refreshes the idle timer.
	if event is InputEventMouseButton and event.pressed:
		_last_input_time_ms = Time.get_ticks_msec()
	elif event is InputEventScreenTouch and event.pressed:
		_last_input_time_ms = Time.get_ticks_msec()
	elif event is InputEventKey and event.pressed:
		_last_input_time_ms = Time.get_ticks_msec()

# endregion
