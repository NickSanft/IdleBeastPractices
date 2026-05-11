## Inventory tab — grid of [InventoryCard] instances.
##
## Phase 12a rewrite: was a flat VBoxContainer of Labels; now a
## GridContainer of themed cards with rarity-tinted borders. Adapts
## to viewport width: 3 columns on phone (<480 px), 5 on tablet
## (≥720 px), 4 in between.
##
## Long-press on a card opens a context menu with sell-all (and any
## future actions like "use as ingredient"). Tap is informational only
## for now (no detail modal — items are simple enough that the card
## itself surfaces all the info).
extends PanelContainer

const _CARD := preload("res://game/scenes/ui/inventory_card.tscn")
const _PALETTE := preload("res://game/resources/palette_colors.gd")
# Breakpoints chosen so the default 720-wide phone viewport gets 4
# columns (each card ~170 dp wide), tablet portrait gets 5. Below
# 480 (very narrow / split-screen) drops to 3.
const _BREAKPOINT_4_COL: float = 480.0
const _BREAKPOINT_5_COL: float = 1000.0

var _scroll: ScrollContainer
var _grid: GridContainer
var _empty_label: Label
var _context_popup: PopupPanel
var _context_target_item_id: StringName = &""

# v0.13.6 — visibility-gated refresh (item_gained fires per caught tap).
var refresh_count: int = 0
var _dirty: bool = false


func _ready() -> void:
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	_grid.columns = _columns_for_width(size.x)
	_scroll.add_child(_grid)

	_empty_label = Label.new()
	_empty_label.text = "Nothing caught yet."
	_empty_label.modulate = _PALETTE.SEPIA_MID
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_child(_empty_label)

	resized.connect(_on_resized)
	visibility_changed.connect(_on_visibility_changed)
	EventBus.item_gained.connect(_on_item_gained)
	EventBus.item_spent.connect(_on_item_spent)
	EventBus.game_loaded.connect(_mark_dirty_or_refresh)
	_refresh()


func _on_visibility_changed() -> void:
	if visible and _dirty:
		_dirty = false
		_refresh()


func _mark_dirty_or_refresh() -> void:
	if visible:
		_refresh()
	else:
		_dirty = true


func is_dirty() -> bool:
	return _dirty


func _exit_tree() -> void:
	if EventBus.item_gained.is_connected(_on_item_gained):
		EventBus.item_gained.disconnect(_on_item_gained)
	if EventBus.item_spent.is_connected(_on_item_spent):
		EventBus.item_spent.disconnect(_on_item_spent)
	if EventBus.game_loaded.is_connected(_refresh):
		EventBus.game_loaded.disconnect(_refresh)


func _on_resized() -> void:
	if _grid != null:
		_grid.columns = _columns_for_width(size.x)


func _columns_for_width(w: float) -> int:
	if w >= _BREAKPOINT_5_COL:
		return 5
	if w >= _BREAKPOINT_4_COL:
		return 4
	return 3


func _on_item_gained(_id: String, _amount: int) -> void:
	_mark_dirty_or_refresh()


func _on_item_spent(_id: String, _amount: int) -> void:
	_mark_dirty_or_refresh()


func _refresh() -> void:
	if not is_instance_valid(_grid):
		return
	refresh_count += 1
	for child in _grid.get_children():
		if child == _empty_label:
			continue
		child.queue_free()
	if GameState.inventory.is_empty():
		_empty_label.visible = true
		# Empty label spans all columns when grid is otherwise empty.
		# GridContainer doesn't natively support col-span; add filler
		# children equal to columns - 1 to push the label alone.
		# Simpler: leave it as one cell; the empty case is rare and
		# the visual oddity is acceptable.
		return
	_empty_label.visible = false
	# Sort items by rarity descending then by display_name. Surfaces
	# rare drops at the top of the inventory which is what the player
	# usually cares about.
	var sorted_keys: Array = GameState.inventory.keys()
	sorted_keys.sort_custom(func(a: String, b: String) -> bool:
		var ra: int = _rarity_of(a)
		var rb: int = _rarity_of(b)
		if ra != rb:
			return ra > rb
		return _name_of(a) < _name_of(b))
	for item_id_str in sorted_keys:
		var count: int = int(GameState.inventory[item_id_str])
		if count <= 0:
			continue
		var item_res := ContentRegistry.item(StringName(item_id_str))
		if item_res == null:
			continue
		var card: PanelContainer = _CARD.instantiate()
		_grid.add_child(card)
		card.bind(item_res, count)
		card.card_long_pressed.connect(_on_card_long_pressed)


func _rarity_of(item_id: String) -> int:
	var item_res := ContentRegistry.item(StringName(item_id))
	if item_res == null:
		return 0
	return int(item_res.rarity)


func _name_of(item_id: String) -> String:
	var item_res := ContentRegistry.item(StringName(item_id))
	if item_res == null:
		return item_id
	return item_res.display_name


func _on_card_long_pressed(item_id: StringName) -> void:
	_context_target_item_id = item_id
	if _context_popup == null:
		_build_context_popup()
	_context_popup.popup_centered(Vector2(280, 0))


func _build_context_popup() -> void:
	_context_popup = PopupPanel.new()
	# Window subtypes don't inherit Control theme cascade; assign
	# explicitly per the v0.10.4 fix.
	_context_popup.theme = preload("res://assets/themes/dusk/amethyst.tres")
	add_child(_context_popup)
	var margins := MarginContainer.new()
	margins.add_theme_constant_override("margin_left", 12)
	margins.add_theme_constant_override("margin_right", 12)
	margins.add_theme_constant_override("margin_top", 12)
	margins.add_theme_constant_override("margin_bottom", 12)
	_context_popup.add_child(margins)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margins.add_child(vbox)
	var heading := Label.new()
	heading.text = "Item options"
	heading.add_theme_font_size_override("font_size", UiScale.size(16))
	vbox.add_child(heading)
	# Currently the only action is Sell All. The hook is in place for
	# future "use as ingredient" / "pin" actions in 12a follow-ups.
	var sell_btn := Button.new()
	sell_btn.text = "Sell all"
	sell_btn.pressed.connect(_on_sell_all_pressed)
	vbox.add_child(sell_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_context_popup.hide)
	vbox.add_child(cancel_btn)


func _on_sell_all_pressed() -> void:
	if _context_target_item_id == &"":
		return
	var item_res := ContentRegistry.item(_context_target_item_id)
	if item_res == null:
		_context_popup.hide()
		return
	var count: int = int(GameState.inventory.get(String(_context_target_item_id), 0))
	if count <= 0:
		_context_popup.hide()
		return
	# Sell value is stored as a BigNumber dict per ItemResource. Multiply
	# by count to get total proceeds.
	var unit_value: BigNumber = BigNumber.from_dict(item_res.sell_value)
	var total: BigNumber = unit_value.multiply_float(float(count))
	GameState.add_gold(total)
	GameState.inventory[String(_context_target_item_id)] = 0
	EventBus.item_spent.emit(String(_context_target_item_id), count)
	_context_popup.hide()
	_refresh()
