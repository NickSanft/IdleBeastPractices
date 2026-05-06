## Phase 12f — achievement evaluator + reward applier.
##
## On every relevant EventBus signal, the autoload re-evaluates each
## still-locked achievement against current GameState. When a trigger
## condition is met:
##   1. the id is recorded in GameState.achievements_unlocked (persisted)
##   2. RP / gold rewards are applied via GameState helpers
##   3. EventBus.achievement_unlocked is emitted so the celebration
##      overlay + ledger grid can react
##
## v0.13.5 — per-frame coalescing. Pre-12f, the simple wiring of
## `signal.connect(evaluate_all)` ran the full 20-achievement walk
## twice per caught tap (monster_tapped + monster_caught). With 12g's
## QuestLog stacking the same fan of subscriptions, a single tap
## during hold-to-tap (12b, up to 8 Hz) was firing >40 evaluator
## walks per second on Android. The fix below coalesces every signal
## fired within a single frame into a single evaluator call via a
## dirty flag drained by `_process`. See `test_achievements_perf.gd`
## for the regression test that asserts the tap-burst budget.
extends Node

## Test/diagnostic counter: number of times `evaluate_all` has run.
## Reset between tests; live builds ignore it.
var eval_count: int = 0

# Set by signal handlers; drained by _process. Coalesces N per-frame
# signals into one evaluator pass.
var _dirty: bool = false


func _ready() -> void:
	# Subscribe to every signal that mutates a tracked source. The
	# evaluator just re-reads GameState, so connecting to too many is
	# cheap; connecting to too few risks an achievement firing one
	# event late. Each handler just sets _dirty — the actual walk
	# happens once per frame in _process.
	EventBus.monster_caught.connect(_mark_dirty.unbind(4))
	EventBus.monster_tapped.connect(_mark_dirty.unbind(2))
	EventBus.pet_acquired.connect(_mark_dirty.unbind(2))
	EventBus.recipe_unlocked.connect(_mark_dirty.unbind(1))
	EventBus.item_crafted.connect(_mark_dirty.unbind(2))
	EventBus.tier_completed.connect(_mark_dirty.unbind(1))
	EventBus.tier_unlocked.connect(_mark_dirty.unbind(1))
	EventBus.prestige_triggered.connect(_mark_dirty.unbind(2))
	# Re-evaluate on load so a save imported from a newer build (or
	# fixture-loaded in tests) immediately reflects unlocks.
	EventBus.game_loaded.connect(_mark_dirty)


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		evaluate_all()


func _mark_dirty() -> void:
	_dirty = true


## True iff at least one signal has been seen since the last
## evaluator run. Public for tests; the live game just lets _process
## drain it.
func is_dirty() -> bool:
	return _dirty


## Walk every achievement, fire any whose trigger now passes and
## hasn't already been recorded. Public so tests can call it directly
## after staging GameState.
##
## Uses `ContentRegistry.achievement_index()` (cached dict) to avoid
## re-allocating the achievement array on every call.
func evaluate_all() -> void:
	eval_count += 1
	var index := ContentRegistry.achievement_index()
	for id in index.keys():
		var ach: AchievementResource = index[id]
		if ach == null:
			continue
		var id_str: String = String(ach.id)
		if GameState.achievements_unlocked.has(id_str):
			continue
		if _evaluate_trigger(ach):
			_unlock(ach)


## Returns true when the achievement's tracked source has crossed its
## threshold. Adding a new Source enum value means extending this match.
func _evaluate_trigger(ach: AchievementResource) -> bool:
	var threshold: int = max(1, int(ach.threshold))
	match ach.source:
		AchievementResource.Source.LEDGER_FIELD:
			var key: String = String(ach.ledger_field)
			if key == "":
				return false
			return int(GameState.ledger.get(key, 0)) >= threshold
		AchievementResource.Source.PRESTIGE_COUNT:
			return int(GameState.prestige_count) >= threshold
		AchievementResource.Source.PETS_OWNED_COUNT:
			return GameState.pets_owned.size() >= threshold
		AchievementResource.Source.NETS_OWNED_COUNT:
			return GameState.nets_owned.size() >= threshold
		AchievementResource.Source.RECIPES_CRAFTED_COUNT:
			return GameState.recipes_crafted.size() >= threshold
		AchievementResource.Source.CURRENT_MAX_TIER:
			return int(GameState.current_max_tier) >= threshold
	return false


func _unlock(ach: AchievementResource) -> void:
	var id_str: String = String(ach.id)
	GameState.achievements_unlocked[id_str] = true
	if ach.rp_reward > 0:
		GameState.add_rancher_points(ach.rp_reward, "achievement:%s" % id_str)
	var gold_reward: BigNumber = BigNumber.from_dict(ach.gold_reward)
	if not gold_reward.is_zero():
		GameState.add_gold(gold_reward)
	EventBus.achievement_unlocked.emit(id_str)


## Convenience for the Ledger grid: count of unlocked vs total.
func progress_summary() -> Dictionary:
	var total: int = ContentRegistry.achievements().size()
	var unlocked: int = GameState.achievements_unlocked.size()
	return {"unlocked": unlocked, "total": total}
