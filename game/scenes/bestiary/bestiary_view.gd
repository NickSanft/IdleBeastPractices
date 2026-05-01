## Bestiary tab: per-species card showing name, tier, sprite, and three slots
## (normal / shiny / variant pet). Unseen species render as "??? — Tier X".
extends PanelContainer

const _SPRITE_FRAME_SIZE := Vector2(32, 32)
const _SPRITE_DISPLAY_SCALE := 3.0
const _SPRITE_BOX: Vector2 = _SPRITE_FRAME_SIZE * _SPRITE_DISPLAY_SCALE
const _CARD_MARGIN := 10

var _list: VBoxContainer


func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	EventBus.monster_caught.connect(_on_monster_caught)
	EventBus.first_catch_of_species.connect(_on_first_catch)
	EventBus.first_shiny_caught.connect(_on_first_shiny)
	EventBus.pet_acquired.connect(_on_pet_acquired)
	EventBus.game_loaded.connect(_refresh)
	_refresh()


func _on_monster_caught(_id: String, _ix: int, _is_shiny: bool, _src: String) -> void:
	_refresh()


func _on_first_catch(_id: String) -> void:
	_refresh()


func _on_first_shiny(_id: String) -> void:
	_refresh()


func _on_pet_acquired(_pet_id: String, _is_variant: bool) -> void:
	_refresh()


func _refresh() -> void:
	if not is_instance_valid(_list):
		return
	for child in _list.get_children():
		child.queue_free()
	# Sort by tier ascending for a stable read order.
	var monsters := ContentRegistry.monsters()
	monsters.sort_custom(func(a: MonsterResource, b: MonsterResource) -> bool:
		if a.tier != b.tier:
			return a.tier < b.tier
		return String(a.id) < String(b.id))
	for m in monsters:
		_list.add_child(_build_card(m))


func _build_card(monster: MonsterResource) -> Control:
	# Card frame: PanelContainer + clip_contents so a runaway sprite or label
	# can't bleed into a sibling card.
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.clip_contents = true
	# Padding inside the panel — keeps text and sprite off the edge.
	var margins := MarginContainer.new()
	margins.add_theme_constant_override("margin_left", _CARD_MARGIN)
	margins.add_theme_constant_override("margin_right", _CARD_MARGIN)
	margins.add_theme_constant_override("margin_top", _CARD_MARGIN)
	margins.add_theme_constant_override("margin_bottom", _CARD_MARGIN)
	card.add_child(margins)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	margins.add_child(hbox)

	var key: String = String(monster.id)
	var seen: bool = GameState.monsters_caught.has(key)

	hbox.add_child(_build_sprite_slot(monster, seen))

	# Text column.
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	hbox.add_child(col)

	var name_label := Label.new()
	if seen:
		name_label.text = "%s — Tier %d" % [monster.display_name, monster.tier]
	else:
		name_label.text = "??? — Tier %d" % monster.tier
		name_label.modulate = Color(0.7, 0.7, 0.7)
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(name_label)

	# Slot row: normal / shiny / variant.
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 14)
	col.add_child(slots)

	var entry: Dictionary = GameState.monsters_caught.get(key, {})
	var normal_count: int = int(entry.get("normal", 0))
	var shiny_count: int = int(entry.get("shiny", 0))
	slots.add_child(_slot_label("Caught", normal_count, normal_count > 0, Color(0.8, 1.0, 0.8)))
	slots.add_child(_slot_label("Shiny", shiny_count, shiny_count > 0, Color(1.0, 0.95, 0.5)))
	var variant_owned: bool = monster.pet != null and GameState.pet_variants_owned.has(String(monster.pet.id))
	slots.add_child(_slot_label("Variant", 1 if variant_owned else 0, variant_owned, Color(0.7, 0.85, 1.0)))

	if seen:
		var flavor := Label.new()
		flavor.text = monster.flavor_text
		flavor.modulate = Color(0.8, 0.8, 0.8)
		flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		flavor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flavor.add_theme_font_size_override("font_size", 13)
		col.add_child(flavor)

	return card


## Builds the left-hand sprite cell. Fixed width/height (~96 px) so it never
## stretches to the card's height and clips the textbox alongside it.
func _build_sprite_slot(monster: MonsterResource, seen: bool) -> Control:
	if seen and monster.sprite != null:
		var atlas := AtlasTexture.new()
		atlas.atlas = monster.sprite
		atlas.region = Rect2(Vector2.ZERO, _SPRITE_FRAME_SIZE)
		var tex := TextureRect.new()
		tex.texture = atlas
		tex.modulate = monster.tint
		tex.custom_minimum_size = _SPRITE_BOX
		tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		return tex
	var qmark := Label.new()
	qmark.text = "?"
	qmark.add_theme_font_size_override("font_size", 36)
	qmark.modulate = Color(0.6, 0.6, 0.6)
	qmark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qmark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	qmark.custom_minimum_size = _SPRITE_BOX
	qmark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	qmark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return qmark


func _slot_label(title: String, count: int, filled: bool, color_filled: Color) -> Control:
	var label := Label.new()
	if filled:
		label.text = ("%s × %d" % [title, count]) if count > 1 else ("%s ✓" % title)
		label.modulate = color_filled
	else:
		label.text = "%s —" % title
		label.modulate = Color(0.5, 0.5, 0.5)
	label.add_theme_font_size_override("font_size", 13)
	return label
