## Regression test for the v0.8.8 input-blocker bug:
##
## Each of the four overlay scenes (AdDiagnosticOverlay,
## SaveIndicatorOverlay, TouchDebugOverlay, NarratorOverlay) sits
## above the gameplay UI as a transparent strip. The overlay's WRAPPER
## Control sets `mouse_filter = MOUSE_FILTER_IGNORE`, but every Label
## / MarginContainer / PanelContainer inside the wrapper defaults to
## `MOUSE_FILTER_STOP` — which silently consumes taps in the child's
## rect even when the overlay is fully transparent. Catches the
## tab-bar-unclickable + drops-2x-button-unclickable bug class user
## reported on Galaxy Z Fold7 and (subtly) on the Godot editor.
##
## Each test instantiates an overlay, walks every Control descendant
## (excluding root visibility-gated nodes like NarratorOverlay's
## bubble, which legitimately becomes STOP when active), and asserts
## the descendant is IGNORE.
extends GutTest

const _AD_DIAG := preload("res://game/scenes/ui/ad_diagnostic_overlay.tscn")
const _SAVE_IND := preload("res://game/scenes/ui/save_indicator_overlay.tscn")
const _TOUCH_DBG := preload("res://game/scenes/ui/touch_debug_overlay.tscn")
const _NARRATOR := preload("res://game/scenes/ui/narrator_overlay.tscn")


func _walk_controls(node: Node, out: Array) -> void:
	if node is Control:
		out.append(node)
	for child in node.get_children():
		_walk_controls(child, out)


func _assert_all_ignore(overlay: Control, exemptions: Array = []) -> void:
	var controls: Array = []
	_walk_controls(overlay, controls)
	for c in controls:
		if c in exemptions:
			continue
		assert_eq(
				c.mouse_filter,
				Control.MOUSE_FILTER_IGNORE,
				"%s (%s) must use MOUSE_FILTER_IGNORE so it doesn't block taps on the gameplay UI underneath" % [
					c.name, c.get_class(),
				])


func test_ad_diagnostic_overlay_does_not_intercept_taps() -> void:
	var overlay: Control = _AD_DIAG.instantiate()
	add_child_autofree(overlay)
	# Wait for _ready so the children get instantiated.
	await wait_frames(1)
	_assert_all_ignore(overlay)


func test_save_indicator_overlay_does_not_intercept_taps() -> void:
	var overlay: Control = _SAVE_IND.instantiate()
	add_child_autofree(overlay)
	await wait_frames(1)
	_assert_all_ignore(overlay)


func test_touch_debug_overlay_does_not_intercept_taps() -> void:
	var overlay: Control = _TOUCH_DBG.instantiate()
	add_child_autofree(overlay)
	await wait_frames(1)
	_assert_all_ignore(overlay)


func test_narrator_overlay_idle_does_not_intercept_taps() -> void:
	# When idle (no narrator line showing), the bubble is invisible
	# and must not block taps. The bubble flips to STOP only inside
	# `_show()`; we don't trigger that here.
	var overlay: Control = _NARRATOR.instantiate()
	add_child_autofree(overlay)
	await wait_frames(1)
	_assert_all_ignore(overlay)


func test_narrator_overlay_active_bubble_flips_to_stop() -> void:
	# Sanity check: when a narrator line appears, the bubble flips to
	# STOP so a dismiss-tap actually hits the bubble. Confirms the
	# visibility-gated state machine works in both directions.
	var overlay: Control = _NARRATOR.instantiate()
	add_child_autofree(overlay)
	await wait_frames(1)
	# Trigger the narrator-line-chosen handler directly so the bubble
	# starts its show animation (which sets mouse_filter = STOP).
	overlay._on_narrator_line_chosen("test_id", "test text", "smug")
	# Use the next frame so the function body has run.
	await wait_frames(1)
	var bubble: Control = overlay._bubble
	assert_eq(
			bubble.mouse_filter,
			Control.MOUSE_FILTER_STOP,
			"narrator bubble must be STOP while visible so dismiss-taps hit it")
