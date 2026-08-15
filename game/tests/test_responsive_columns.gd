## v0.14.4 (Phase 13c.4) — UiScale.columns + responsive grid tests.
##
## Asserts the contract every multi-column secondary view depends on:
##   - `UiScale.columns(width, min_card_dp)` returns floor(width / min)
##     clamped to ≥ 1.
##   - The three views that adopted the helper (crafting, net_shop,
##     upgrade_tree) re-set GridContainer.columns when their `resized`
##     signal fires (orientation change, foldable open, tablet rotation).
extends GutTest

const _CRAFTING := preload("res://game/scenes/crafting/crafting_view.tscn")
const _NET_SHOP := preload("res://game/scenes/ui/net_shop.tscn")
const _UPGRADE_TREE := preload("res://game/scenes/ui/upgrade_tree.tscn")


func before_each() -> void:
	# columns() scales its threshold by the accessibility font scale, so these
	# assertions are only meaningful against a pinned scale. Another file
	# leaving 1.5 behind would otherwise silently halve every expected count.
	Settings.font_scale = 1.0


func after_each() -> void:
	Settings.font_scale = 1.0


# region — UiScale.columns

func test_columns_floors_width_over_min_card() -> void:
	# 720 wide / 320 dp per card → 2 columns.
	assert_eq(UiScale.columns(720.0, 320.0), 2)
	# 1280 wide / 320 → 4.
	assert_eq(UiScale.columns(1280.0, 320.0), 4)
	# 480 wide / 320 → 1 (480/320 = 1.5, floors to 1).
	assert_eq(UiScale.columns(480.0, 320.0), 1)


## The accessibility font scale must shrink the column count, because a card's
## minimum width grows with its text. Pre-fix this returned the 1.0x count at
## every scale, so at 1.5x the grid demanded more width than the viewport had
## and the spill cascaded up to orientation_root (caught on CI as the Shop tab
## measuring 1308 against a 1280 viewport).
func test_columns_shrink_as_the_font_scale_grows() -> void:
	Settings.font_scale = 1.0
	var base: int = UiScale.columns(1280.0, 340.0)
	assert_eq(base, 3, "1280 / 340 floors to 3 at normal scale")

	Settings.font_scale = 1.5
	var scaled: int = UiScale.columns(1280.0, 340.0)
	assert_eq(scaled, 2, "1280 / (340 * 1.5) floors to 2 — cards need the extra room")
	assert_lt(scaled, base, "a larger font must never keep the same column count")

	Settings.font_scale = 1.0


func test_columns_clamps_to_at_least_one() -> void:
	# Narrower than min_card → still 1 column, never 0.
	assert_eq(UiScale.columns(100.0, 320.0), 1)
	assert_eq(UiScale.columns(320.0, 320.0), 1)


func test_columns_handles_invalid_inputs() -> void:
	# Defensive: negative or zero inputs return 1 instead of dividing.
	assert_eq(UiScale.columns(0.0, 320.0), 1)
	assert_eq(UiScale.columns(-100.0, 320.0), 1)
	assert_eq(UiScale.columns(720.0, 0.0), 1)
	assert_eq(UiScale.columns(720.0, -10.0), 1)


func test_columns_widens_with_landscape_aspect() -> void:
	# Phone portrait at 720 dp wide vs landscape at ~1200 dp wide
	# (post-rail). Same min_card_dp; landscape gets more columns.
	var portrait_cols: int = UiScale.columns(720.0, 320.0)
	var landscape_cols: int = UiScale.columns(1200.0, 320.0)
	assert_gt(landscape_cols, portrait_cols,
		"landscape views must reflow into more columns")

# endregion


# region — view-level responsiveness

func _grid_columns(view: Node) -> int:
	# All three responsive views store the GridContainer in `_list`.
	if "_list" in view and view.get("_list") != null:
		return view.get("_list").columns
	return -1


func test_crafting_view_reflows_columns_on_resize() -> void:
	var view = _CRAFTING.instantiate()
	add_child_autofree(view)
	# Force a portrait-phone size, then a landscape-phone size.
	view.size = Vector2(720, 1280)
	view._on_resized.call() if view.has_method("_on_resized") else null
	var portrait_cols: int = _grid_columns(view)
	view.size = Vector2(1280, 720)
	view._on_resized.call() if view.has_method("_on_resized") else null
	var landscape_cols: int = _grid_columns(view)
	assert_gt(landscape_cols, portrait_cols,
		"crafting view must add columns when wider")


func test_net_shop_reflows_columns_on_resize() -> void:
	var view = _NET_SHOP.instantiate()
	add_child_autofree(view)
	view.size = Vector2(720, 1280)
	view._on_resized.call() if view.has_method("_on_resized") else null
	var portrait_cols: int = _grid_columns(view)
	view.size = Vector2(1280, 720)
	view._on_resized.call() if view.has_method("_on_resized") else null
	var landscape_cols: int = _grid_columns(view)
	assert_gt(landscape_cols, portrait_cols,
		"net_shop must add columns when wider")


func test_upgrade_tree_reflows_columns_on_resize() -> void:
	var view = _UPGRADE_TREE.instantiate()
	add_child_autofree(view)
	view.size = Vector2(720, 1280)
	view._on_resized.call() if view.has_method("_on_resized") else null
	var portrait_cols: int = _grid_columns(view)
	view.size = Vector2(1280, 720)
	view._on_resized.call() if view.has_method("_on_resized") else null
	var landscape_cols: int = _grid_columns(view)
	assert_gt(landscape_cols, portrait_cols,
		"upgrade_tree must add columns when wider")

# endregion
