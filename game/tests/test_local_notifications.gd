## v0.15.14 — LocalNotificationManager seam (retention bundle).
##
## The seam fires no real OS notifications (no native plugin), but the stub
## backend records schedule/cancel calls so the offline-cap nudge wiring —
## schedule on app-pause, cancel on resume — is unit-testable on desktop/CI.
extends GutTest

const _MAIN_SCENE := preload("res://game/scenes/main.tscn")


func before_each() -> void:
	ContentRegistry.ensure_loaded()
	GameState.from_dict({})
	# Reset the singleton stub recorder between tests.
	var b: LocalNotificationBackend = LocalNotificationManager.backend
	if b is StubLocalNotificationBackend:
		(b as StubLocalNotificationBackend).scheduled.clear()
		(b as StubLocalNotificationBackend).canceled_ids.clear()
		(b as StubLocalNotificationBackend).schedule_count = 0


# region — stub backend

func test_stub_records_schedule_and_cancel() -> void:
	var b := StubLocalNotificationBackend.new()
	add_child_autofree(b)
	b.schedule("x", "title", "body", 120.0)
	assert_true(b.scheduled.has("x"))
	assert_almost_eq(float(b.scheduled["x"]["delay_seconds"]), 120.0, 0.01)
	b.cancel("x")
	assert_false(b.scheduled.has("x"))
	assert_true("x" in b.canceled_ids)


func test_stub_cancel_all_clears_everything() -> void:
	var b := StubLocalNotificationBackend.new()
	add_child_autofree(b)
	b.schedule("a", "t", "b", 1.0)
	b.schedule("b", "t", "b", 2.0)
	b.cancel_all()
	assert_eq(b.scheduled.size(), 0)
	assert_eq(b.canceled_ids.size(), 2)

# endregion


# region — manager

func test_uses_stub_backend_without_native_plugin() -> void:
	# No "GodotLocalNotification" singleton in CI/desktop → stub is selected.
	assert_true(LocalNotificationManager.backend is StubLocalNotificationBackend)


func test_manager_schedules_offline_cap_warning() -> void:
	LocalNotificationManager.schedule_offline_cap_warning(3600.0)
	var b: StubLocalNotificationBackend = LocalNotificationManager.backend
	assert_true(b.scheduled.has(LocalNotificationManager.NOTIF_OFFLINE_CAP))
	assert_almost_eq(
			float(b.scheduled[LocalNotificationManager.NOTIF_OFFLINE_CAP]["delay_seconds"]),
			3600.0, 0.01)


func test_manager_skips_nonpositive_delay() -> void:
	LocalNotificationManager.schedule_offline_cap_warning(0.0)
	var b: StubLocalNotificationBackend = LocalNotificationManager.backend
	assert_false(b.scheduled.has(LocalNotificationManager.NOTIF_OFFLINE_CAP),
			"a non-positive remaining time schedules nothing")


func test_manager_cancel_removes_pending() -> void:
	LocalNotificationManager.schedule_offline_cap_warning(3600.0)
	LocalNotificationManager.cancel_offline_cap_warning()
	var b: StubLocalNotificationBackend = LocalNotificationManager.backend
	assert_false(b.scheduled.has(LocalNotificationManager.NOTIF_OFFLINE_CAP))
	assert_true(LocalNotificationManager.NOTIF_OFFLINE_CAP in b.canceled_ids)

# endregion


# region — Main lifecycle wiring

func test_pause_schedules_and_resume_cancels() -> void:
	var main: Node = _MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_frames(1)
	var b: StubLocalNotificationBackend = LocalNotificationManager.backend
	b.scheduled.clear()
	b.canceled_ids.clear()
	GameState.active_net = "basic_net"  # offline production requires a net
	main._notification(NOTIFICATION_APPLICATION_PAUSED)
	assert_true(b.scheduled.has(LocalNotificationManager.NOTIF_OFFLINE_CAP),
			"backgrounding schedules the offline-cap nudge")
	main._notification(NOTIFICATION_APPLICATION_RESUMED)
	assert_false(b.scheduled.has(LocalNotificationManager.NOTIF_OFFLINE_CAP),
			"returning before the cap fills cancels the nudge")


func test_multiple_background_notifications_schedule_once() -> void:
	# One backgrounding fires PAUSED + FOCUS_OUT + WM_WINDOW_FOCUS_OUT. The
	# debounce flag must collapse those to a single backend schedule() call
	# (else a real backend does redundant JNI/timer work each time).
	var main: Node = _MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_frames(1)
	var b: StubLocalNotificationBackend = LocalNotificationManager.backend
	b.scheduled.clear()
	b.schedule_count = 0
	GameState.active_net = "basic_net"
	main._notification(NOTIFICATION_APPLICATION_PAUSED)
	main._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	main._notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	assert_eq(b.schedule_count, 1, "three background notifications must schedule the nudge only once")
	# After a resume the debounce re-arms, so the next backgrounding schedules again.
	main._notification(NOTIFICATION_APPLICATION_RESUMED)
	main._notification(NOTIFICATION_APPLICATION_PAUSED)
	assert_eq(b.schedule_count, 2, "a resume re-arms the debounce for the next background")


func test_pause_without_net_schedules_nothing() -> void:
	var main: Node = _MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_frames(1)
	var b: StubLocalNotificationBackend = LocalNotificationManager.backend
	b.scheduled.clear()
	GameState.active_net = ""
	main._notification(NOTIFICATION_APPLICATION_PAUSED)
	assert_false(b.scheduled.has(LocalNotificationManager.NOTIF_OFFLINE_CAP),
			"no net → no offline production → no nudge")

# endregion
