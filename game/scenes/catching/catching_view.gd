## The main catch screen: tap monsters, watch the auto-net work, advance tiers.
extends Control

const _MONSTER_INSTANCE_SCENE := preload("res://game/scenes/catching/monster_instance.tscn")
const _SPAWN_INTERVAL_SECONDS := 1.2
const _TIER_COMPLETE_CATCH_THRESHOLD := 25

var _spawn_root: Node2D
var _spawn_bounds: Rect2 = Rect2(40, 200, 640, 900)
var _spawn_timer: float = 0.0
var _auto_accumulator: float = 0.0
var _instance_counter: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	ContentRegistry.ensure_loaded()
	_rng.randomize()
	# Critical: this Control must NOT intercept mouse events, or the Area2D
	# children of MonsterInstance never receive input_event. The scene file
	# also sets this to IGNORE; we re-assert here for safety.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_check_tier_progression(monster.tier)


func _check_tier_progression(catch_tier: int) -> void:
	# Tier completion gate: caught all 3 species in this tier AND ≥25 of any.
	if catch_tier != GameState.current_max_tier:
		return
	if GameState.tiers_completed.has(catch_tier):
		return
	var pool := ContentRegistry.monsters()
	var tier_species: Array[StringName] = []
	for m in pool:
		if m.tier == catch_tier:
			tier_species.append(m.id)
	if tier_species.is_empty():
		return
	var all_seen: bool = true
	var max_count: int = 0
	for sid in tier_species:
		var key: String = String(sid)
		if not GameState.monsters_caught.has(key):
			all_seen = false
			break
		var entry: Dictionary = GameState.monsters_caught[key]
		var count: int = int(entry.get("normal", 0)) + int(entry.get("shiny", 0))
		max_count = max(max_count, count)
	if not all_seen or max_count < _TIER_COMPLETE_CATCH_THRESHOLD:
		return
	# Tier complete!
	GameState.tiers_completed.append(catch_tier)
	EventBus.tier_completed.emit(catch_tier)
	# Award pets for every species in the completed tier that has one defined.
	for sid in tier_species:
		var monster_res := ContentRegistry.monster(sid)
		if monster_res == null or monster_res.pet == null:
			continue
		# Variant roll: chance is per-pet, independent of shiny.
		var rng_local := RandomNumberGenerator.new()
		rng_local.randomize()
		var is_variant: bool = rng_local.randf() < monster_res.pet.variant_rate
		GameState.add_pet(monster_res.pet.id, is_variant)
	if GameState.current_max_tier <= catch_tier:
		GameState.current_max_tier = catch_tier + 1
		EventBus.tier_unlocked.emit(GameState.current_max_tier)
