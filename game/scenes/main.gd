## Phase 0 main scene: loads save on ready, builds a placeholder label,
## saves on quit. Replaced in Phase 1 with the tab-based main UI.
extends Control


func _ready() -> void:
	get_tree().root.close_requested.connect(_on_close_requested)
	var loaded: Dictionary = SaveManager.load_save()
	GameState.from_dict(loaded)
	_build_placeholder_ui()


func _build_placeholder_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.text = "Critterancher"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Phase 0 placeholder"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	box.add_child(subtitle)

	var version_label := Label.new()
	version_label.text = "Save schema v%d" % SaveManager.CURRENT_VERSION
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version_label.add_theme_font_size_override("font_size", 14)
	version_label.modulate = Color(0.7, 0.7, 0.7)
	box.add_child(version_label)


func _on_close_requested() -> void:
	SaveManager.save(GameState.to_dict())
	get_tree().quit()
