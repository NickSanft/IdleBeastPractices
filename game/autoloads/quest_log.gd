## Phase 12g — three-tier concurrent quest log.
##
## Maintains GameState.active_quests (slot 0 SHORT, 1 MEDIUM, 2 LONG)
## and orchestrates fill-on-empty + ladder advancement on completion.
##
## Cadence:
##   _ready:                      ensure each slot has a quest
##   evaluate_progress (signaled): bump current values, fire completion
##                                 if threshold crossed
##   _on_completed:               apply reward, emit quest_completed,
##                                advance ladder OR pick next from pool
##
## The picker is deterministic, NOT random: `_pick_for_slot` sorts the
## eligible ids alphabetically and returns the first. The consequence is
## load-bearing — a slot holds its pick until that quest completes, so an
## unsatisfiable quest pins its slot forever and starves every quest that
## sorts after it. (This shipped: `long_pets_10` asked for 10 pets against
## a supply of 3 and bricked the LONG slot from the first fill.) Content is
## guarded against a repeat by game/tests/test_content_integrity.gd.
extends Node

const SLOT_SHORT := 0
const SLOT_MEDIUM := 1
const SLOT_LONG := 2

# Cached per-slot snapshot of the last-emitted progress, so we don't
# spam quest_progress_changed every signal tick. Slot -> int.
var _last_progress: Dictionary = {0: -1, 1: -1, 2: -1}

## Test/diagnostic counter: number of times `evaluate_progress` has
## actually run. Useful as the assertion target for the per-tap budget
## regression test.
var eval_count: int = 0

# Coalesce per-frame events into a single evaluator pass. See the
# matching note in achievements.gd. Without this, a caught tap on
# Android fired evaluate_progress 3× (monster_tapped, currency_changed
# from add_gold, monster_caught) — and at hold-to-tap's 8 Hz the cost
# was visible in frame timings.
var _dirty: bool = false


func _ready() -> void:
	# Same fan of signals the Achievements autoload subscribes to —
	# any of them might tip a quest's progress past threshold. We
	# don't need a payload, just a re-evaluate trigger.
	EventBus.monster_caught.connect(_mark_dirty.unbind(4))
	EventBus.monster_tapped.connect(_mark_dirty.unbind(2))
	EventBus.pet_acquired.connect(_mark_dirty.unbind(2))
	EventBus.recipe_unlocked.connect(_mark_dirty.unbind(1))
	EventBus.item_crafted.connect(_mark_dirty.unbind(2))
	EventBus.tier_completed.connect(_mark_dirty.unbind(1))
	EventBus.tier_unlocked.connect(_mark_dirty.unbind(1))
	EventBus.prestige_triggered.connect(_mark_dirty.unbind(2))
	EventBus.currency_changed.connect(_mark_dirty.unbind(2))
	# After load, fill empty slots and re-emit progress so the strip
	# can paint its initial state.
	EventBus.game_loaded.connect(_on_game_loaded)
	# Also fill on _ready so a fresh launch (no save) starts with
	# something in each slot.
	call_deferred("_initial_fill")


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		evaluate_progress()


func _mark_dirty() -> void:
	_dirty = true


func is_dirty() -> bool:
	return _dirty


func _on_game_loaded() -> void:
	_initial_fill()
	evaluate_progress()


func _initial_fill() -> void:
	ensure_slot_filled(SLOT_SHORT)
	ensure_slot_filled(SLOT_MEDIUM)
	ensure_slot_filled(SLOT_LONG)
	evaluate_progress()


## Walk every slot, re-read the quest's tracked source, fire completion
## if crossed. Public for tests + main.gd post-prestige refill.
func evaluate_progress() -> void:
	eval_count += 1
	for slot in [SLOT_SHORT, SLOT_MEDIUM, SLOT_LONG]:
		var quest_id_str: String = String(GameState.active_quests.get(slot, ""))
		if quest_id_str == "":
			ensure_slot_filled(slot)
			quest_id_str = String(GameState.active_quests.get(slot, ""))
			if quest_id_str == "":
				continue
		var quest: QuestResource = ContentRegistry.quest(StringName(quest_id_str))
		if quest == null:
			# Stale id (e.g., quest was removed in a content update);
			# clear and refill so the player isn't stuck staring at it.
			GameState.active_quests[slot] = ""
			ensure_slot_filled(slot)
			continue
		var current: int = _evaluate_value(quest)
		var target: int = max(1, int(quest.threshold))
		if _last_progress.get(slot, -1) != current:
			_last_progress[slot] = current
			EventBus.quest_progress_changed.emit(slot, current, target)
		if current >= target:
			_on_completed(slot, quest)


func _on_completed(slot: int, quest: QuestResource) -> void:
	var quest_id_str: String = String(quest.id)
	# Order matters: clear slot + mark completed BEFORE applying
	# rewards. add_rancher_points / add_gold emit currency_changed,
	# which re-enters evaluate_progress via the EventBus subscription.
	# If the slot still pointed at this (already-completed) quest,
	# the re-entry would re-fire _on_completed and recurse infinitely.
	GameState.quests_completed[quest_id_str] = true
	GameState.active_quests[slot] = ""
	_last_progress[slot] = -1
	# Apply rewards.
	if quest.rp_reward > 0:
		GameState.add_rancher_points(quest.rp_reward, "quest:%s" % quest_id_str)
	var gold_reward: BigNumber = BigNumber.from_dict(quest.gold_reward)
	if not gold_reward.is_zero():
		GameState.add_gold(gold_reward)
	if String(quest.item_reward_id) != "" and quest.item_reward_amount > 0:
		GameState.add_item(quest.item_reward_id, quest.item_reward_amount)
	EventBus.quest_completed.emit(quest_id_str)
	if quest.repeatable and String(quest.next_quest_id) != "":
		_activate(slot, String(quest.next_quest_id))
	else:
		ensure_slot_filled(slot)


func ensure_slot_filled(slot: int) -> void:
	if String(GameState.active_quests.get(slot, "")) != "":
		return
	var pick: QuestResource = _pick_for_slot(slot)
	if pick == null:
		return
	_activate(slot, String(pick.id))


func _activate(slot: int, quest_id_str: String) -> void:
	GameState.active_quests[slot] = quest_id_str
	_last_progress[slot] = -1
	EventBus.quest_activated.emit(slot, quest_id_str)


## Returns a quest eligible for the given slot — same QuestTier, not
## currently active in another slot, not already completed (for
## non-repeatables), not the head of a ladder whose chain has already
## been completed past it. Picks deterministically by sorting eligible
## ids alphabetically and returning the first — keeps tests stable
## without a seed plumbed through.
##
## Uses `ContentRegistry.quest_index()` to avoid the per-call array
## allocation, and pre-computes the ladder predecessor map so the
## eligibility check is O(1) per quest instead of O(N).
func _pick_for_slot(slot: int) -> QuestResource:
	var target_tier: int = _slot_to_quest_tier(slot)
	var index := ContentRegistry.quest_index()

	var active_ids: Dictionary = {}
	for s in GameState.active_quests.keys():
		var v: String = String(GameState.active_quests[s])
		if v != "":
			active_ids[v] = true

	# predecessor_of[next_id] = id of the quest that points to it via
	# next_quest_id. Built once per pick instead of re-scanning all
	# quests inside the eligibility loop.
	var predecessor_of: Dictionary = {}
	for k in index.keys():
		var q: QuestResource = index[k]
		if q == null:
			continue
		var next_id_str: String = String(q.next_quest_id)
		if next_id_str != "":
			predecessor_of[next_id_str] = String(q.id)

	var eligible: Array[QuestResource] = []
	for k in index.keys():
		var q: QuestResource = index[k]
		if q == null:
			continue
		if q.quest_tier != target_tier:
			continue
		var id_str: String = String(q.id)
		if active_ids.has(id_str):
			continue
		if GameState.quests_completed.has(id_str):
			continue
		# Ladder tail: if some other quest points at this one via
		# next_quest_id and that predecessor isn't completed yet,
		# issue the head first.
		var pred: String = String(predecessor_of.get(id_str, ""))
		if pred != "" and not GameState.quests_completed.has(pred):
			continue
		eligible.append(q)
	if eligible.is_empty():
		return null
	eligible.sort_custom(func(a, b): return String(a.id) < String(b.id))
	return eligible[0]


func _slot_to_quest_tier(slot: int) -> int:
	match slot:
		SLOT_SHORT: return QuestResource.QuestTier.SHORT
		SLOT_MEDIUM: return QuestResource.QuestTier.MEDIUM
		SLOT_LONG: return QuestResource.QuestTier.LONG
	return QuestResource.QuestTier.SHORT


func _evaluate_value(q: QuestResource) -> int:
	match q.source:
		QuestResource.Source.LEDGER_FIELD:
			var key: String = String(q.ledger_field)
			if key == "":
				return 0
			return int(GameState.ledger.get(key, 0))
		QuestResource.Source.PRESTIGE_COUNT:
			return int(GameState.prestige_count)
		QuestResource.Source.PETS_OWNED_COUNT:
			return GameState.pets_owned.size()
		QuestResource.Source.NETS_OWNED_COUNT:
			return GameState.nets_owned.size()
		QuestResource.Source.RECIPES_CRAFTED_COUNT:
			return GameState.recipes_crafted.size()
		QuestResource.Source.CURRENT_MAX_TIER:
			return int(GameState.current_max_tier)
		QuestResource.Source.RUN_GOLD_EARNED:
			# BigNumber → int via to_float. Quests under 2^53 worth of
			# gold are fine; the largest threshold authored is 1M, so
			# precision is non-issue.
			return int(BigNumber.from_dict(GameState.total_gold_earned_this_run).to_float())
	return 0


## For QuestStrip rendering. Returns
##   {quest, current, target, progress}
## with quest possibly null if the slot is empty / unfillable.
func slot_state(slot: int) -> Dictionary:
	var quest_id_str: String = String(GameState.active_quests.get(slot, ""))
	if quest_id_str == "":
		return {"quest": null, "current": 0, "target": 0, "progress": 0.0}
	var quest: QuestResource = ContentRegistry.quest(StringName(quest_id_str))
	if quest == null:
		return {"quest": null, "current": 0, "target": 0, "progress": 0.0}
	var current: int = _evaluate_value(quest)
	var target: int = max(1, int(quest.threshold))
	var baseline: int = max(0, int(quest.baseline))
	var span: int = max(1, target - baseline)
	var progress: float = clamp(float(current - baseline) / float(span), 0.0, 1.0)
	return {"quest": quest, "current": current, "target": target, "progress": progress}
