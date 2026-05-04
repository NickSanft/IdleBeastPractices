## Phase 10d — bestiary tab as a Pokédex of `bestiary_card` instances.
##
## Layout: a `GridContainer` of cards, one per registered monster,
## sorted by tier then by id. Column count adapts to viewport width:
## 1 column under 480px, 2 columns 480..900, 4 columns above 900.
##
## Tapping a card opens a `bestiary_card_detail` PopupPanel; closing
## the popup returns the user to their previous scroll position
## (PopupPanel doesn't disturb the host's scroll state).
##
## Backwards-compat: tests-and-other-screens have been observed to
## read `_list` as the cards container — kept as the GridContainer
## member name so the test suite keeps working.
extends PanelContainer

const _CARD_SCENE := preload("res://game/scenes/bestiary/bestiary_card.tscn")
const _DETAIL_SCENE := preload("res://game/scenes/bestiary/bestiary_card_detail.tscn")

# Column-count breakpoints based on the bestiary view's own width.
# Phone (vertical 720): 2 columns; tablet portrait: 4 columns.
const _BREAKPOINT_2_COL: float = 480.0
const _BREAKPOINT_4_COL: float = 900.0

var _list: GridContainer
var _scroll: ScrollContainer
var _detail: PopupPanel
var _cards: Array[PanelContainer] = []


func _ready() -> void:
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	_list = GridContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("h_separation", 8)
	_list.add_theme_constant_override("v_separation", 8)
	_list.columns = _columns_for_width(size.x)
	_scroll.add_child(_list)

	_detail = _DETAIL_SCENE.instantiate()
	add_child(_detail)

	resized.connect(_on_resized)
	EventBus.monster_caught.connect(_on_monster_caught)
	EventBus.first_catch_of_species.connect(_on_first_catch)
	EventBus.first_shiny_caught.connect(_on_first_shiny)
	EventBus.pet_acquired.connect(_on_pet_acquired)
	EventBus.game_loaded.connect(_rebuild)
	_rebuild()


func _on_resized() -> void:
	if _list != null:
		_list.columns = _columns_for_width(size.x)


func _columns_for_width(w: float) -> int:
	if w >= _BREAKPOINT_4_COL:
		return 4
	if w >= _BREAKPOINT_2_COL:
		return 2
	return 1


# Catch / unlock signals just refresh existing cards in place — no
# need to wipe the grid (cards refresh themselves).
func _on_monster_caught(_id: String, _ix: int, _is_shiny: bool, _src: String) -> void:
	_refresh_cards()


func _on_first_catch(_id: String) -> void:
	_refresh_cards()


func _on_first_shiny(_id: String) -> void:
	_refresh_cards()


func _on_pet_acquired(_pet_id: String, _is_variant: bool) -> void:
	_refresh_cards()


func _refresh_cards() -> void:
	for card in _cards:
		if is_instance_valid(card):
			card.refresh()


# Full rebuild — used on first paint and on game_loaded (when the
# entire monster registry might have shifted).
func _rebuild() -> void:
	if not is_instance_valid(_list):
		return
	for child in _list.get_children():
		child.queue_free()
	_cards.clear()
	var monsters := ContentRegistry.monsters()
	monsters.sort_custom(func(a: MonsterResource, b: MonsterResource) -> bool:
		if a.tier != b.tier:
			return a.tier < b.tier
		return String(a.id) < String(b.id))
	for m in monsters:
		var card: PanelContainer = _CARD_SCENE.instantiate()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.set_monster(m)
		card.card_tapped.connect(_on_card_tapped)
		_list.add_child(card)
		_cards.append(card)


func _on_card_tapped(monster_id: StringName) -> void:
	var monster: MonsterResource = ContentRegistry.monster(monster_id)
	if monster == null:
		return
	_detail.bind_monster(monster)
	_detail.popup_centered(Vector2(420, 480))
