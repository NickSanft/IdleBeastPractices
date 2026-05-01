## Battle tab: roster, fight button, frame-replay.
##
## State machine:
##   IDLE     - show pet roster + Fight button (or "no pets" message)
##   BATTLING - replay BattleLog frames at configurable speed
##   POST     - show result + Continue button
extends PanelContainer

const _TICK_SECONDS_PER_FRAME := 0.25  # game-tick duration
const _MAX_PETS_IN_FIGHT := 3
const _SPEED_OPTIONS: Array[float] = [1.0, 2.0, 4.0]

enum _State { IDLE, BATTLING, POST }

var _state: int = _State.IDLE
var _root_vbox: VBoxContainer
var _status_label: Label
var _content_panel: PanelContainer
var _content_box: VBoxContainer
var _action_button: Button
var _speed_index: int = 0
var _battle_log: Dictionary
var _replay_frame_index: int = 0
var _replay_accumulator: float = 0.0
var _player_team_summary: Array = []   # per-pet display info
var _enemy_team_summary: Array = []
var _player_hp: Array[float] = []
var _player_max_hp: Array[float] = []
var _enemy_hp: Array[float] = []
var _enemy_max_hp: Array[float] = []
var _player_bars: Array[ProgressBar] = []
var _enemy_bars: Array[ProgressBar] = []
var _action_log_label: Label


func _ready() -> void:
	_root_vbox = VBoxContainer.new()
	_root_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_vbox.add_theme_constant_override("separation", 12)
	add_child(_root_vbox)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 22)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root_vbox.add_child(_status_label)

	_content_panel = PanelContainer.new()
	_content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root_vbox.add_child(_content_panel)
	_content_box = VBoxContainer.new()
	_content_panel.add_child(_content_box)

	_action_button = Button.new()
	_action_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_button.pressed.connect(_on_action_pressed)
	_root_vbox.add_child(_action_button)

	EventBus.pet_acquired.connect(_on_pet_acquired)
	EventBus.game_loaded.connect(_render_idle)
	set_process(false)
	_render_idle()


func _on_pet_acquired(_pet_id: String, _is_variant: bool) -> void:
	if _state == _State.IDLE:
		_render_idle()


func _render_idle() -> void:
	_state = _State.IDLE
	set_process(false)
	_clear_content()
	var pets: Array[PetResource] = GameState.owned_pets()
	if pets.is_empty():
		var label := Label.new()
		label.text = "Complete a tier to earn your first pet."
		label.modulate = Color(0.85, 0.85, 0.85)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_content_box.add_child(label)
		_status_label.text = "No pets in roster"
		_action_button.text = "Fight"
		_action_button.disabled = true
		return
	_status_label.text = "Roster"
	for pet in pets.slice(0, _MAX_PETS_IN_FIGHT):
		var row := Label.new()
		row.text = "  %s  —  ATK %d / DEF %d / HP %d  (%s)" % [
			pet.display_name,
			int(pet.base_attack),
			int(pet.base_defense),
			int(pet.base_hp),
			String(pet.ability_id),
		]
		row.add_theme_font_size_override("font_size", 16)
		_content_box.add_child(row)
	if pets.size() > _MAX_PETS_IN_FIGHT:
		var note := Label.new()
		note.text = "  (Battle uses your first %d pets.)" % _MAX_PETS_IN_FIGHT
		note.modulate = Color(0.7, 0.7, 0.7)
		_content_box.add_child(note)
	_action_button.text = "Fight"
	_action_button.disabled = false


func _on_action_pressed() -> void:
	if _state == _State.IDLE:
		_start_battle()
	elif _state == _State.BATTLING:
		_cycle_speed()
	elif _state == _State.POST:
		_render_idle()


func _cycle_speed() -> void:
	_speed_index = (_speed_index + 1) % _SPEED_OPTIONS.size()
	_update_action_button_text()


func _update_action_button_text() -> void:
	if _state == _State.BATTLING:
		_action_button.text = "Speed: %dx" % int(_SPEED_OPTIONS[_speed_index])
	elif _state == _State.POST:
		_action_button.text = "Continue"
	else:
		_action_button.text = "Fight"


func _start_battle() -> void:
	var pets: Array[PetResource] = GameState.owned_pets().slice(0, _MAX_PETS_IN_FIGHT)
	if pets.is_empty():
		return
	var enemies: Array[MonsterResource] = _generate_enemy_team()
	if enemies.is_empty():
		return
	var battle_seed: int = int(Time.get_unix_time_from_system()) ^ Engine.get_process_frames()
	var rp_mult: float = GameState.multiplier(&"rp_mult")
	_battle_log = BattleSystem.simulate(battle_seed, pets, enemies, rp_mult)
	EventBus.battle_started.emit(str(battle_seed))
	_player_team_summary = _summarize_team(pets, "player")
	_enemy_team_summary = _summarize_monsters(enemies, "enemy")
	_state = _State.BATTLING
	_replay_frame_index = 0
	_replay_accumulator = 0.0
	_render_battle()
	_update_action_button_text()
	set_process(true)


func _generate_enemy_team() -> Array[MonsterResource]:
	# 3 monsters of the player's current_max_tier (or tier 1 if higher tier has no content).
	var pool := ContentRegistry.monsters()
	var target_tier: int = max(1, GameState.current_max_tier)
	var candidates: Array[MonsterResource] = []
	for m in pool:
		if m.tier == target_tier:
			candidates.append(m)
	if candidates.is_empty():
		# Fall back to tier 1.
		for m in pool:
			if m.tier == 1:
				candidates.append(m)
	if candidates.is_empty():
		return []
	# Take 3 (with replacement if pool is smaller).
	var team: Array[MonsterResource] = []
	for i in 3:
		team.append(candidates[i % candidates.size()])
	return team


func _summarize_team(pets: Array[PetResource], team: String) -> Array:
	var out: Array = []
	_player_hp = []
	_player_max_hp = []
	for i in pets.size():
		var p: PetResource = pets[i]
		out.append({"id": String(p.id), "display_name": p.display_name})
		if team == "player":
			_player_hp.append(p.base_hp)
			_player_max_hp.append(p.base_hp)
	return out


func _summarize_monsters(monsters: Array[MonsterResource], _team: String) -> Array:
	var out: Array = []
	_enemy_hp = []
	_enemy_max_hp = []
	for i in monsters.size():
		var m: MonsterResource = monsters[i]
		out.append({"id": String(m.id), "display_name": m.display_name})
		var tier: int = max(1, m.tier)
		var hp: float = float(20 * tier + 10)
		_enemy_hp.append(hp)
		_enemy_max_hp.append(hp)
	return out


func _render_battle() -> void:
	_clear_content()
	_status_label.text = "Battle: tick %d / %d" % [int(_battle_log["ticks"]), 600]
	_player_bars = _build_team_section("Your pets", _player_team_summary, _player_hp, _player_max_hp, false)
	_enemy_bars = _build_team_section("Enemies", _enemy_team_summary, _enemy_hp, _enemy_max_hp, true)
	_action_log_label = Label.new()
	_action_log_label.text = ""
	_action_log_label.add_theme_font_size_override("font_size", 14)
	_action_log_label.modulate = Color(0.9, 0.9, 0.9)
	_action_log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_box.add_child(_action_log_label)


func _build_team_section(
		title: String,
		team: Array,
		hp: Array[float],
		max_hp: Array[float],
		is_enemy: bool) -> Array[ProgressBar]:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_content_box.add_child(box)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 18)
	box.add_child(heading)
	var bars: Array[ProgressBar] = []
	for i in team.size():
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = team[i]["display_name"]
		name_label.custom_minimum_size = Vector2(160, 0)
		row.add_child(name_label)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = max_hp[i]
		bar.value = hp[i]
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.modulate = Color(0.85, 0.4, 0.45) if is_enemy else Color(0.45, 0.85, 0.55)
		row.add_child(bar)
		bars.append(bar)
		box.add_child(row)
	return bars


func _process(delta: float) -> void:
	if _state != _State.BATTLING:
		return
	var speed: float = _SPEED_OPTIONS[_speed_index]
	_replay_accumulator += delta * speed
	while _replay_accumulator >= _TICK_SECONDS_PER_FRAME and _replay_frame_index < _battle_log["frames"].size():
		_apply_replay_frame(_battle_log["frames"][_replay_frame_index])
		_replay_frame_index += 1
		_replay_accumulator -= _TICK_SECONDS_PER_FRAME
	if _replay_frame_index >= _battle_log["frames"].size():
		_finish_replay()


func _apply_replay_frame(frame: Dictionary) -> void:
	var target: String = String(frame.get("target", ""))
	var hp_remaining: int = int(frame.get("hp_remaining", 0))
	var parts: PackedStringArray = target.split("_")
	if parts.size() < 2:
		return
	var team: String = parts[0]
	var index: int = int(parts[1])
	var bars: Array[ProgressBar] = _player_bars if team == "player" else _enemy_bars
	if index < 0 or index >= bars.size():
		return
	bars[index].value = max(0, hp_remaining)
	# Action log
	if _action_log_label != null:
		var actor: String = String(frame.get("actor", ""))
		var action: String = String(frame.get("action", ""))
		var damage: int = int(frame.get("damage", 0))
		var line: String
		if action.begins_with("ability:"):
			line = "%s used %s — %d" % [actor, action.substr(8), -damage if damage < 0 else damage]
		else:
			line = "%s hit %s for %d" % [actor, target, damage]
		_action_log_label.text = line


func _finish_replay() -> void:
	_state = _State.POST
	set_process(false)
	var winner: String = String(_battle_log.get("winner", "draw"))
	var ticks: int = int(_battle_log.get("ticks", 0))
	if winner == "player":
		var rewards: Dictionary = _battle_log.get("rewards", {})
		var rp: int = int(rewards.get("rancher_points", 0))
		_status_label.text = "Victory in %d ticks  •  +%d RP" % [ticks, rp]
		if rp > 0:
			GameState.add_rancher_points(rp, "battle")
	elif winner == "enemy":
		_status_label.text = "Defeat in %d ticks" % ticks
	else:
		_status_label.text = "Drawn at the tick cap (%d)" % ticks
	EventBus.battle_ended.emit(str(_battle_log.get("seed", 0)), winner == "player", _battle_log.get("rewards", {}))
	_action_button.text = "Continue"


func _clear_content() -> void:
	if _content_box == null:
		return
	for child in _content_box.get_children():
		child.queue_free()
