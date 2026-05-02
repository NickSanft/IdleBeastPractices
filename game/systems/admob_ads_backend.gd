## Real AdMob backend wrapping the Poing Studios godot-admob plugin
## (res://addons/admob). Used in place of StubAdsBackend on Android
## devices where the plugin singleton "PoingGodotAdMob" is registered.
##
## Lifecycle for each rewarded video:
##   show_rewarded(reward_id)
##     -> RewardedAdLoader.new().load(unit_id, AdRequest, _load_callback)
##     -> _on_ad_loaded(ad)              ad.show(_reward_listener)
##     -> _on_user_earned_reward(item)   _reward_earned = true
##     -> _on_ad_dismissed()             emits completed/failed and destroys ad
##
## Reward signals are emitted on dismiss (not on the earned callback) so the
## game's UI transitions happen on a clean screen, not over the ad surface.
class_name AdMobAdsBackend
extends AdsBackend

## Google's documented test rewarded ad unit. Always serves a test ad
## regardless of network conditions. Used when the project setting
## `admob/rewarded_unit_id` is empty (default in source; CI release jobs
## patch it with the ADMOB_REWARDED_UNIT_ID secret).
const _TEST_REWARDED_UNIT := "ca-app-pub-3940256099942544/5224354917"

const _PLUGIN_SINGLETON := "PoingGodotAdMob"

var _initialized: bool = false
var _is_loading: bool = false
var _pending_reward_id: String = ""
var _reward_earned: bool = false
var _rewarded_ad: RewardedAd = null
var _load_callback: RewardedAdLoadCallback
var _content_callback: FullScreenContentCallback
var _reward_listener: OnUserEarnedRewardListener


func _ready() -> void:
	if not _is_plugin_available():
		return
	_setup_callbacks()
	_initialize_admob()


static func is_plugin_loaded() -> bool:
	return Engine.has_singleton(_PLUGIN_SINGLETON)


func _is_plugin_available() -> bool:
	return Engine.has_singleton(_PLUGIN_SINGLETON)


func _initialize_admob() -> void:
	var listener := OnInitializationCompleteListener.new()
	listener.on_initialization_complete = _on_initialization_complete
	# Conservative defaults for an idle game with no age verification.
	# UNSPECIFIED is the SDK's "don't apply special handling" value.
	var config := RequestConfiguration.new()
	MobileAds.set_request_configuration(config)
	MobileAds.initialize(listener)


func _setup_callbacks() -> void:
	_load_callback = RewardedAdLoadCallback.new()
	_load_callback.on_ad_loaded = _on_ad_loaded
	_load_callback.on_ad_failed_to_load = _on_ad_failed_to_load

	_content_callback = FullScreenContentCallback.new()
	_content_callback.on_ad_dismissed_full_screen_content = _on_ad_dismissed
	_content_callback.on_ad_failed_to_show_full_screen_content = _on_ad_failed_to_show

	_reward_listener = OnUserEarnedRewardListener.new()
	_reward_listener.on_user_earned_reward = _on_user_earned_reward


func is_available() -> bool:
	return _is_plugin_available() and _initialized and not _is_loading and _pending_reward_id == ""


func show_rewarded(reward_id: String) -> void:
	if not _is_plugin_available():
		failed.emit(reward_id, "no_plugin")
		return
	if not _initialized:
		failed.emit(reward_id, "not_initialized")
		return
	if _is_loading or _pending_reward_id != "":
		failed.emit(reward_id, "another_in_flight")
		return
	_pending_reward_id = reward_id
	_reward_earned = false
	_is_loading = true
	var unit_id: String = _resolve_ad_unit_id()
	RewardedAdLoader.new().load(unit_id, AdRequest.new(), _load_callback)


func _resolve_ad_unit_id() -> String:
	# `admob/use_test_ad_units=true` short-circuits the configured value and
	# forces Google's universal test ad unit. Used while the production
	# AdMob account is "in review" and real units return "Publisher Data
	# not found". Defaults to false so production builds use the real unit.
	if bool(ProjectSettings.get_setting("admob/use_test_ad_units", false)):
		return _TEST_REWARDED_UNIT
	var configured: String = String(ProjectSettings.get_setting("admob/rewarded_unit_id", ""))
	if configured.is_empty():
		return _TEST_REWARDED_UNIT
	return configured


func _on_initialization_complete(_status: InitializationStatus) -> void:
	_initialized = true


func _on_ad_loaded(ad: RewardedAd) -> void:
	_is_loading = false
	_rewarded_ad = ad
	ad.full_screen_content_callback = _content_callback
	ad.show(_reward_listener)


func _on_ad_failed_to_load(error: LoadAdError) -> void:
	_is_loading = false
	var reward_id := _pending_reward_id
	_pending_reward_id = ""
	failed.emit(reward_id, "load_failed:" + error.message)


func _on_user_earned_reward(_item: RewardedItem) -> void:
	# Just record — emit on dismiss so UI transitions happen on a clean screen.
	_reward_earned = true


func _on_ad_dismissed() -> void:
	var reward_id := _pending_reward_id
	var earned := _reward_earned
	_pending_reward_id = ""
	_reward_earned = false
	_destroy_ad()
	if earned:
		completed.emit(reward_id, true)
	else:
		failed.emit(reward_id, "user_canceled")


func _on_ad_failed_to_show(error: AdError) -> void:
	var reward_id := _pending_reward_id
	_pending_reward_id = ""
	_reward_earned = false
	_destroy_ad()
	failed.emit(reward_id, "show_failed:" + error.message)


func _destroy_ad() -> void:
	if _rewarded_ad:
		_rewarded_ad.destroy()
		_rewarded_ad = null
