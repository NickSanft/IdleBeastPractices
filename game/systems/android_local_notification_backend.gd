## Android local-notification backend — wraps a native plugin singleton.
##
## v0.15.14 ships the SEAM only. No such plugin exists yet, so
## is_plugin_loaded() returns false and LocalNotificationManager falls back to
## the stub. When a real plugin (exposing schedule/cancel via a
## "GodotLocalNotification" singleton) is integrated, flip
## permissions/post_notifications=true in export_presets.cfg and this backend
## activates with no caller changes — exactly how AdMobAdsBackend layers on.
##
## NOTE: Android 13+ POST_NOTIFICATIONS is a RUNTIME permission. The native
## plugin (not Godot core, not this file) must request it before scheduling.
class_name AndroidLocalNotificationBackend
extends LocalNotificationBackend

const _PLUGIN_SINGLETON := "GodotLocalNotification"


static func is_plugin_loaded() -> bool:
	return Engine.has_singleton(_PLUGIN_SINGLETON)


func _plugin() -> Object:
	if Engine.has_singleton(_PLUGIN_SINGLETON):
		return Engine.get_singleton(_PLUGIN_SINGLETON)
	return null


func is_available() -> bool:
	return _plugin() != null


func schedule(notification_id: String, title: String, body: String, delay_seconds: float) -> void:
	var p: Object = _plugin()
	if p == null:
		push_warning("AndroidLocalNotificationBackend.schedule: plugin singleton missing")
		return
	# Guarded by has_method so a partial / future-revised plugin can't crash the
	# schedule call; the exact signature is finalized when the plugin lands.
	if p.has_method("schedule"):
		p.call("schedule", notification_id, title, body, int(round(delay_seconds)))
	notification_scheduled.emit(notification_id)


func cancel(notification_id: String) -> void:
	var p: Object = _plugin()
	if p != null and p.has_method("cancel"):
		p.call("cancel", notification_id)
	notification_canceled.emit(notification_id)


func cancel_all() -> void:
	var p: Object = _plugin()
	if p != null and p.has_method("cancel_all"):
		p.call("cancel_all")
