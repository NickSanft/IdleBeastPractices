## Abstract backend for rewarded-video orchestration. Concrete impls:
##   - StubAdsBackend (Phase 6a): confirmation-dialog simulator
##   - AdMobBackend   (Phase 6b): wraps the Poing Studios AdMob plugin
##
## AdsManager swaps backends in one line. The signal contract is fixed
## so UI callers stay backend-agnostic.
class_name AdsBackend
extends Node

signal completed(reward_id: String, granted: bool)
signal failed(reward_id: String, reason: String)


func is_available() -> bool:
	return false


func show_rewarded(reward_id: String) -> void:
	push_error("AdsBackend.show_rewarded: not implemented")
	failed.emit(reward_id, "not_implemented")
