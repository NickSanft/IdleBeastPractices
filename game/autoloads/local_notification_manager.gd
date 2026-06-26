## Orchestrates local OS notifications via a swappable backend, mirroring
## AdsManager. v0.15.14 — a testable seam for the retention bundle.
##
## The only notification today is the "your offline catch reserve is full —
## come back!" nudge: scheduled when the app is backgrounded (to fire when the
## offline cap finishes filling) and canceled when the player returns first.
##
## No native plugin ships yet, so the stub backend is always selected in
## practice (records calls, fires no real notification). Main's lifecycle hooks
## drive schedule/cancel; the stub makes that wiring unit-testable on desktop/CI.
extends Node

signal notification_scheduled(notification_id: String)
signal notification_canceled(notification_id: String)
signal notification_clicked(notification_id: String)

## Stable id for the offline-cap-full nudge.
const NOTIF_OFFLINE_CAP := "offline_cap_full"

var backend: LocalNotificationBackend


func _ready() -> void:
	# Real Android backend when a native plugin singleton is present; the
	# recording stub everywhere else (editor, CI, Windows, Web).
	if AndroidLocalNotificationBackend.is_plugin_loaded():
		backend = AndroidLocalNotificationBackend.new()
	else:
		backend = StubLocalNotificationBackend.new()
	add_child(backend)
	backend.notification_scheduled.connect(_on_backend_scheduled)
	backend.notification_canceled.connect(_on_backend_canceled)
	backend.notification_clicked.connect(_on_backend_clicked)


## True if the active backend can actually post notifications (only the native
## Android backend with a loaded plugin; the stub reports true so the seam runs
## end-to-end in tests, but it posts nothing).
func is_available() -> bool:
	return backend != null and backend.is_available()


## Schedule the "offline reserve is full" nudge to fire `remaining_seconds` from
## now (i.e. when the offline catch-cap finishes filling). A non-positive
## remaining means the cap is already full or disabled — nothing to schedule.
func schedule_offline_cap_warning(remaining_seconds: float) -> void:
	if backend == null:
		return
	if remaining_seconds <= 0.0:
		return
	backend.schedule(
			NOTIF_OFFLINE_CAP,
			"Your beasts are waiting!",
			"Your offline catch reserve is full — come back to collect it.",
			remaining_seconds)


func cancel_offline_cap_warning() -> void:
	if backend == null:
		return
	backend.cancel(NOTIF_OFFLINE_CAP)


func _on_backend_scheduled(notification_id: String) -> void:
	notification_scheduled.emit(notification_id)


func _on_backend_canceled(notification_id: String) -> void:
	notification_canceled.emit(notification_id)


func _on_backend_clicked(notification_id: String) -> void:
	notification_clicked.emit(notification_id)
