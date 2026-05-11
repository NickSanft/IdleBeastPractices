## Phase 14g — gold L-bracket corner trim behaviour.
##
## The brackets Control (`game/scenes/ui/gold_brackets.gd`) is a
## reusable decoration that draws 8 small filled rects forming an
## L at each of 4 corners. Drops into any Control to give it the
## styles.css `.pixel-card::before` look.
##
## Tests pin:
##   - Decoration only (mouse_filter = IGNORE so taps fall through)
##   - Reads the active palette's gold token (not a hardcoded color)
##   - Repaints on Settings.theme_changed (so a palette swap retints)
##   - Anchored full-rect with -2 px inset per styles.css
extends GutTest

const _SCRIPT := preload("res://game/scenes/ui/gold_brackets.gd")
const _DUSK := preload("res://assets/themes/dusk/palette_dusk.gd")


func before_each() -> void:
	Settings.theme_id = Settings.THEME_AMETHYST


func _new_brackets() -> Control:
	var brackets: Control = _SCRIPT.new()
	add_child_autofree(brackets)
	return brackets


func test_brackets_are_decoration_only() -> void:
	# Mouse filter must be IGNORE so the brackets don't eat taps
	# meant for the underlying card.
	var b := _new_brackets()
	await wait_frames(1)
	assert_eq(b.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"brackets must be decoration only — mouse_filter = IGNORE")


func test_brackets_anchor_full_rect_with_negative_inset() -> void:
	# styles.css `.pixel-card::before { inset: -2px }`: the brackets
	# extend 2 px past the card edge to read as "RPG window" trim.
	var b := _new_brackets()
	await wait_frames(1)
	assert_eq(b.offset_left, -2.0,
		"brackets must inset by -2 px on left per styles.css")
	assert_eq(b.offset_right, 2.0,
		"brackets must inset by -2 px on right per styles.css")
	assert_eq(b.offset_top, -2.0)
	assert_eq(b.offset_bottom, 2.0)


func test_brackets_read_active_palette_gold() -> void:
	# The gold color must come from PaletteDusk.active(), not a
	# hardcoded constant. A future palette refactor that drops the
	# `gold` token would crash here.
	var b := _new_brackets()
	await wait_frames(1)
	var expected: Color = _DUSK.active()["gold"]
	assert_eq(b._gold, expected,
		"brackets must read the active palette's gold token")


func test_brackets_repaint_on_theme_changed() -> void:
	# A Settings palette swap must update the cached gold color +
	# trigger a queue_redraw so the next frame paints the new tint.
	Settings.theme_id = Settings.THEME_AMETHYST
	var b := _new_brackets()
	await wait_frames(1)
	var amethyst_gold: Color = _DUSK.amethyst()["gold"]
	assert_eq(b._gold, amethyst_gold)
	# Swap to Ember and verify the cached color updates.
	Settings.set_theme_id(Settings.THEME_EMBER)
	await wait_frames(1)
	var ember_gold: Color = _DUSK.ember()["gold"]
	assert_eq(b._gold, ember_gold,
		"theme_changed must update the cached gold token to the new palette's value")
	# Reset for following tests.
	Settings.set_theme_id(Settings.THEME_AMETHYST)
