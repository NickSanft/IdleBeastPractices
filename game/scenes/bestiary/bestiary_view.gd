## Bestiary tab: per-species card showing name, tier, sprite, and three slots
## (normal / shiny / variant pet). Unseen species render as "??? — Tier X".
extends PanelContainer

const _SPRITE_FRAME_SIZE := Vector2(32, 32)
const _SPRITE_DISPLAY_SCALE := 2.0

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
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	card.add_child(hbox)

	var key: String = String(monster.id)
	var seen: bool = GameState.monsters_caught.has(key)

	# Sprite (or '?' placeholder).
	var sprite_root := Control.new()
	sprite_root.custom_minimum_size = _SPRITE_FRAME_SIZE * _SPRITE_DISPLAY_SCALE
	hbox.add_child(sprite_root)
	if seen and monster.sprite != null:
		var sprite := TextureRect.new()
		sprite.texture = monster.sprite
		sprite.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite.modulate = monster.tint
		# Region-clip to first frame.
		sprite.size = _SPRITE_FRAME_SIZE * _SPRITE_DISPLAY_SCALE
		var atlas := AtlasTexture.new()
		atlas.atlas = monster.sprite
		atlas.region = Rect2(Vector2.ZERO, _SPRITE_FRAME_SIZE)
		sprite.texture = atlas
		sprite.anchor_right = 1.0
		sprite.anchor_bottom = 1.0
		sprite_root.add_child(sprite)
	else:
		var qmark := Label.new()
		qmark.text = "?"
		qmark.add_theme_font_size_override("font_size", 36)
		qmark.modulate = Color(0.6, 0.6, 0.6)
		qmark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		qmark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		qmark.set_anchors_preset(Control.PRESET_FULL_RECT)
		sprite_root.add_child(qmark)

	# Text column.
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	hbox.add_child(col)

	var name_label := Label.new()
	if seen:
		name_label.text = "%s — Tier %d" % [monster.display_name, monster.tier]
	else:
		name_label.text = "??? — Tier %d" % monster.tier
		name_label.modulate = Color(0.7, 0.7, 0.7)
	name_label.add_theme_font_size_override("font_size", 18)
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
	# Variant tracks the pet flag — pet_variants_owned holds the pet id, not species id.
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


func _slot_label(title: String, count: int, filled: bool, color_filled: Color) -> Control:
	var label := Label.new()
	if filled:
		label.text = "%s × %d" % [title, count] if count > 1 else "%s ✓" % title
		label.modulate = color_filled
	else:
		label.text = "%s —" % title
		label.modulate = Color(0.5, 0.5, 0.5)
	label.add_theme_font_size_override("font_size", 13)
	return label
