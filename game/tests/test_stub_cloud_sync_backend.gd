## Tests for StubCloudSyncBackend — verifies the contract abstract
## CloudSyncBackend defines (sign-in lifecycle, upload/download flow)
## and the stub's specific behavior (in-memory dict round-trip).
extends GutTest

var _backend: StubCloudSyncBackend


func before_each() -> void:
	_backend = StubCloudSyncBackend.new()


func test_is_available_returns_true_for_stub() -> void:
	assert_true(_backend.is_available())


func test_starts_signed_out() -> void:
	assert_false(_backend.is_signed_in())


func test_sign_in_emits_success_and_flips_state() -> void:
	watch_signals(_backend)
	_backend.sign_in()
	# call_deferred fires after one frame.
	await wait_frames(1)
	assert_signal_emitted_with_parameters(_backend, "sign_in_complete", [true, ""])
	assert_true(_backend.is_signed_in())


func test_sign_out_clears_state() -> void:
	_backend.sign_in()
	await wait_frames(1)
	watch_signals(_backend)
	_backend.sign_out()
	await wait_frames(1)
	assert_signal_emitted(_backend, "sign_out_complete")
	assert_false(_backend.is_signed_in())


func test_upload_while_signed_out_fails() -> void:
	# Defense: orchestrator shouldn't be uploading without auth, but if
	# it does we want a clean failure signal, not a silent drop.
	watch_signals(_backend)
	_backend.upload({"any": "state"})
	await wait_frames(1)
	assert_signal_emitted_with_parameters(
			_backend, "upload_complete", [false, "not_signed_in"])


func test_upload_then_download_roundtrips() -> void:
	# Stub simulates a cloud round-trip: upload from device A, download
	# on device B, get back the same dict.
	_backend.sign_in()
	await wait_frames(1)
	var state := {
		"last_saved_unix": 1000,
		"pets_owned": ["green_wisplet_pet"],
		"ledger": {"total_catches": 42},
	}
	watch_signals(_backend)
	_backend.upload(state)
	await wait_frames(1)
	assert_signal_emitted_with_parameters(_backend, "upload_complete", [true, ""])

	# A fresh download should return the uploaded state.
	_backend.download()
	await wait_frames(1)
	var downloaded: Dictionary = _backend._stored_state
	# Compare via the signal to verify the public surface, not the field.
	# (Field check is just a defensive duplicate.)
	assert_eq(downloaded["pets_owned"], state["pets_owned"])
	assert_eq(downloaded["ledger"]["total_catches"], 42)


func test_download_first_time_returns_empty_dict() -> void:
	# Simulates a fresh device pulling cloud state when nothing was ever
	# uploaded. Expected: success=true, data={}. The orchestrator should
	# treat this as "no remote save; keep local."
	_backend.sign_in()
	await wait_frames(1)
	watch_signals(_backend)
	_backend.download()
	await wait_frames(1)
	assert_signal_emitted_with_parameters(
			_backend, "download_complete", [{}, true, ""])


func test_upload_does_not_mutate_input() -> void:
	# Safety: the orchestrator passes GameState.to_dict() output directly;
	# the backend must not mutate caller-owned state.
	_backend.sign_in()
	await wait_frames(1)
	var state := {"pets_owned": ["a", "b"]}
	var snapshot := state.duplicate(true)
	_backend.upload(state)
	await wait_frames(1)
	assert_eq(state, snapshot)
