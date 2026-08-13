## Persistence robustness — the paths that can silently destroy a save.
##
## Three defects lived here, none of them covered by a test, all of them
## capable of costing a player their whole account:
##
##   1. `GameState.last_saved_unix` was never refreshed after a write.
##      SaveManager stamped the timestamp into the DUPLICATED dict it wrote to
##      disk and never back onto the autoload, so the in-memory field held
##      whatever was loaded at boot — 0 on a fresh install. Since
##      SaveConflictResolver picks the merge BASE by that field and
##      CloudSyncManager feeds it `GameState.to_dict()`, an older cloud
##      snapshot could beat a device that had just played for hours.
##   2. `LocalFileBackend.write` never checked whether the bytes landed, so a
##      full disk produced a truncated .tmp that the rename then promoted over
##      the good save — returning true and emitting `game_saved`.
##   3. `SaveManager.load_save` returned a bare `{}` for corrupt JSON, an empty
##      read, and a too-new version alike — indistinguishable from a genuine
##      first launch, so the game seeded a new ranch and the 10-second autosave
##      overwrote the original within seconds.
##
## These tests touch the REAL user:// save, so every test clears it on both
## sides and sweeps the quarantine files the failure paths create.
extends GutTest

const _SAVE_PATH := "user://save.json"
const _TMP_PATH := "user://save.json.tmp"
const _MAIN_SCENE := preload("res://game/scenes/main.tscn")
## Fixed wall-clock (2033), same rationale as test_daily_login_integration:
## deterministic day maths, and ahead of any on-disk last_saved_unix so a boot
## in these tests never trips the clock-backward guard.
const _FIXED_NOW := 2_000_000_000


func before_each() -> void:
	SaveManager.backend.clear()
	_sweep_backups()
	GameState._reset_to_defaults()


func after_each() -> void:
	SaveManager.backend.clear()
	_sweep_backups()
	GameState._reset_to_defaults()
	TimeManager._test_now_override = -1


## Quarantine deliberately leaves save.json.bak-<unix> behind for recovery;
## tests must not accumulate them in the user data dir.
func _sweep_backups() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var entry: String = dir.get_next()
		if entry == "":
			break
		if entry.begins_with("save.json.bak-"):
			dir.remove(entry)
	dir.list_dir_end()


func _write_raw(path: String, contents: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(contents)
	f.close()


## The corrupt-input tests exist to drive paths that deliberately push_error —
## and malformed JSON also makes the engine log its own parse error. Assert the
## message we actually care about (so the intent is pinned, not merely
## silenced), then clear the remainder so GUT does not fail the test for the
## very errors it was written to provoke.
func _expect_error(text: String) -> void:
	assert_push_error(text)
	for e in get_errors():
		e.handled = true


func _count_backups() -> int:
	var n: int = 0
	var dir := DirAccess.open("user://")
	if dir == null:
		return 0
	dir.list_dir_begin()
	while true:
		var entry: String = dir.get_next()
		if entry == "":
			break
		if entry.begins_with("save.json.bak-"):
			n += 1
	dir.list_dir_end()
	return n


# region — 1. last_saved_unix stays in step with disk

func test_save_refreshes_the_in_memory_timestamp() -> void:
	GameState.last_saved_unix = 0
	SaveManager.save(GameState.to_dict())
	assert_gt(GameState.last_saved_unix, 0,
			"save() must stamp the in-memory field, not only the dict it writes")


func test_saved_timestamp_matches_what_landed_on_disk() -> void:
	GameState.last_saved_unix = 0
	SaveManager.save(GameState.to_dict())
	var on_disk: Dictionary = JSON.parse_string(SaveManager.backend.read())
	assert_eq(GameState.last_saved_unix, int(on_disk["last_saved_unix"]),
			"in-memory stamp and on-disk stamp must agree — the resolver compares them")


## The defect in its sharpest form: a device with no prior save holds
## last_saved_unix = 0 for the whole session, so its very first cloud merge
## treats ANY remote as newer and discards everything played that session.
func test_fresh_session_wins_the_merge_against_an_older_remote() -> void:
	GameState._reset_to_defaults()
	GameState.current_max_tier = 9
	SaveManager.save(GameState.to_dict())

	var local: Dictionary = GameState.to_dict()
	# A FIXED past stamp, deliberately not derived from GameState
	# .last_saved_unix. Deriving it would make this a tautology: revert the fix
	# and the field stays 0, the remote becomes negative, and local still wins
	# for the wrong reason. With 1000 fixed, reverting the fix flips the result.
	var remote: Dictionary = {
		"last_saved_unix": 1_000,
		"current_max_tier": 1,
		"active_net": "stale_remote_net",
	}
	var merged: Dictionary = SaveConflictResolver.resolve(local, remote)
	assert_eq(int(merged["last_saved_unix"]), GameState.last_saved_unix,
			"the just-played local save must be the merge base")
	assert_ne(String(merged.get("active_net", "")), "stale_remote_net",
			"an older remote must not overwrite unmerged local fields")

# endregion


# region — 2. writes fail closed

func test_write_round_trips_over_an_existing_save() -> void:
	assert_true(SaveManager.backend.write('{"a":1}'))
	assert_true(SaveManager.backend.write('{"a":2}'),
			"a second write must succeed — the rename has to overwrite the target")
	assert_eq(SaveManager.backend.read(), '{"a":2}')


## Failure injection: the whole point of the write rewrite is that a failed
## write must never touch save.json. Occupying the .tmp path with a DIRECTORY
## makes FileAccess.open fail for real, rather than asserting the happy path and
## calling it "fails closed".
func test_a_failed_write_leaves_the_previous_save_intact() -> void:
	assert_true(SaveManager.backend.write('{"good":1}'))
	var dir := DirAccess.open("user://")
	dir.make_dir(_TMP_PATH.get_file())

	var ok: bool = SaveManager.backend.write('{"replacement":2}')
	_expect_error("failed to open")
	assert_false(ok, "write must report failure when the tmp cannot be opened")
	assert_eq(SaveManager.backend.read(), '{"good":1}',
			"a failed write must leave the previous save byte-identical")

	# And the two consequences nothing else guards: the marker must NOT advance
	# (main's resume tick treats it as "last credited at", so a fake advance
	# would drop an offline window), and game_saved must NOT fire (CloudSyncManager
	# uploads on it — pushing state we failed to persist locally).
	GameState.last_saved_unix = 4242
	watch_signals(EventBus)
	var saved: bool = SaveManager.save(GameState.to_dict())
	_expect_error("failed to open")
	assert_false(saved, "SaveManager.save must surface the backend failure")
	assert_eq(GameState.last_saved_unix, 4242, "a failed write must not advance the marker")
	assert_signal_not_emitted(EventBus, "game_saved")

	dir.remove(_TMP_PATH.get_file())


func test_write_leaves_no_tmp_behind_on_success() -> void:
	assert_true(SaveManager.backend.write('{"a":1}'))
	assert_false(FileAccess.file_exists(_TMP_PATH),
			"the .tmp must be consumed by the rename, not left to be 'recovered' later")


## A crash inside write()'s rename window leaves a complete .tmp and no
## save.json. Reporting "no save" there sends SaveManager down the first-launch
## path and strands recoverable progress.
func test_a_lone_tmp_is_recovered() -> void:
	SaveManager.backend.clear()
	_write_raw(_TMP_PATH, '{"version":%d,"current_max_tier":7}' % SaveManager.CURRENT_VERSION)
	assert_true(SaveManager.backend.exists(), "a lone .tmp counts as a save on disk")
	var loaded: Dictionary = SaveManager.load_save()
	assert_false(SaveManager.load_failed, "a VALID .tmp is a successful load, not a failure")
	assert_eq(int(loaded.get("current_max_tier", 0)), 7)


func test_save_json_wins_over_a_stale_tmp() -> void:
	_write_raw(_SAVE_PATH, '{"version":%d,"current_max_tier":5}' % SaveManager.CURRENT_VERSION)
	_write_raw(_TMP_PATH, '{"version":%d,"current_max_tier":99}' % SaveManager.CURRENT_VERSION)
	var loaded: Dictionary = SaveManager.load_save()
	assert_eq(int(loaded.get("current_max_tier", 0)), 5,
			"the committed save takes precedence; .tmp is only a fallback")

# endregion


# region — 3. the loader fails closed, not open

func test_corrupt_json_is_reported_and_quarantined() -> void:
	_write_raw(_SAVE_PATH, "{ this is not json")
	var loaded: Dictionary = SaveManager.load_save()
	_expect_error("save file is not a JSON object")
	assert_true(loaded.is_empty(), "an unusable save yields defaults")
	assert_true(SaveManager.load_failed,
			"corrupt must be distinguishable from first launch — otherwise the autosave eats it")
	assert_eq(_count_backups(), 1, "the original bytes must be preserved, not destroyed")
	assert_false(FileAccess.file_exists(_SAVE_PATH), "the unusable file is moved aside")


func test_a_save_from_a_newer_build_is_not_silently_wiped() -> void:
	_write_raw(_SAVE_PATH, '{"version":%d,"current_max_tier":12}' % (SaveManager.CURRENT_VERSION + 1))
	var loaded: Dictionary = SaveManager.load_save()
	_expect_error("is newer than client version")
	assert_true(loaded.is_empty())
	assert_true(SaveManager.load_failed)
	assert_eq(_count_backups(), 1,
			"downgrading builds must not destroy the newer save")


func test_empty_save_file_is_treated_as_a_failure() -> void:
	_write_raw(_SAVE_PATH, "")
	var loaded: Dictionary = SaveManager.load_save()
	_expect_error("save file was empty or unreadable")
	assert_true(loaded.is_empty())
	assert_true(SaveManager.load_failed)


## Quarantine must also consume a bad .tmp, or read() "recovers" the same
## unusable bytes on every subsequent boot and re-quarantines them forever.
func test_quarantine_consumes_a_bad_tmp_so_it_is_not_re_recovered() -> void:
	SaveManager.backend.clear()
	_write_raw(_TMP_PATH, "{ garbage")
	assert_true(SaveManager.load_save().is_empty())
	_expect_error("save file is not a JSON object")
	assert_true(SaveManager.load_failed)
	assert_false(FileAccess.file_exists(_TMP_PATH), "the bad .tmp must not survive")
	SaveManager.load_save()
	assert_false(SaveManager.load_failed, "second boot is a clean first launch, not another failure")


func test_genuine_first_launch_is_not_flagged_as_a_failure() -> void:
	SaveManager.backend.clear()
	var loaded: Dictionary = SaveManager.load_save()
	assert_true(loaded.is_empty())
	assert_false(SaveManager.load_failed, "no save at all is a first launch, not corruption")
	assert_eq(_count_backups(), 0, "nothing to preserve, nothing to write")


func _day_index() -> int:
	return DailyLoginSystem.local_day_index(TimeManager.now_unix(), TimeManager.tz_bias_minutes())


## Boot pops the welcome-back / daily-reward modals on a fresh state, and
## _resume_tick deliberately refuses to stack on a visible modal. Clear them so
## the resume path under test is actually reached.
func _clear_boot_modals(main: Node) -> void:
	for name in ["_welcome_back_dialog", "_daily_reward_dialog"]:
		var d: Node = main.get(name)
		if d != null and is_instance_valid(d):
			# remove_child BEFORE queue_free: queue_free is deferred, so the
			# node would keep the parent window's single exclusive-child slot
			# until end of frame and the next modal could not open.
			if d.get_parent() != null:
				d.get_parent().remove_child(d)
			d.queue_free()
		main.set(name, null)
	main._pending_daily_summary = {}


## The retention half of this cluster: leaving the app resident in the
## background across local midnight used to break the login streak, because
## _apply_daily_login ran only in _ready(). DailyQuests already re-checked on
## these same notifications, so the asymmetry was the bug.
func test_resume_across_local_midnight_rolls_the_daily_login() -> void:
	TimeManager._test_now_override = _FIXED_NOW
	var main: Node = _MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_frames(1)
	_clear_boot_modals(main)
	# Keep offline progress out of this assertion — no net means no production.
	GameState.active_net = ""
	var boot_day: int = _day_index()
	assert_eq(GameState.daily_login_last_day, boot_day, "boot should have claimed today")

	TimeManager._test_now_override = _FIXED_NOW + 86_400
	main._notification(NOTIFICATION_APPLICATION_RESUMED)

	assert_eq(GameState.daily_login_last_day, _day_index(),
			"a resume after midnight must claim the new day rather than wait for a cold boot")
	assert_eq(GameState.daily_login_streak, 2, "consecutive days extend the streak")


## WM_WINDOW_FOCUS_IN is window-level: it fires on desktop alt-tab and during
## startup, so it deliberately does NOT drive the resume tick. Removing that
## exclusion does fail the full suite today, but only incidentally — as
## "Unexpected Errors" from another file's frame pumping. This asserts the
## design decision semantically so it cannot quietly regress.
func test_window_focus_alone_does_not_credit_a_resume() -> void:
	TimeManager._test_now_override = _FIXED_NOW
	var main: Node = _MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_frames(1)
	_clear_boot_modals(main)
	GameState.active_net = ""
	var day_before: int = GameState.daily_login_last_day

	TimeManager._test_now_override = _FIXED_NOW + 86_400
	main._notification(NOTIFICATION_WM_WINDOW_FOCUS_IN)

	assert_eq(GameState.daily_login_last_day, day_before,
			"a window-level focus must not roll the day — only app-level resumes do")


## The modal guard must swallow the burst of two-to-three focus notifications a
## single Android resume can dispatch, so the day is claimed once.
func test_resume_notification_burst_claims_only_once() -> void:
	TimeManager._test_now_override = _FIXED_NOW
	var main: Node = _MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_frames(1)
	_clear_boot_modals(main)
	GameState.active_net = ""

	TimeManager._test_now_override = _FIXED_NOW + 86_400
	main._notification(NOTIFICATION_APPLICATION_RESUMED)
	var streak_after_first: int = GameState.daily_login_streak
	main._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	main._notification(NOTIFICATION_WM_WINDOW_FOCUS_IN)
	assert_eq(GameState.daily_login_streak, streak_after_first,
			"the same day must not be claimed three times")


## The resume tick re-saves on purpose: that advances the "last credited at"
## marker ON DISK, so a process kill after a resume cannot re-credit the same
## offline window at the next boot.
func test_resume_advances_the_on_disk_credit_marker() -> void:
	TimeManager._test_now_override = _FIXED_NOW
	var main: Node = _MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_frames(1)
	_clear_boot_modals(main)
	GameState.active_net = ""

	GameState.last_saved_unix = 1
	main._notification(NOTIFICATION_APPLICATION_RESUMED)
	assert_gt(GameState.last_saved_unix, 1, "resume must re-stamp the marker")
	var on_disk: Dictionary = JSON.parse_string(SaveManager.backend.read())
	assert_eq(int(on_disk["last_saved_unix"]), GameState.last_saved_unix,
			"and persist it, or the next boot re-credits the same window")


# endregion


# region — regressions the resume tick could have introduced

## The resume tick made _show_welcome_back reachable more than once per process.
## It used to instantiate a fresh dialog every call and never free the old one —
## harmless when it ran once from _ready, a currency duplicator afterwards: every
## live instance stays connected to the global AdsManager.rewarded_completed and
## would claim its own stale summary on one grant.
func test_repeated_resumes_do_not_stack_welcome_back_dialogs() -> void:
	TimeManager._test_now_override = _FIXED_NOW
	var main: Node = _MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_frames(1)
	_clear_boot_modals(main)
	# A real net, so the offline path actually reaches the dialog — the other
	# resume tests blank it out and would miss this entirely.
	GameState.active_net = "basic_net"

	for i in 3:
		TimeManager._test_now_override = _FIXED_NOW + (i + 1) * 7_200
		GameState.last_saved_unix = TimeManager.now_unix() - 7_200
		main._show_welcome_back({
			"seconds": 3600.0, "raw_seconds": 7200.0, "catches_by_species": {},
			"items_gained": {}, "gold_gained": BigNumber.from_float(100.0),
			"shinies_caught": 0, "capped": true,
		})
		await wait_frames(1)

	var dialogs: int = 0
	for c in main.get_children():
		if c is AcceptDialog and c.get_script() != null \
				and String(c.get_script().resource_path).ends_with("welcome_back_dialog.gd"):
			dialogs += 1
	assert_eq(dialogs, 1, "the welcome-back dialog must be reused, not stacked")


## Defence in depth for the same defect: even with one instance, the ad handler
## filtered on reward_id alone. Only the dialog whose button started the ad may
## claim it.
func test_a_dialog_that_did_not_start_an_ad_ignores_the_grant() -> void:
	var dlg: AcceptDialog = preload("res://game/scenes/ui/welcome_back_dialog.tscn").instantiate()
	add_child_autofree(dlg)
	await wait_frames(1)
	dlg.show_summary({
		"seconds": 3600.0, "raw_seconds": 3600.0, "catches_by_species": {},
		"items_gained": {}, "gold_gained": BigNumber.from_float(100.0),
		"shinies_caught": 0, "capped": false,
	})
	var claims: Array = []
	dlg.claimed.connect(func(s): claims.append(s))
	# No button was tapped, so _ad_in_flight is false for this instance.
	AdsManager.rewarded_completed.emit(AdsManager.REWARD_OFFLINE_2X, true)
	await wait_frames(1)
	assert_eq(claims.size(), 0,
			"a dialog that never started an ad must not claim someone else's grant")


## The honest timestamp means a defaults-only session gets stamped with `now` by
## the 10s autosave. On a reinstall that would out-timestamp the Play Games
## snapshot it is about to download and win the merge base — inverting "restore
## my progress on a new phone".
func test_a_seeded_session_does_not_outrank_a_real_remote() -> void:
	SaveManager.backend.clear()
	_sweep_backups()
	SaveManager.load_save()
	assert_true(SaveManager.state_is_seeded, "no save on disk means the state is seeded")

	GameState._reset_to_defaults()
	SaveManager.save(GameState.to_dict())  # the autosave stamping an empty ranch
	var local: Dictionary = GameState.to_dict()
	var remote: Dictionary = {
		"last_saved_unix": GameState.last_saved_unix - 500_000,
		"current_max_tier": 30,
		"active_net": "real_history_net",
	}
	# Mirrors CloudSyncManager's seeded branch.
	local = local.duplicate(true)
	local["last_saved_unix"] = 0
	var merged: Dictionary = SaveConflictResolver.resolve(local, remote)
	assert_eq(String(merged.get("active_net", "")), "real_history_net",
			"the established cloud save must be the merge base, not the empty local one")
	assert_eq(int(merged.get("current_max_tier", 0)), 30)


func test_loading_a_real_save_clears_the_seeded_flag() -> void:
	SaveManager.save(GameState.to_dict())
	SaveManager.load_save()
	assert_false(SaveManager.state_is_seeded,
			"a genuine save carries history and must keep its timestamp authority")

# endregion


# region — misc

func test_a_healthy_save_clears_a_previous_failure_flag() -> void:
	_write_raw(_SAVE_PATH, "{ broken")
	SaveManager.load_save()
	_expect_error("save file is not a JSON object")
	assert_true(SaveManager.load_failed)
	SaveManager.backend.clear()
	_sweep_backups()
	SaveManager.save(GameState.to_dict())
	SaveManager.load_save()
	assert_false(SaveManager.load_failed, "the flag must be reset per load, not latched")

# endregion
