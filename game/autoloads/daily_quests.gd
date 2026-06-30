## v0.15.15 — daily-resetting quest set (retention bundle).
##
## Manages a small set of DAILY-tier quests that reset at local midnight. Each
## tracks a per-day DELTA of a lifetime ledger counter (catches / taps / shinies):
## at day-start the counter is snapshotted as a baseline, and progress =
## current - baseline. Completing one grants progress-scaled gold; completing the
## whole day's set grants a Rancher-Points bonus (the retention driver).
##
## Mirrors QuestLog's cadence: subscribe to the catch/tap signals, coalesce per
## frame via a dirty flag, and mark a quest done BEFORE granting its reward so a
## reward-driven re-evaluation can't double-fire. The day boundary reuses
## DailyLoginSystem.local_day_index; the pick/curve maths live in the pure
## DailyQuestsSystem.
extends Node

# Per-quest-id snapshot of the last-emitted progress, to avoid spamming
# daily_quest_progress_changed every signal tick. quest_id -> int.
var _last_progress: Dictionary = {}

## Diagnostic counter — number of evaluate_progress() passes.
var eval_count: int = 0

var _dirty: bool = false


func _ready() -> void:
	# Catches + shinies arrive via monster_caught; taps via monster_tapped —
	# the only ledger counters the daily quests track. (No currency_changed
	# subscription, so reward grants can't re-enter the evaluator.)
	EventBus.monster_caught.connect(_mark_dirty.unbind(4))
	EventBus.monster_tapped.connect(_mark_dirty.unbind(2))
	EventBus.game_loaded.connect(_on_game_loaded)
	# Fresh launch (no save) — initialize once content + state are ready.
	call_deferred("_initialize")


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		evaluate_progress()


func _mark_dirty() -> void:
	_dirty = true


func is_dirty() -> bool:
	return _dirty


## Returning to the app (possibly across midnight) — roll the set over if the
## local day changed, then repaint.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_RESUMED, \
		NOTIFICATION_APPLICATION_FOCUS_IN, \
		NOTIFICATION_WM_WINDOW_FOCUS_IN:
			if _check_reset():
				evaluate_progress()


func _on_game_loaded() -> void:
	# Defer: on boot, game_loaded fires from inside SaveManager.load_save BEFORE
	# main calls GameState.from_dict, so running _initialize now would reset the
	# set against stale pre-load state (then get overwritten). Deferring runs it
	# once, after from_dict, with the real loaded state. (Idempotent vs the
	# _ready deferral — _check_reset no-ops within a day.)
	call_deferred("_initialize")


func _initialize() -> void:
	ContentRegistry.ensure_loaded()
	_check_reset()
	evaluate_progress()


## Roll over to today's daily set if the local day changed (or nothing is set up
## yet). Returns true if a reset happened. Idempotent within a day.
func _check_reset() -> bool:
	var today: int = DailyLoginSystem.local_day_index(
			TimeManager.now_unix(), TimeManager.tz_bias_minutes())
	if today == GameState.daily_quests_reset_day and not GameState.daily_quests_active.is_empty():
		return false
	_reset_for_day(today)
	return true


func _reset_for_day(today: int) -> void:
	ContentRegistry.ensure_loaded()
	GameState.daily_quests_reset_day = today
	GameState.daily_quests_active = DailyQuestsSystem.pick_for_day(_daily_pool(), today)
	GameState.daily_quests_done = {}
	GameState.daily_quests_bonus_claimed = false
	GameState.daily_quest_baselines = _snapshot_baselines(GameState.daily_quests_active)
	_last_progress.clear()
	EventBus.daily_quests_reset.emit()


## Walk the day's quests, emit progress, complete any that crossed threshold,
## and grant the complete-all bonus once every quest is done. Public for tests.
func evaluate_progress() -> void:
	eval_count += 1
	_check_reset()
	var active: Array = GameState.daily_quests_active
	if active.is_empty():
		return
	for qid_v in active:
		var qid: String = String(qid_v)
		var quest: QuestResource = ContentRegistry.quest(StringName(qid))
		if quest == null:
			continue
		var current: int = _daily_progress(quest)
		var target: int = max(1, int(quest.threshold))
		if int(_last_progress.get(qid, -1)) != current:
			_last_progress[qid] = current
			# Emit the raw (unclamped) current so subscribers get the true value;
			# display sites clamp to target themselves.
			EventBus.daily_quest_progress_changed.emit(qid, current, target)
		if current >= target and not GameState.daily_quests_done.has(qid):
			_complete_daily(qid)
	if not GameState.daily_quests_bonus_claimed and _all_done():
		_grant_complete_all_bonus()


func _complete_daily(qid: String) -> void:
	# Mark done BEFORE the reward so a reward-driven re-evaluation skips it.
	GameState.daily_quests_done[qid] = true
	var gold: BigNumber = DailyQuestsSystem.quest_gold(
			BigNumber.from_dict(GameState.total_gold_earned_this_run), GameState.current_max_tier)
	if not gold.is_zero():
		GameState.add_gold(gold)
	EventBus.daily_quest_completed.emit(qid)


func _grant_complete_all_bonus() -> void:
	GameState.daily_quests_bonus_claimed = true
	var rp: int = DailyQuestsSystem.complete_all_rp(GameState.current_max_tier)
	if rp > 0:
		GameState.add_rancher_points(rp, "daily_quests_complete_all")
	EventBus.daily_quests_all_completed.emit(rp)


func _all_done() -> bool:
	if GameState.daily_quests_active.is_empty():
		return false
	for qid_v in GameState.daily_quests_active:
		if not GameState.daily_quests_done.has(String(qid_v)):
			return false
	return true


func _daily_pool() -> Array:
	var out: Array = []
	for q in ContentRegistry.quests():
		if q != null and q.quest_tier == QuestResource.QuestTier.DAILY:
			out.append(q)
	return out


func _snapshot_baselines(active_ids: Array) -> Dictionary:
	var baselines: Dictionary = {}
	for qid_v in active_ids:
		var quest: QuestResource = ContentRegistry.quest(StringName(qid_v))
		if quest == null:
			continue
		var field: String = String(quest.ledger_field)
		baselines[field] = int(GameState.ledger.get(field, 0))
	return baselines


## Per-day delta = current lifetime counter - the day-start baseline.
func _daily_progress(quest: QuestResource) -> int:
	var field: String = String(quest.ledger_field)
	var current: int = int(GameState.ledger.get(field, 0))
	var baseline: int = int(GameState.daily_quest_baselines.get(field, current))
	return max(0, current - baseline)


## For DailyQuestsView. Returns {quest, current, target, progress, done}.
func quest_state(qid: String) -> Dictionary:
	var quest: QuestResource = ContentRegistry.quest(StringName(qid))
	if quest == null:
		return {"quest": null, "current": 0, "target": 0, "progress": 0.0, "done": false}
	var current: int = _daily_progress(quest)
	var target: int = max(1, int(quest.threshold))
	var done: bool = GameState.daily_quests_done.has(qid)
	# A completed quest shows a full bar even if the counter kept climbing.
	var progress: float = 1.0 if done else clamp(float(current) / float(target), 0.0, 1.0)
	return {
		"quest": quest,
		"current": min(current, target),
		"target": target,
		"progress": progress,
		"done": done,
	}


## True once every daily quest is complete.
func all_complete() -> bool:
	return _all_done()


## Number of today's daily quests completed so far (for the nav badge).
func completed_count() -> int:
	var n: int = 0
	for qid_v in GameState.daily_quests_active:
		if GameState.daily_quests_done.has(String(qid_v)):
			n += 1
	return n


## Number of daily quests in today's set (0 before the first reset).
func active_count() -> int:
	return GameState.daily_quests_active.size()
