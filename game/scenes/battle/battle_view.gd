## Battle tab: roster, fight button, frame-replay.
##
## State machine:
##   IDLE                - show pet roster + stage info + Fight button
##                         (or "no pets" message)
##   BATTLING            - replay current encounter's BattleLog frames
##                         at configurable speed
##   BETWEEN_ENCOUNTERS  - despawn old enemy combatants, spawn next
##                         encounter's enemies, brief 0.6s pause
##   POST                - show stage result + Continue button
##
## v0.10.5 (Phase 10e.1): single-encounter visual rewrite.
## v0.10.8 (Phase 10e.2): multi-encounter stages. Each "Fight" runs a
## sequence of 1-N encounters from a [BattleStageResource]. Pet HP
## carries between encounters; team wipe ends the stage early. Stage
## rewards (RP) are summed across encounters and credited once on
## stage completion.
extends PanelContainer

const _BATTLE_MAP := preload("res://game/scenes/battle/battle_map.tscn")
const _COMBATANT := preload("res://game/scenes/battle/combatant.tscn")
const _PALETTE := preload("res://game/resources/palette_colors.gd")

const _TICK_SECONDS_PER_FRAME := 0.25  # game-tick duration
const _MAX_PETS_IN_FIGHT := 3
const _SPEED_OPTIONS: Array[float] = [1.0, 2.0, 4.0]
const _BETWEEN_ENCOUNTERS_SECS := 0.7

enum _State { IDLE, BATTLING, BETWEEN_ENCOUNTERS, POST }

var _state: int = _State.IDLE
var _root_vbox: VBoxContainer
var _status_label: Label
var _content_panel: PanelContainer
var _content_box: VBoxContainer
var _action_button: Button
var _speed_index: int = 0

# Phase 10e.2 — stage state.
var _active_stage: BattleStageResource
var _stage_log: Dictionary
var _current_encounter_index: int = 0
var _between_timer: float = 0.0

# Per-encounter playback state.
var _battle_log: Dictionary    # current encounter's BattleLog
var _replay_frame_index: int = 0
var _replay_accumulator: float = 0.0
var _player_team_summary: Array = []   # per-pet display info (id + name + sprite + tint + max_hp)
var _enemy_team_summary: Array = []    # for the CURRENT encounter
var _action_log_label: Label
var _skip_button: Button

# Phase 10e.1: SubViewport-hosted map + combatants. Only populated
# while _state in {BATTLING, BETWEEN_ENCOUNTERS, POST}.
var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _battle_map: Node2D
var _player_combatants: Array[Node2D] = []
var _enemy_combatants: Array[Node2D] = []
## In-flight despawn tweens. Killed in _teardown_battle_map so their
## queue_free callbacks don't fire on already-freed combatants
## (which would trigger Godot's "lambda capture was freed" warning).
var _despawn_tweens: Array[Tween] = []


func _ready() -> void:
	_root_vbox = VBoxContainer.new()
	_root_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_vbox.add_theme_constant_override("separation", 12)
	add_child(_root_vbox)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", UiScale.size(22))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root_vbox.add_child(_status_label)

	_content_panel = PanelContainer.new()
	_content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root_vbox.add_child(_content_panel)
	_content_box = VBoxContainer.new()
	_content_panel.add_child(_content_box)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	button_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root_vbox.add_child(button_row)

	_action_button = Button.new()
	_action_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_button.pressed.connect(_on_action_pressed)
	button_row.add_child(_action_button)

	_skip_button = Button.new()
	_skip_button.text = "Skip (ad)"
	_skip_button.visible = false
	_skip_button.pressed.connect(_on_skip_pressed)
	button_row.add_child(_skip_button)

	EventBus.pet_acquired.connect(_on_pet_acquired)
	EventBus.game_loaded.connect(_render_idle)
	AdsManager.rewarded_completed.connect(_on_rewarded_completed)
	AdsManager.rewarded_failed.connect(_on_rewarded_failed)
	# Phase 11e: persist battle speed across sessions. Idle players
	# tend to set 4x once and never want it reset.
	_speed_index = clampi(int(Settings.battle_speed_index), 0, _SPEED_OPTIONS.size() - 1)
	set_process(false)
	_render_idle()


func _on_pet_acquired(_pet_id: String, _is_variant: bool) -> void:
	if _state == _State.IDLE:
		_render_idle()


func _render_idle() -> void:
	_state = _State.IDLE
	set_process(false)
	if _skip_button != null:
		_skip_button.visible = false
		_skip_button.disabled = false
	_clear_content()
	_teardown_battle_map()
	var pets: Array[PetResource] = GameState.owned_pets()
	if pets.is_empty():
		var label := Label.new()
		label.text = "Complete a tier to earn your first pet."
		label.modulate = Color(0.85, 0.85, 0.85)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_content_box.add_child(label)
		# Phase 11d: empty state must give the player a path forward.
		# Switch to the Catch tab on tap.
		var to_catch_btn := Button.new()
		to_catch_btn.text = "Go to Catch"
		to_catch_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		to_catch_btn.pressed.connect(func() -> void:
			EventBus.tab_switch_requested.emit("Catch"))
		_content_box.add_child(to_catch_btn)
		_status_label.text = "No pets in roster"
		_action_button.text = "Fight"
		_action_button.disabled = true
		return
	# Phase 10e.2: surface the active stage so the player can see what
	# they're walking into. ContentRegistry picks the highest-tier
	# stage their current_max_tier unlocks.
	var stage: BattleStageResource = ContentRegistry.default_stage_for_tier(GameState.current_max_tier)
	if stage == null:
		_status_label.text = "No stage available"
		_action_button.text = "Fight"
		_action_button.disabled = true
		var note := Label.new()
		note.text = "No battle stages are unlocked yet. Complete a tier to unlock one."
		note.modulate = _PALETTE.SEPIA_MID
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_content_box.add_child(note)
		return
	_active_stage = stage
	_status_label.text = "Stage: %s" % stage.display_name
	var subtitle := Label.new()
	subtitle.text = "Tier %d  •  %d encounters" % [stage.tier, stage.encounters.size()]
	subtitle.add_theme_font_size_override("font_size", UiScale.size(14))
	subtitle.modulate = _PALETTE.SEPIA_MID
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_box.add_child(subtitle)

	var roster_heading := Label.new()
	roster_heading.text = "Roster"
	roster_heading.add_theme_font_size_override("font_size", UiScale.size(18))
	_content_box.add_child(roster_heading)
	for pet in GameState.battle_team(_MAX_PETS_IN_FIGHT):
		var row := Label.new()
		row.text = "  %s  —  ATK %d / DEF %d / HP %d  (%s)" % [
			pet.display_name,
			int(pet.base_attack),
			int(pet.base_defense),
			int(pet.base_hp),
			String(pet.ability_id),
		]
		row.add_theme_font_size_override("font_size", UiScale.size(16))
		_content_box.add_child(row)
	if pets.size() > _MAX_PETS_IN_FIGHT:
		var note := Label.new()
		note.text = "  (Battle uses your strongest %d pets.)" % _MAX_PETS_IN_FIGHT
		note.modulate = Color(0.7, 0.7, 0.7)
		_content_box.add_child(note)
	_action_button.text = "Fight"
	_action_button.disabled = false


func _on_action_pressed() -> void:
	if _state == _State.IDLE:
		_start_stage()
	elif _state == _State.BATTLING:
		_cycle_speed()
	elif _state == _State.POST:
		_render_idle()


func _cycle_speed() -> void:
	_speed_index = (_speed_index + 1) % _SPEED_OPTIONS.size()
	# Phase 11e: persist immediately so the next session inherits.
	Settings.set_battle_speed_index(_speed_index)
	_update_action_button_text()


func _update_action_button_text() -> void:
	if _state == _State.BATTLING:
		_action_button.text = "Speed: %dx" % int(_SPEED_OPTIONS[_speed_index])
	elif _state == _State.POST:
		_action_button.text = "Continue"
	elif _state == _State.BETWEEN_ENCOUNTERS:
		_action_button.text = "Advancing…"
	else:
		_action_button.text = "Fight"


# region — Phase 10e.2: stage orchestration

## Kicks off the active stage. Builds the StageLog up front (BattleSystem
## simulates everything deterministically), then plays back encounter 0.
## Subsequent encounters are queued via _begin_encounter as the previous
## one's frames exhaust.
func _start_stage() -> void:
	var pets: Array[PetResource] = GameState.battle_team(_MAX_PETS_IN_FIGHT)
	if pets.is_empty():
		return
	if _active_stage == null:
		return
	if _active_stage.encounters.is_empty():
		push_warning("BattleView._start_stage: stage %s has no encounters" % String(_active_stage.id))
		return
	var battle_seed: int = int(Time.get_unix_time_from_system()) ^ Engine.get_process_frames()
	var rp_mult: float = GameState.multiplier(&"rp_mult")
	_stage_log = BattleSystem.simulate_stage(battle_seed, pets, _active_stage, rp_mult)
	EventBus.battle_started.emit(str(battle_seed))
	_player_team_summary = _summarize_pets(pets)
	_setup_battle_map_with_player_team()

	_update_skip_visibility()

	_current_encounter_index = 0
	_begin_encounter(0)


## v0.15.19 — the stage outcome is predetermined the moment the StageLog is
## simulated, so never sell an ad-skip into a loss: skipping a doomed replay
## pays an ad to reach "Stage failed" with zero rewards. The skip exists to
## fast-forward a WIN.
func _update_skip_visibility() -> void:
	if _skip_button == null:
		return
	_skip_button.visible = String(_stage_log.get("winner", "")) == "player"
	_skip_button.disabled = not AdsManager.is_available()


## Begin playback of encounter `index` from the StageLog. Spawns the
## encounter's enemy combatants and resets the per-encounter replay
## state. The player team is NOT respawned — combatants persist across
## encounters so HP carries visibly.
func _begin_encounter(index: int) -> void:
	var encounter_logs: Array = _stage_log.get("encounters", [])
	if index < 0 or index >= encounter_logs.size():
		_finish_stage()
		return
	_battle_log = encounter_logs[index]
	_current_encounter_index = index
	_replay_frame_index = 0
	_replay_accumulator = 0.0

	var encounter: EncounterResource = _active_stage.encounters[index]
	var enemy_monsters: Array[MonsterResource] = []
	for mid in encounter.monster_ids:
		var m: MonsterResource = ContentRegistry.monster(mid)
		if m != null:
			enemy_monsters.append(m)
	_enemy_team_summary = _summarize_monsters(enemy_monsters)
	_spawn_enemy_team()

	_status_label.text = "%s — Encounter %d / %d" % [
			_active_stage.display_name, index + 1, encounter_logs.size(),
	]
	_state = _State.BATTLING
	_update_action_button_text()
	# Optional Peniber line for this encounter.
	if encounter.narrator_line_id != &"" and Narrator.has_method("try_speak"):
		Narrator.try_speak(encounter.narrator_line_id)
	set_process(true)


# endregion


func _summarize_pets(pets: Array[PetResource]) -> Array:
	# Per-pet display info threaded into the combatant on spawn.
	# `sprite` is best-effort: PetResource doesn't always carry its own
	# sprite; fall back to the originating monster's sprite via
	# source_monster_id when needed.
	var out: Array = []
	for p in pets:
		var tex: Texture2D = p.sprite
		if tex == null and p.source_monster_id != StringName(""):
			var src: MonsterResource = ContentRegistry.monster(p.source_monster_id)
			if src != null:
				tex = src.sprite
		out.append({
			"id": String(p.id),
			"display_name": p.display_name,
			"sprite": tex,
			"tint": p.tint,
			"max_hp": p.base_hp,
		})
	return out


func _summarize_monsters(monsters: Array[MonsterResource]) -> Array:
	var out: Array = []
	for m in monsters:
		var tier: int = max(1, m.tier)
		var hp: float = float(20 * tier + 10)
		out.append({
			"id": String(m.id),
			"display_name": m.display_name,
			"sprite": m.sprite,
			"tint": m.tint,
			"max_hp": hp,
		})
	return out


# region — Phase 10e.1 visual rendering


## Build the SubViewport + battle_map subtree and spawn the player team.
## Enemy team is spawned per-encounter via _spawn_enemy_team.
##
## v0.14.2 (Phase 13c.2) — landscape side-by-side. In landscape the
## battle map gets a much wider aspect ratio than the SubViewport's
## fixed 720×520, so we put the action log in a sidebar to its left
## and let the viewport stretch into the freed horizontal space. In
## portrait the layout is unchanged: viewport on top, log below.
func _setup_battle_map_with_player_team() -> void:
	_teardown_battle_map()

	var landscape: bool = DeviceLayout.is_landscape
	# In landscape, _content_box (a VBox) hosts a single HBox child
	# containing [action_log_sidebar, viewport_container]. In portrait
	# the viewport and log are stacked siblings of _content_box, same
	# as before.
	var viewport_parent: Control = _content_box
	if landscape:
		var hbox := HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		hbox.add_theme_constant_override("separation", 8)
		_content_box.add_child(hbox)
		viewport_parent = hbox

	_action_log_label = Label.new()
	_action_log_label.text = ""
	_action_log_label.add_theme_font_size_override("font_size", UiScale.size(14))
	_action_log_label.modulate = _PALETTE.SEPIA_MID
	_action_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if landscape:
		# Sidebar: ~180-px wide column on the LEFT of the map, holds
		# the live action log so the player can read it without it
		# eating vertical real estate from the already-short landscape
		# viewport.
		_action_log_label.custom_minimum_size = Vector2(180, 0)
		_action_log_label.size_flags_horizontal = Control.SIZE_FILL
		_action_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_action_log_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		viewport_parent.add_child(_action_log_label)

	_viewport_container = SubViewportContainer.new()
	_viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport_container.stretch = true
	viewport_parent.add_child(_viewport_container)

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(720, 520)
	_viewport.transparent_bg = true
	_viewport.handle_input_locally = false
	_viewport.disable_3d = true
	_viewport.gui_disable_input = true
	_viewport_container.add_child(_viewport)

	_battle_map = _BATTLE_MAP.instantiate()
	_viewport.add_child(_battle_map)
	_battle_map.apply_tier_palette(int(GameState.current_max_tier))

	if not landscape:
		# Portrait: log goes BELOW the viewport, full width.
		_action_log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_content_box.add_child(_action_log_label)

	_player_combatants = _spawn_team("player", _player_team_summary)


## Spawn fresh enemy combatants for the current encounter. Old enemy
## combatants must be despawned BEFORE this is called (handled by
## _begin_between_encounters).
func _spawn_enemy_team() -> void:
	_enemy_combatants = _spawn_team("enemy", _enemy_team_summary)


func _spawn_team(team: String, summary: Array) -> Array[Node2D]:
	var out: Array[Node2D] = []
	if _battle_map == null:
		return out
	var layer: Node2D = _battle_map.combatants_layer()
	for i in summary.size():
		var entry: Dictionary = summary[i]
		var c: Node2D = _COMBATANT.instantiate()
		c.setup(
				team,
				i,
				float(entry["max_hp"]),
				_battle_map.engagement_pos(team, i),
				_battle_map.start_pos(team, i),
				_battle_map.facing_for_team(team),
				entry.get("sprite", null) as Texture2D,
				entry.get("tint", Color.WHITE) as Color)
		layer.add_child(c)
		out.append(c)
	return out


func _teardown_battle_map() -> void:
	# Kill any in-flight despawn tweens before freeing combatants —
	# otherwise the tween's queue_free callback fires after its
	# captured combatant is already gone, which Godot reports as
	# "lambda capture was freed".
	for t in _despawn_tweens:
		if t != null and t.is_valid():
			t.kill()
	_despawn_tweens.clear()
	if _viewport_container != null and is_instance_valid(_viewport_container):
		_viewport_container.queue_free()
	_viewport_container = null
	_viewport = null
	_battle_map = null
	_player_combatants.clear()
	_enemy_combatants.clear()


## Despawn enemy combatants only — used between encounters. Player
## combatants persist (HP carries via _battle_log frames already
## applied; subsequent encounters reference the same indices).
func _despawn_enemy_combatants() -> void:
	for c in _enemy_combatants:
		if is_instance_valid(c):
			# Tween a quick fade-out before queue_free so the transition
			# reads as a deliberate beat rather than an instant pop.
			# The tween is tracked so _teardown_battle_map can kill it
			# before freeing combatants out from under it.
			var t := create_tween()
			_despawn_tweens.append(t)
			t.tween_property(c, "modulate:a", 0.0, 0.2)
			t.tween_callback(func() -> void:
				if is_instance_valid(c):
					c.queue_free())
	_enemy_combatants.clear()


# endregion


func _process(delta: float) -> void:
	if _state == _State.BATTLING:
		_step_battling(delta)
	elif _state == _State.BETWEEN_ENCOUNTERS:
		_step_between_encounters(delta)


func _step_battling(delta: float) -> void:
	var speed: float = _SPEED_OPTIONS[_speed_index]
	_replay_accumulator += delta * speed
	while _replay_accumulator >= _TICK_SECONDS_PER_FRAME and _replay_frame_index < _battle_log["frames"].size():
		_apply_replay_frame(_battle_log["frames"][_replay_frame_index])
		_replay_frame_index += 1
		_replay_accumulator -= _TICK_SECONDS_PER_FRAME
	if _replay_frame_index >= _battle_log["frames"].size():
		_finish_encounter_replay()


func _step_between_encounters(delta: float) -> void:
	_between_timer += delta * _SPEED_OPTIONS[_speed_index]
	if _between_timer >= _BETWEEN_ENCOUNTERS_SECS:
		_between_timer = 0.0
		_begin_encounter(_current_encounter_index + 1)


func _apply_replay_frame(frame: Dictionary) -> void:
	var actor_id: String = String(frame.get("actor", ""))
	var target_id: String = String(frame.get("target", ""))
	var actor: Node2D = _combatant_for(actor_id)
	var target: Node2D = _combatant_for(target_id)
	if actor != null and target != null and actor.has_method("play_attack_lunge"):
		actor.play_attack_lunge(target.position)
	if target != null and target.has_method("apply_damage"):
		var hp_remaining: int = int(frame.get("hp_remaining", 0))
		target.apply_damage(hp_remaining)
	if _action_log_label != null:
		var action: String = String(frame.get("action", ""))
		var damage: int = int(frame.get("damage", 0))
		var line: String
		if action.begins_with("ability:"):
			line = "%s used %s — %d" % [actor_id, action.substr(8), -damage if damage < 0 else damage]
		else:
			line = "%s hit %s for %d" % [actor_id, target_id, damage]
		_action_log_label.text = line


func _combatant_for(id: String) -> Node2D:
	var parts: PackedStringArray = id.split("_")
	if parts.size() < 2:
		return null
	var team: String = parts[0]
	var index: int = int(parts[1])
	var pool: Array[Node2D] = _player_combatants if team == "player" else _enemy_combatants
	if index < 0 or index >= pool.size():
		return null
	return pool[index]


## Called when the current encounter's frames are exhausted. Decides
## whether to roll into the next encounter (if one exists and the
## player team won this encounter) or to terminate the stage.
func _finish_encounter_replay() -> void:
	var encounter_winner: String = String(_battle_log.get("winner", "draw"))
	var encounter_logs: Array = _stage_log.get("encounters", [])
	var has_next: bool = _current_encounter_index + 1 < encounter_logs.size()
	if encounter_winner == "player" and has_next:
		_begin_between_encounters()
		return
	# Either the team wiped or this was the final encounter — finalize.
	_finish_stage()


func _begin_between_encounters() -> void:
	_state = _State.BETWEEN_ENCOUNTERS
	_between_timer = 0.0
	_despawn_enemy_combatants()
	if _action_log_label != null:
		_action_log_label.text = "Advancing to encounter %d…" % (_current_encounter_index + 2)
	_update_action_button_text()


func _finish_stage() -> void:
	_state = _State.POST
	set_process(false)
	if _skip_button != null:
		_skip_button.visible = false
	var winner: String = String(_stage_log.get("winner", "draw"))
	var rewards: Dictionary = _stage_log.get("rewards", {})
	var rp: int = int(rewards.get("rancher_points", 0))
	if winner == "player":
		_status_label.text = "Stage cleared  •  +%d RP" % rp
		if rp > 0:
			GameState.add_rancher_points(rp, "battle")
		# Optional Peniber stage-cleared line.
		if _active_stage != null and _active_stage.narrator_stage_clear_id != &"" and Narrator.has_method("try_speak"):
			Narrator.try_speak(_active_stage.narrator_stage_clear_id)
	else:
		# v0.15.19 — actionable loss copy: stages are tuned so tier 3+
		# requires crafted gear, so "get better gear" is nearly always
		# the correct next step for a losing player.
		_status_label.text = "Stage failed at encounter %d\nYour pets need better gear — craft equipment in the Crafting tab." % (_current_encounter_index + 1)
	EventBus.battle_ended.emit(
			str(_stage_log.get("seed", 0)),
			winner == "player",
			rewards)
	_action_button.text = "Continue"


func _on_skip_pressed() -> void:
	if _state != _State.BATTLING:
		return
	if _skip_button != null:
		_skip_button.disabled = true
	AdsManager.show_rewarded(AdsManager.REWARD_BATTLE_INSTANT_FINISH)


func _on_rewarded_completed(reward_id: String, granted: bool) -> void:
	if reward_id != AdsManager.REWARD_BATTLE_INSTANT_FINISH:
		return
	if _state != _State.BATTLING:
		return
	EventBus.rewarded_video_completed.emit(reward_id, granted)
	if granted:
		_fast_forward_replay()
	else:
		# User canceled — keep battling at current speed.
		if _skip_button != null:
			_skip_button.disabled = false


func _on_rewarded_failed(reward_id: String, _reason: String) -> void:
	if reward_id != AdsManager.REWARD_BATTLE_INSTANT_FINISH:
		return
	if _state == _State.BATTLING and _skip_button != null:
		_skip_button.disabled = false


## Skip the rest of the stage — apply every remaining frame across all
## remaining encounters in one pass. Used by the rewarded-video skip.
func _fast_forward_replay() -> void:
	var encounter_logs: Array = _stage_log.get("encounters", [])
	# Finish the current encounter's frames first.
	while _replay_frame_index < _battle_log["frames"].size():
		_apply_replay_frame(_battle_log["frames"][_replay_frame_index])
		_replay_frame_index += 1
	# If the player won, fast-forward through any remaining encounters.
	while String(_battle_log.get("winner", "")) == "player" \
			and _current_encounter_index + 1 < encounter_logs.size():
		# Despawn old enemies + spawn the next encounter without the
		# transition delay.
		_despawn_enemy_combatants()
		_current_encounter_index += 1
		_battle_log = encounter_logs[_current_encounter_index]
		var enc_resource: EncounterResource = _active_stage.encounters[_current_encounter_index]
		var enemy_monsters: Array[MonsterResource] = []
		for mid in enc_resource.monster_ids:
			var m: MonsterResource = ContentRegistry.monster(mid)
			if m != null:
				enemy_monsters.append(m)
		_enemy_team_summary = _summarize_monsters(enemy_monsters)
		_spawn_enemy_team()
		_replay_frame_index = 0
		while _replay_frame_index < _battle_log["frames"].size():
			_apply_replay_frame(_battle_log["frames"][_replay_frame_index])
			_replay_frame_index += 1
	_finish_stage()


func _clear_content() -> void:
	if _content_box == null:
		return
	for child in _content_box.get_children():
		child.queue_free()
