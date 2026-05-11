## Settings tab: volume sliders for music + SFX. Writes through Settings,
## which persists to user://settings.cfg and emits audio_settings_changed
## so AudioManager re-applies the dB values to every player.
extends PanelContainer

const _DUSK := preload("res://assets/themes/dusk/palette_dusk.gd")

var _master_slider: HSlider
var _music_slider: HSlider
var _sfx_slider: HSlider
var _master_value_label: Label
var _music_value_label: Label
var _sfx_value_label: Label
var _cloud_status_label: Label
var _cloud_button: Button
var _wipe_confirm: ConfirmationDialog
## Phase 14f — theme picker buttons. Three toggle-Buttons (Amethyst /
## Twilight / Ember). Each tinted to the matching palette's `card`
## color so the picker is self-illustrating. The active one shows
## a gold border via the `pressed` stylebox override.
var _theme_buttons: Dictionary = {}   # id_str -> Button


func _ready() -> void:
	# Wrap the whole panel in a ScrollContainer so the cloud-save
	# section, sliders, and spacer don't get clipped on small phones
	# in portrait. Without this, the lower section is unreachable on
	# anything shorter than ~720x1280 once the bigger v0.8.3 tap
	# targets and the cloud-save section land.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 16)
	scroll.add_child(vbox)

	var heading := Label.new()
	heading.text = "Settings"
	heading.add_theme_font_size_override("font_size", UiScale.size(26))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(heading)

	# Phase 14f — theme picker. Sits at the top of Settings so the
	# whole rest of the screen visually demos the choice the moment
	# you tap one of the three palettes.
	_build_theme_section(vbox)

	# Phase 12a: Master volume slider — the audio_master_db field has
	# always existed in Settings + the cfg, but had no setter and no
	# UI control. AudioManager._apply_volumes now writes the value
	# through to AudioServer's Master bus on every audio_settings_
	# changed signal.
	_master_slider = _build_volume_slider(
			vbox,
			"Master",
			Settings.audio_master_db,
			func(v: float) -> void:
				Settings.set_master_db(v)
				_master_value_label.text = _format_db(v))
	_master_value_label = _master_slider.get_meta("value_label")

	_music_slider = _build_volume_slider(
			vbox,
			"Music",
			Settings.music_db,
			func(v: float) -> void:
				Settings.set_music_db(v)
				_music_value_label.text = _format_db(v))
	_music_value_label = _music_slider.get_meta("value_label")

	_sfx_slider = _build_volume_slider(
			vbox,
			"SFX",
			Settings.sfx_db,
			func(v: float) -> void:
				Settings.set_sfx_db(v)
				_sfx_value_label.text = _format_db(v))
	_sfx_value_label = _sfx_slider.get_meta("value_label")

	_build_accessibility_section(vbox)
	# v0.14.7 (Phase 13g): the language section was a one-entry
	# OptionButton placeholder that printed to console on tap with a
	# subtitle promising future locales. That read as a bug (a dead
	# control). Hiding the section until i18n actually lands; the
	# `_build_language_section` function is kept around as a one-call
	# revival point.
	_build_tutorial_section(vbox)
	_build_cloud_save_section(vbox)
	_build_reset_progress_section(vbox)

	# Spacer at the bottom so the sliders sit at the top of the panel.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)


## Phase 14f — Theme picker section. Three toggle-Buttons in an HBox
## per palette (Amethyst / Twilight / Ember). Tapping a button writes
## through to `Settings.set_theme_id`, which emits `theme_changed`,
## which `main.gd._on_theme_changed` consumes to swap the .tres and
## repaint the bottom nav.
##
## Each button is itself tinted to its palette's `card` color so the
## picker reads as a tactile palette demo strip. The active button
## gets a gold border via the `pressed` stylebox override below.
func _build_theme_section(parent: Container) -> void:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)
	parent.add_child(section)

	var heading := Label.new()
	heading.text = "Theme"
	heading.add_theme_font_size_override("font_size", UiScale.size(18))
	section.add_child(heading)

	var blurb := Label.new()
	blurb.text = "Choose a palette. The chrome (cards, panels, buttons) repaints immediately."
	blurb.add_theme_font_size_override("font_size", UiScale.size(13))
	blurb.modulate = _DUSK.active()["ink_dim"]
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(blurb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(row)

	# Build one button per palette. Each button stores its id in `meta`
	# so the toggled handler can dispatch generically.
	for id_str in Settings.VALID_THEME_IDS:
		var btn := Button.new()
		btn.text = id_str.capitalize()
		btn.toggle_mode = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# 58-dp tap target floor (UiScale.tap_target()). Without this
		# the theme buttons fall below Material's 48-dp recommendation
		# and the existing tap-target sweep fails.
		btn.custom_minimum_size = Vector2(0, UiScale.tap_target())
		btn.set_meta("theme_id", id_str)
		btn.pressed.connect(_on_theme_button_pressed.bind(id_str))
		_theme_buttons[id_str] = btn
		row.add_child(btn)

	_apply_theme_button_styling()
	# Highlight the currently-active palette.
	for id_str in _theme_buttons:
		_theme_buttons[id_str].button_pressed = (id_str == Settings.theme_id)


## Per-palette stylebox: bg = that palette's `card` color, border =
## its `border`, ink = its `ink`. Active state (`pressed` stylebox)
## adds a 2-px gold border so "this is the chosen one" reads at a
## glance even when the palettes look similar in muted ambient light.
func _apply_theme_button_styling() -> void:
	for id_str in _theme_buttons:
		var palette: Dictionary = _DUSK.by_id(id_str)
		var btn: Button = _theme_buttons[id_str]

		var normal_sb := StyleBoxFlat.new()
		normal_sb.bg_color = palette["card"]
		normal_sb.border_color = palette["border"]
		normal_sb.set_border_width_all(2)
		normal_sb.set_corner_radius_all(0)
		normal_sb.content_margin_left = 12.0
		normal_sb.content_margin_right = 12.0
		normal_sb.content_margin_top = 10.0
		normal_sb.content_margin_bottom = 10.0
		btn.add_theme_stylebox_override("normal", normal_sb)

		var hover_sb: StyleBoxFlat = normal_sb.duplicate()
		hover_sb.bg_color = palette["card_2"]
		btn.add_theme_stylebox_override("hover", hover_sb)

		# Active: gold border, slightly brighter bg.
		var active_sb: StyleBoxFlat = normal_sb.duplicate()
		active_sb.bg_color = palette["card_2"]
		active_sb.border_color = palette["gold"]
		btn.add_theme_stylebox_override("pressed", active_sb)
		btn.add_theme_stylebox_override("hover_pressed", active_sb)

		btn.add_theme_color_override("font_color", palette["ink"])
		btn.add_theme_color_override("font_pressed_color", palette["gold"])
		btn.add_theme_color_override("font_hover_color", palette["ink"])
		btn.add_theme_color_override("font_hover_pressed_color", palette["gold"])


func _on_theme_button_pressed(id_str: String) -> void:
	Settings.set_theme_id(id_str)
	# Update the toggle state on every button so only the chosen one
	# remains pressed (toggle_mode means a 2nd press would un-press it).
	for other_id in _theme_buttons:
		_theme_buttons[other_id].button_pressed = (other_id == id_str)


## Reset Progress section: a single destructive button that wipes the
## save file (and in-memory state) after a confirmation dialog. Useful
## for testing fresh-start flows and as an emergency reset for players
## whose state has somehow gotten wedged.
func _build_reset_progress_section(parent: Container) -> void:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)
	parent.add_child(section)

	var heading := Label.new()
	heading.text = "Reset Progress"
	heading.add_theme_font_size_override("font_size", UiScale.size(18))
	section.add_child(heading)

	var blurb := Label.new()
	blurb.text = "Wipe all saved progress: gold, items, pets, upgrades, prestige, ledger. This cannot be undone."
	blurb.add_theme_font_size_override("font_size", UiScale.size(14))
	# Phase 14f: parchment SEPIA_MID → Dusk `ink_dim` for secondary text.
	blurb.modulate = _DUSK.active()["ink_dim"]
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(blurb)

	var btn := Button.new()
	btn.text = "Wipe save data…"
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Tint the label red as a destructive cue. Theme-driven Button
	# colors are kept; this is just an extra signal on top.
	# Phase 14f: parchment BLOOD_RUBY → Dusk `danger` for destructive cues.
	btn.add_theme_color_override("font_color", _DUSK.active()["danger"])
	btn.add_theme_color_override("font_hover_color", _DUSK.active()["danger"])
	btn.pressed.connect(_on_wipe_pressed)
	section.add_child(btn)


func _on_wipe_pressed() -> void:
	if _wipe_confirm == null:
		_wipe_confirm = ConfirmationDialog.new()
		_wipe_confirm.title = "Wipe save data?"
		_wipe_confirm.dialog_text = "This will permanently erase all progress (gold, items, pets, upgrades, prestige, ledger).\n\nAre you sure?"
		_wipe_confirm.ok_button_text = "Wipe progress"
		_wipe_confirm.cancel_button_text = "Cancel"
		# ConfirmationDialog is a Window subtype — assign the theme so
		# its label + buttons paint with the parchment/brass UI rather
		# than the dark mobile-default theme on get_tree().root.
		_wipe_confirm.theme = preload("res://assets/themes/dusk/amethyst.tres")
		_wipe_confirm.confirmed.connect(_on_wipe_confirmed)
		add_child(_wipe_confirm)
	_wipe_confirm.popup_centered(Vector2(420, 200))


func _on_wipe_confirmed() -> void:
	var ok: bool = SaveManager.clear_save()
	if not ok:
		push_warning("Wipe save: SaveManager.clear_save returned false")
		return
	print("[settings] save wiped; GameState reset to defaults")


## Phase 11b — Accessibility section: reduce-motion toggle, haptics
## toggle, font-scale slider. Each control writes through Settings,
## which persists to settings.cfg and emits accessibility_settings_
## changed so any subscribing UI can refresh without a scene reload.
func _build_accessibility_section(parent: Container) -> void:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)
	parent.add_child(section)

	var heading := Label.new()
	heading.text = "Accessibility"
	heading.add_theme_font_size_override("font_size", UiScale.size(18))
	section.add_child(heading)

	# Reduce motion toggle. When on, animation-heavy effects (catching
	# screen shake, monster bumps, floating numbers, combatant lunges,
	# parallax scroll) skip their tweens and snap to final state.
	var motion_row := HBoxContainer.new()
	motion_row.add_theme_constant_override("separation", 12)
	section.add_child(motion_row)
	var motion_check := CheckBox.new()
	motion_check.button_pressed = Settings.reduce_motion
	motion_check.toggled.connect(func(on: bool) -> void:
		Settings.set_reduce_motion(on))
	motion_row.add_child(motion_check)
	var motion_label := Label.new()
	motion_label.text = "Reduce motion"
	motion_label.add_theme_font_size_override("font_size", UiScale.size(16))
	motion_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	motion_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	motion_row.add_child(motion_label)

	var motion_blurb := Label.new()
	motion_blurb.text = "Skips screen shake, sprite bumps, floating gold drift, combatant bobs, and parallax scrolling. Use if motion makes you queasy."
	motion_blurb.add_theme_font_size_override("font_size", UiScale.size(13))
	motion_blurb.modulate = _DUSK.active()["ink_dim"]
	motion_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(motion_blurb)

	# Haptics toggle. Defaults true; turning off skips
	# Input.vibrate_handheld() calls in the global button handler and
	# the per-tap catch handler.
	var hap_row := HBoxContainer.new()
	hap_row.add_theme_constant_override("separation", 12)
	section.add_child(hap_row)
	var hap_check := CheckBox.new()
	hap_check.button_pressed = Settings.haptics_enabled
	hap_check.toggled.connect(func(on: bool) -> void:
		Settings.set_haptics_enabled(on))
	hap_row.add_child(hap_check)
	var hap_label := Label.new()
	hap_label.text = "Haptic feedback"
	hap_label.add_theme_font_size_override("font_size", UiScale.size(16))
	hap_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hap_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hap_row.add_child(hap_label)

	# Phase 12b: hold-to-tap. Highest-leverage clicker accessibility
	# add per Game Accessibility Guidelines — serves players with
	# RSI / motor sensitivities + phones that can't keep up with
	# rapid taps. Defaults off so existing players see no change.
	var hold_row := HBoxContainer.new()
	hold_row.add_theme_constant_override("separation", 12)
	section.add_child(hold_row)
	var hold_check := CheckBox.new()
	hold_check.button_pressed = Settings.hold_to_tap_enabled
	hold_check.toggled.connect(func(on: bool) -> void:
		Settings.set_hold_to_tap_enabled(on))
	hold_row.add_child(hold_check)
	var hold_label := Label.new()
	hold_label.text = "Hold to auto-tap"
	hold_label.add_theme_font_size_override("font_size", UiScale.size(16))
	hold_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hold_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hold_row.add_child(hold_label)

	# Hold rate slider — only meaningful when the toggle is on, but
	# always editable; the rate persists either way.
	var rate_header := HBoxContainer.new()
	section.add_child(rate_header)
	var rate_name := Label.new()
	rate_name.text = "Hold tap rate"
	rate_name.add_theme_font_size_override("font_size", UiScale.size(16))
	rate_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rate_header.add_child(rate_name)
	var rate_value := Label.new()
	rate_value.text = "%.0f Hz" % Settings.hold_tap_rate_hz
	rate_value.add_theme_font_size_override("font_size", UiScale.size(14))
	rate_value.modulate = _DUSK.active()["ink_dim"]
	rate_header.add_child(rate_value)

	var rate_slider := HSlider.new()
	rate_slider.min_value = Settings.HOLD_TAP_RATE_MIN
	rate_slider.max_value = Settings.HOLD_TAP_RATE_MAX
	rate_slider.step = 1.0
	rate_slider.value = Settings.hold_tap_rate_hz
	rate_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rate_slider.value_changed.connect(func(v: float) -> void:
		Settings.set_hold_tap_rate_hz(v)
		rate_value.text = "%.0f Hz" % Settings.hold_tap_rate_hz)
	section.add_child(rate_slider)

	# Phase 12b: color-blind mode toggle. Adds shape redundancy
	# (✓ / · suffixes) on bestiary slot pills so filled vs unfilled
	# state reads without color discrimination.
	var cb_row := HBoxContainer.new()
	cb_row.add_theme_constant_override("separation", 12)
	section.add_child(cb_row)
	var cb_check := CheckBox.new()
	cb_check.button_pressed = Settings.colorblind_mode
	cb_check.toggled.connect(func(on: bool) -> void:
		Settings.set_colorblind_mode(on))
	cb_row.add_child(cb_check)
	var cb_label := Label.new()
	cb_label.text = "Color-blind mode"
	cb_label.add_theme_font_size_override("font_size", UiScale.size(16))
	cb_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cb_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cb_row.add_child(cb_label)
	var cb_blurb := Label.new()
	cb_blurb.text = "Adds shape markers alongside color so bestiary slot states are readable without color discrimination."
	cb_blurb.add_theme_font_size_override("font_size", UiScale.size(13))
	cb_blurb.modulate = _DUSK.active()["ink_dim"]
	cb_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(cb_blurb)

	# Font scale slider.
	var font_header := HBoxContainer.new()
	section.add_child(font_header)
	var font_name := Label.new()
	font_name.text = "Text size"
	font_name.add_theme_font_size_override("font_size", UiScale.size(16))
	font_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	font_header.add_child(font_name)
	var font_value := Label.new()
	font_value.text = "%.0f%%" % (Settings.font_scale * 100.0)
	font_value.add_theme_font_size_override("font_size", UiScale.size(14))
	font_value.modulate = _DUSK.active()["ink_dim"]
	font_header.add_child(font_value)

	var font_slider := HSlider.new()
	font_slider.min_value = Settings.FONT_SCALE_MIN
	font_slider.max_value = Settings.FONT_SCALE_MAX
	font_slider.step = 0.05
	font_slider.value = Settings.font_scale
	font_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	font_slider.value_changed.connect(func(v: float) -> void:
		Settings.set_font_scale(v)
		font_value.text = "%.0f%%" % (Settings.font_scale * 100.0))
	section.add_child(font_slider)


## Phase 12a — Language picker. Shipped with one entry ("English")
## as a placeholder; the structure is in place so future locale
## work can drop in additional languages by adding entries here +
## wiring TranslationServer.set_locale on selection.
func _build_language_section(parent: Container) -> void:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)
	parent.add_child(section)

	var heading := Label.new()
	heading.text = "Language"
	heading.add_theme_font_size_override("font_size", UiScale.size(18))
	section.add_child(heading)

	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.add_item("English", 0)
	picker.selected = 0
	# Placeholder hook — real locale switching ships with the
	# localization phase (currently out of scope per IMPLEMENTATION_
	# PLAN §13). For now the picker is selectable but always English.
	picker.item_selected.connect(func(_idx: int) -> void:
		print("[settings] language picker tapped — single locale shipped"))
	section.add_child(picker)

	var note := Label.new()
	note.text = "Additional languages will arrive in a future update."
	note.add_theme_font_size_override("font_size", UiScale.size(13))
	note.modulate = _DUSK.active()["ink_dim"]
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(note)


## Phase 12c — Replay tutorial button. Only visible after at least
## one tutorial step has fired (no point showing it on a fresh save
## that hasn't seen any tutorial yet). Resets TutorialState and
## re-fires the first-launch check via main.gd.
func _build_tutorial_section(parent: Container) -> void:
	if not TutorialState.has_any_progress():
		return
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)
	parent.add_child(section)

	var heading := Label.new()
	heading.text = "Tutorial"
	heading.add_theme_font_size_override("font_size", UiScale.size(18))
	section.add_child(heading)

	var btn := Button.new()
	btn.text = "Replay tutorial"
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(_on_replay_tutorial_pressed)
	section.add_child(btn)

	var blurb := Label.new()
	blurb.text = "Resets tutorial coachmarks. They'll re-appear at their trigger conditions in this session."
	blurb.add_theme_font_size_override("font_size", UiScale.size(13))
	blurb.modulate = _DUSK.active()["ink_dim"]
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(blurb)


func _on_replay_tutorial_pressed() -> void:
	# Walk up to Main and call replay_tutorial. Settings can't reach
	# main.gd's class directly; find via tree.
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main == null or not main.has_method("replay_tutorial"):
		# Fallback: just clear the state. The next session will show
		# tap_first_monster on its first launch check.
		TutorialState.reset()
		return
	main.replay_tutorial()


## Cloud Save section: status indicator + sign-in button. Hidden on
## platforms where CloudSyncManager.backend is null (editor / desktop /
## web — PGS plugin only registers its singleton on Android).
func _build_cloud_save_section(parent: Container) -> void:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)
	parent.add_child(section)

	var heading := Label.new()
	heading.text = "Cloud Save"
	heading.add_theme_font_size_override("font_size", UiScale.size(18))
	section.add_child(heading)

	_cloud_status_label = Label.new()
	_cloud_status_label.add_theme_font_size_override("font_size", UiScale.size(14))
	_cloud_status_label.modulate = Color(0.85, 0.85, 0.85)
	_cloud_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(_cloud_status_label)

	_cloud_button = Button.new()
	_cloud_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cloud_button.pressed.connect(_on_cloud_button_pressed)
	section.add_child(_cloud_button)

	# Subscribe to status updates so the section reflects sign-in /
	# sync-in-flight in real time.
	CloudSyncManager.status_changed.connect(_refresh_cloud_section)
	_refresh_cloud_section(CloudSyncManager.status)


func _refresh_cloud_section(_status: String) -> void:
	if _cloud_status_label == null or _cloud_button == null:
		return
	match CloudSyncManager.status:
		CloudSyncManager.STATUS_DISABLED:
			_cloud_status_label.text = "Cloud sync is only available on Android with the Play Games Services plugin."
			_cloud_button.text = "(Unavailable on this platform)"
			_cloud_button.disabled = true
		CloudSyncManager.STATUS_SIGNED_OUT:
			_cloud_status_label.text = "Sign in to sync your progress across devices via Google Play Games."
			_cloud_button.text = "Sign in to Google Play Games"
			_cloud_button.disabled = false
		CloudSyncManager.STATUS_DOWNLOADING:
			_cloud_status_label.text = "Syncing from cloud…"
			_cloud_button.text = "(Syncing)"
			_cloud_button.disabled = true
		CloudSyncManager.STATUS_UPLOADING:
			_cloud_status_label.text = "Uploading to cloud…"
			_cloud_button.text = "(Syncing)"
			_cloud_button.disabled = true
		CloudSyncManager.STATUS_IDLE:
			_cloud_status_label.text = "Signed in. Progress is being synced automatically."
			_cloud_button.text = "Sign out"
			_cloud_button.disabled = false
		CloudSyncManager.STATUS_ERROR:
			_cloud_status_label.text = "Cloud sync error: %s" % CloudSyncManager.last_error
			_cloud_button.text = "Try sign-in again"
			_cloud_button.disabled = false


func _on_cloud_button_pressed() -> void:
	if CloudSyncManager.is_signed_in():
		CloudSyncManager.sign_out()
	else:
		CloudSyncManager.sign_in()


func _build_volume_slider(
		parent: Container,
		title: String,
		initial_db: float,
		on_change: Callable) -> HSlider:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 4)
	parent.add_child(section)

	var header := HBoxContainer.new()
	section.add_child(header)
	var name_label := Label.new()
	name_label.text = title
	name_label.add_theme_font_size_override("font_size", UiScale.size(18))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)
	var value_label := Label.new()
	value_label.text = _format_db(initial_db)
	value_label.add_theme_font_size_override("font_size", UiScale.size(16))
	value_label.modulate = Color(0.85, 0.85, 0.85)
	header.add_child(value_label)

	var slider := HSlider.new()
	slider.min_value = Settings.MIN_DB
	slider.max_value = Settings.MAX_DB
	slider.step = 0.5
	slider.value = initial_db
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(on_change)
	# Stash the value label on the slider so the caller can update it.
	slider.set_meta("value_label", value_label)
	section.add_child(slider)
	return slider


func _format_db(db: float) -> String:
	if db <= Settings.MIN_DB + 0.01:
		return "Muted"
	return "%.1f dB" % db
