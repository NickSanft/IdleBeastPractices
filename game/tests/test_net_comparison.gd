## Phase 12a — net_shop's stat-delta line surfaces upgrade math vs
## the equipped net. Verifies the formatter returns "" in cases that
## shouldn't show a delta and produces the expected BBCode for an
## actual upgrade.
extends GutTest

const _SCENE := preload("res://game/scenes/ui/net_shop.tscn")


func before_each() -> void:
	GameState.from_dict({})
	ContentRegistry.ensure_loaded()


func _shop() -> PanelContainer:
	var s: PanelContainer = _SCENE.instantiate()
	add_child_autofree(s)
	return s


func test_no_delta_when_no_active_net() -> void:
	GameState.active_net = ""
	var shop := _shop()
	await wait_frames(2)
	var any_net: NetResource = ContentRegistry.nets()[0]
	assert_eq(shop._format_stat_delta(any_net), "",
			"no equipped net → no delta line")


func test_no_delta_when_target_is_already_owned() -> void:
	GameState.nets_owned = ["basic_net", "tier2_net"]
	GameState.active_net = "basic_net"
	var shop := _shop()
	await wait_frames(2)
	var owned: NetResource = ContentRegistry.net(&"tier2_net")
	assert_eq(shop._format_stat_delta(owned), "",
			"already-owned nets must not show a delta line")


func test_no_delta_when_comparing_against_self() -> void:
	GameState.nets_owned = ["basic_net"]
	GameState.active_net = "basic_net"
	var shop := _shop()
	await wait_frames(2)
	var same: NetResource = ContentRegistry.net(&"basic_net")
	assert_eq(shop._format_stat_delta(same), "")


func test_delta_appears_for_unowned_upgrade() -> void:
	GameState.nets_owned = ["basic_net"]
	GameState.active_net = "basic_net"
	var shop := _shop()
	await wait_frames(2)
	var upgrade: NetResource = ContentRegistry.net(&"tier2_net")
	var delta_text: String = shop._format_stat_delta(upgrade)
	assert_true(delta_text.length() > 0,
			"unowned tier2_net must surface a stat-delta vs basic_net")
	# Should reference the active net's name and at least one of the
	# stat keywords. Doesn't pin the exact string so future copy
	# tweaks don't break the test.
	assert_string_contains(delta_text, "Basic Net")
