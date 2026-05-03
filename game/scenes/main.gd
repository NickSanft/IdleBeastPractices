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
const _TOUCH_DEBUG_OVERLAY := preload("res://game/scenes/ui/touch_debug_overlay.tscn")
const _WELCOME_BACK_DIALOG := preload("res://game/scenes/ui/welcome_back_dialog.tscn")

var _welcome_back_dialog: AcceptDialog
var _tabs: TabContainer
var _ad_diag_overlay: Control
var _save_indicator_overlay: Control
var _touch_debug_overlay: Control


func _ready() -> void:
	get_tree().root.close_requested.connect(_on_close_requested)
	ContentRegistry.ensure_loaded()
	_apply_mobile_default_theme()
	_install_global_haptic_feedback()
	_build_ui()
	var loaded: Dictionary = SaveManager.load_save()
	GameState.from_dict(loaded)
	GameState.reconcile_pet_awards()
	GameState.reconcile_total_gold_earned_this_run()
	_apply_offline_progress(loaded)
	_seed_default_net_if_needed()
	_start_periodic_save()

	# Optional one-shot screenshot generator for Play Store listing.
	# Activated via `godot --path . -- --screenshots`. Seeds GameState
	# with a mid-game snapshot, hides diagnostic overlays, sizes the
	# window to 1080x1920 (Play Store-compliant 9:16 portrait, fits
	# all three Play Console categories: phone / 7" tablet / 10"
	# tablet), cycles through key tabs and saves PNGs.
	if "--screenshots" in OS.get_cmdline_user_args():
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
	_tabs = tabs

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
	_ad_diag_overlay = _AD_DIAGNOSTIC_OVERLAY.instantiate()
	add_child(_ad_diag_overlay)

	# Bottom-right toast that flashes "Saved <HH:MM:SS>" each time
	# SaveManager.save() commits — diagnostic for the v0.8.2 cycle so
	# the user can verify save lifecycle hooks are actually firing on
	# Android. Cheap; subscribes to EventBus.game_saved.
	_save_indicator_overlay = _SAVE_INDICATOR_OVERLAY.instantiate()
	add_child(_save_indicator_overlay)

	# Crosshair that paints at every touch / click position for ~0.8 s.
	# v0.8.5 diagnostic — confirms whether Godot's hit-test coordinate
	# matches where the user thought they tapped. Cheap (only paints
	# while a tap is recent); will be gated behind a debug flag in a
	# follow-up release once we've confirmed the user's input issue.
	_touch_debug_overlay = _TOUCH_DEBUG_OVERLAY.instantiate()
	add_child(_touch_debug_overlay)


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

	# Buttons: 48 dp tap target per Material's accessibility floor
	# (text height ~22 px + 14 px top + 14 px bottom = ~50 px = 48 dp
	# at our viewport scale). v0.8.4 dialed this down to 8/12 thinking
	# the padding was the source of the hit-test mismatch; research
	# (godotengine/godot#118153 — canvas_items stretch input mapping)
	# pointed at the real culprit (now mitigated via
	# `display/window/stretch/aspect="keep"` in project.godot), so
	# v0.8.5 restores the proper 48 dp size.
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.22, 0.24, 0.30)
	btn_normal.content_margin_top = 14.0
	btn_normal.content_margin_bottom = 14.0
	btn_normal.content_margin_left = 18.0
	btn_normal.content_margin_right = 18.0
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
	Input.vibrate_handheld(20)


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
	# v0.8.5: TabContainer + MOUSE_FILTER_STOP can dispatch tab clicks
	# in two different coordinate systems on Godot 4.6 (godotengine/
	# godot#91987), causing hit-test mismatches especially on Android.
	# PASS lets the child TabBar handle input cleanly without the
	# parent re-emitting a duplicate event.
	tabs.mouse_filter = Control.MOUSE_FILTER_PASS

	for state in ["tab_selected", "tab_unselected", "tab_hovered", "tab_focus"]:
		var sb := StyleBoxFlat.new()
		# v0.8.5: restored to 14/18 alongside the button stylebox bump
		# now that the canvas_items stretch input bug is mitigated via
		# project.godot's stretch/aspect="keep".
		sb.content_margin_top = 14
		sb.content_margin_bottom = 14
		sb.content_margin_left = 18
		sb.content_margin_right = 18
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
