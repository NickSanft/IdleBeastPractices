## Phase 14f — Settings palette switcher behavior.
##
## Covers:
##   1. Settings.theme_id default + setter clamps to valid ids
##   2. Setter emits theme_changed
##   3. Setter persists via save_to_disk / load_from_disk round-trip
##   4. PaletteDusk.active() reads Settings.theme_id
##   5. settings_view's 3 theme buttons swap the active palette
##   6. main.gd repaints the bottom nav on theme_changed (styleboxes update)
extends GutTest

const _SETTINGS_VIEW := preload("res://game/scenes/ui/settings_view.tscn")
const _MAIN_SCENE := preload("res://game/scenes/main.tscn")


func before_each() -> void:
	# Reset to Amethyst before each test so test order doesn't leak.
	Settings.theme_id = Settings.THEME_AMETHYST
	# Same for the font scale — the live-rebuild test below bumps it to 1.5.
	Settings.font_scale = 1.0


# region — Settings.theme_id contract

func test_default_theme_id_is_amethyst() -> void:
	# A fresh Settings autoload defaults to Amethyst — matches what's
	# loaded into the Theme.tres at the window root on startup.
	assert_eq(Settings.theme_id, Settings.THEME_AMETHYST,
		"Settings.theme_id must default to Amethyst on first launch")


func test_set_theme_id_accepts_three_valid_ids() -> void:
	for id_str in [Settings.THEME_AMETHYST, Settings.THEME_TWILIGHT, Settings.THEME_EMBER]:
		Settings.set_theme_id(id_str)
		assert_eq(Settings.theme_id, id_str)


func test_set_theme_id_clamps_unknown_to_amethyst() -> void:
	# Unknown ids fall back to Amethyst — guards against a future
	# palette removal breaking a save with a stale theme_id.
	Settings.theme_id = Settings.THEME_TWILIGHT
	Settings.set_theme_id("nonexistent-palette")
	assert_eq(Settings.theme_id, Settings.THEME_AMETHYST,
		"unknown theme_id must clamp to Amethyst")


func test_set_theme_id_emits_theme_changed() -> void:
	# theme_changed must fire whenever the id actually changes.
	# Subscribers (main.gd, scenes that use PaletteDusk.active())
	# rely on this signal for live repaint.
	var fires: Array = []
	Settings.theme_changed.connect(func() -> void: fires.append(true))
	Settings.set_theme_id(Settings.THEME_TWILIGHT)
	assert_eq(fires.size(), 1, "theme_changed must fire on a real change")
	# Same value doesn't re-fire (avoids redundant rebuilds).
	Settings.set_theme_id(Settings.THEME_TWILIGHT)
	assert_eq(fires.size(), 1,
		"theme_changed must NOT fire on a no-op set (already that id)")


func test_theme_id_persists_across_save_round_trip() -> void:
	Settings.set_theme_id(Settings.THEME_EMBER)
	Settings.save_to_disk()
	# Mutate in memory, then reload from disk.
	Settings.theme_id = Settings.THEME_AMETHYST
	Settings.load_from_disk()
	assert_eq(Settings.theme_id, Settings.THEME_EMBER,
		"theme_id must round-trip through settings.cfg")

# endregion


# region — PaletteDusk.active() reads Settings.theme_id

func test_active_returns_amethyst_by_default() -> void:
	Settings.theme_id = Settings.THEME_AMETHYST
	var palette: Dictionary = PaletteDusk.active()
	# Token compare against the canonical amethyst palette.
	assert_eq(palette["bg_deep"], PaletteDusk.amethyst()["bg_deep"],
		"PaletteDusk.active() must mirror amethyst() when theme_id == 'amethyst'")


func test_active_switches_to_twilight() -> void:
	Settings.theme_id = Settings.THEME_TWILIGHT
	var active: Dictionary = PaletteDusk.active()
	assert_eq(active["bg_deep"], PaletteDusk.twilight()["bg_deep"],
		"PaletteDusk.active() must return Twilight tokens when theme_id == 'twilight'")
	# Sanity check: the Twilight bg differs from Amethyst's so a real
	# swap is visible — not a paste-error in the palette file.
	assert_ne(active["bg_deep"], PaletteDusk.amethyst()["bg_deep"])


func test_active_switches_to_ember() -> void:
	Settings.theme_id = Settings.THEME_EMBER
	var active: Dictionary = PaletteDusk.active()
	assert_eq(active["bg_deep"], PaletteDusk.ember()["bg_deep"])
	assert_ne(active["bg_deep"], PaletteDusk.amethyst()["bg_deep"])

# endregion


# region — settings_view picker actually flips Settings.theme_id

func test_settings_view_renders_three_theme_buttons() -> void:
	var view: PanelContainer = _SETTINGS_VIEW.instantiate()
	add_child_autofree(view)
	await wait_frames(1)
	assert_eq(view._theme_buttons.size(), 3,
		"Theme picker must render one button per VALID_THEME_IDS entry")
	for id_str in Settings.VALID_THEME_IDS:
		assert_true(view._theme_buttons.has(id_str),
			"Theme picker must include button for %s" % id_str)


func test_settings_view_initial_button_state_matches_settings() -> void:
	Settings.theme_id = Settings.THEME_TWILIGHT
	var view: PanelContainer = _SETTINGS_VIEW.instantiate()
	add_child_autofree(view)
	await wait_frames(1)
	assert_true(view._theme_buttons[Settings.THEME_TWILIGHT].button_pressed,
		"Twilight button must start pressed when Settings.theme_id == twilight")
	assert_false(view._theme_buttons[Settings.THEME_AMETHYST].button_pressed)
	assert_false(view._theme_buttons[Settings.THEME_EMBER].button_pressed)


func test_pressing_theme_button_updates_settings_id() -> void:
	var view: PanelContainer = _SETTINGS_VIEW.instantiate()
	add_child_autofree(view)
	await wait_frames(1)
	# Direct handler call (Button.pressed.emit() doesn't simulate the
	# toggle flip; the .bind handler is the source of truth here).
	view._on_theme_button_pressed(Settings.THEME_EMBER)
	assert_eq(Settings.theme_id, Settings.THEME_EMBER,
		"theme button press must propagate to Settings.set_theme_id")
	# And the picker UI updates the active button.
	assert_true(view._theme_buttons[Settings.THEME_EMBER].button_pressed)
	assert_false(view._theme_buttons[Settings.THEME_AMETHYST].button_pressed)

# endregion


# region — main.gd repaints nav on theme_changed

func test_main_loads_correct_theme_for_current_theme_id() -> void:
	# Persisted Ember → main.gd builds the Ember-palette theme at startup.
	# v0.15.13 — the theme is built at runtime (no resource_path), so we
	# verify by the palette-derived Label ink color instead of a file path.
	Settings.theme_id = Settings.THEME_EMBER
	Settings.save_to_disk()
	var main: Node = _MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_frames(1)
	var theme: Theme = (main as Control).theme
	assert_not_null(theme)
	assert_eq(theme.get_color("font_color", "Label"), PaletteDusk.ember()["ink"],
		"Main.theme must use the Ember palette when theme_id == 'ember'")
	# Reset for following tests.
	Settings.theme_id = Settings.THEME_AMETHYST
	Settings.save_to_disk()


func test_theme_changed_swaps_window_root_theme() -> void:
	# Default boot at Amethyst, then flip to Twilight live — the
	# window root's theme must update without a scene reload.
	Settings.theme_id = Settings.THEME_AMETHYST
	var main: Node = _MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_frames(1)
	assert_eq(get_tree().root.theme.get_color("font_color", "Label"),
		PaletteDusk.amethyst()["ink"], "boots with the Amethyst palette")
	Settings.set_theme_id(Settings.THEME_TWILIGHT)
	await wait_frames(1)
	assert_eq(get_tree().root.theme.get_color("font_color", "Label"),
		PaletteDusk.twilight()["ink"],
		"theme_changed must rebuild the window-root theme with the new palette")
	# Reset for following tests.
	Settings.theme_id = Settings.THEME_AMETHYST


func test_theme_changed_repaints_nav_button_styleboxes() -> void:
	# After a theme swap, every primary nav button must have a
	# stylebox sourced from the active palette's `bg_deep`. Without
	# the `_apply_nav_styleboxes` call on theme_changed, the nav
	# would keep the previous palette's flat black bar — visible.
	Settings.theme_id = Settings.THEME_AMETHYST
	var main: Node = _MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_frames(2)
	var nav_buttons: Dictionary = main._nav_buttons
	assert_gt(nav_buttons.size(), 0, "expected primary nav buttons to be built")
	Settings.set_theme_id(Settings.THEME_EMBER)
	await wait_frames(1)
	var ember_bg: Color = PaletteDusk.ember()["bg_deep"]
	for btn_name in nav_buttons:
		var btn: Button = nav_buttons[btn_name]
		var sb: StyleBoxFlat = btn.get_theme_stylebox("normal")
		assert_eq(sb.bg_color, ember_bg,
			"%s nav button normal stylebox bg must match the active palette's bg_deep" % btn_name)
	# Reset for following tests.
	Settings.theme_id = Settings.THEME_AMETHYST

# endregion


# region — main.gd live-rebuilds the root theme on a font-scale change
#
# v0.15.13 — the font slider fires accessibility_settings_changed per
# 0.05 step; main coalesces those into one rebuild drained in _process.
# This pins the end-to-end live path: moving the slider must actually
# rescale the theme-variation font sizes baked into the root theme.

func test_font_scale_change_live_rebuilds_root_theme() -> void:
	Settings.font_scale = 1.0
	var main: Node = _MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_frames(2)
	# UiCaption is sized by DuskThemeBuilder._scaled(9, font_scale) → 9 at 1.0×.
	var base: int = get_tree().root.theme.get_font_size("font_size", "UiCaption")
	assert_eq(base, 9, "UiCaption should be 9 px at the default font scale")
	# Bump the slider via the emitting setter; the rebuild is deferred to
	# the next _process drain (coalesced). Pump _process explicitly — the
	# headless GUT harness doesn't reliably tick it (same reason
	# test_buttons_on_screen calls main._process(0.0) by hand).
	Settings.set_font_scale(1.5)
	main._process(0.0)
	await wait_frames(1)
	var scaled: int = get_tree().root.theme.get_font_size("font_size", "UiCaption")
	assert_eq(scaled, 14,
		"a live font-scale bump to 1.5 must rebuild the root theme: UiCaption 9→round(9*1.5)=14")
	# Reset for following tests (and so 1.5 never leaks into a later file).
	Settings.font_scale = 1.0

# endregion
