## v0.13.6 — regression tests for the hidden-tab refresh budget.
##
## Background: tapping an enemy on the catching screen fires
## `monster_caught`, `currency_changed`, `item_gained`, etc. Pre-fix,
## six other views (bestiary, crafting, inventory, net_shop,
## upgrade_tree, prestige) all subscribed to those signals and
## ran a full DOM rebuild on each one — even when the view itself
## was hidden behind another tab. The bestiary alone tore down and
## rebuilt 240 Labels (60 monsters × 4 pills) per caught tap.
## Combined the freeze was ~1s on Android.
##
## Now every rebuilder uses the same gate:
##   - if visible: refresh immediately (player needs to see it)
##   - if hidden:  set a dirty flag; defer until visibility_changed
##
## These tests cover the contract:
##   - Hidden views drop signal-driven refreshes to ZERO.
##   - The dirty flag is set so the deferred work isn't lost.
##   - Becoming visible drains the dirty flag with exactly ONE refresh,
##     not one-per-suppressed-signal.
##   - Visible views still refresh per signal (no behaviour change
##     for the foreground tab).
##
## We exercise each of the six views as separate cases so a future
## maintainer who adds a new rebuilder and forgets the gate fails on
## a specific test name rather than a generic budget assertion.
extends GutTest


const _BESTIARY_SCENE := preload("res://game/scenes/bestiary/bestiary_view.tscn")
const _CRAFTING_SCENE := preload("res://game/scenes/crafting/crafting_view.tscn")
const _INVENTORY_SCENE := preload("res://game/scenes/ui/inventory_panel.tscn")
const _NET_SHOP_SCENE := preload("res://game/scenes/ui/net_shop.tscn")
const _UPGRADE_TREE_SCENE := preload("res://game/scenes/ui/upgrade_tree.tscn")
const _PRESTIGE_SCENE := preload("res://game/scenes/prestige/prestige_view.tscn")


# Helper — instantiates a view, adds it to the test tree (so signals
# wire up via _ready), then forces it hidden. Returns the view +
# resets refresh_count so the test asserts only post-hide signal cost.
func _make_hidden(scene: PackedScene) -> Node:
	var view := scene.instantiate()
	add_child_autofree(view)
	# Initial _refresh in _ready raises the count to 1; we want to
	# measure only what happens AFTER we hide it.
	view.visible = false
	view.refresh_count = 0
	return view


# region — bestiary

func test_bestiary_hidden_skips_refresh_on_monster_caught() -> void:
	var view: Node = _make_hidden(_BESTIARY_SCENE)
	for i in 20:
		EventBus.monster_caught.emit("red_wisplet", i, false, "tap")
	assert_eq(view.refresh_count, 0,
		"bestiary must NOT refresh while hidden (20 caught taps -> 0 refreshes)")
	assert_true(view.is_dirty(),
		"bestiary should be dirty after a missed signal, so it can refresh on show")


func test_bestiary_drains_dirty_flag_on_show() -> void:
	var view: Node = _make_hidden(_BESTIARY_SCENE)
	for i in 5:
		EventBus.monster_caught.emit("red_wisplet", i, false, "tap")
	# Player switches to the bestiary tab.
	view.visible = true
	assert_eq(view.refresh_count, 1,
		"becoming visible must run exactly one refresh, not one-per-suppressed-signal")
	assert_false(view.is_dirty(), "dirty flag must be cleared after the refresh")


func test_bestiary_visible_still_refreshes_per_signal() -> void:
	# Foreground behaviour preserved: a visible bestiary repaints
	# immediately so the catch count ticks up live.
	var view = _BESTIARY_SCENE.instantiate()
	add_child_autofree(view)
	view.visible = true
	view.refresh_count = 0
	EventBus.monster_caught.emit("red_wisplet", 1, false, "tap")
	assert_gt(view.refresh_count, 0, "visible bestiary must refresh on monster_caught")

# endregion


# region — crafting

func test_crafting_hidden_skips_refresh_on_currency_changed() -> void:
	var view: Node = _make_hidden(_CRAFTING_SCENE)
	for _i in 20:
		EventBus.currency_changed.emit("gold", 1)
	assert_eq(view.refresh_count, 0,
		"crafting view must NOT refresh while hidden (20 currency_changed -> 0 refreshes)")
	assert_true(view.is_dirty())


func test_crafting_drains_on_show() -> void:
	var view: Node = _make_hidden(_CRAFTING_SCENE)
	EventBus.currency_changed.emit("gold", 1)
	EventBus.item_gained.emit("wisplet_ectoplasm", 3)
	view.visible = true
	assert_eq(view.refresh_count, 1)
	assert_false(view.is_dirty())

# endregion


# region — inventory

func test_inventory_hidden_skips_refresh_on_item_gained() -> void:
	var view: Node = _make_hidden(_INVENTORY_SCENE)
	for _i in 20:
		EventBus.item_gained.emit("wisplet_ectoplasm", 1)
	assert_eq(view.refresh_count, 0,
		"inventory must NOT refresh while hidden (20 item_gained -> 0 refreshes)")
	assert_true(view.is_dirty())


func test_inventory_drains_on_show() -> void:
	var view: Node = _make_hidden(_INVENTORY_SCENE)
	EventBus.item_gained.emit("wisplet_ectoplasm", 1)
	view.visible = true
	assert_eq(view.refresh_count, 1)

# endregion


# region — net_shop

func test_net_shop_hidden_skips_refresh_on_currency_changed() -> void:
	var view: Node = _make_hidden(_NET_SHOP_SCENE)
	for _i in 20:
		EventBus.currency_changed.emit("gold", 1)
	assert_eq(view.refresh_count, 0,
		"net_shop must NOT refresh while hidden (20 currency_changed -> 0 refreshes)")


func test_net_shop_drains_on_show() -> void:
	var view: Node = _make_hidden(_NET_SHOP_SCENE)
	EventBus.currency_changed.emit("gold", 1)
	view.visible = true
	assert_eq(view.refresh_count, 1)

# endregion


# region — upgrade_tree

func test_upgrade_tree_hidden_skips_refresh_on_currency_changed() -> void:
	var view: Node = _make_hidden(_UPGRADE_TREE_SCENE)
	for _i in 20:
		EventBus.currency_changed.emit("gold", 1)
	assert_eq(view.refresh_count, 0,
		"upgrade_tree must NOT refresh while hidden (20 currency_changed -> 0 refreshes)")


func test_upgrade_tree_drains_on_show() -> void:
	var view: Node = _make_hidden(_UPGRADE_TREE_SCENE)
	EventBus.currency_changed.emit("gold", 1)
	view.visible = true
	assert_eq(view.refresh_count, 1)

# endregion


# region — prestige_view

func test_prestige_hidden_skips_refresh_on_currency_changed() -> void:
	var view: Node = _make_hidden(_PRESTIGE_SCENE)
	for _i in 20:
		EventBus.currency_changed.emit("gold", 1)
	assert_eq(view.refresh_count, 0,
		"prestige_view must NOT refresh while hidden (20 currency_changed -> 0 refreshes)")


func test_prestige_drains_on_show() -> void:
	var view: Node = _make_hidden(_PRESTIGE_SCENE)
	EventBus.currency_changed.emit("gold", 1)
	view.visible = true
	assert_eq(view.refresh_count, 1)

# endregion
