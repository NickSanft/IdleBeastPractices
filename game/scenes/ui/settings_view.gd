## Settings tab: volume sliders for music + SFX. Writes through Settings,
## which persists to user://settings.cfg and emits audio_settings_changed
## so AudioManager re-applies the dB values to every player.
extends PanelContainer

var _music_slider: HSlider
var _sfx_slider: HSlider
var _music_value_label: Label
var _sfx_value_label: Label


func _ready() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 16)
	add_child(vbox)

	var heading := Label.new()
	heading.text = "Settings"
	heading.add_theme_font_size_override("font_size", 26)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(heading)

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

	# Spacer at the bottom so the sliders sit at the top of the panel.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)


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
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)
	var value_label := Label.new()
	value_label.text = _format_db(initial_db)
	value_label.add_theme_font_size_override("font_size", 16)
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
