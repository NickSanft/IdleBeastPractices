## Tests for CloudSyncManager — orchestration of sign-in / download /
## merge / debounced upload flows.
##
## Headless test runs don't have the PGS plugin singleton registered, so
## CloudSyncManager._ready() leaves `backend` null and `status` stays
## STATUS_DISABLED. Each test that needs an active backend swaps in a
## StubCloudSyncBackend before exercising the orchestration.
extends GutTest

var _saved_backend: CloudSyncBackend
var _stub: StubCloudSyncBackend


func before_each() -> void:
	_saved_backend = CloudSyncManager.backend
	if _saved_backend != null:
		# Detach signals from the real backend so the stub's signals
		# drive the orchestrator instead.
		if _saved_backend.sign_in_complete.is_connected(CloudSyncManager._on_sign_in_complete):
			_saved_backend.sign_in_complete.disconnect(CloudSyncManager._on_sign_in_complete)
		if _saved_backend.upload_complete.is_connected(CloudSyncManager._on_upload_complete):
			_saved_backend.upload_complete.disconnect(CloudSyncManager._on_upload_complete)
		if _saved_backend.download_complete.is_connected(CloudSyncManager._on_download_complete):
			_saved_backend.download_complete.disconnect(CloudSyncManager._on_download_complete)
		if _saved_backend.sign_out_complete.is_connected(CloudSyncManager._on_sign_out_complete):
			_saved_backend.sign_out_complete.disconnect(CloudSyncManager._on_sign_out_complete)
	_stub = StubCloudSyncBackend.new()
	CloudSyncManager.backend = _stub
	CloudSyncManager._initial_sync_done = false
	# Reset status to a known state — between tests the autoload retains
	# state from the previous run.
	CloudSyncManager.status = CloudSyncManager.STATUS_SIGNED_OUT
	_stub.sign_in_complete.connect(CloudSyncManager._on_sign_in_complete)
	_stub.upload_complete.connect(CloudSyncManager._on_upload_complete)
	_stub.download_complete.connect(CloudSyncManager._on_download_complete)
	_stub.sign_out_complete.connect(CloudSyncManager._on_sign_out_complete)


func after_each() -> void:
	if _stub != null:
		_stub.sign_in_complete.disconnect(CloudSyncManager._on_sign_in_complete)
		_stub.upload_complete.disconnect(CloudSyncManager._on_upload_complete)
		_stub.download_complete.disconnect(CloudSyncManager._on_download_complete)
		_stub.sign_out_complete.disconnect(CloudSyncManager._on_sign_out_complete)
	CloudSyncManager.backend = _saved_backend


func test_disabled_when_no_pgs_plugin() -> void:
	# Headless / desktop / web: no PGS plugin -> _saved_backend should
	# have been null when CloudSyncManager booted.
	assert_null(_saved_backend,
			"CloudSyncManager should not pick a real backend without the PGS plugin")


func test_sign_in_then_download_emits_idle() -> void:
	watch_signals(CloudSyncManager)
	CloudSyncManager.sign_in()
	# Stub deferred-emits sign_in_complete on the next frame; the
	# orchestrator then calls download() which deferred-emits
	# download_complete on the frame after that.
	await wait_frames(3)
	assert_eq(CloudSyncManager.status, CloudSyncManager.STATUS_IDLE)
	assert_true(CloudSyncManager.is_signed_in())
	assert_true(CloudSyncManager._initial_sync_done)


func test_upload_after_save_only_fires_when_signed_in() -> void:
	# Without sign-in, EventBus.game_saved should be a no-op.
	EventBus.game_saved.emit()
	await wait_frames(1)
	# No assertion-error and status stays SIGNED_OUT (not UPLOADING).
	assert_eq(CloudSyncManager.status, CloudSyncManager.STATUS_SIGNED_OUT)


func test_status_changed_signal_fires_on_transitions() -> void:
	watch_signals(CloudSyncManager)
	CloudSyncManager.sign_in()
	await wait_frames(3)
	# At minimum we should have transitioned through DOWNLOADING and
	# landed at IDLE.
	var emissions: Array = get_signal_emit_count(CloudSyncManager, "status_changed") as Array if get_signal_emit_count(CloudSyncManager, "status_changed") is Array else []
	# get_signal_emit_count returns a count; we just want to know the
	# signal fired at least once between sign_in and now.
	assert_gt(get_signal_emit_count(CloudSyncManager, "status_changed"), 0)


func test_sign_out_resets_initial_sync_flag() -> void:
	CloudSyncManager.sign_in()
	await wait_frames(3)
	assert_true(CloudSyncManager._initial_sync_done)
	CloudSyncManager.sign_out()
	await wait_frames(1)
	assert_false(CloudSyncManager._initial_sync_done)
	assert_eq(CloudSyncManager.status, CloudSyncManager.STATUS_SIGNED_OUT)


func test_idempotent_sign_in() -> void:
	# Calling sign_in twice should not re-trigger the network round-trip.
	CloudSyncManager.sign_in()
	await wait_frames(3)
	var first_status := CloudSyncManager.status
	CloudSyncManager.sign_in()  # Already signed in -> no-op
	await wait_frames(1)
	assert_eq(CloudSyncManager.status, first_status,
			"second sign_in() should be a no-op when already signed in")
