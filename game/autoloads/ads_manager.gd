## Rewarded-video orchestration with a swappable backend.
##
## Phase 6a ships a StubBackend that pops a confirmation dialog instead of
## showing a real ad — useful for editor / dev / CI runs and for shaping
## the gameplay flow without the AdMob SDK in the loop.
##
## Phase 6b will land an AdMobBackend that wraps the Poing Studios Godot
## plugin. The backend swap is a single line; everything in this file and
## every reward-bearing UI hook stays the same.
##
## Reward IDs (stable strings — UI sites pass these by name):
##   REWARD_OFFLINE_2X            : 2× offline-progress reward on welcome-back
##   REWARD_BATTLE_INSTANT_FINISH : skip to end of current battle replay
##   REWARD_DROPS_2X_NEXT_10      : double item drops on the next 10 catches
extends Node

signal rewarded_completed(reward_id: String, granted: bool)
signal rewarded_failed(reward_id: String, reason: String)

const REWARD_OFFLINE_2X := "offline_2x"
const REWARD_BATTLE_INSTANT_FINISH := "battle_instant_finish"
const REWARD_DROPS_2X_NEXT_10 := "drops_2x_next_10"
const DROPS_2X_CATCH_COUNT := 10

var backend: AdsBackend


func _ready() -> void:
	# Phase 6a: stub. Phase 6b detects the AdMob plugin and swaps in the
	# real backend if loaded.
	backend = StubAdsBackend.new()
	add_child(backend)
	backend.completed.connect(_on_backend_completed)
	backend.failed.connect(_on_backend_failed)


## Returns true if a rewarded video can be shown right now. Stub backend
## always returns true; AdMob backend will return false during cooldowns,
## offline, or when fill rate is zero.
func is_available() -> bool:
	return backend != null and backend.is_available()


## Trigger the rewarded video for `reward_id`. Async — listen for
## `rewarded_completed` to apply the reward, or `rewarded_failed` to
## handle a no-fill / user-cancel case.
func show_rewarded(reward_id: String) -> void:
	if backend == null:
		rewarded_failed.emit(reward_id, "no_backend")
		return
	backend.show_rewarded(reward_id)


func _on_backend_completed(reward_id: String, granted: bool) -> void:
	rewarded_completed.emit(reward_id, granted)


func _on_backend_failed(reward_id: String, reason: String) -> void:
	rewarded_failed.emit(reward_id, reason)
