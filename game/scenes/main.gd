## Main scene: load save, compute offline progress, set up tabbed UI,
## save on quit. Replaces the Phase 0 placeholder.
extends Control

## Periodic-save cadence in seconds. The OS can kill an Android app
## without warning (low memory, force-stop, system update); this Timer
## bounds how much progress a hard kill can lose. Lowered from 30 s to
## 10 s in v0.8.2 after the user reported persistence failures even
## with the lifecycle-notification handler in place — every 10 s is
## still cheap (a single small JSON write) and dramatically narrows
## the worst-case loss window.
const _PERIODIC_SAVE_SECONDS := 10.0

const _CURRENCY_BAR := preload("res://game/scenes/ui/currency_bar.tscn")
const _CATCHING_VIEW := preload("res://game/scenes/catching/catching_view.tscn")
const _BATTLE_VIEW := preload("res://game/scenes/battle/battle_view.tscn")
const _INVENTORY_PANEL := preload("res://game/scenes/ui/inventory_panel.tscn")
const _NET_SHOP := preload("res://game/scenes/ui/net_shop.tscn")
const _UPGRADE_TREE := preload("res://game/scenes/ui/upgrade_tree.tscn")
const _PRESTIGE_VIEW := preload("res://game/scenes/prestige/prestige_view.tscn")
const _BESTIARY_VIEW := preload("res://game/scenes/bestiary/bestiary_view.tscn")
const _CRAFTING_VIEW := preload("res://game/scenes/crafting/crafting_view.tscn")
const _LEDGER_VIEW := preload("res://game/scenes/ledger/ledger_view.tscn")
## v0.15.15 — dedicated Daily-quests view (More menu).
const _DAILY_QUESTS_VIEW := preload("res://game/scenes/ui/daily_quests_view.tscn")
const _SETTINGS_VIEW := preload("res://game/scenes/ui/settings_view.tscn")
const _NARRATOR_OVERLAY := preload("res://game/scenes/ui/narrator_overlay.tscn")
const _AD_DIAGNOSTIC_OVERLAY := preload("res://game/scenes/ui/ad_diagnostic_overlay.tscn")
const _SAVE_INDICATOR_OVERLAY := preload("res://game/scenes/ui/save_indicator_overlay.tscn")
const _TOUCH_DEBUG_OVERLAY := preload("res://game/scenes/ui/touch_debug_overlay.tscn")
const _WELCOME_BACK_DIALOG := preload("res://game/scenes/ui/welcome_back_dialog.tscn")
## v0.15.14 — daily-login reward modal (retention bundle).
const _DAILY_REWARD_DIALOG := preload("res://game/scenes/ui/daily_reward_dialog.tscn")

# v0.15.13 — Dusk fonts, preloaded so the theme can be BUILT at runtime
# (with the accessibility font-scale baked in) rather than loading the
# static .tres whose sizes ignore the slider.
const _DUSK_DISPLAY_FONT := preload("res://assets/fonts/dusk/PressStart2P-Regular.ttf")
const _DUSK_UI_FONT := preload("res://assets/fonts/dusk/Silkscreen-Regular.ttf")
const _DUSK_BODY_FONT := preload("res://assets/fonts/dusk/VT323-Regular.ttf")

var _welcome_back_dialog: AcceptDialog
## v0.15.14 — daily-login reward modal + a one-slot queue so it's shown AFTER
## the welcome-back (offline) dialog when both are pending on the same launch.
var _daily_reward_dialog: AcceptDialog
var _pending_daily_summary: Dictionary = {}
## v0.15.14 — debounce: one backgrounding fires several FOCUS_OUT/PAUSED
## notifications; without this we'd schedule the offline-cap nudge once per
## notification. Set when scheduled, cleared on resume.
var _offline_cap_scheduled: bool = false
var _tabs: TabContainer
var _ad_diag_overlay: Control
var _save_indicator_overlay: Control
var _touch_debug_overlay: Control

## v0.9.0 nav split: 4 primary destinations get bottom-nav buttons;
## the rest live behind a "More" sheet. Order in PRIMARY drives the
## bottom-nav button order from left to right. Order in SECONDARY
## drives the More-sheet menu order.
##
## v0.15.11 — reordered to match the player's mental model "catch →
## fill the book → buy a better net → fight" (per the UI/UX research).
## Bestiary (the progression engine — completing a tier's species
## unlocks the next) and Shop (where auto-catch nets, the biggest early
## power jump, are bought) were buried in More while lower-stakes
## Inventory + Upgrades held two of four scarce primary slots. Promoted
## Bestiary + Shop; demoted Inventory + Upgrades to More.
const _PRIMARY_NAV: Array[String] = ["Catch", "Bestiary", "Shop", "Battle"]
const _SECONDARY_NAV: Array[String] = ["Daily", "Inventory", "Upgrades", "Crafting", "Prestige", "Ledger", "Settings"]
## v0.14.8 — bumped 64 → 72 dp to land in the Material bottom-nav
## "comfortable" range (72–80 dp) and the popular-Android-idle norm.
## Pre-bump every nav button rendered shorter than its on-screen
## emoji felt like it warranted.
const _NAV_BUTTON_HEIGHT_DP := 72.0

## v0.9.1 icons. Emoji glyphs because they need zero asset pipeline
## work and render reliably across Android system fonts. Each icon
## is prepended to the button text with a non-breaking space so the
## glyph reads as part of the label rather than floating loose.
const _NAV_ICONS: Dictionary = {
	"Catch": "🐾",
	"Battle": "⚔",
	"Inventory": "📦",
	"Upgrades": "⬆",
	"More": "☰",
	"Shop": "🛒",
	"Crafting": "🛠",
	"Bestiary": "📖",
	"Prestige": "✨",
	"Ledger": "📊",
	"Settings": "⚙",
	"Daily": "📅",
}


static func _label_with_icon(tab_name: String) -> String:
	var icon: String = _NAV_ICONS.get(tab_name, "")
	if icon == "":
		return tab_name
	return "%s  %s" % [icon, tab_name]

## Bottom-nav button widgets, keyed by the destination tab name. Used
## to flip `button_pressed` so the active primary tab gets visual
## emphasis via the v0.8.3 mobile theme's pressed stylebox.
var _nav_buttons: Dictionary = {}
var _more_button: Button
## v0.15.16 — daily-quest progress badge overlaid on the More button's
## top-right corner (the Daily view lives in the More sheet). Shows "done/total"
## while daily quests are incomplete; hidden once all are done. A label nested
## in the badge panel; both ignore mouse so taps still reach the More button.
var _daily_badge: PanelContainer
var _daily_badge_label: Label
## v0.9.1 custom More sheet — built lazily on first open, reused
## thereafter. Replaces the v0.9.0 system PopupMenu.
var _more_popup: PopupPanel

## Phase 11a — celebration / toast subsystems. Wired into EventBus
## signals via _install_celebrations() at startup.
const _CELEBRATION_OVERLAY := preload("res://game/scenes/ui/celebration_overlay.tscn")
const _TOAST := preload("res://game/scenes/ui/toast.tscn")
const _COACHMARK := preload("res://game/scenes/ui/coachmark.tscn")
const _QUEST_STRIP := preload("res://game/scenes/ui/quest_strip.tscn")
## Phase 14e: first-launch Peniber intro overlay. Gated by
## TutorialState.STEP_PENIBER_INTRO_SHOWN so it only plays once per save.
const _PENIBER_INTRO_OVERLAY := preload("res://game/scenes/ui/peniber_intro_overlay.gd")
var _celebration_overlay: CanvasLayer
var _toast: CanvasLayer
var _coachmark: CanvasLayer


func _ready() -> void:
	get_tree().root.close_requested.connect(_on_close_requested)
	# v0.15.11 — own the Android hardware Back button. By default the
	# SceneTree quits the app on Back (quit_on_go_back); we intercept it
	# in `_notification(NOTIFICATION_WM_GO_BACK_REQUEST)` to dismiss an open
	# overlay / return to Catch / confirm exit instead. Never disable
	# Back — intercept it (Google Play guidance).
	get_tree().quit_on_go_back = false
	ContentRegistry.ensure_loaded()
	_apply_mobile_default_theme()
	_install_global_haptic_feedback()
	_build_ui()
	_install_celebrations()
	_install_tutorial_director()
	# Phase 11d: empty-state hint buttons in Battle / Crafting can
	# request a tab switch without reaching into Main directly.
	EventBus.tab_switch_requested.connect(_navigate_to_tab)
	var loaded: Dictionary = SaveManager.load_save()
	GameState.from_dict(loaded)
	GameState.reconcile_pet_awards()
	GameState.reconcile_total_gold_earned_this_run()
	_apply_offline_progress(loaded)
	_apply_daily_login()
	_seed_default_net_if_needed()
	_start_periodic_save()

	# Optional one-shot screenshot generator for Play Store listing.
	# Activated via `godot --path . -- --screenshots`. Seeds GameState
	# with a mid-game snapshot, hides diagnostic overlays, sizes the
	# window to 1080x1920 (Play Store-compliant 9:16 portrait, fits
	# all three Play Console categories: phone / 7" tablet / 10"
	# tablet), cycles through key tabs and saves PNGs.
	if "--screenshots" in OS.get_cmdline_user_args():
		# v0.15.14 — the boot daily-login / welcome-back modals would block the
		# tab captures (a fresh seeded state is always day-1 claimable). Dismiss
		# them before generating.
		for d in [_welcome_back_dialog, _daily_reward_dialog]:
			if d != null and is_instance_valid(d):
				d.queue_free()
		_welcome_back_dialog = null
		_daily_reward_dialog = null
		_pending_daily_summary = {}
		await _run_screenshot_mode()
		get_tree().quit()
		return


func _start_periodic_save() -> void:
	# Auto-save every _PERIODIC_SAVE_SECONDS. Cheap on disk (a single small
	# JSON write) and bounds worst-case progress loss when the OS kills the
	# app without firing a lifecycle notification.
	var timer := Timer.new()
	timer.wait_time = _PERIODIC_SAVE_SECONDS
	timer.one_shot = false
	timer.autostart = true
	timer.timeout.connect(_save_now)
	add_child(timer)


func _save_now() -> void:
	SaveManager.save(GameState.to_dict())


## v0.15.14 — schedule the offline-cap-full notification for when the player's
## idle catch reserve finishes filling (cap_seconds from now, since we save on
## background and the cap accrues from the last save). Skips when there's no
## auto-catch net equipped (offline produces nothing, so nothing to nudge for).
## LocalNotificationManager no-ops without a native plugin; the stub records it.
func _schedule_offline_cap_notification() -> void:
	# Debounce — a single backgrounding fires PAUSED + FOCUS_OUT +
	# WM_WINDOW_FOCUS_OUT; only schedule once until the next resume.
	if _offline_cap_scheduled:
		return
	if String(GameState.active_net) == "":
		return
	var cap_mult: float = GameState.multiplier(&"offline_cap")
	var cap_seconds: float = OfflineProgressSystem.DEFAULT_CAP_SECONDS * cap_mult
	LocalNotificationManager.schedule_offline_cap_warning(cap_seconds)
	_offline_cap_scheduled = true


## Persist on every Android lifecycle event that could be the last
## one we get. v0.7.5 only handled NOTIFICATION_APPLICATION_PAUSED;
## v0.8.2 expands coverage after a user report that saves still
## weren't persisting on a Galaxy Z Fold7 (Android 16):
##   - APPLICATION_PAUSED:    home button, app switcher, screen-off
##   - APPLICATION_FOCUS_OUT: same triggers but routed through the
##                            focus subsystem; some Android versions /
##                            OEMs dispatch one but not the other.
##   - WM_WINDOW_FOCUS_OUT:   window-level focus loss; redundant on
##                            most devices but cheap insurance.
##
## Saving on every one is idempotent and fast (single JSON write).
## NOTIFICATION_WM_CLOSE_REQUEST is Window-only and is covered by the
## `close_requested` signal connection above.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, \
		NOTIFICATION_APPLICATION_FOCUS_OUT, \
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_save_now()
			# v0.15.14 — we just saved (last_saved_unix ≈ now), so the offline
			# cap fills cap_seconds from now. Schedule the "come back" nudge for
			# then. No-op until a native notification plugin ships; the stub
			# records it so the wiring is testable.
			_schedule_offline_cap_notification()
		NOTIFICATION_APPLICATION_RESUMED, \
		NOTIFICATION_APPLICATION_FOCUS_IN, \
		NOTIFICATION_WM_WINDOW_FOCUS_IN:
			# Player returned before the cap filled — cancel the pending nudge
			# and re-arm the debounce for the next backgrounding.
			_offline_cap_scheduled = false
			LocalNotificationManager.cancel_offline_cap_warning()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			# v0.15.11 — Android hardware Back. On Android subwindows are
			# embedded in the main window, so this notification reaches
			# Main and we own the back-stack here.
			_handle_go_back()


## v0.15.11 — Android Back-button back-stack. Closes the top-most
## surface first, one level per press. With quit_on_go_back disabled
## nothing auto-closes on Back, so Main is the single owner here.
##
## Priority (top of the visual stack downward):
##   0. First-launch Peniber intro owns the screen → no-op (dismiss it
##      via tap / SKIP, never Back; and never pop Exit behind it).
##   1. A tracked modal dialog (exit-confirm, welcome-back) → cancel it.
##   2. The More sheet → close it.
##   3. The celebration overlay (once its input-lock elapses, like taps).
##   4. A tutorial coachmark → dismiss it.
##   5. Not on the Catch (home) tab → return to Catch.
##   6. On Catch with nothing open → confirm exit (never quit silently).
func _handle_go_back() -> void:
	# 0. The forced first-launch intro modal owns the screen.
	if get_tree().get_first_node_in_group("peniber_intro") != null:
		return
	# 1. Tracked modal dialogs (Android "Back == cancel the dialog").
	#    These sit above everything (exclusive Windows); cancel the
	#    top-most. Guard welcome_back with is_instance_valid — it's
	#    instantiated fresh and never nulled.
	if _exit_confirm != null and _exit_confirm.visible:
		_exit_confirm.hide()
		return
	if _welcome_back_dialog != null and is_instance_valid(_welcome_back_dialog) \
			and _welcome_back_dialog.visible:
		_welcome_back_dialog.hide()
		return
	# v0.15.14 — daily-login reward modal (shown after welcome-back, so at most
	# one of the two is visible at a time). Back dismisses it like other modals.
	if _daily_reward_dialog != null and is_instance_valid(_daily_reward_dialog) \
			and _daily_reward_dialog.visible:
		_daily_reward_dialog.hide()
		return
	# 2. More sheet open → close it.
	if _more_popup != null and _more_popup.visible:
		_more_popup.hide()
		return
	# 3. Celebration overlay (respect its brief input-lock, same as taps).
	if _celebration_overlay != null and _celebration_overlay.has_method("is_dismissable") \
			and _celebration_overlay.is_dismissable():
		_celebration_overlay.dismiss()
		return
	# 4. Tutorial coachmark visible → dismiss it.
	if _coachmark != null and _coachmark.visible and _coachmark.has_method("dismiss"):
		_coachmark.dismiss()
		return
	# 5. Not on Catch → go home.
	var catch_idx: int = _find_tab_index("Catch")
	if _tabs != null and catch_idx >= 0 and _tabs.current_tab != catch_idx:
		_navigate_to_tab("Catch")
		return
	# 6. On Catch, nothing open → confirm exit.
	_show_exit_confirm()


## Exit-confirmation dialog. OK quits; Cancel dismisses. Built lazily +
## cached. min_size set explicitly per the v0.15.8 popup-sizing fix so
## the dialog doesn't size oddly on first popup.
var _exit_confirm: ConfirmationDialog

func _show_exit_confirm() -> void:
	if _exit_confirm == null:
		_exit_confirm = ConfirmationDialog.new()
		_exit_confirm.title = "Exit Idle Beasts?"
		_exit_confirm.dialog_text = "Leave the game? Your progress is saved automatically."
		_exit_confirm.ok_button_text = "Exit"
		_exit_confirm.cancel_button_text = "Keep playing"
		_exit_confirm.min_size = Vector2(420, 200)
		# Window subtype — assign the Dusk theme so it doesn't fall back
		# to Godot's default styleboxes.
		_exit_confirm.theme = load("res://assets/themes/dusk/%s.tres" % Settings.theme_id)
		_exit_confirm.confirmed.connect(_on_exit_confirmed)
		add_child(_exit_confirm)
	_exit_confirm.popup_centered(Vector2(420, 200))


func _on_exit_confirmed() -> void:
	# Persist one final time before quitting (belt-and-braces; periodic
	# save + lifecycle saves already cover this).
	_save_now()
	get_tree().quit()


## v0.14.0 (Phase 13b) — root UI layout wraps everything in a
## safe-area MarginContainer that pads inward from the device's
## status bar / gesture bar / notch via `DeviceLayout.safe_area`.
##
## v0.14.2 (Phase 13c.2) — orientation-aware composition.
##
## The persistent UI children (currency bar, TabContainer, quest
## strip, nav buttons) are instantiated ONCE and stored as members.
## `_apply_orientation_layout()` then composes them into either:
##   - PORTRAIT: VBox { currency_bar / tabs / quest_strip / bottom_nav }
##   - LANDSCAPE: HBox { left_rail (vertical nav) / VBox { currency_bar / tabs / quest_strip } }
##
## On `DeviceLayout.layout_changed` the composition root
## (`_orientation_root`) is rebuilt; the persistent children are
## re-parented rather than torn down, so per-tab game state (live
## battle replay, hold-to-tap state, etc.) survives orientation
## flips intact.
##
## The MarginContainer subscribes to `DeviceLayout.layout_changed`
## so orientation flips, foldable open/close, and split-screen
## resizes all re-apply the safe area without a scene reload.
var _safe_margin: MarginContainer
## Composition root rebuilt on every orientation change. Child of
## _safe_margin. The persistent UI elements get re-parented into
## either the portrait or landscape layout under this node.
var _orientation_root: Control
## Persistent children. Created once in _build_ui, reparented on
## every orientation flip.
var _currency_bar: Control
var _quest_strip: Control

## v0.15.1 (Phase 14b) — resize-latency coalescing.
##
## Pre-coalesce, every `DeviceLayout.layout_changed` emit ran both
## `_apply_safe_area_margins` AND `_apply_orientation_layout`
## immediately. A desktop window drag fires `size_changed` dozens
## of times per second; on Android, a foldable mid-fold can fire
## several times during the animation; each emit triggered a full
## composition-root tear-down + rebuild (queue_free old root,
## allocate new VBox/HBox, re-parent five persistent children).
##
## Now: handlers just set the matching dirty flag. `_process` drains
## once per frame. AND: orientation root only rebuilds if
## `DeviceLayout.is_landscape` actually flipped from the last
## applied value — most resize events change only safe area, not
## orientation, so the heavy rebuild stays rare.
##
## Test counters expose `safe_area_apply_count` /
## `orientation_apply_count` for the resize-latency regression
## tests. Reset by `reset_layout_apply_counters()`.
var _safe_area_dirty: bool = false
var _orientation_dirty: bool = false
## v0.15.13 — coalesces theme rebuilds. The font-scale slider fires
## accessibility_settings_changed per 0.05 step during a drag; rebuilding
## the whole theme + propagating it tree-wide on each step is wasteful.
## Set the flag in the handlers; `_process` drains it to one rebuild/frame.
var _theme_dirty: bool = false
var _last_applied_landscape: bool = false
var safe_area_apply_count: int = 0
var orientation_apply_count: int = 0
## Width of the left-side rail in landscape mode. v0.14.8 bumped
## 80 → 88 dp so the rail matches the new bottom-nav 72-dp portrait
## height plus a small visual buffer — keeps icons and labels from
## hugging the content edge in landscape.
const _LEFT_RAIL_WIDTH_DP := 88.0


func _build_ui() -> void:
	_safe_margin = MarginContainer.new()
	_safe_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_safe_margin)
	_apply_safe_area_margins()
	_last_applied_landscape = DeviceLayout.is_landscape
	# v0.15.1 (Phase 14b) — both subscribers route through a single
	# dirty-flag handler. `_process` drains the flags once per frame,
	# coalescing burst-resize events (desktop drag, foldable mid-fold)
	# into one safe-area apply + (at most) one orientation rebuild.
	DeviceLayout.layout_changed.connect(_on_layout_changed)

	# Build the persistent children once. They get re-parented on
	# every orientation flip — see _apply_orientation_layout().
	_currency_bar = _CURRENCY_BAR.instantiate()
	_currency_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# v0.9.0: TabContainer still owns the content area + visibility
	# management, but its tab bar is hidden — navigation moved to
	# the bottom-anchored / left-rail nav. Keeps the existing scene
	# wiring (TabContainer.current_tab drives which child is visible)
	# while lifting interaction into the thumb zone.
	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.tabs_visible = false
	_tabs = tabs

	var catch_tab: Control = _CATCHING_VIEW.instantiate()
	catch_tab.name = "Catch"
	_tabs.add_child(catch_tab)

	var battle_tab: Control = _BATTLE_VIEW.instantiate()
	battle_tab.name = "Battle"
	_tabs.add_child(battle_tab)

	var inventory_tab: Control = _INVENTORY_PANEL.instantiate()
	inventory_tab.name = "Inventory"
	_tabs.add_child(inventory_tab)

	var bestiary_tab: Control = _BESTIARY_VIEW.instantiate()
	bestiary_tab.name = "Bestiary"
	_tabs.add_child(bestiary_tab)

	var crafting_tab: Control = _CRAFTING_VIEW.instantiate()
	crafting_tab.name = "Crafting"
	_tabs.add_child(crafting_tab)

	var ledger_tab: Control = _LEDGER_VIEW.instantiate()
	ledger_tab.name = "Ledger"
	_tabs.add_child(ledger_tab)

	var daily_tab: Control = _DAILY_QUESTS_VIEW.instantiate()
	daily_tab.name = "Daily"
	_tabs.add_child(daily_tab)

	var shop_tab: Control = _NET_SHOP.instantiate()
	shop_tab.name = "Shop"
	_tabs.add_child(shop_tab)

	var upgrades_tab: Control = _UPGRADE_TREE.instantiate()
	upgrades_tab.name = "Upgrades"
	_tabs.add_child(upgrades_tab)

	var prestige_tab: Control = _PRESTIGE_VIEW.instantiate()
	prestige_tab.name = "Prestige"
	_tabs.add_child(prestige_tab)

	var settings_tab: Control = _SETTINGS_VIEW.instantiate()
	settings_tab.name = "Settings"
	_tabs.add_child(settings_tab)

	# Phase 12g — quest strip. Three rows (SHORT/MEDIUM/LONG) with
	# progress bars; visible from every tab since it's a sibling of
	# the TabContainer in the orientation root, not a per-tab child.
	_quest_strip = _QUEST_STRIP.instantiate()
	_quest_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# v0.9.0: bottom navigation buttons. Now built standalone so the
	# orientation-aware composer can place them either as a horizontal
	# bar (portrait) or a vertical rail (landscape).
	_build_nav_buttons()

	# Compose into the active orientation's root layout. The
	# layout_changed subscription above will re-call this whenever
	# the device flips.
	_apply_orientation_layout()

	# NarratorOverlay sits ABOVE the tab container so it can float over any
	# tab. Mouse_filter is IGNORE on the overlay so background taps still
	# reach the catching view; only the speech bubble itself catches taps.
	var overlay: Control = _NARRATOR_OVERLAY.instantiate()
	add_child(overlay)

	# v0.11.2 (Phase 11c): three diagnostic overlays — ad lifecycle
	# banner, "Saved <HH:MM:SS>" toast, touch crosshair — gated behind
	# OS.is_debug_build(). They were left on in production through
	# Phase 10 because the Android input + save-lifecycle bugs they
	# debugged were still being investigated; those are resolved now,
	# so release builds no longer paint green outlines on every Button
	# (touch debug) or flash "Saved" toasts every save tick.
	if OS.is_debug_build():
		_ad_diag_overlay = _AD_DIAGNOSTIC_OVERLAY.instantiate()
		add_child(_ad_diag_overlay)

		_save_indicator_overlay = _SAVE_INDICATOR_OVERLAY.instantiate()
		add_child(_save_indicator_overlay)

		_touch_debug_overlay = _TOUCH_DEBUG_OVERLAY.instantiate()
		add_child(_touch_debug_overlay)


## v0.15.13 — the root theme is BUILT at runtime via
## `DuskThemeBuilder.build(palette, display/ui/body fonts, Settings.font_scale)`
## rather than loaded from a static `.tres`, so theme-variation text
## (currency labels/values, tier %, tab labels, badges, Peniber dialog)
## honors the accessibility font-size slider. The palette comes from
## `PaletteDusk.by_id(Settings.theme_id)`, so the Settings palette picker
## (Phase 14f) keeps working. The built theme is assigned to BOTH
## `get_tree().root.theme` (so popup Windows inherit it) and `self.theme`
## (Main's subtree). Inline `UiScale.size(N)` call sites still compound
## `BASE_SCALE` on top, as before.
##
## Called on _ready, re-run synchronously on `theme_changed` (a discrete
## palette tap), and re-run via a once-per-frame dirty flag on
## `accessibility_settings_changed` (the font slider) — so a slider DRAG
## collapses into a single rebuild instead of one per 0.05 step.
func _apply_mobile_default_theme() -> void:
	if not Settings.accessibility_settings_changed.is_connected(_on_accessibility_settings_changed):
		Settings.accessibility_settings_changed.connect(_on_accessibility_settings_changed)
	# Phase 14f — subscribe to theme_changed so the Settings palette
	# picker actually swaps the live theme without a scene reload.
	if not Settings.theme_changed.is_connected(_on_theme_changed):
		Settings.theme_changed.connect(_on_theme_changed)
	var palette: Dictionary = PaletteDusk.by_id(Settings.theme_id)
	# build() is declared `-> Theme` and unconditionally returns a fresh
	# Theme, so no null guard is needed.
	var dusk_theme: Theme = DuskThemeBuilder.build(
			palette,
			_DUSK_DISPLAY_FONT,
			_DUSK_UI_FONT,
			_DUSK_BODY_FONT,
			Settings.font_scale)

	# Slider grabber — Dusk doesn't define this in the builder yet (handoff
	# focused on the core controls). Bolt on a "bright ink" grabber so the
	# audio sliders in Settings stay tappable. Build-time mutation is safe
	# now: this is a fresh Theme each call, not a shared cached resource.
	var slider_grabber := StyleBoxFlat.new()
	slider_grabber.bg_color = palette["ink"]
	slider_grabber.corner_radius_top_left = 0
	slider_grabber.corner_radius_top_right = 0
	slider_grabber.corner_radius_bottom_left = 0
	slider_grabber.corner_radius_bottom_right = 0
	slider_grabber.content_margin_top = 8
	slider_grabber.content_margin_bottom = 8
	slider_grabber.content_margin_left = 8
	slider_grabber.content_margin_right = 8
	dusk_theme.set_stylebox("grabber_area", "HSlider", slider_grabber)
	dusk_theme.set_stylebox("grabber_area_highlight", "HSlider", slider_grabber)

	# v0.15.1.1 — assign to BOTH the window root AND Main itself.
	# Just setting `get_tree().root.theme` was reaching the window
	# but Main's subtree inherits from its own `theme` property
	# (which the .tscn used to populate with main_theme.tres,
	# shadowing the window theme). Setting `self.theme` ensures
	# Main's children pick up Dusk even if a future scene re-adds
	# a per-scene theme override.
	get_tree().root.theme = dusk_theme
	self.theme = dusk_theme


## Phase 11b — Settings.accessibility_settings_changed handler.
## Currently re-applies the mobile theme so font_scale changes take
## effect immediately on the open scene without requiring a reload.
## reduce_motion and haptics_enabled are read at the call site for
## each animation/haptic, so they don't need a re-apply step.
func _on_accessibility_settings_changed() -> void:
	# v0.15.13 — coalesce: the font-scale slider fires this per 0.05 step,
	# and a fast drag can cross several steps in one frame. Mark dirty and
	# let _process rebuild the theme once on the next frame instead of N
	# times this frame.
	_theme_dirty = true


## Phase 14f — Settings.theme_changed handler (palette swap). A palette
## swap is a single discrete tap (no drag to coalesce), so rebuild
## synchronously for an instant swap, then repaint the bottom nav's
## per-state styleboxes (which read PaletteDusk.active()).
func _on_theme_changed() -> void:
	_apply_mobile_default_theme()
	_apply_nav_styleboxes()


## v0.15.1 (Phase 14b) — layout_changed handler. Sets dirty flags
## so `_process` can drain them once per frame regardless of how
## many `size_changed` events the OS fired this frame.
func _on_layout_changed() -> void:
	_safe_area_dirty = true
	_orientation_dirty = true


## v0.15.1 — drain dirty flags. Safe-area apply runs whenever the
## flag is set (cheap — 4 theme constants). Orientation rebuild
## only runs when `is_landscape` actually flipped from the last
## applied value (heavy — composition root tear-down + 5 child
## reparents). The "flip only" check is what makes a desktop window
## resize cheap: drag fires hundreds of size_changed events but
## landscape rarely flips, so the rebuild stays at zero.
func _process(_delta: float) -> void:
	if _theme_dirty:
		_theme_dirty = false
		# Rebuild the theme once per frame for a coalesced font-slider drag.
		# (Palette swaps rebuild synchronously in _on_theme_changed.) The
		# nav's per-state styleboxes are palette-based, not font-based, so
		# they don't need repainting on a font-scale change.
		_apply_mobile_default_theme()
	if _safe_area_dirty:
		_safe_area_dirty = false
		_apply_safe_area_margins()
	if _orientation_dirty:
		_orientation_dirty = false
		if DeviceLayout.is_landscape != _last_applied_landscape:
			_last_applied_landscape = DeviceLayout.is_landscape
			_apply_orientation_layout()


## Test helper — reset counters before a per-frame resize burst.
## Live gameplay never calls this; only the latency regression test
## does, before staging the burst.
func reset_layout_apply_counters() -> void:
	safe_area_apply_count = 0
	orientation_apply_count = 0


## Phase 13b — re-apply DeviceLayout.safe_area to the root margin
## container. Called on _build_ui (first layout) and on every
## layout_changed event (orientation flip, safe-area change,
## foldable open). The math: convert the safe-area Rect2 in
## viewport coords into the four MarginContainer constants.
##
## On desktop / web where safe area equals the full window, every
## margin is 0 — the wrapper is a no-op cost.
func _apply_safe_area_margins() -> void:
	if _safe_margin == null:
		return
	var safe: Rect2 = DeviceLayout.safe_area
	var view_size: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		return
	safe_area_apply_count += 1
	var top: int = int(max(0.0, safe.position.y))
	var left: int = int(max(0.0, safe.position.x))
	var right: int = int(max(0.0, view_size.x - (safe.position.x + safe.size.x)))
	var bottom: int = int(max(0.0, view_size.y - (safe.position.y + safe.size.y)))
	_safe_margin.add_theme_constant_override("margin_top", top)
	_safe_margin.add_theme_constant_override("margin_left", left)
	_safe_margin.add_theme_constant_override("margin_right", right)
	_safe_margin.add_theme_constant_override("margin_bottom", bottom)


## Wire a 20-millisecond haptic pulse to every Button press in the
## tree, so the user gets a tactile "tap registered" cue regardless of
## which screen they're on. `Input.vibrate_handheld(20)` is a no-op on
## desktop (we only ever fire it on Android) and is the recommended
## duration for `EFFECT_CLICK`-equivalent button feedback per Android's
## haptic guidelines (10-20 ms).
##
## Implementation: walk the tree once after _build_ui completes (called
## via call_deferred so child nodes are in place), then re-walk on
## SceneTree.node_added so any Button instantiated later (catching view
## drops-2x button, welcome-back claim button, etc.) also gets wired.
##
## We connect to `pressed` rather than `button_down` so the haptic
## fires only on a successful click, not on mid-drag presses.
func _install_global_haptic_feedback() -> void:
	get_tree().node_added.connect(_maybe_wire_haptic_to)
	call_deferred("_walk_and_wire_haptics", self)


# region — Phase 11a celebrations

## Mounts the celebration overlay + toast, then routes EventBus
## signals to them. Tier-spectrum dispatch:
##
##   T4 (full-screen overlay):
##     - tier_completed
##     - first_shiny_caught
##     - prestige_triggered
##     - battle_ended (won)
##
##   T2 (toast):
##     - pet_acquired
##     - recipe_unlocked
##
## Smaller events (currency_changed, item_gained, monster_caught) are
## already covered by per-screen feedback (floating numbers, particles,
## audio stings). Surfacing those here would over-celebrate the loop.
func _install_celebrations() -> void:
	_celebration_overlay = _CELEBRATION_OVERLAY.instantiate()
	add_child(_celebration_overlay)
	_toast = _TOAST.instantiate()
	add_child(_toast)
	EventBus.tier_completed.connect(_on_celebrate_tier_completed)
	EventBus.first_shiny_caught.connect(_on_celebrate_first_shiny)
	EventBus.prestige_triggered.connect(_on_celebrate_prestige)
	EventBus.battle_ended.connect(_on_celebrate_battle_ended)
	EventBus.pet_acquired.connect(_on_toast_pet_acquired)
	EventBus.recipe_unlocked.connect(_on_toast_recipe_unlocked)
	EventBus.achievement_unlocked.connect(_on_achievement_unlocked)
	EventBus.quest_completed.connect(_on_quest_completed)


func _on_celebrate_tier_completed(tier: int) -> void:
	var pets := CatchingSystem.pets_to_award_for_tier(ContentRegistry.monsters(), tier)
	var pet_names: Array[String] = []
	for p in pets:
		pet_names.append(p.display_name)
	var body: String
	if pet_names.is_empty():
		body = "You've cleared every species at this tier."
	elif pet_names.size() == 1:
		body = "Joining your roster: %s." % pet_names[0]
	else:
		body = "Joining your roster: %s." % ", ".join(pet_names)
	# v0.15.12 — surface the permanent RP bonus, but ONLY on the first-ever
	# completion of this tier (the bonus is one-time). This handler runs
	# during `tier_completed.emit`, which fires BEFORE the grant records the
	# tier in tiers_rp_awarded — so "not yet awarded" == first completion.
	# Post-prestige replays re-complete the tier but grant nothing, so they
	# must not claim "+RP" either.
	if not GameState.tiers_rp_awarded.has(tier):
		var rp_bonus: int = CatchingSystem.tier_completion_rp(tier)
		if rp_bonus > 0:
			body += "\n+%d Rancher Points." % rp_bonus
	_celebration_overlay.show_celebration("Tier %d Complete!" % tier, body)


func _on_celebrate_first_shiny(monster_id: String) -> void:
	var monster: MonsterResource = ContentRegistry.monster(StringName(monster_id))
	var sprite: Texture2D = monster.sprite if monster != null else null
	var body: String = "A %s, no less." % (monster.display_name if monster != null else "specimen")
	_celebration_overlay.show_celebration("First Shiny!", body, sprite)


func _on_celebrate_prestige(rp_gained: int, prestige_count: int) -> void:
	var title: String = "Prestige #%d" % prestige_count
	var body: String = "You earned %d Rancher Points and reset the run." % rp_gained
	_celebration_overlay.show_celebration(title, body)


func _on_celebrate_battle_ended(_battle_id: String, won: bool, rewards: Dictionary) -> void:
	if not won:
		return   # losses use the BattleView's own POST screen
	var rp: int = int(rewards.get("rancher_points", 0))
	var body: String = "+%d Rancher Points." % rp if rp > 0 else "All encounters cleared."
	_celebration_overlay.show_celebration("Stage Cleared!", body)


func _on_toast_pet_acquired(pet_id: String, is_variant: bool) -> void:
	var pet: PetResource = ContentRegistry.pet(StringName(pet_id))
	if pet == null:
		return
	var prefix: String = "Variant " if is_variant else ""
	_toast.show_toast("%spet acquired: %s" % [prefix, pet.display_name])


## Phase 12f — achievements ride the celebration spectrum:
##   BRONZE / SILVER → toast (subtle, doesn't interrupt the loop)
##   GOLD            → full celebration overlay (rare; deserves the moment)
## Reward application happens in the Achievements autoload before this
## fires, so the user sees the unlock + the gold/RP gain at the same time.
func _on_achievement_unlocked(achievement_id: String) -> void:
	var ach: AchievementResource = ContentRegistry.achievement(StringName(achievement_id))
	if ach == null:
		return
	var reward_suffix: String = ""
	if ach.rp_reward > 0:
		reward_suffix = "  +%d RP" % ach.rp_reward
	if ach.tier == AchievementResource.Tier.GOLD:
		var body: String = "%s%s" % [ach.description, reward_suffix]
		_celebration_overlay.show_celebration("Achievement: %s" % ach.display_name, body, ach.sprite)
	else:
		_toast.show_toast("Achievement: %s%s" % [ach.display_name, reward_suffix], 3.5)


## Phase 12g — quest completions toast quietly (SHORT cycles every
## minute or two; full celebration would over-celebrate the loop).
## LONG-tier completions get a slightly longer-dwelling toast since
## they're prestige-cycle milestones. Reward application happens in
## QuestLog before this fires.
func _on_quest_completed(quest_id: String) -> void:
	var quest: QuestResource = ContentRegistry.quest(StringName(quest_id))
	if quest == null:
		return
	var reward_suffix: String = ""
	if quest.rp_reward > 0:
		reward_suffix = "  +%d RP" % quest.rp_reward
	var dwell: float = 4.0 if quest.quest_tier == QuestResource.QuestTier.LONG else 2.5
	_toast.show_toast("Quest done: %s%s" % [quest.display_name, reward_suffix], dwell)


func _on_toast_recipe_unlocked(recipe_id: String) -> void:
	var recipe: CraftingRecipeResource = ContentRegistry.recipe(StringName(recipe_id))
	if recipe == null:
		# Fallback: show a generic message rather than swallowing the
		# event silently.
		_toast.show_toast("New recipe unlocked")
		return
	_toast.show_toast("Recipe unlocked: %s" % recipe.display_name)

# endregion


# region — Phase 12c tutorial director

## Mounts the coachmark and subscribes to EventBus signals so each
## tutorial step fires when its trigger condition is met. Steps are
## scoped to the easiest-to-target UI:
##   - tap_first_monster:    fires after _build_ui if catches==0; targets
##                           the catch tab button to draw the eye there.
##   - buy_first_net:        fires when player hits 100 gold with no net
##                           owned; targets the More button (shop is
##                           inside More).
##   - enter_battle:         fires on first pet_acquired; targets Battle.
##   - craft_first_recipe:   fires when current_max_tier reaches 2 with
##                           no recipes crafted; targets the More button.
## Each fire calls TutorialState.mark_seen on dismissal so it doesn't
## replay without an explicit Replay-tutorial.
func _install_tutorial_director() -> void:
	_coachmark = _COACHMARK.instantiate()
	add_child(_coachmark)
	# Defer the first-launch check so the bottom-nav has a settled
	# rect by the time we call get_global_rect on it.
	call_deferred("_check_tap_first_monster")
	# Phase 14e: first-launch Peniber intro overlay. Deferred so the
	# overlay paints on top of a fully-laid-out scene; checking the
	# TutorialState gate is cheap enough that the defer doesn't cost
	# anything visible. If the player has already seen the intro this
	# is a no-op.
	call_deferred("_check_peniber_intro")
	EventBus.currency_changed.connect(_on_currency_changed_tutorial)
	EventBus.pet_acquired.connect(_on_pet_acquired_tutorial)
	EventBus.tier_unlocked.connect(_on_tier_unlocked_tutorial)


## Phase 14e: show the 4-beat Peniber intro overlay on first launch.
## Self-gated via TutorialState.STEP_PENIBER_INTRO_SHOWN; subsequent
## launches are no-ops. The overlay manages its own dismissal +
## queue_free; we only have to spawn it.
func _check_peniber_intro() -> void:
	_PENIBER_INTRO_OVERLAY.show_intro_if_unseen(self)


func _check_tap_first_monster() -> void:
	if not TutorialState.should_show(TutorialState.STEP_TAP_FIRST_MONSTER):
		return
	if int(GameState.ledger.get("total_catches", 0)) > 0:
		# Player has caught at least once — they've already learned this.
		TutorialState.mark_seen(TutorialState.STEP_TAP_FIRST_MONSTER)
		return
	# Target the Catch nav button — points the eye at the right tab
	# even if the player happens to be on a different tab. Won't fire
	# while they're already on Catch (tap will dismiss it).
	var target: Button = _nav_buttons.get("Catch", null)
	if target == null:
		return
	_coachmark.show_for(target,
			"Tap a wandering monster on the Catch screen to catch it.",
			TutorialState.STEP_TAP_FIRST_MONSTER)


func _on_currency_changed_tutorial(currency_id: String, _new_value: Variant) -> void:
	if currency_id != "gold":
		return
	# buy_first_net trigger: 100 gold + no nets owned.
	if not TutorialState.should_show(TutorialState.STEP_BUY_FIRST_NET):
		return
	if not GameState.nets_owned.is_empty():
		TutorialState.mark_seen(TutorialState.STEP_BUY_FIRST_NET)
		return
	if GameState.current_gold().lt(BigNumber.from_float(100.0)):
		return
	# v0.15.11 — Shop is now a primary nav button (was behind More), so
	# point the coachmark directly at it instead of "Tap More → Shop".
	var target: Button = _nav_buttons.get("Shop", null)
	if target == null:
		return
	_coachmark.show_for(target,
			"You can afford a Basic Net. Tap Shop to buy one and start auto-catching.",
			TutorialState.STEP_BUY_FIRST_NET)


func _on_pet_acquired_tutorial(_pet_id: String, _is_variant: bool) -> void:
	if not TutorialState.should_show(TutorialState.STEP_ENTER_BATTLE):
		return
	var target: Button = _nav_buttons.get("Battle", null)
	if target == null:
		return
	_coachmark.show_for(target,
			"You earned a pet! Visit Battle to send your team into a stage.",
			TutorialState.STEP_ENTER_BATTLE)


func _on_tier_unlocked_tutorial(tier: int) -> void:
	# craft_first_recipe trigger: tier 2 unlocked with no recipes
	# crafted yet. Tier 2 is when the first net upgrade becomes
	# available, which is the natural moment to introduce crafting.
	if tier < 2:
		return
	if not TutorialState.should_show(TutorialState.STEP_CRAFT_FIRST_RECIPE):
		return
	if not GameState.recipes_crafted.is_empty():
		TutorialState.mark_seen(TutorialState.STEP_CRAFT_FIRST_RECIPE)
		return
	# v0.15.11 — point at the actual More button. The old code looked it
	# up in `_nav_buttons` (which holds only the 4 primary buttons, never
	# "More"), so `target` was always null and this coachmark NEVER showed
	# — a long-standing dead FTUE step. Crafting is still behind More, so
	# the "Tap More → Crafting" copy stays correct.
	var target: Button = _more_button
	if target == null:
		return
	_coachmark.show_for(target,
			"Tier 2 unlocked. Tap More → Crafting to forge a stronger net.",
			TutorialState.STEP_CRAFT_FIRST_RECIPE)


## Public hook: the Settings "Replay tutorial" button calls this to
## reset all tutorial state and re-fire the first-launch check.
func replay_tutorial() -> void:
	TutorialState.reset()
	# Re-check tap_first_monster from a clean slate. Other steps will
	# fire when their EventBus triggers next match.
	call_deferred("_check_tap_first_monster")

# endregion


func _walk_and_wire_haptics(node: Node) -> void:
	_maybe_wire_haptic_to(node)
	for child in node.get_children():
		_walk_and_wire_haptics(child)


func _maybe_wire_haptic_to(node: Node) -> void:
	if not node is Button:
		return
	var button: Button = node
	if button.pressed.is_connected(_on_any_button_pressed):
		return
	button.pressed.connect(_on_any_button_pressed)


func _on_any_button_pressed() -> void:
	# v0.11.1 (Phase 11b): respect the user's haptics preference. The
	# OS-level haptic-disable still wins (vibrate_handheld is a no-op
	# when the system has haptics off), but the in-app toggle gives
	# users finer control without leaving the game.
	if not Settings.haptics_enabled:
		return
	Input.vibrate_handheld(20)


## Bigger, fingertap-friendly tab bar. Default Godot tabs are ~28 px
## tall with a 16 px font — way too small on a 1280-tall portrait
## phone. We bump font size and pad the tab styleboxes vertically so
## each tab's hit-box is closer to Material's 48 dp recommendation,
## and turn on horizontal scrolling so 10 tabs don't fight for the
## same 720 px of viewport width.
## v0.9.0 bottom navigation: 4 primary destinations as toggleable
## buttons + a "More" button that opens a PopupMenu listing the
## secondary destinations.
##
## v0.14.2 (Phase 13c.2) — split into "build buttons" (this) and
## "compose them into a parent" (`_apply_orientation_layout`'s helpers).
## Buttons are reused across orientation flips so signal connections
## and `button_pressed` toggle state survive rotation.
func _build_nav_buttons() -> void:
	# v0.14.7 (Phase 13g): every nav button has a `tooltip_text` so
	# screen readers can announce the destination by name even when
	# the icon emoji is unfamiliar. The button text still includes
	# the emoji + name for sighted users.
	for tab_name in _PRIMARY_NAV:
		var btn := Button.new()
		btn.text = _label_with_icon(tab_name)
		btn.tooltip_text = tab_name
		btn.toggle_mode = true
		btn.pressed.connect(_on_nav_button_pressed.bind(tab_name))
		_nav_buttons[tab_name] = btn

	_more_button = Button.new()
	_more_button.text = _label_with_icon("More")
	_more_button.tooltip_text = "More tabs"
	# v0.15.11 — toggle_mode so the More button can show the active
	# (gold-inset) stylebox while a More-sheet (secondary) screen is the
	# current tab. `_set_active_nav` drives `button_pressed`; the actual
	# press still fires `_on_more_pressed` to open the sheet.
	_more_button.toggle_mode = true
	_more_button.pressed.connect(_on_more_pressed)

	# v0.15.16 — daily-quest progress badge overlaid on the More button.
	_build_daily_badge()

	# Phase 14f — apply the styles.css `.tabbar` per-state styleboxes.
	# Each primary nav button gets a `normal` (bg-deep + ink_mute text)
	# and a `pressed`/`hover` (gold inset top bar + card_2 gradient bg
	# + gold text) variant. Read from PaletteDusk.active() so a theme
	# switch in Settings repaints the nav without code changes here.
	_apply_nav_styleboxes()

	# Initial selection: Catch (the home / main loop tab).
	_set_active_nav("Catch")


## v0.15.16 — daily-quest progress badge. A small "done/total" chip pinned to
## the More button's top-right corner (the Daily view lives in the More sheet),
## so daily progress is visible from any screen without opening it. Built once
## with the More button (which is reused across orientation flips, so the badge
## travels with it). Both the panel and its label ignore the mouse so taps pass
## through to the button.
func _build_daily_badge() -> void:
	_daily_badge = PanelContainer.new()
	_daily_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Pin to the top-right corner, growing left + down so it sizes to content.
	_daily_badge.anchor_left = 1.0
	_daily_badge.anchor_right = 1.0
	_daily_badge.anchor_top = 0.0
	_daily_badge.anchor_bottom = 0.0
	_daily_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_daily_badge.grow_vertical = Control.GROW_DIRECTION_END
	# Zero-size anchor rect pinned 2 px in from the top-right corner; the grow
	# directions above expand it left + down to the content's minimum size.
	_daily_badge.offset_left = -2
	_daily_badge.offset_right = -2
	_daily_badge.offset_top = 1
	_daily_badge.offset_bottom = 1
	_daily_badge_label = Label.new()
	_daily_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_daily_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_daily_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_daily_badge.add_child(_daily_badge_label)
	_more_button.add_child(_daily_badge)
	_restyle_daily_badge()

	# Recount on any daily-quest change. game_loaded is deferred so it runs
	# AFTER GameState.from_dict + DailyQuests._initialize (a same-day save load
	# emits no completion/reset signal, so this is what paints the loaded count).
	EventBus.daily_quest_completed.connect(_refresh_daily_badge.unbind(1))
	EventBus.daily_quests_all_completed.connect(_refresh_daily_badge.unbind(1))
	EventBus.daily_quests_reset.connect(_refresh_daily_badge)
	EventBus.game_loaded.connect(_refresh_daily_badge, CONNECT_DEFERRED)
	# Repaint colors on palette swap + rescale the badge font with the slider
	# (the inline font-size override doesn't follow the theme on its own).
	Settings.theme_changed.connect(_restyle_daily_badge)
	Settings.accessibility_settings_changed.connect(_restyle_daily_badge)
	_refresh_daily_badge()


## (Re)apply the badge's palette colors + scaled font. Split out so theme /
## font-scale changes can repaint it without rebuilding the node.
func _restyle_daily_badge() -> void:
	if _daily_badge == null:
		return
	var palette: Dictionary = PaletteDusk.active()
	var sb := StyleBoxFlat.new()
	sb.bg_color = palette["gold"]
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	_daily_badge.add_theme_stylebox_override("panel", sb)
	_daily_badge_label.add_theme_font_size_override("font_size", UiScale.size(8))
	_daily_badge_label.add_theme_color_override("font_color", palette["bg_deep"])


## Show "done/total" while daily quests are incomplete; hide once all are done
## (clean nav when there's nothing left to do) or before the set is initialized.
func _refresh_daily_badge() -> void:
	if _daily_badge == null:
		return
	var total: int = DailyQuests.active_count()
	var done: int = DailyQuests.completed_count()
	if total <= 0 or done >= total:
		_daily_badge.visible = false
		return
	_daily_badge_label.text = "%d/%d" % [done, total]
	_daily_badge.visible = true


## Phase 14f — applies styles.css `.tabbar button` styleboxes to every
## nav button. Called once at build time + again on Settings.theme_changed
## so a palette swap repaints the bar live.
##
## styles.css contract:
##   .tabbar button (normal)
##     bg: var(--bg-deep)
##     color: var(--ink-mute)
##     border-right: 1px dashed var(--border-soft) (omitted in Godot —
##       no per-edge dashed StyleBoxFlat support; we ship a solid
##       border instead)
##
##   .tabbar button[data-active=true] (pressed / current tab)
##     color: var(--gold)
##     bg: linear-gradient(180deg, card_2, card)  → flat card_2 below
##     box-shadow: inset 0 2px 0 var(--gold)  → 2-px gold top border
##     box-shadow: inset 0 -2px 0 #00000080  → 2-px black bottom
func _apply_nav_styleboxes() -> void:
	if _nav_buttons.is_empty():
		return
	var palette: Dictionary = PaletteDusk.active()

	# Normal state: flat bg_deep + ink_mute text + soft 1-px right border.
	var normal_sb := StyleBoxFlat.new()
	normal_sb.bg_color = palette["bg_deep"]
	normal_sb.border_color = palette["border_soft"]
	normal_sb.border_width_right = 1
	normal_sb.border_width_top = 2   # styles.css `.tabbar` border-top
	normal_sb.border_width_left = 0
	normal_sb.border_width_bottom = 0
	normal_sb.set_corner_radius_all(0)
	normal_sb.content_margin_left = 6.0
	normal_sb.content_margin_right = 6.0
	normal_sb.content_margin_top = 8.0
	normal_sb.content_margin_bottom = 8.0

	# Hover state: subtle bg lift to bg_2 (slightly brighter purple).
	var hover_sb: StyleBoxFlat = normal_sb.duplicate()
	hover_sb.bg_color = palette["bg_2"]

	# Pressed / active state: card_2 bg, 2-px gold inset top bar, dark
	# inset bottom. styles.css uses a linear gradient card_2→card; flat
	# card_2 is the cleanest StyleBoxFlat approximation.
	var pressed_sb := StyleBoxFlat.new()
	pressed_sb.bg_color = palette["card_2"]
	pressed_sb.border_color = palette["gold"]
	pressed_sb.border_width_top = 2
	pressed_sb.border_width_right = 1
	pressed_sb.border_width_left = 0
	pressed_sb.border_width_bottom = 0
	pressed_sb.set_corner_radius_all(0)
	pressed_sb.content_margin_left = 6.0
	pressed_sb.content_margin_right = 6.0
	pressed_sb.content_margin_top = 8.0
	pressed_sb.content_margin_bottom = 8.0
	# Approximate the inset `box-shadow: inset 0 -2px 0 #00000080` via
	# a slight shadow_offset; in practice the gold top border + card_2
	# bg already telegraph "this is the active tab" clearly.

	var ink_mute: Color = palette["ink_mute"]
	var gold: Color = palette["gold"]

	for btn in _nav_buttons.values():
		btn.add_theme_stylebox_override("normal", normal_sb)
		btn.add_theme_stylebox_override("hover", hover_sb)
		btn.add_theme_stylebox_override("pressed", pressed_sb)
		# Toggle buttons also paint a `pressed` stylebox while held
		# AND a `hover_pressed` while hovered-while-active. Both should
		# match the active state.
		btn.add_theme_stylebox_override("hover_pressed", pressed_sb)
		btn.add_theme_color_override("font_color", ink_mute)
		btn.add_theme_color_override("font_pressed_color", gold)
		btn.add_theme_color_override("font_hover_color", ink_mute)
		btn.add_theme_color_override("font_hover_pressed_color", gold)
		btn.add_theme_color_override("font_focus_color", gold)

	# More button uses the same styling — but it's a non-toggle Button
	# so only the normal/hover states apply. The pressed state still
	# paints during the brief moment of tap-down for visual confirmation.
	if _more_button != null:
		_more_button.add_theme_stylebox_override("normal", normal_sb)
		_more_button.add_theme_stylebox_override("hover", hover_sb)
		_more_button.add_theme_stylebox_override("pressed", pressed_sb)
		_more_button.add_theme_color_override("font_color", ink_mute)
		_more_button.add_theme_color_override("font_pressed_color", gold)


## Phase 13c.2 — orientation-aware root composition.
##
## Tears down the previous composition root (if any) without touching
## the persistent children, then rebuilds it for the active
## orientation. The persistent children (currency_bar, _tabs,
## quest_strip, nav buttons) are re-parented; their internal state
## (catching view's RNG, battle replay frame, hold-to-tap, scroll
## position, etc.) survives the flip intact.
func _apply_orientation_layout() -> void:
	if _safe_margin == null:
		return
	orientation_apply_count += 1
	# Detach persistent children from any current parent so they can
	# be safely re-added under the new composition root. `remove_child`
	# is a no-op if the parent is null.
	for node in _persistent_layout_children():
		var parent := node.get_parent()
		if parent != null:
			parent.remove_child(node)
	# Tear down the previous composition root (containers only — the
	# persistent children were already detached above).
	if _orientation_root != null and is_instance_valid(_orientation_root):
		_orientation_root.queue_free()
	if DeviceLayout.is_landscape:
		_orientation_root = _build_landscape_layout()
	else:
		_orientation_root = _build_portrait_layout()
	_safe_margin.add_child(_orientation_root)


func _persistent_layout_children() -> Array[Control]:
	# Order doesn't matter — each child is reparented to the right
	# slot inside the new layout.
	var out: Array[Control] = []
	if _currency_bar != null: out.append(_currency_bar)
	if _tabs != null: out.append(_tabs)
	if _quest_strip != null: out.append(_quest_strip)
	for tab_name in _PRIMARY_NAV:
		if _nav_buttons.has(tab_name):
			out.append(_nav_buttons[tab_name])
	if _more_button != null: out.append(_more_button)
	return out


## Portrait root: VBox { currency_bar / tabs / quest_strip / bottom_nav }.
## Mirrors the pre-13c.2 layout exactly so existing screens (and the
## screenshot mode) look identical to v0.13.x in portrait.
func _build_portrait_layout() -> Control:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 0)

	vbox.add_child(_currency_bar)
	vbox.add_child(_tabs)
	vbox.add_child(_quest_strip)

	var bottom_nav := HBoxContainer.new()
	bottom_nav.add_theme_constant_override("separation", 0)
	bottom_nav.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for tab_name in _PRIMARY_NAV:
		var btn: Button = _nav_buttons[tab_name]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_FILL
		btn.custom_minimum_size = Vector2(0.0, _NAV_BUTTON_HEIGHT_DP)
		bottom_nav.add_child(btn)
	_more_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_more_button.size_flags_vertical = Control.SIZE_FILL
	_more_button.custom_minimum_size = Vector2(0.0, _NAV_BUTTON_HEIGHT_DP)
	bottom_nav.add_child(_more_button)
	vbox.add_child(bottom_nav)
	return vbox


## Landscape root: HBox { left_rail (vertical nav) / VBox { currency_bar / tabs / quest_strip } }.
## Phase 13c.2's user-visible payoff: in landscape the bottom-bar
## stops eating ~9 % of vertical real estate and the catching screen
## breathes. Same buttons, same handlers, just rotated 90°.
func _build_landscape_layout() -> Control:
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 0)

	var rail := VBoxContainer.new()
	rail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.custom_minimum_size = Vector2(_LEFT_RAIL_WIDTH_DP, 0)
	rail.add_theme_constant_override("separation", 0)
	for tab_name in _PRIMARY_NAV:
		var btn: Button = _nav_buttons[tab_name]
		btn.size_flags_horizontal = Control.SIZE_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(_LEFT_RAIL_WIDTH_DP, _NAV_BUTTON_HEIGHT_DP)
		rail.add_child(btn)
	_more_button.size_flags_horizontal = Control.SIZE_FILL
	_more_button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_more_button.custom_minimum_size = Vector2(_LEFT_RAIL_WIDTH_DP, _NAV_BUTTON_HEIGHT_DP)
	rail.add_child(_more_button)
	hbox.add_child(rail)

	var content_vbox := VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_vbox.add_theme_constant_override("separation", 0)
	content_vbox.add_child(_currency_bar)
	content_vbox.add_child(_tabs)
	content_vbox.add_child(_quest_strip)
	hbox.add_child(content_vbox)
	return hbox


## Bottom-nav button handler — switches the (hidden) TabContainer's
## current_tab to the named tab and updates the active highlight.
func _on_nav_button_pressed(tab_name: String) -> void:
	_navigate_to_tab(tab_name)


func _navigate_to_tab(tab_name: String) -> void:
	if _tabs == null:
		return
	var idx: int = _find_tab_index(tab_name)
	if idx < 0:
		push_warning("nav: tab not found: " + tab_name)
		return
	_tabs.current_tab = idx
	_set_active_nav(tab_name)


func _find_tab_index(tab_name: String) -> int:
	for i in _tabs.get_tab_count():
		if _tabs.get_tab_title(i) == tab_name:
			return i
	return -1


## Toggle the `button_pressed` flag on each primary-nav button so the
## one matching `tab_name` shows the active (gold-inset) stylebox; the
## others go back to the normal stylebox.
##
## v0.15.11 — when the active destination is a SECONDARY (More-sheet)
## screen, no primary lights up but the More button does, so the player
## always sees which "zone" they're in (pre-fix, the 6 More-sheet
## screens had zero active indication anywhere).
func _set_active_nav(tab_name: String) -> void:
	# Iterator var renamed from `name` to avoid shadowing Node.name.
	for nav_name in _nav_buttons:
		_nav_buttons[nav_name].button_pressed = (nav_name == tab_name)
	if _more_button != null:
		_more_button.button_pressed = _SECONDARY_NAV.has(tab_name)


## More-button handler: opens a custom-styled PopupPanel that reads as
## a bottom sheet — full-width, anchored to the bottom of the screen,
## one 64-dp button per secondary destination. Replaces the v0.9.0
## system PopupMenu, whose default small-text styling clashed with
## the surrounding 18 sp / 64 dp Material-style bottom nav.
##
## Built once and cached on `_more_popup` (declared at class scope
## above) so subsequent opens reuse the same control without
## rebuilding the sub-tree.
func _on_more_pressed() -> void:
	if _more_popup == null:
		_build_more_popup()
	# Size the popup to the device width with a small lateral inset.
	var viewport_w: float = get_viewport().get_visible_rect().size.x
	var more_rect: Rect2 = _more_button.get_global_rect()
	# v0.15.15 — cap the height to the space above the nav bar so a tall menu
	# (7 items × large font) can't push its top items off-screen; the inner
	# ScrollContainer scrolls within the cap. content_est mirrors the layout:
	# heading + N buttons (+ separations) + the 12-dp top/bottom margins.
	var content_est: float = 40.0 + float(_SECONDARY_NAV.size()) * (_NAV_BUTTON_HEIGHT_DP + 4.0) + 24.0
	var available: float = max(120.0, more_rect.position.y - 8.0 - 16.0)
	var popup_h: int = int(min(content_est, available))
	_more_popup.size = Vector2i(int(viewport_w - 16), popup_h)
	# Anchor as a bottom sheet: y just above the nav bar.
	_more_popup.position = Vector2i(
			8,
			int(more_rect.position.y - _more_popup.size.y - 8))
	_more_popup.popup()


func _build_more_popup() -> void:
	_more_popup = PopupPanel.new()
	# PopupPanel is a Window subtype — Window subtrees don't inherit the
	# theme of their parent Control, so without this assignment the
	# popup falls back to Godot's default styleboxes (visibly: teal-
	# green focus outlines on the secondary-nav buttons that don't
	# match the rest of the parchment/brass UI).
	_more_popup.theme = preload("res://assets/themes/dusk/amethyst.tres")
	add_child(_more_popup)
	# v0.15.11 — when the sheet is dismissed without picking a destination
	# (tap-outside / Back), re-sync the More button's active state to the
	# current tab so it doesn't stay lit after being opened from a primary
	# screen (toggle_mode flips button_pressed on the opening press).
	_more_popup.popup_hide.connect(_resync_more_active_state)

	var margins := MarginContainer.new()
	margins.add_theme_constant_override("margin_left", 12)
	margins.add_theme_constant_override("margin_right", 12)
	margins.add_theme_constant_override("margin_top", 12)
	margins.add_theme_constant_override("margin_bottom", 12)
	_more_popup.add_child(margins)

	# v0.15.15 — the sheet now has 7 secondary destinations; on a small / split-
	# screen / large-font device the column can exceed the space above the nav
	# bar. A ScrollContainer lets it scroll instead of clipping the top items
	# off-screen (the popup height is capped in _on_more_pressed).
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margins.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)

	var heading := Label.new()
	heading.text = "More"
	heading.add_theme_font_size_override("font_size", UiScale.size(18))
	heading.modulate = Color(0.85, 0.85, 0.85)
	vbox.add_child(heading)

	for tab_name in _SECONDARY_NAV:
		var btn := Button.new()
		btn.text = _label_with_icon(tab_name)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0.0, _NAV_BUTTON_HEIGHT_DP)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_more_item_selected.bind(tab_name))
		vbox.add_child(btn)


func _on_more_item_selected(tab_name: String) -> void:
	if _more_popup != null:
		_more_popup.hide()
	_navigate_to_tab(tab_name)


## v0.15.11 — re-derive the More button's active state from the current
## tab. Called when the More sheet is dismissed without a selection (its
## `popup_hide` signal), so opening the sheet from a primary screen and
## tapping away doesn't leave More spuriously lit.
func _resync_more_active_state() -> void:
	if _more_button == null or _tabs == null:
		return
	var idx: int = _tabs.current_tab
	if idx < 0 or idx >= _tabs.get_tab_count():
		_more_button.button_pressed = false
		return
	var current_title: String = _tabs.get_tab_title(idx)
	_more_button.button_pressed = _SECONDARY_NAV.has(current_title)


func _seed_default_net_if_needed() -> void:
	# Phase 1 first-launch QoL: if no nets are owned and no gold has been earned,
	# the player can't yet afford the basic net. We don't auto-grant — taps work
	# without a net. The net shop is reachable from the Shop tab.
	pass


func _apply_offline_progress(loaded: Dictionary) -> void:
	if loaded.is_empty():
		return
	var last_saved_unix: int = int(loaded.get("last_saved_unix", 0))
	if last_saved_unix <= 0:
		return
	var offline_cap_mult: float = GameState.multiplier(&"offline_cap")
	# v0.15.17 — pass the UNCAPPED elapsed; OfflineProgressSystem.compute owns
	# the clamp (single source of truth) and needs the raw value to set
	# `capped`/`raw_seconds` truthfully. Pre-fix the cap was applied here
	# first, so raw == cap inside compute and the welcome-back dialog's
	# "(capped)" note was dead code that could never render.
	var elapsed: float = TimeManager.compute_offline_elapsed(last_saved_unix, INF)
	if elapsed <= 60.0:
		return  # Don't pop the dialog for sub-minute trips.
	var net_id_str: String = String(GameState.active_net)
	if net_id_str == "":
		return
	var net := ContentRegistry.net(StringName(net_id_str))
	if net == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var summary := OfflineProgressSystem.compute(
			ContentRegistry.monsters(),
			net,
			GameState.current_max_tier,
			elapsed,
			rng,
			offline_cap_mult,
			GameState.multiplier(&"auto_speed"),
			GameState.multiplier(&"drop_amount"),
			GameState.multiplier(&"gold_mult"),
			GameState.multiplier(&"shiny_rate"))
	EventBus.offline_progress_calculated.emit(summary)
	# v0.11.4 (Phase 11e fix for F48): apply rewards IMMEDIATELY before
	# showing the welcome-back dialog. Pre-fix, a force-quit at the
	# dialog (or process-killed mid-presentation) lost the offline
	# progress entirely. Now the rewards land in GameState and persist
	# via the next save tick regardless of whether the player taps
	# Claim. The dialog becomes a confirmation/summary; the 2x ad path
	# adds ANOTHER summary's worth on top via the existing handler.
	_on_welcome_back_claimed(summary)
	_show_welcome_back(summary)


func _show_welcome_back(summary: Dictionary) -> void:
	_welcome_back_dialog = _WELCOME_BACK_DIALOG.instantiate()
	add_child(_welcome_back_dialog)
	_welcome_back_dialog.claimed.connect(_on_welcome_back_claimed)
	_welcome_back_dialog.show_summary(summary)


func _on_welcome_back_claimed(summary: Dictionary) -> void:
	# Apply the offline rewards now that the player has acknowledged them.
	var gold: BigNumber = summary.get("gold_gained", BigNumber.zero())
	GameState.add_gold(gold)
	for item_id_str in summary.get("items_gained", {}).keys():
		var amount: int = int(summary["items_gained"][item_id_str])
		GameState.add_item(StringName(item_id_str), amount)
	for monster_id_str in summary.get("catches_by_species", {}).keys():
		var entry: Dictionary = summary["catches_by_species"][monster_id_str]
		for i in int(entry.get("normal", 0)):
			GameState.record_catch(StringName(monster_id_str), false, "offline")
		for i in int(entry.get("shiny", 0)):
			GameState.record_catch(StringName(monster_id_str), true, "offline")
	GameState.ledger["total_offline_seconds_credited"] = int(GameState.ledger["total_offline_seconds_credited"]) + int(summary.get("seconds", 0))


## v0.15.14 — daily-login reward (retention bundle). Runs once at boot, after
## offline progress. Detects whether today (LOCAL calendar day) is a fresh,
## claimable login; if so grants the escalating cycle reward to GameState
## IMMEDIATELY (so a force-quit at the modal never loses it — the same
## pre-apply contract WelcomeBackDialog uses) and shows the acknowledgment
## modal. When the welcome-back (offline) dialog is also up on this launch,
## the daily modal is queued to show after it dismisses (never stacked).
func _apply_daily_login() -> void:
	var today: int = DailyLoginSystem.local_day_index(
			TimeManager.now_unix(), TimeManager.tz_bias_minutes())
	var decision: Dictionary = DailyLoginSystem.evaluate(
			today, GameState.daily_login_last_day, GameState.daily_login_streak)
	if not bool(decision.get("claimable", false)):
		return
	var cycle_day: int = int(decision["cycle_day"])
	var reward: Dictionary = DailyLoginSystem.reward_for(
			cycle_day,
			BigNumber.from_dict(GameState.total_gold_earned_this_run),
			GameState.current_max_tier)
	# Apply BEFORE showing the modal — rewards persist on the next save tick
	# regardless of whether the player taps Collect.
	var gold: BigNumber = reward["gold"]
	GameState.add_gold(gold)
	var rp: int = int(reward["rp"])
	if rp > 0:
		GameState.add_rancher_points(rp, "daily_login")
	GameState.daily_login_streak = int(decision["new_streak"])
	GameState.daily_login_last_day = today
	var summary: Dictionary = {
		"cycle_day": cycle_day,
		"streak": GameState.daily_login_streak,
		"gold": gold,
		"rp": rp,
		"missed": bool(decision.get("missed", false)),
	}
	EventBus.daily_reward_claimed.emit(summary)
	# Sequence after the welcome-back dialog if it's currently shown.
	if _welcome_back_dialog != null and is_instance_valid(_welcome_back_dialog) \
			and _welcome_back_dialog.visible:
		_pending_daily_summary = summary
		_welcome_back_dialog.visibility_changed.connect(_on_welcome_back_dismissed_show_daily)
	else:
		_show_daily_reward(summary)


## One-shot: show the queued daily reward once the welcome-back dialog hides.
func _on_welcome_back_dismissed_show_daily() -> void:
	if _welcome_back_dialog != null and is_instance_valid(_welcome_back_dialog) \
			and _welcome_back_dialog.visible:
		return  # still visible — wait for the hide
	if _welcome_back_dialog != null and is_instance_valid(_welcome_back_dialog) \
			and _welcome_back_dialog.visibility_changed.is_connected(_on_welcome_back_dismissed_show_daily):
		_welcome_back_dialog.visibility_changed.disconnect(_on_welcome_back_dismissed_show_daily)
	if _pending_daily_summary.is_empty():
		return
	var summary: Dictionary = _pending_daily_summary
	_pending_daily_summary = {}
	# Defer one frame so the just-hidden welcome-back window fully releases its
	# exclusive-child slot before the daily modal claims it. Showing it
	# synchronously here races that release and Godot logs "parent already has
	# another exclusive child".
	_show_daily_reward.call_deferred(summary)


func _show_daily_reward(summary: Dictionary) -> void:
	_daily_reward_dialog = _DAILY_REWARD_DIALOG.instantiate()
	add_child(_daily_reward_dialog)
	_daily_reward_dialog.doubled.connect(_on_daily_reward_doubled)
	_daily_reward_dialog.show_reward(summary)


## v0.15.18 — rewarded-ad daily doubler. The base reward was pre-applied in
## _apply_daily_login; a granted ad applies the GOLD again (total 2×). RP is
## deliberately NOT doubled (see DailyRewardDialog's doc comment). No second
## EventBus.daily_reward_claimed emit — quest/achievement evaluators already
## counted this claim once and must not double-count it.
func _on_daily_reward_doubled(summary: Dictionary) -> void:
	var gold: BigNumber = summary.get("gold", BigNumber.zero())
	GameState.add_gold(gold)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	# v0.11.2 (Phase 11c): F2 and F3 are debug-only. F3 in particular
	# wipes save state with no confirm — a Bluetooth keyboard or
	# accidental press on a desktop release build would silently
	# erase progress. Production builds now ignore both keys.
	if not OS.is_debug_build():
		return
	match event.keycode:
		KEY_F2:
			Settings.debug_fast_pets = not Settings.debug_fast_pets
			print("[debug] FAST_PETS = %s (lowers tier threshold to 2 + forces variants when on)" % Settings.debug_fast_pets)
			get_viewport().set_input_as_handled()
		KEY_F3:
			_reset_all_progress()
			get_viewport().set_input_as_handled()
		_:
			# v0.9.3: number-key shortcuts (1-0) jump to the matching
			# TabContainer index. Only active in debug builds — gated
			# by OS.is_debug_build() so production releases ignore them.
			# Used by the Maestro test suite to drive trailing-tab nav
			# without depending on `swipe`/coordinate taps that don't
			# reliably scroll Godot's TabContainer tab bar in the
			# emulator (see tests/maestro/README.md).
			if not OS.is_debug_build():
				return
			var key_to_index: Dictionary = {
				KEY_1: 0, KEY_2: 1, KEY_3: 2, KEY_4: 3, KEY_5: 4,
				KEY_6: 5, KEY_7: 6, KEY_8: 7, KEY_9: 8, KEY_0: 9,
			}
			if not key_to_index.has(event.keycode):
				return
			var idx: int = key_to_index[event.keycode]
			if _tabs == null or idx >= _tabs.get_tab_count():
				return
			_tabs.current_tab = idx
			_set_active_nav(_tabs.get_tab_title(idx))
			get_viewport().set_input_as_handled()


## Wipes save state and reloads first-launch defaults. Bound to F3.
## Useful for testing the catch loop / tier progression / battle flow
## from scratch without hand-deleting user://save.json.
func _reset_all_progress() -> void:
	GameState.from_dict({})
	SaveManager.save(GameState.to_dict())
	# Force every reactive UI to refresh.
	EventBus.game_loaded.emit()
	EventBus.currency_changed.emit("gold", GameState.current_gold())
	EventBus.currency_changed.emit("rancher_points", GameState.current_rancher_points())
	print("[debug] PROGRESS RESET — back to first-launch defaults.")


## One-shot Play Store screenshot generator. Run via:
##   godot --path . -- --screenshots
## Output lands in `OS.get_user_data_dir() + "/screenshots/"` as PNGs.
func _run_screenshot_mode() -> void:
	# Hide debug overlays so they don't end up in marketing screenshots.
	if _ad_diag_overlay:
		_ad_diag_overlay.visible = false
	if _save_indicator_overlay:
		_save_indicator_overlay.visible = false
	if _touch_debug_overlay:
		_touch_debug_overlay.visible = false

	# Seed mid-game state so screens look populated.
	_seed_screenshot_state()
	EventBus.game_loaded.emit()
	EventBus.currency_changed.emit("gold", GameState.current_gold())
	EventBus.currency_changed.emit("rancher_points", GameState.current_rancher_points())
	# Resize to Play Store-compliant 9:16 portrait. 1080x1920 satisfies
	# phone, 7" tablet, AND 10" tablet listing constraints in one go.
	get_window().size = Vector2i(1080, 1920)
	# Three frames for layout to settle after the resize.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var out_dir := OS.get_user_data_dir() + "/screenshots"
	DirAccess.make_dir_recursive_absolute(out_dir)

	# Tab name -> output filename. Six shots cover the breadth of the
	# game in marketing terms.
	var shots: Array[Dictionary] = [
		{"tab": "Catch", "name": "01_catch.png"},
		{"tab": "Battle", "name": "02_battle.png"},
		{"tab": "Bestiary", "name": "03_bestiary.png"},
		{"tab": "Inventory", "name": "04_inventory.png"},
		{"tab": "Upgrades", "name": "05_upgrades.png"},
		{"tab": "Settings", "name": "06_settings.png"},
	]

	for shot in shots:
		var idx := -1
		for i in _tabs.get_tab_count():
			if _tabs.get_tab_title(i) == shot["tab"]:
				idx = i
				break
		if idx < 0:
			push_warning("screenshot tab not found: " + shot["tab"])
			continue
		_tabs.current_tab = idx
		# Wait for tab content to render. Catch screen needs more time
		# because monsters spawn over time; force-spawn a few so the
		# screenshot isn't an empty room.
		if shot["tab"] == "Catch":
			var catch_view := _tabs.get_child(idx)
			if catch_view != null:
				for s in 4:
					if catch_view.has_method("_spawn_one"):
						var net = catch_view.call("_active_net")
						catch_view.call("_spawn_one", net)
				for f in 240:   # 4 s — let monsters wander to varied positions
					await get_tree().process_frame
		else:
			for f in 4:
				await get_tree().process_frame
		var image: Image = get_viewport().get_texture().get_image()
		var path: String = out_dir + "/" + shot["name"]
		image.save_png(path)
		print("[screenshot] saved ", path)

	print("[screenshot] all done. Output at: ", out_dir)


## Seeds GameState with a mid-game snapshot for marketing screenshots:
## ~50K gold, a stocked bestiary, a few pets, a leveled-up active net,
## and a few upgrades purchased.
func _seed_screenshot_state() -> void:
	# Currencies
	GameState.currencies = {
		"gold": {"m": 5.27, "e": 4},   # 52.7K gold
		"rancher_points": 12,
	}
	GameState.total_gold_earned_this_run = {"m": 8.4, "e": 4}
	# Inventory
	GameState.inventory = {
		"wisplet_ectoplasm": 247,
		"centiphantom_jelly": 88,
		"hush_shroud": 41,
		"wraith_cinder": 17,
	}
	# Bestiary entries — a few species, with one shiny.
	GameState.monsters_caught = {
		"green_wisplet": {"normal": 102, "shiny": 3},
		"red_wisplet": {"normal": 67, "shiny": 1},
		"blue_wisplet": {"normal": 54, "shiny": 0},
		"dawn_centiphantom": {"normal": 38, "shiny": 1},
		"dusk_centiphantom": {"normal": 22, "shiny": 0},
		"dust_centiphantom": {"normal": 19, "shiny": 0},
		"bramble_hush": {"normal": 12, "shiny": 0},
		"glowmoth_hush": {"normal": 8, "shiny": 0},
	}
	GameState.pets_owned = ["green_wisplet_pet", "dawn_centiphantom_pet"]
	GameState.pet_variants_owned = ["green_wisplet_pet"]
	GameState.nets_owned = ["basic_net", "tier2_net"]
	GameState.active_net = "tier2_net"
	GameState.current_max_tier = 4
	GameState.tiers_completed = [1, 2, 3]
	GameState.upgrades_purchased = [
		{"id": "tap_speed_1", "level": 2},
		{"id": "gold_mult_1", "level": 1},
	]
	GameState.recipes_crafted = ["recipe_tier2_net"]
	GameState.ledger = {
		"total_catches": 322,
		"total_taps": 1547,
		"total_shinies": 5,
		"session_count": 14,
		"total_play_seconds": 7423,
		"total_offline_seconds_credited": 2100,
		"prestige_count": 0,
		"first_launch_unix": int(Time.get_unix_time_from_system()) - 7423,
		"peniber_quotes_seen": 28,
	}


func _on_close_requested() -> void:
	SaveManager.save(GameState.to_dict())
	get_tree().quit()
