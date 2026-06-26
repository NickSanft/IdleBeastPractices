## Abstract backend for scheduling local OS notifications. Concrete impls:
##   - StubLocalNotificationBackend:    in-memory recorder (editor / CI / desktop)
##   - AndroidLocalNotificationBackend: wraps a future native plugin singleton
##
## LocalNotificationManager swaps backends in one line; the signal contract is
## fixed so callers stay backend-agnostic. v0.15.14 — built as a testable seam
## for the retention bundle. No native plugin ships yet, so the stub is always
## selected in practice (see the AdsManager / AdsBackend pattern this mirrors).
class_name LocalNotificationBackend
extends Node

## Abstract-interface signals: emitted by concrete subclasses, relayed by
## LocalNotificationManager to game logic.
@warning_ignore("unused_signal")
signal notification_scheduled(notification_id: String)
@warning_ignore("unused_signal")
signal notification_canceled(notification_id: String)
## Fired when the user taps a delivered notification (native backend only).
@warning_ignore("unused_signal")
signal notification_clicked(notification_id: String)


func is_available() -> bool:
	return false


## Schedule a notification to fire `delay_seconds` from now. Re-scheduling the
## same id replaces any prior pending one.
func schedule(_notification_id: String, _title: String, _body: String, _delay_seconds: float) -> void:
	push_error("LocalNotificationBackend.schedule: not implemented")


func cancel(_notification_id: String) -> void:
	push_error("LocalNotificationBackend.cancel: not implemented")


func cancel_all() -> void:
	push_error("LocalNotificationBackend.cancel_all: not implemented")
