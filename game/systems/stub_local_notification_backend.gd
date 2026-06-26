## In-memory local-notification backend for editor / CI / desktop. v0.15.14.
##
## It can't post real OS notifications, so it RECORDS scheduled/canceled ids
## (a test seam, like AudioManager's sfx counters) and emits the same signals
## the native backend will. This makes the retention seam — schedule on
## app-pause, cancel on resume — fully unit-testable without a device.
class_name StubLocalNotificationBackend
extends LocalNotificationBackend

## id -> {title, body, delay_seconds}. Public so tests can assert exactly what
## the lifecycle wiring scheduled.
var scheduled: Dictionary = {}
## ids passed to cancel(), in order — public for the same reason.
var canceled_ids: Array[String] = []
## Total schedule() calls — distinct from scheduled.size() (which de-dups by id),
## so tests can verify call-level debouncing of the lifecycle wiring.
var schedule_count: int = 0


## NOTE: returns true so the seam runs end-to-end in tests, but this backend
## posts NO real OS notification. Callers must not read is_available()==true as
## "a real notification will fire" — see LocalNotificationManager.is_available.
func is_available() -> bool:
	return true


func schedule(notification_id: String, title: String, body: String, delay_seconds: float) -> void:
	schedule_count += 1
	scheduled[notification_id] = {"title": title, "body": body, "delay_seconds": delay_seconds}
	notification_scheduled.emit(notification_id)


func cancel(notification_id: String) -> void:
	scheduled.erase(notification_id)
	canceled_ids.append(notification_id)
	notification_canceled.emit(notification_id)


func cancel_all() -> void:
	var ids: Array = scheduled.keys()
	scheduled.clear()
	for id_str in ids:
		canceled_ids.append(String(id_str))
		notification_canceled.emit(String(id_str))
