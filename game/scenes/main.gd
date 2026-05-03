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
const _SETTINGS_VIEW := preload("res://game/scenes/ui/settings_view.tscn")
const _NARRATOR_OVERLAY := preload("res://game/scenes/ui/narrator_overlay.tscn")
const _AD_DIAGNOSTIC_OVERLAY := preload("res://game/scenes/ui/ad_diagnostic_overlay.tscn")
const _SAVE_INDICATOR_OVERLAY := preload("res://game/scenes/ui/save_indicator_overlay.tscn")
const _WELCOME_BACK_DIALOG := preload("res://game/scenes/ui/welcome_back_dialog.tscn")

var _welcome_back_dialog: AcceptDialog


func _ready() -> void:
	get_tree().root.close_requested.connect(_on_close_requested)
	ContentRegistry.ensure_loaded()
	_apply_mobile_default_theme()
	_build_ui()
	var loaded: Dictionary = SaveManager.load_save()
	GameState.from_dict(loaded)
	GameState.reconcile_pet_awards()
	GameState.reconcile_total_gold_earned_this_run()
	_apply_offline_progress(loaded)
	_seed_default_net_if_needed()
	_start_periodic_save()


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


func _build_ui() -> void:
	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_vbox.add_theme_constant_override("separation", 0)
	add_child(root_vbox)

	var currency_bar: Control = _CURRENCY_BAR.instantiate()
	currency_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(currency_bar)

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_apply_mobile_tab_theme(tabs)
	root_vbox.add_child(tabs)

	var catch_tab: Control = _CATCHING_VIEW.instantiate()
	catch_tab.name = "Catch"
	tabs.add_child(catch_tab)

	var battle_tab: Control = _BATTLE_VIEW.instantiate()
	battle_tab.name = "Battle"
	tabs.add_child(battle_tab)

	var inventory_tab: Control = _INVENTORY_PANEL.instantiate()
	inventory_tab.name = "Inventory"
	tabs.add_child(inventory_tab)

	var bestiary_tab: Control = _BESTIARY_VIEW.instantiate()
	bestiary_tab.name = "Bestiary"
	tabs.add_child(bestiary_tab)

	var crafting_tab: Control = _CRAFTING_VIEW.instantiate()
	crafting_tab.name = "Crafting"
	tabs.add_child(crafting_tab)

	var ledger_tab: Control = _LEDGER_VIEW.instantiate()
	ledger_tab.name = "Ledger"
	tabs.add_child(ledger_tab)

	var shop_tab: Control = _NET_SHOP.instantiate()
	shop_tab.name = "Shop"
	tabs.add_child(shop_tab)

	var upgrades_tab: Control = _UPGRADE_TREE.instantiate()
	upgrades_tab.name = "Upgrades"
	tabs.add_child(upgrades_tab)

	var prestige_tab: Control = _PRESTIGE_VIEW.instantiate()
	prestige_tab.name = "Prestige"
	tabs.add_child(prestige_tab)

	var settings_tab: Control = _SETTINGS_VIEW.instantiate()
	settings_tab.name = "Settings"
	tabs.add_child(settings_tab)

	# NarratorOverlay sits ABOVE the tab container so it can float over any
	# tab. Mouse_filter is IGNORE on the overlay so background taps still
	# reach the catching view; only the speech bubble itself catches taps.
	var overlay: Control = _NARRATOR_OVERLAY.instantiate()
	add_child(overlay)

	# Top-of-screen banner that surfaces ad lifecycle events for debugging.
	# Subscribes to AdsManager.requested / rewarded_completed / rewarded_failed.
	var ad_diag: Control = _AD_DIAGNOSTIC_OVERLAY.instantiate()
	add_child(ad_diag)

	# Bottom-right toast that flashes "Saved <HH:MM:SS>" each time
	# SaveManager.save() commits — diagnostic for the v0.8.2 cycle so
	# the user can verify save lifecycle hooks are actually firing on
	# Android. Cheap; subscribes to EventBus.game_saved.
	var save_indicator: Control = _SAVE_INDICATOR_OVERLAY.instantiate()
	add_child(save_indicator)


## Project-wide theme assigned to the root window so every Control
## inherits mobile-friendly defaults — bigger buttons, larger fonts.
## Per-control `add_theme_*_override` calls already in the codebase
## still take precedence; this just raises the floor everywhere else.
##
## v0.8.3: user reported on Galaxy Z Fold7 (Android 16) that buttons
## were too small to reliably hit and the tab bar was hard to scroll
## through. Applied across the board.
func _apply_mobile_default_theme() -> void:
	var theme := Theme.new()

	# Buttons: bigger hit-box via vertical padding; rounded corners
	# so the bigger surface still reads as a button rather than a slab.
	# v0.8.4: reduced from 14/18 to 8/12 after a hit-test-mismatch
	# report — the larger margins were making the stylebox draw past
	# the actual control rect on screens where the parent container
	# constrained the button height (sliders, anchored corner buttons).
	# Net result is still a comfortable ~36-40 dp tap target for
	# label-only buttons but no longer fights the layout.
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.22, 0.24, 0.30)
	btn_normal.content_margin_top = 8.0
	btn_normal.content_margin_bottom = 8.0
	btn_normal.content_margin_left = 12.0
	btn_normal.content_margin_right = 12.0
	btn_normal.corner_radius_top_left = 6
	btn_normal.corner_radius_top_right = 6
	btn_normal.corner_radius_bottom_left = 6
	btn_normal.corner_radius_bottom_right = 6
	var btn_hover: StyleBoxFlat = btn_normal.duplicate(true)
	btn_hover.bg_color = Color(0.28, 0.30, 0.38)
	var btn_pressed: StyleBoxFlat = btn_normal.duplicate(true)
	btn_pressed.bg_color = Color(0.34, 0.38, 0.48)
	var btn_disabled: StyleBoxFlat = btn_normal.duplicate(true)
	btn_disabled.bg_color = Color(0.18, 0.18, 0.20)

	theme.set_stylebox("normal", "Button", btn_normal)
	theme.set_stylebox("hover", "Button", btn_hover)
	theme.set_stylebox("pressed", "Button", btn_pressed)
	theme.set_stylebox("disabled", "Button", btn_disabled)
	theme.set_font_size("font_size", "Button", 18)

	# Labels: bump up for phone readability. Custom-styled labels
	# (currency_bar, peniber overlay) override per-control.
	theme.set_font_size("font_size", "Label", 16)
	theme.set_font_size("font_size", "RichTextLabel", 16)

	# CheckBox / OptionButton inherit Button styling so they get the
	# same hit-box bump. Sliders need an explicit grabber bump.
	var slider_grabber := StyleBoxFlat.new()
	slider_grabber.bg_color = Color(0.92, 0.92, 0.96)
	slider_grabber.corner_radius_top_left = 12
	slider_grabber.corner_radius_top_right = 12
	slider_grabber.corner_radius_bottom_left = 12
	slider_grabber.corner_radius_bottom_right = 12
	slider_grabber.content_margin_top = 8
	slider_grabber.content_margin_bottom = 8
	slider_grabber.content_margin_left = 8
	slider_grabber.content_margin_right = 8
	theme.set_stylebox("grabber_area", "HSlider", slider_grabber)
	theme.set_stylebox("grabber_area_highlight", "HSlider", slider_grabber)

	get_tree().root.theme = theme


## Bigger, fingertap-friendly tab bar. Default Godot tabs are ~28 px
## tall with a 16 px font — way too small on a 1280-tall portrait
## phone. We bump font size and pad the tab styleboxes vertically so
## each tab's hit-box is closer to Material's 48 dp recommendation,
## and turn on horizontal scrolling so 10 tabs don't fight for the
## same 720 px of viewport width.
func _apply_mobile_tab_theme(tabs: TabContainer) -> void:
	tabs.add_theme_font_size_override("font_size", 18)
	tabs.tabs_rearrange_group = -1
	tabs.tab_alignment = TabBar.ALIGNMENT_LEFT

	for state in ["tab_selected", "tab_unselected", "tab_hovered", "tab_focus"]:
		var sb := StyleBoxFlat.new()
		# v0.8.4: relaxed padding from 14/18 to 10/14 to match the
		# button stylebox correction (see _apply_mobile_default_theme).
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		# Tint the selected tab so it's visually distinct on touch.
		if state == "tab_selected":
			sb.bg_color = Color(0.32, 0.36, 0.44)
		elif state == "tab_hovered":
			sb.bg_color = Color(0.28, 0.30, 0.36)
		else:
			sb.bg_color = Color(0.18, 0.20, 0.24)
		sb.border_color = Color(0.45, 0.48, 0.55) if state == "tab_selected" else Color(0.0, 0.0, 0.0, 0.0)
		sb.border_width_top = 2 if state == "tab_selected" else 0
		tabs.add_theme_stylebox_override(state, sb)


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
	var cap: float = OfflineProgressSystem.DEFAULT_CAP_SECONDS * offline_cap_mult
	var elapsed: float = TimeManager.compute_offline_elapsed(last_saved_unix, cap)
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


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_F2:
			Settings.debug_fast_pets = not Settings.debug_fast_pets
			print("[debug] FAST_PETS = %s (lowers tier threshold to 2 + forces variants when on)" % Settings.debug_fast_pets)
			get_viewport().set_input_as_handled()
		KEY_F3:
			_reset_all_progress()
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


func _on_close_requested() -> void:
	SaveManager.save(GameState.to_dict())
	get_tree().quit()
