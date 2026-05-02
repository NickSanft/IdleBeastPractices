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


func test_show_rewarded_emits_requested_signal() -> void:
	# v0.7.1: lets diagnostic overlays distinguish "tap registered, ad in
	# flight" from "ad never asked for" when a load silently fails.
	watch_signals(AdsManager)
	AdsManager.show_rewarded(AdsManager.REWARD_DROPS_2X_NEXT_10)
	assert_signal_emitted_with_parameters(
			AdsManager,
			"requested",
			["drops_2x_next_10"])


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


func test_stub_backend_when_admob_plugin_absent() -> void:
	# Phase 6b: AdsManager picks AdMobAdsBackend when the Poing Studios
	# plugin singleton "PoingGodotAdMob" is registered (Android device with
	# the plugin loaded), and StubAdsBackend everywhere else. Headless test
	# runs don't register the singleton, so the stub should win here.
	assert_false(AdMobAdsBackend.is_plugin_loaded(),
			"PoingGodotAdMob should not be loaded in headless tests")
	assert_true(_saved_backend is StubAdsBackend,
			"Without the AdMob plugin, AdsManager defaults to StubAdsBackend")


func test_admob_backend_fail_softs_without_plugin() -> void:
	# AdMobAdsBackend should NOT crash when instantiated without the plugin
	# singleton — `_ready` short-circuits, `is_available` returns false,
	# and `show_rewarded` emits failed("no_plugin") instead of touching the
	# (uninitialized) RewardedAdLoader.
	var backend := AdMobAdsBackend.new()
	add_child_autofree(backend)
	assert_false(backend.is_available())
	watch_signals(backend)
	backend.show_rewarded("offline_2x")
	assert_signal_emitted_with_parameters(
			backend,
			"failed",
			["offline_2x", "no_plugin"])


func test_admob_backend_resolves_test_unit_when_setting_empty() -> void:
	# project.godot ships `admob/rewarded_unit_id=""`; the backend should
	# fall back to Google's documented test rewarded unit when empty so dev
	# builds (without the ADMOB_REWARDED_UNIT_ID secret) still serve test
	# ads end-to-end.
	var prior: Variant = ProjectSettings.get_setting("admob/rewarded_unit_id", "")
	ProjectSettings.set_setting("admob/rewarded_unit_id", "")
	var backend := AdMobAdsBackend.new()
	add_child_autofree(backend)
	assert_eq(backend._resolve_ad_unit_id(), AdMobAdsBackend._TEST_REWARDED_UNIT)
	# Configured override path.
	ProjectSettings.set_setting("admob/rewarded_unit_id", "ca-app-pub-1234567890123456/0987654321")
	assert_eq(backend._resolve_ad_unit_id(), "ca-app-pub-1234567890123456/0987654321")
	ProjectSettings.set_setting("admob/rewarded_unit_id", prior)
