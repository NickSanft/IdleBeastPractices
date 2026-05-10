## Phase 14 — one-shot runner that builds the Dusk pixel-RPG theme
## resources from `DuskThemeBuilder` + `PaletteDusk` and saves them
## under `assets/themes/dusk/*.tres`.
##
## Usage:
##   godot --headless --path . --script res://tools/build_dusk_themes.gd
##
## Run this whenever you tweak a palette token, the StyleBoxFlat
## defaults, or the type-variation font sizes. The produced .tres
## files are committed; the runner is the single source of truth so
## edits don't accidentally drift from styles.css.
extends SceneTree


const _DISPLAY_FONT := "res://assets/fonts/dusk/PressStart2P-Regular.ttf"
const _UI_FONT := "res://assets/fonts/dusk/Silkscreen-Regular.ttf"
const _BODY_FONT := "res://assets/fonts/dusk/VT323-Regular.ttf"


func _initialize() -> void:
	var display_font := load(_DISPLAY_FONT) as FontFile
	var ui_font := load(_UI_FONT) as FontFile
	var body_font := load(_BODY_FONT) as FontFile
	if display_font == null or ui_font == null or body_font == null:
		push_error("[build_dusk_themes] one or more fonts failed to load. Run --import first.")
		quit(1)
		return

	_save("amethyst", PaletteDusk.amethyst(), display_font, ui_font, body_font)
	_save("twilight", PaletteDusk.twilight(), display_font, ui_font, body_font)
	_save("ember", PaletteDusk.ember(), display_font, ui_font, body_font)
	print("[build_dusk_themes] built amethyst.tres + twilight.tres + ember.tres")
	quit(0)


func _save(
		palette_id: String,
		palette: Dictionary,
		display_font: FontFile,
		ui_font: FontFile,
		body_font: FontFile) -> void:
	var theme := DuskThemeBuilder.build(palette, display_font, ui_font, body_font)
	var path := "res://assets/themes/dusk/%s.tres" % palette_id
	var err := ResourceSaver.save(theme, path)
	if err != OK:
		push_error("[build_dusk_themes] failed to save %s (err %d)" % [path, err])
		quit(1)
		return
	print("[build_dusk_themes] saved %s" % path)
