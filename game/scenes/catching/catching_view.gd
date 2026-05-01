## The main catch screen: tap monsters, watch the auto-net work, advance tiers.
extends Control

const _MONSTER_INSTANCE_SCENE := preload("res://game/scenes/catching/monster_instance.tscn")
const _SPAWN_INTERVAL_SECONDS := 1.2
const _TIER_COMPLETE_CATCH_THRESHOLD := 25
const _DEBUG_LOG := true
## Live runtime toggle (F2 in main.gd flips Settings.debug_fast_pets). When on:
## tier completion fires after just _TIER_DEBUG_THRESHOLD catches per species
## (default 2) instead of 25, and every pet variant roll auto-succeeds.
const _TIER_DEBUG_THRESHOLD := 2

var _spawn_root: Node2D
var _spawn_bounds: Rect2 = Rect2(40, 200, 640, 900)
var _spawn_timer: float = 0.0
var _auto_accumulator: float = 0.0
var _instance_counter: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	ContentRegistry.ensure_loaded()
	_rng.randomize()
	# Hit-test taps via this Control's _gui_input rather than relying on
	# Area2D physics picking — the latter is unreliable inside a TabContainer
	# because the Control hierarchy consumes the event before the physics
	# layer sees it. STOP means we get _gui_input; IGNORE would miss it.
	mouse_filter = Control.MOUSE_FILTER_STOP
	_spawn_root = Node2D.new()
	_spawn_root.name = "SpawnRoot"
	add_child(_spawn_root)
	# Configure spawn bounds based on current viewport (square area below currency bar).
	var size: Vector2 = get_viewport().get_visible_rect().size
	_spawn_bounds = Rect2(20, 80, size.x - 40, size.y - 200)
	resized.connect(_on_resized)
	# Seed: if there's no active net, the catch screen still works (taps only).
	set_process(true)


func _on_resized() -> void:
	var size: Vector2 = get_viewport().get_visible_rect().size
	_spawn_bounds = Rect2(20, 80, max(40.0, size.x - 40), max(120.0, size.y - 200))


func _process(delta: float) -> void:
	_handle_spawning(delta)
	_handle_auto_catch(delta)


## Detect taps and hit-test against on-screen monster instances. We use
## _gui_input rather than Area2D.input_event because Area2D physics picking
## doesn't reliably fire when the Area2D lives under a TabContainer's content
## Control — the GUI consumes the click before the picking pass.
func _gui_input(event: InputEvent) -> void:
	var is_tap: bool = false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		is_tap = true
	elif event is InputEventScreenTouch and event.pressed:
		is_tap = true
	if not is_tap:
		return
	# event.position is in this Control's local coords. Node2D children of
	# the Control share the same local space (Node2D.position == screen-relative
	# offset from the Control's top-left).
	var click_local: Vector2 = event.position
	if _DEBUG_LOG:
		print("[catch] _gui_input click @ %s, %d on-screen monsters" % [
			click_local, _spawn_root.get_child_count() if _spawn_root != null else 0,
		])
	var hit: Node2D = _find_monster_at(click_local)
	if hit == null:
		return
	accept_event()
	_on_monster_tapped(hit)


func _find_monster_at(local_pos: Vector2) -> Node2D:
	if _spawn_root == null:
		return null
	# 32×32 sprite at scale 3 = 96×96 hit box centered on monster.position.
	var half: Vector2 = Vector2(48, 48)
	# Iterate in reverse so the topmost-rendered (last child) wins.
	var children: Array = _spawn_root.get_children()
	for i in range(children.size() - 1, -1, -1):
		var inst = children[i]
		if not inst.has_method("play_catch_and_despawn"):
			continue
		var rect: Rect2 = Rect2(inst.position - half, half * 2.0)
		if rect.has_point(local_pos):
			return inst
	return null


func _handle_spawning(delta: float) -> void:
	_spawn_timer += delta
	if _spawn_timer < _SPAWN_INTERVAL_SECONDS:
		return
	_spawn_timer = 0.0
	var net := _active_net()
	var max_on_screen: int = net.spawn_max if net != null else 3
	if _spawn_root.get_child_count() >= max_on_screen:
		return
	_spawn_one(net)


func _handle_auto_catch(delta: float) -> void:
	var net := _active_net()
	if net == null:
		_auto_accumulator = 0.0
		return
	var auto_speed_mult: float = GameState.multiplier(&"auto_speed")
	var result := CatchingSystem.auto_catch_count(_auto_accumulator, delta, net.catches_per_second, auto_speed_mult)
	_auto_accumulator = result["accumulator"]
	for i in int(result["count"]):
		var inst := _pick_random_on_screen_monster()
		if inst == null:
			# Try to spawn one inline so the auto-catch doesn't sit idle.
			_spawn_one(net)
			inst = _pick_random_on_screen_monster()
			if inst == null:
				return
		_resolve_auto_catch(inst)


func _active_net() -> NetResource:
	var id_str: String = GameState.active_net
	if id_str == "":
		# Fall back to the default net if owned but not equipped (shouldn't happen).
		if GameState.nets_owned.size() > 0:
			id_str = GameState.nets_owned[0]
		else:
			return null
	return ContentRegistry.net(StringName(id_str))


func _spawn_one(net: NetResource) -> void:
	var pool := ContentRegistry.monsters()
	# If no net is equipped yet, allow tap-only spawning of tier-1 monsters
	# so the player isn't stuck on first launch.
	var effective_net := net
	if effective_net == null:
		var fallback := NetResource.new()
		fallback.targets_tiers = [1] as Array[int]
		fallback.spawn_max = 3
		fallback.catches_per_second = 0.0
		effective_net = fallback
	var picked := CatchingSystem.pick_spawn(pool, GameState.current_max_tier, effective_net, _rng)
	if picked == null:
		return
	_instance_counter += 1
	var inst: Node2D = _MONSTER_INSTANCE_SCENE.instantiate()
	inst.monster = picked
	inst.instance_id = _instance_counter
	inst.bounds = _spawn_bounds
	var x: float = randf_range(_spawn_bounds.position.x + 32, _spawn_bounds.position.x + _spawn_bounds.size.x - 32)
	var y: float = randf_range(_spawn_bounds.position.y + 32, _spawn_bounds.position.y + _spawn_bounds.size.y - 32)
	inst.position = Vector2(x, y)
	_spawn_root.add_child(inst)
	inst.tapped.connect(_on_monster_tapped)
	EventBus.monster_spawned.emit(String(picked.id), _instance_counter)


func _pick_random_on_screen_monster() -> Node:
	var children := _spawn_root.get_children()
	if children.is_empty():
		return null
	# Filter out any actively-being-caught instances (input disabled).
	var alive: Array = []
	for c in children:
		if c.has_method("play_catch_and_despawn"):
			alive.append(c)
	if alive.is_empty():
		return null
	return alive[_rng.randi_range(0, alive.size() - 1)]


func _on_monster_tapped(inst: Node2D) -> void:
	GameState.record_tap()
	# Trigger feedback now so the player sees their click registered even if
	# this tap doesn't yet cross the catch difficulty.
	if inst.has_method("play_tap_feedback"):
		inst.play_tap_feedback()
	if inst.monster != null:
		EventBus.monster_tapped.emit(String(inst.monster.id), inst.instance_id)
	var monster: MonsterResource = inst.monster
	var outcome := CatchingSystem.resolve_tap(
			monster,
			inst.tap_progress,
			_rng,
			GameState.multiplier(&"tap_speed"),
			GameState.multiplier(&"drop_amount"),
			GameState.multiplier(&"gold_mult"),
			GameState.multiplier(&"shiny_rate"))
	if not bool(outcome["caught"]):
		inst.tap_progress = float(outcome["tap_progress"])
		return
	_apply_catch_rewards(monster, outcome, "tap")
	inst.play_catch_and_despawn()
	EventBus.monster_caught.emit(String(monster.id), inst.instance_id, bool(outcome["is_shiny"]), "tap")


func _resolve_auto_catch(inst: Node2D) -> void:
	var monster: MonsterResource = inst.monster
	var outcome := CatchingSystem.resolve_auto(
			monster,
			_rng,
			GameState.multiplier(&"drop_amount"),
			GameState.multiplier(&"gold_mult"),
			GameState.multiplier(&"shiny_rate"))
	_apply_catch_rewards(monster, outcome, "net")
	inst.play_catch_and_despawn()
	EventBus.monster_caught.emit(String(monster.id), inst.instance_id, bool(outcome["is_shiny"]), "net")


func _apply_catch_rewards(monster: MonsterResource, outcome: Dictionary, source: String) -> void:
	GameState.record_catch(monster.id, bool(outcome["is_shiny"]), source)
	if outcome.has("drop_item_id") and outcome["drop_item_id"] != &"":
		GameState.add_item(outcome["drop_item_id"], int(outcome["drop_amount"]))
	GameState.add_gold(outcome["gold"])
	if _DEBUG_LOG:
		var gold: BigNumber = outcome["gold"]
		print("[catch] resolved: %s caught via %s, +%s gold, +%d %s%s" % [
			String(monster.id),
			source,
			gold.format(),
			int(outcome.get("drop_amount", 0)),
			String(outcome.get("drop_item_id", "")),
			"  ✨SHINY" if bool(outcome.get("is_shiny", false)) else "",
		])
	_check_tier_progression(monster.tier)


func _check_tier_progression(catch_tier: int) -> void:
	# Only fire on the player's leading edge tier.
	if catch_tier != GameState.current_max_tier:
		return
	if GameState.tiers_completed.has(catch_tier):
		return
	var threshold: int = _TIER_DEBUG_THRESHOLD if Settings.debug_fast_pets else _TIER_COMPLETE_CATCH_THRESHOLD
	var status := CatchingSystem.tier_completion_status(
			ContentRegistry.monsters(),
			GameState.monsters_caught,
			catch_tier,
			threshold)
	if not bool(status["is_complete"]):
		return
	_award_tier_completion(catch_tier)


## Side-effect-only: applies tier_completed to GameState, awards every
## species' pet in that tier (variant rolls per-pet), advances current_max_tier.
## Idempotent — add_pet skips already-owned pets.
func _award_tier_completion(catch_tier: int) -> void:
	if not GameState.tiers_completed.has(catch_tier):
		GameState.tiers_completed.append(catch_tier)
		EventBus.tier_completed.emit(catch_tier)
	if _DEBUG_LOG:
		print("[catch] TIER %d COMPLETE — awarding pets" % catch_tier)
	for pet in CatchingSystem.pets_to_award_for_tier(ContentRegistry.monsters(), catch_tier):
		var rng_local := RandomNumberGenerator.new()
		rng_local.randomize()
		var roll_ceiling: float = 1.0 if Settings.debug_fast_pets else pet.variant_rate
		var is_variant: bool = rng_local.randf() < roll_ceiling
		var added: bool = GameState.add_pet(pet.id, is_variant)
		if _DEBUG_LOG:
			print("[catch]   pet awarded: %s (variant=%s, new=%s)" % [
				String(pet.id), is_variant, added,
			])
	if GameState.current_max_tier <= catch_tier:
		GameState.current_max_tier = catch_tier + 1
		EventBus.tier_unlocked.emit(GameState.current_max_tier)
