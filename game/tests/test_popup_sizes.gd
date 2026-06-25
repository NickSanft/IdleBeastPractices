## v0.15.8 — popup-size structural regression tests.
##
## Catches the bug class the user reported as "the pet notification
## takes up almost the entire screen on the left side": popups with
## auto-sizing PanelContainers containing autowrap labels grew to fit
## the longest line of text instead of wrapping. Symptoms:
##   - celebration_overlay: PRESET_CENTER kept offsets at (0,0) →
##     anchor at viewport center but rect grew from (0,0) origin.
##   - coachmark: only `custom_minimum_size.x = 240` as a floor → no
##     CAP, so long hints sized the bubble much wider.
##   - toast: `grow_horizontal = BOTH + custom_minimum_size.x = 280` →
##     same problem as coachmark, but centered.
##
## Each test below shows the popup with a deliberately-long body
## string, then asserts the rendered Control's width is bounded by
## a sane budget (half the viewport for cards, 320 px for toasts).
extends GutTest

const _CELEBRATION_SCENE := preload("res://game/scenes/ui/celebration_overlay.tscn")
const _TOAST_SCENE := preload("res://game/scenes/ui/toast.tscn")
const _COACHMARK_SCENE := preload("res://game/scenes/ui/coachmark.tscn")

const _LONG_BODY := "This is a deliberately long body string designed to exercise the autowrap loop. Without a finite wrap budget the PanelContainer would expand to fit this entire line on a single row, pushing the card past the viewport edge."


func before_each() -> void:
	# These width/center budgets assume the default 1.0× font scale. Reset
	# it so a leak from an earlier test file (e.g. a max-font-scale layout
	# test) can't silently widen these cards and fail the assertions.
	Settings.font_scale = 1.0


# region — celebration overlay stays bounded

func test_celebration_card_width_stays_within_budget() -> void:
	# styles.css spec for `.peniber` / `.pixel-card`: cards center on
	# the screen at a fixed width. The user-reported bug had cards
	# growing to fill the whole left half of the screen.
	#
	# Post-fix the card is locked to exactly _CARD_WIDTH (360 px) via
	# anchor offsets. Even with a very long body the card stays 360 px
	# wide and grows DOWN, not RIGHT.
	var overlay: CanvasLayer = _CELEBRATION_SCENE.instantiate()
	add_child_autofree(overlay)
	overlay.show_celebration("First Pet!", _LONG_BODY)
	# Wait for layout to settle. PanelContainer's auto-sizing runs over
	# one or two frames as the child labels measure themselves.
	await wait_frames(3)
	# Card width must be ≤ 400 (fixed 360 + a small tolerance for
	# StyleBox border/padding rounding).
	assert_lt(overlay._card.size.x, 400.0,
		"celebration card must stay near _CARD_WIDTH (360); long body must wrap, not widen — got %.1f" % overlay._card.size.x)
	# Sanity: card has SOME width (not collapsed to 0).
	assert_gt(overlay._card.size.x, 300.0,
		"celebration card must reach _CARD_WIDTH floor — got %.1f" % overlay._card.size.x)


func test_celebration_card_centered_horizontally_on_viewport() -> void:
	# Post-fix the card anchors at (0.5, 0.5) with offsets at -180/+180.
	# The card's center.x must therefore be close to viewport.x / 2,
	# not stuck against the left edge.
	var overlay: CanvasLayer = _CELEBRATION_SCENE.instantiate()
	add_child_autofree(overlay)
	overlay.show_celebration("Test", "Hi")
	await wait_frames(3)
	var view_w: float = get_viewport().get_visible_rect().size.x
	var card_center_x: float = overlay._card.position.x + overlay._card.size.x * 0.5
	assert_almost_eq(card_center_x, view_w * 0.5, 2.0,
		"celebration card center must be at viewport center; got center=%.1f viewport_w=%.1f" % [card_center_x, view_w])

# endregion


# region — toast banner stays bounded

func test_toast_banner_width_stays_within_budget() -> void:
	# Toast banner locked to _BANNER_WIDTH (280 px). Long text wraps
	# instead of widening the banner past the viewport edge.
	var toast: CanvasLayer = _TOAST_SCENE.instantiate()
	add_child_autofree(toast)
	toast.show_toast(_LONG_BODY)
	await wait_frames(3)
	assert_lt(toast._banner.size.x, 320.0,
		"toast banner must stay near _BANNER_WIDTH (280); long body must wrap, not widen — got %.1f" % toast._banner.size.x)


func test_toast_banner_centered_horizontally() -> void:
	# anchors at 0.5/0.5 with offsets -140/+140 → banner center matches
	# viewport center, regardless of label text length.
	var toast: CanvasLayer = _TOAST_SCENE.instantiate()
	add_child_autofree(toast)
	toast.show_toast(_LONG_BODY)
	await wait_frames(3)
	var view_w: float = get_viewport().get_visible_rect().size.x
	var banner_center_x: float = toast._banner.position.x + toast._banner.size.x * 0.5
	assert_almost_eq(banner_center_x, view_w * 0.5, 2.0,
		"toast banner center must be at viewport center; got center=%.1f viewport_w=%.1f" % [banner_center_x, view_w])

# endregion


# region — coachmark bubble stays bounded

func test_coachmark_bubble_width_stays_within_budget() -> void:
	# Bubble anchor-bounded to _BUBBLE_MIN_WIDTH (240). The user-reported
	# bug had the bubble fill from x=12 to x=708 (essentially the whole
	# viewport width).
	var coachmark: CanvasLayer = _COACHMARK_SCENE.instantiate()
	add_child_autofree(coachmark)
	# Build a target Control so the bubble has something to anchor to.
	var target := Button.new()
	target.text = "Target"
	target.position = Vector2(100, 800)
	target.size = Vector2(100, 60)
	add_child_autofree(target)
	await wait_frames(1)
	coachmark.show_for(target, _LONG_BODY, &"test_coachmark_size")
	await wait_frames(3)
	assert_lt(coachmark._bubble.size.x, 280.0,
		"coachmark bubble must stay near _BUBBLE_MIN_WIDTH (240); long hint must wrap, not widen — got %.1f" % coachmark._bubble.size.x)
	# Clean up the test step from TutorialState so other tests don't
	# inherit our marked-seen state.
	TutorialState.reset()

# endregion
