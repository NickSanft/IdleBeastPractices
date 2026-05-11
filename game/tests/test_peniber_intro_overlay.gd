## Phase 14e — first-launch Peniber intro overlay behaviour.
##
## The intro overlay (`game/scenes/ui/peniber_intro_overlay.gd`) plays
## the 4 beats from `data.js → PENIBER_INTRO` on first launch only.
## Tests pin:
##   - 4-beat advance via bubble tap
##   - Skip button dismisses early
##   - TutorialState gate (only shows when not seen)
##   - On dismissal, mark_seen flips so it doesn't replay next launch
##   - Title / bubble / wizard / dots all wired
extends GutTest

const _SCENE := preload("res://game/scenes/ui/peniber_intro_overlay.tscn")
const _SCRIPT := preload("res://game/scenes/ui/peniber_intro_overlay.gd")


func before_each() -> void:
	# Each test starts with a clean TutorialState — otherwise the gate
	# is closed and show_intro_if_unseen() returns immediately.
	TutorialState.reset()


func _new_overlay() -> CanvasLayer:
	var overlay: CanvasLayer = _SCENE.instantiate()
	add_child_autofree(overlay)
	return overlay


func test_overlay_builds_with_title_wizard_bubble() -> void:
	var o := _new_overlay()
	await wait_frames(1)
	assert_not_null(o._backdrop, "fullscreen dim backdrop must be built")
	assert_not_null(o._title_label, "title label must be built")
	assert_not_null(o._sub_label, "subtitle label must be built")
	assert_not_null(o._wizard_stage, "wizard stage container must be built")
	assert_not_null(o._wizard_root, "wizard root group must be built")
	assert_not_null(o._hat_spark, "hat sparkle must be built")
	assert_not_null(o._bubble, "dialog bubble must be built")
	assert_not_null(o._bubble_text, "bubble body text must be built")
	assert_not_null(o._bubble_skip, "SKIP button must be built")
	assert_not_null(o._bubble_pin, "gold PENIBER pin must be built")


func test_title_uses_displayheading_variation() -> void:
	# styles.css `.intro-overlay .title h1`: Press Start 2P 18 px gold.
	# DisplayHeading is the 18 px Press Start 2P variation per dusk_theme_builder.
	var o := _new_overlay()
	await wait_frames(1)
	assert_eq(o._title_label.theme_type_variation, &"DisplayHeading",
		"title must use DisplayHeading variation per styles.css `.intro-overlay .title h1`")
	assert_eq(o._title_label.text, "IDLE BEASTS")


func test_bubble_text_uses_bodyintro_variation() -> void:
	# styles.css `.intro-overlay .pen-bubble .text`: VT323 19 px.
	# BodyIntro is the 19-px VT323 variation per dusk_theme_builder.
	var o := _new_overlay()
	await wait_frames(1)
	assert_eq(o._bubble_text.theme_type_variation, &"BodyIntro",
		"bubble text must use BodyIntro variation per styles.css `.intro-overlay .pen-bubble .text`")


func test_four_page_dots_built() -> void:
	# 4 page-indicator dots, one per beat. styles.css uses 6×6 squares.
	var o := _new_overlay()
	await wait_frames(1)
	assert_eq(o._bubble_dot_rects.size(), 4,
		"4 page dots must be built (one per PENIBER_INTRO beat)")
	for dot in o._bubble_dot_rects:
		assert_eq(dot.custom_minimum_size, Vector2(6, 6),
			"each page dot must be 6×6 px per styles.css `.pen-bubble .dots i`")


func test_first_beat_dot_is_gold_others_are_ink_mute() -> void:
	var o := _new_overlay()
	await wait_frames(1)
	var palette: Dictionary = preload("res://assets/themes/dusk/palette_dusk.gd").amethyst()
	assert_eq(o._bubble_dot_rects[0].color, palette["gold"],
		"first beat's dot must be gold to signal current page")
	for i in [1, 2, 3]:
		assert_eq(o._bubble_dot_rects[i].color, palette["ink_mute"],
			"non-current dots must be ink_mute per styles.css")


func test_tapping_bubble_advances_to_next_beat() -> void:
	var o := _new_overlay()
	await wait_frames(1)
	# Fast-forward typewriter to end so next tap advances rather than
	# fast-forwarding.
	o._bubble_text.visible_characters = o._bubble_text.text.length()
	# Synthetic tap on the bubble.
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	o._on_bubble_input(event)
	await wait_frames(1)
	assert_eq(o._current_beat, 1,
		"second beat must be active after first bubble tap")
	# Dot 1 should now be gold; dot 0 should be ink_mute.
	var palette: Dictionary = preload("res://assets/themes/dusk/palette_dusk.gd").amethyst()
	assert_eq(o._bubble_dot_rects[1].color, palette["gold"])
	assert_eq(o._bubble_dot_rects[0].color, palette["ink_mute"])


func test_first_tap_during_typewriter_fast_forwards() -> void:
	# Tap during typewriter reveal should fill the body to full length
	# rather than advancing the beat.
	#
	# The first beat is ~73 chars at 22 ms/char ≈ 1.6 s of reveal, so
	# after 1 frame (~16 ms) visible_characters is somewhere in [0, 5]
	# — strictly less than text.length(). That's the precondition the
	# fast-forward branch needs to hit.
	var o := _new_overlay()
	await wait_frames(1)
	var total: int = o._bubble_text.text.length()
	assert_lt(o._bubble_text.visible_characters, total,
		"typewriter must still be mid-reveal one frame after _ready")
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	o._on_bubble_input(event)
	# After fast-forward, visible_characters == text.length() but the
	# beat stays at 0 (we didn't advance, we just skipped the type).
	assert_eq(o._current_beat, 0,
		"tap during typewriter must NOT advance the beat — only fast-forward")
	assert_eq(o._bubble_text.visible_characters, total,
		"tap during typewriter must reveal all characters")


func test_skip_button_dismisses_overlay() -> void:
	# Track whether the dismiss signal fired.
	var o := _new_overlay()
	await wait_frames(1)
	var dismissed: Array = []
	o.intro_dismissed.connect(func() -> void: dismissed.append(true))
	o._on_skip_pressed()
	# Dismissal tweens fade for 0.2 s, then emits.
	await wait_seconds(0.3)
	assert_eq(dismissed.size(), 1,
		"intro_dismissed must fire after SKIP press")


func test_tap_through_last_beat_dismisses() -> void:
	var o := _new_overlay()
	await wait_frames(1)
	var dismissed: Array = []
	o.intro_dismissed.connect(func() -> void: dismissed.append(true))
	# Advance past all 4 beats. Each requires (1) fast-forward then (2) advance.
	for i in 4:
		# Fast-forward the typewriter.
		o._bubble_text.visible_characters = o._bubble_text.text.length()
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		o._on_bubble_input(event)
		await wait_frames(1)
	# After the 4th advance, we should be dismissing.
	await wait_seconds(0.3)
	assert_eq(dismissed.size(), 1,
		"intro_dismissed must fire after advancing past the last beat")


func test_show_intro_if_unseen_returns_false_when_already_seen() -> void:
	# Gate test: if the step is marked, show_intro_if_unseen is a no-op.
	TutorialState.mark_seen(TutorialState.STEP_PENIBER_INTRO_SHOWN)
	var parent := Node.new()
	add_child_autofree(parent)
	var shown: bool = _SCRIPT.show_intro_if_unseen(parent)
	assert_false(shown,
		"show_intro_if_unseen must return false once STEP_PENIBER_INTRO_SHOWN is marked")
	# And no overlay child should have been added.
	var has_overlay: bool = false
	for child in parent.get_children():
		if child.get_script() == _SCRIPT:
			has_overlay = true
	assert_false(has_overlay, "no overlay should be added when intro is already seen")


func test_show_intro_if_unseen_returns_true_and_adds_overlay() -> void:
	var parent := Node.new()
	add_child_autofree(parent)
	var shown: bool = _SCRIPT.show_intro_if_unseen(parent)
	assert_true(shown, "first-launch path must show the overlay")
	# And an overlay must now be a child of parent.
	var found_overlay: CanvasLayer = null
	for child in parent.get_children():
		if child is CanvasLayer and child.get_script() == _SCRIPT:
			found_overlay = child
	assert_not_null(found_overlay,
		"show_intro_if_unseen must add a CanvasLayer overlay as a child of parent")
