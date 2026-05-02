## Tests for AdsManager: contract-level checks for reward IDs, backend
## delegation, and signal forwarding. The autoload's real backend is a
## stub by default — we swap in a FakeAdsBackend per-test so we can
## drive completion/failure deterministically without touching dialogs.
extends GutTest


class FakeAdsBackend extends AdsBackend:
	var available: bool = true
	var last_request: String = ""
	var requests: Array[String] = []

	func is_available() -> bool:
		return available

	func show_rewarded(reward_id: String) -> void:
		last_request = reward_id
		requests.append(reward_id)


var _saved_backend: AdsBackend
var _fake: FakeAdsBackend


func before_each() -> void:
	_saved_backend = AdsManager.backend
	if _saved_backend != null:
		AdsManager.remove_child(_saved_backend)
	_fake = FakeAdsBackend.new()
	AdsManager.add_child(_fake)
	AdsManager.backend = _fake
	# Reconnect AdsManager's listener to the fake backend's signals so
	# completed/failed get forwarded to AdsManager.rewarded_completed/_failed.
	_fake.completed.connect(AdsManager._on_backend_completed)
	_fake.failed.connect(AdsManager._on_backend_failed)


func after_each() -> void:
	if _fake != null and is_instance_valid(_fake):
		AdsManager.remove_child(_fake)
		_fake.queue_free()
	if _saved_backend != null and is_instance_valid(_saved_backend):
		AdsManager.add_child(_saved_backend)
	AdsManager.backend = _saved_backend


func test_reward_id_constants_are_stable_strings() -> void:
	# UI sites pass these by name; renaming them silently breaks every
	# callsite. Lock in the literal values.
	assert_eq(AdsManager.REWARD_OFFLINE_2X, "offline_2x")
	assert_eq(AdsManager.REWARD_BATTLE_INSTANT_FINISH, "battle_instant_finish")
	assert_eq(AdsManager.REWARD_DROPS_2X_NEXT_10, "drops_2x_next_10")
	assert_eq(AdsManager.DROPS_2X_CATCH_COUNT, 10)


func test_is_available_delegates_to_backend() -> void:
	_fake.available = true
	assert_true(AdsManager.is_available())
	_fake.available = false
	assert_false(AdsManager.is_available())


func test_show_rewarded_routes_to_backend() -> void:
	AdsManager.show_rewarded(AdsManager.REWARD_OFFLINE_2X)
	assert_eq(_fake.last_request, "offline_2x")
	AdsManager.show_rewarded(AdsManager.REWARD_BATTLE_INSTANT_FINISH)
	assert_eq(_fake.requests.size(), 2)
	assert_eq(_fake.requests[1], "battle_instant_finish")


func test_backend_completed_forwards_to_rewarded_completed() -> void:
	watch_signals(AdsManager)
	_fake.completed.emit(AdsManager.REWARD_DROPS_2X_NEXT_10, true)
	assert_signal_emitted_with_parameters(
			AdsManager,
			"rewarded_completed",
			["drops_2x_next_10", true])


func test_backend_failed_forwards_to_rewarded_failed() -> void:
	watch_signals(AdsManager)
	_fake.failed.emit(AdsManager.REWARD_OFFLINE_2X, "user_canceled")
	assert_signal_emitted_with_parameters(
			AdsManager,
			"rewarded_failed",
			["offline_2x", "user_canceled"])


func test_show_rewarded_with_no_backend_fires_failed() -> void:
	# Edge case: backend cleared (e.g. during shutdown / before _ready).
	# Should fail-soft rather than crash.
	AdsManager.backend = null
	watch_signals(AdsManager)
	AdsManager.show_rewarded(AdsManager.REWARD_OFFLINE_2X)
	assert_signal_emitted_with_parameters(
			AdsManager,
			"rewarded_failed",
			["offline_2x", "no_backend"])
	# Restore the fake so after_each can clean up symmetrically.
	AdsManager.backend = _fake


func test_stub_backend_is_default() -> void:
	# After-each restores the original backend; verify it really was a stub
	# (the production default for Phase 6a, swapped only in Phase 6b).
	# We test this by inspecting the saved backend reference, not the live
	# AdsManager.backend (which is the fake mid-test).
	assert_true(_saved_backend is StubAdsBackend,
			"AdsManager should default to StubAdsBackend in Phase 6a")
