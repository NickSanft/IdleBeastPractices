## Authoritative game time + offline duration calculation + anti-cheat clock check.
extends Node

const OFFLINE_CAP_DEFAULT_SECONDS := 3600.0

var session_start_unix: int = 0
var clock_warning: bool = false


func _ready() -> void:
	session_start_unix = now_unix()


func now_unix() -> int:
	return int(Time.get_unix_time_from_system())


## Compute how many seconds elapsed since `last_save_unix`, capped at `cap_seconds`.
## If the device clock is earlier than `last_save_unix`, set clock_warning=true and return 0.
func compute_offline_elapsed(last_save_unix: int, cap_seconds: float) -> float:
	if last_save_unix <= 0:
		return 0.0
	var now := now_unix()
	if now < last_save_unix:
		clock_warning = true
		push_warning("TimeManager: device clock is earlier than last save (%d < %d) — crediting 0 offline seconds" % [now, last_save_unix])
		return 0.0
	var delta: float = float(now - last_save_unix)
	return clampf(delta, 0.0, cap_seconds)
