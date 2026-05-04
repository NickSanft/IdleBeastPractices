## Phase 12a — single inventory item card.
##
## Shows the item's icon (or "?" placeholder), count, display name, and
## a rarity-tinted border. Tappable + long-press-aware so the player
## can sell-all / use-as-ingredient via context menu.
##
## Rarity tints (sourced from [PaletteColors]):
##   COMMON    — parchment / sepia border (default)
##   UNCOMMON  — sage green
##   RARE      — dusk blue
##   EPIC      — blood ruby
##
## Tap fires `card_tapped(item_id)`. Long-press fires
## `card_long_pressed(item_id)` after the global long-press threshold.
extends PanelContainer

signal card_tapped(item_id: StringName)
signal card_long_pressed(item_id: StringName)

const _PALETTE := preload("res://game/resources/palette_colors.gd")
const _RARITY_BORDER_COLORS := {
	0: Color(0.72, 0.55, 0.20, 1.0),  # COMMON — brass
	1: Color(0.40, 0.55, 0.36, 1.0),  # UNCOMMON — sage
	2: Color(0.36, 0.42, 0.58, 1.0),  # RARE — dusk
	3: Color(0.65, 0.16, 0.22, 1.0),  # EPIC — ruby
}
const _LONG_PRESS_THRESHOLD_SECS := 0.5

var item: ItemResource
var count: int = 0

var _icon_rect: TextureRect
var _qmark: Label
var _count_label: Label
var _name_label: Label
var _press_started_unix: float = 0.0
var _press_handled: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(0, 96)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	# Sprite cell — icon if available, else a "?" glyph fallback.
	var sprite_cell := CenterContainer.new()
	sprite_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sprite_cell.custom_minimum_size = Vector2(0, 48)
	vbox.add_child(sprite_cell)

	_icon_rect = TextureRect.new()
	_icon_rect.custom_minimum_size = Vector2(40, 40)
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite_cell.add_child(_icon_rect)

	_qmark = Label.new()
	_qmark.text = "?"
	_qmark.add_theme_font_size_override("font_size", 28)
	_qmark.modulate = _PALETTE.SEPIA_MID
	_qmark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qmark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_qmark.custom_minimum_size = Vector2(40, 40)
	_qmark.visible = false
	sprite_cell.add_child(_qmark)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 12)
	_name_label.modulate = _PALETTE.INK_BLACK
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_name_label)

	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", 14)
	_count_label.modulate = _PALETTE.SEPIA_DARK
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_count_label)


func bind(p_item: ItemResource, p_count: int) -> void:
	item = p_item
	count = p_count
	_refresh()


func _refresh() -> void:
	if item == null or _name_label == null:
		return
	_name_label.text = item.display_name
	_count_label.text = "× %d" % count
	if item.sprite != null:
		_icon_rect.texture = item.sprite
		_icon_rect.visible = true
		_qmark.visible = false
	else:
		_icon_rect.visible = false
		_qmark.visible = true
	_apply_rarity_border(int(item.rarity))


## Applies the rarity-tinted border via a per-card StyleBoxFlat
## override. Doesn't leak back into the global theme — the override
## scopes to this PanelContainer only.
func _apply_rarity_border(rarity: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = _PALETTE.PARCHMENT
	sb.border_color = _RARITY_BORDER_COLORS.get(rarity, _RARITY_BORDER_COLORS[0])
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 3
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_right = 4
	sb.corner_radius_bottom_left = 4
	sb.content_margin_left = 6.0
	sb.content_margin_top = 6.0
	sb.content_margin_right = 6.0
	sb.content_margin_bottom = 6.0
	add_theme_stylebox_override("panel", sb)


func _gui_input(event: InputEvent) -> void:
	if item == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_started_unix = Time.get_ticks_msec() / 1000.0
			_press_handled = false
		elif _press_started_unix > 0.0:
			var held: float = (Time.get_ticks_msec() / 1000.0) - _press_started_unix
			_press_started_unix = 0.0
			if held >= _LONG_PRESS_THRESHOLD_SECS:
				if not _press_handled:
					_press_handled = true
					card_long_pressed.emit(item.id)
			else:
				accept_event()
				card_tapped.emit(item.id)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_press_started_unix = Time.get_ticks_msec() / 1000.0
			_press_handled = false
		elif _press_started_unix > 0.0:
			var held: float = (Time.get_ticks_msec() / 1000.0) - _press_started_unix
			_press_started_unix = 0.0
			if held >= _LONG_PRESS_THRESHOLD_SECS:
				if not _press_handled:
					_press_handled = true
					card_long_pressed.emit(item.id)
			else:
				accept_event()
				card_tapped.emit(item.id)


# Auto-fire long-press while the finger is still down so the user
# doesn't have to lift to trigger it. Polls in _process while a press
# is active.
func _process(_delta: float) -> void:
	if _press_started_unix == 0.0 or _press_handled:
		return
	var held: float = (Time.get_ticks_msec() / 1000.0) - _press_started_unix
	if held >= _LONG_PRESS_THRESHOLD_SECS:
		_press_handled = true
		card_long_pressed.emit(item.id)
