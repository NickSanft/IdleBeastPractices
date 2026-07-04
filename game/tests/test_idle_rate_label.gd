## v0.15.17 — catching view's "Idle ≈ N gold/min" readout.
##
## The label is passive (mouse IGNORE), sits in the reserved bottom band,
## hides entirely when nothing is catchable (no net / zero rate), and
## refreshes on a 1 s accumulator (there is no net-equipped signal to
## subscribe to; see the field comment in catching_view.gd).
extends GutTest

const _SCENE := preload("res://game/scenes/catching/catching_view.tscn")


func before_each() -> void:
	GameState._reset_to_defaults()


func after_each() -> void:
	GameState._reset_to_defaults()


func _make_view() -> Control:
	var view: Control = _SCENE.instantiate()
	add_child_autofree(view)
	await wait_frames(1)
	return view


func test_hidden_when_no_net_equipped() -> void:
	GameState.active_net = ""
	var view: Control = await _make_view()
	view._refresh_idle_rate()
	assert_false(view._idle_rate_label.visible,
			"taps-only players get a clean screen, not a zero readout")


func test_shows_gold_per_minute_with_active_net() -> void:
	GameState.active_net = "basic_net"
	var view: Control = await _make_view()
	view._refresh_idle_rate()
	assert_true(view._idle_rate_label.visible)
	assert_string_contains(view._idle_rate_label.text, "gold/min")
	assert_string_contains(view._idle_rate_label.text, "Idle")


func test_accumulator_refreshes_after_one_second() -> void:
	GameState.active_net = ""
	var view: Control = await _make_view()
	view._refresh_idle_rate()
	assert_false(view._idle_rate_label.visible, "precondition: hidden")
	# Equip a net; the readout must appear via the 1 s accumulator path.
	GameState.active_net = "basic_net"
	# The live _process already ran during _make_view's awaited frames and
	# pre-loaded the accumulator with real frame deltas — zero it so the
	# manual pumps below are deterministic under CI load (review finding).
	view._idle_rate_accumulator = 0.0
	view._handle_idle_rate_refresh(0.5)
	assert_false(view._idle_rate_label.visible, "sub-second: not yet refreshed")
	view._handle_idle_rate_refresh(0.6)
	assert_true(view._idle_rate_label.visible, "accumulator crossed 1 s -> refreshed")


func test_label_is_tap_transparent() -> void:
	GameState.active_net = "basic_net"
	var view: Control = await _make_view()
	assert_eq(view._idle_rate_label.mouse_filter, Control.MOUSE_FILTER_IGNORE,
			"a mis-tap near the readout must fall through to monster taps")
