## Phase 6a stub: pops a confirmation dialog and grants the reward
## immediately on confirm, or fires `failed` with reason "user_canceled"
## on cancel. No real ad served. Lets the rest of the rewarded-video
## flow be tested end-to-end without the AdMob SDK.
class_name StubAdsBackend
extends AdsBackend

const _REWARD_LABELS := {
	"offline_2x":            "Watch a (simulated) ad to double your offline rewards?",
	"battle_instant_finish": "Watch a (simulated) ad to instantly finish this battle?",
	"drops_2x_next_10":      "Watch a (simulated) ad for 2× drops on your next 10 catches?",
}

var _dialog: ConfirmationDialog
var _pending_reward_id: String = ""


func _ready() -> void:
	_dialog = ConfirmationDialog.new()
	# AcceptDialog defaults to exclusive=true. The offline reward path pops
	# this stub dialog from inside WelcomeBackDialog (itself an AcceptDialog
	# already exclusive of /root). Two exclusive children on the same parent
	# is illegal and Godot logs:
	#   "Attempting to make child window exclusive, but the parent window
	#    already has another exclusive child."
	# Non-exclusive is fine for a confirm-style stub — input still goes to
	# the topmost popup.
	_dialog.exclusive = false
	_dialog.title = "Rewarded Video (stub)"
	_dialog.get_ok_button().text = "Watch"
	_dialog.confirmed.connect(_on_confirmed)
	_dialog.canceled.connect(_on_canceled)
	add_child(_dialog)


func is_available() -> bool:
	return true


func show_rewarded(reward_id: String) -> void:
	if _pending_reward_id != "":
		# Stub doesn't support concurrent reward requests; reject the new one.
		failed.emit(reward_id, "another_in_flight")
		return
	_pending_reward_id = reward_id
	_dialog.dialog_text = _REWARD_LABELS.get(reward_id,
			"Watch a (simulated) ad to receive: %s" % reward_id)
	_dialog.popup_centered()


func _on_confirmed() -> void:
	var reward_id: String = _pending_reward_id
	_pending_reward_id = ""
	completed.emit(reward_id, true)


func _on_canceled() -> void:
	var reward_id: String = _pending_reward_id
	_pending_reward_id = ""
	failed.emit(reward_id, "user_canceled")
