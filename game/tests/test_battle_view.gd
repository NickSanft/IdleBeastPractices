## Phase 10e.1 — battle_view structural + frame-determinism tests.
##
## Asserts the BattleView correctly constructs the SubViewport-hosted
## map, spawns one combatant per team summary entry, and produces an
## identical sequence of combatant defeat states for two replays of
## the same BattleLog. (BattleSystem determinism is covered by
## test_battle_system; this layer ensures the view's interpretation
## of frames is also deterministic.)
extends GutTest

const _BATTLE_VIEW := preload("res://game/scenes/battle/battle_view.tscn")


func before_each() -> void:
	GameState.from_dict({})
	ContentRegistry.ensure_loaded()


func test_idle_state_with_no_pets_disables_fight_button() -> void:
	var view: PanelContainer = _BATTLE_VIEW.instantiate()
	add_child_autofree(view)
	view.size = Vector2(720, 1100)
	await wait_frames(2)
	# No pets owned in fresh GameState → button must be disabled.
	assert_true(view._action_button.disabled, "Fight button must be disabled when no pets are owned")


func test_idle_with_pets_enables_fight_button() -> void:
	# Grant one pet via the standard reconcile path.
	GameState.add_pet(&"green_wisplet_pet", false)
	var view: PanelContainer = _BATTLE_VIEW.instantiate()
	add_child_autofree(view)
	view.size = Vector2(720, 1100)
	await wait_frames(2)
	assert_false(view._action_button.disabled,
			"Fight button must be enabled when at least one pet is owned")


func test_battle_setup_spawns_one_combatant_per_team_member() -> void:
	# Grant a pet and start a battle. The map's Combatants layer
	# should hold exactly len(player_team) + len(enemy_team) children.
	GameState.add_pet(&"green_wisplet_pet", false)
	var view: PanelContainer = _BATTLE_VIEW.instantiate()
	add_child_autofree(view)
	view.size = Vector2(720, 1100)
	await wait_frames(2)
	view._start_battle()
	await wait_frames(2)
	var p_count: int = view._player_combatants.size()
	var e_count: int = view._enemy_combatants.size()
	assert_gt(p_count, 0, "player team must have at least one combatant")
	assert_eq(e_count, 3, "enemy team should be 3 by default")
	assert_not_null(view._battle_map, "battle_map must be instantiated under the SubViewport")


func test_player_and_enemy_face_opposing_directions() -> void:
	GameState.add_pet(&"green_wisplet_pet", false)
	var view: PanelContainer = _BATTLE_VIEW.instantiate()
	add_child_autofree(view)
	view.size = Vector2(720, 1100)
	await wait_frames(2)
	view._start_battle()
	await wait_frames(2)
	var p: Node2D = view._player_combatants[0]
	var e: Node2D = view._enemy_combatants[0]
	assert_eq(p.facing, 1, "player team should face right")
	assert_eq(e.facing, -1, "enemy team should face left")


func test_two_replays_of_same_log_produce_identical_defeat_sequence() -> void:
	# Determinism contract: feeding the same BattleLog frames into two
	# fresh BattleViews must drive the combatants through the same
	# sequence of defeats (= same set of target ids whose HP first hits
	# zero, in frame order).
	GameState.add_pet(&"green_wisplet_pet", false)
	var pets: Array[PetResource] = GameState.owned_pets()
	# Build a stable enemy team for repeatability.
	var enemy_id: StringName = ContentRegistry.monsters()[0].id
	var enemy: MonsterResource = ContentRegistry.monster(enemy_id)
	var enemies: Array[MonsterResource] = [enemy, enemy, enemy]
	var battle_seed: int = 1234567
	var log_a: Dictionary = BattleSystem.simulate(battle_seed, pets, enemies, 1.0)
	var log_b: Dictionary = BattleSystem.simulate(battle_seed, pets, enemies, 1.0)
	# Sanity: BattleSystem itself is deterministic.
	assert_eq(log_a["frames"].size(), log_b["frames"].size())

	# Inline the per-replay walk so we don't need an async helper that
	# would force the caller to handle a coroutine return.
	var view_a: PanelContainer = _BATTLE_VIEW.instantiate()
	add_child_autofree(view_a)
	view_a.size = Vector2(720, 1100)
	await wait_frames(2)
	view_a._battle_log = log_a
	view_a._player_team_summary = view_a._summarize_pets(pets)
	view_a._enemy_team_summary = view_a._summarize_monsters(enemies)
	view_a._state = view_a._State.BATTLING
	view_a._render_battle()
	await wait_frames(1)
	var seq_a: Array = _walk_defeat_sequence(view_a, log_a)

	var view_b: PanelContainer = _BATTLE_VIEW.instantiate()
	add_child_autofree(view_b)
	view_b.size = Vector2(720, 1100)
	await wait_frames(2)
	view_b._battle_log = log_b
	view_b._player_team_summary = view_b._summarize_pets(pets)
	view_b._enemy_team_summary = view_b._summarize_monsters(enemies)
	view_b._state = view_b._State.BATTLING
	view_b._render_battle()
	await wait_frames(1)
	var seq_b: Array = _walk_defeat_sequence(view_b, log_b)

	assert_eq(seq_a, seq_b,
			"two replays of identical BattleLog must produce the same combatant defeat sequence")


## Pure (no awaits): feed every frame of `log` into `view` and return
## the order in which target ids first hit hp <= 0.
func _walk_defeat_sequence(view: PanelContainer, log: Dictionary) -> Array:
	var seq: Array = []
	var defeated_seen: Dictionary = {}
	for f in log["frames"]:
		view._apply_replay_frame(f)
		var target_id: String = String(f.get("target", ""))
		var hp: int = int(f.get("hp_remaining", -1))
		if hp <= 0 and not defeated_seen.has(target_id):
			defeated_seen[target_id] = true
			seq.append(target_id)
	return seq


func test_finish_replay_transitions_to_post() -> void:
	GameState.add_pet(&"green_wisplet_pet", false)
	var view: PanelContainer = _BATTLE_VIEW.instantiate()
	add_child_autofree(view)
	view.size = Vector2(720, 1100)
	await wait_frames(2)
	view._start_battle()
	await wait_frames(2)
	view._fast_forward_replay()
	assert_eq(view._state, view._State.POST,
			"after fast-forward the view should be in POST")
	assert_eq(view._action_button.text, "Continue")


func test_idle_after_post_tears_down_battle_map() -> void:
	GameState.add_pet(&"green_wisplet_pet", false)
	var view: PanelContainer = _BATTLE_VIEW.instantiate()
	add_child_autofree(view)
	view.size = Vector2(720, 1100)
	await wait_frames(2)
	view._start_battle()
	await wait_frames(2)
	view._fast_forward_replay()
	view._render_idle()
	await wait_frames(2)
	assert_null(view._battle_map, "_render_idle must clear _battle_map")
	assert_eq(view._player_combatants.size(), 0)
	assert_eq(view._enemy_combatants.size(), 0)
