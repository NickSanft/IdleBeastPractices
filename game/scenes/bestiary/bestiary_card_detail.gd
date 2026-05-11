## Phase 10d — modal opened when a bestiary card is tapped.
##
## Shows a single species' full sheet: scaled sprite, flavor text,
## drop info, catch counters (normal / shiny), variant status, and
## (where available) the Peniber line that fired on first catch.
##
## Self-contained `PopupPanel` so the bestiary view can `popup_centered`
## without reaching into the modal's internals.
extends PopupPanel

const _DUSK := preload("res://assets/themes/dusk/palette_dusk.gd")
const _SPRITE_FRAME_SIZE := Vector2(32, 32)
const _SPRITE_DISPLAY_SCALE := 4.0
const _SPRITE_BOX: Vector2 = _SPRITE_FRAME_SIZE * _SPRITE_DISPLAY_SCALE


func _ready() -> void:
	# PopupPanel sizes itself to its content; give it a sane minimum
	# so a long flavor line doesn't squash the sprite.
	min_size = Vector2(360, 0)
	exclusive = true   # tap outside dismisses
	# Window subtypes don't inherit Control theme; assign explicitly so
	# buttons + RichTextLabels in the modal use the parchment/brass theme.
	theme = preload("res://assets/themes/dusk/amethyst.tres")


## Build the body. Called by the view right before popup_centered.
func bind_monster(monster: MonsterResource) -> void:
	# Wipe any prior content (popups can be re-shown for different species).
	for child in get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	var key: String = String(monster.id)
	var entry: Dictionary = GameState.monsters_caught.get(key, {})
	var normal_count: int = int(entry.get("normal", 0))
	var shiny_count: int = int(entry.get("shiny", 0))
	var seen: bool = normal_count > 0 or shiny_count > 0

	# Header — name + tier.
	var name_label := Label.new()
	name_label.text = monster.display_name if seen else "??? — Tier %d" % monster.tier
	name_label.add_theme_font_size_override("font_size", UiScale.size(24))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	if seen:
		var tier_label := Label.new()
		tier_label.text = "Tier %d" % monster.tier
		# Phase 14d: SEPIA_MID → `ink_dim` per the bestiary_card sweep.
		tier_label.modulate = _DUSK.amethyst()["ink_dim"]
		tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tier_label.add_theme_font_size_override("font_size", UiScale.size(14))
		vbox.add_child(tier_label)

	# Big sprite.
	if monster.sprite != null:
		var sprite_cell := CenterContainer.new()
		sprite_cell.custom_minimum_size = Vector2(0, _SPRITE_BOX.y + 4)
		var atlas := AtlasTexture.new()
		atlas.atlas = monster.sprite
		atlas.region = Rect2(Vector2.ZERO, _SPRITE_FRAME_SIZE)
		var tex := TextureRect.new()
		tex.texture = atlas
		tex.custom_minimum_size = _SPRITE_BOX
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if seen:
			tex.modulate = monster.tint
		else:
			# Same silhouette material as the card.
			var shader := Shader.new()
			shader.code = """
shader_type canvas_item;
void fragment() {
	vec4 src = texture(TEXTURE, UV);
	COLOR = vec4(0.06, 0.05, 0.07, src.a);
}
"""
			var mat := ShaderMaterial.new()
			mat.shader = shader
			tex.material = mat
		sprite_cell.add_child(tex)
		vbox.add_child(sprite_cell)

	if seen:
		var flavor := Label.new()
		flavor.text = monster.flavor_text
		flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Phase 14d: SEPIA_DARK was a strong sepia for primary body text;
		# Dusk equivalent is `ink` (bright purple-white) since the
		# parchment-era "dark text on light bg" inverts on the dusk
		# popup bg.
		flavor.modulate = _DUSK.amethyst()["ink"]
		flavor.add_theme_font_size_override("font_size", UiScale.size(14))
		flavor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(flavor)

		var stats := _stats_text(monster, normal_count, shiny_count, entry)
		var stats_label := Label.new()
		stats_label.text = stats
		stats_label.add_theme_font_size_override("font_size", UiScale.size(13))
		vbox.add_child(stats_label)

		var quote := _peniber_first_catch_line(monster.id)
		if quote != "":
			var quote_label := Label.new()
			quote_label.text = "“%s”" % quote
			quote_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			# Phase 14d: SEPIA_MID → `ink_dim` for secondary quote text.
			# Peniber quotes stay slightly dimmed so they read as
			# flavor rather than primary content.
			quote_label.modulate = _DUSK.amethyst()["ink_dim"]
			quote_label.add_theme_font_size_override("font_size", UiScale.size(13))
			quote_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			vbox.add_child(quote_label)

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(hide)
	vbox.add_child(close)


func _stats_text(monster: MonsterResource, normal_count: int, shiny_count: int, _entry: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("Caught: %d" % normal_count)
	lines.append("Shinies: %d" % shiny_count)
	if monster.drop_item != null:
		var lo: int = monster.drop_amount_min
		var hi: int = monster.drop_amount_max
		var range_text: String = "%d" % lo if lo == hi else "%d–%d" % [lo, hi]
		lines.append("Drops: %s × %s" % [monster.drop_item.display_name, range_text])
	if monster.pet != null:
		var pet_id: String = String(monster.pet.id)
		var owned: bool = GameState.pets_owned.has(pet_id)
		var variant_owned: bool = GameState.pet_variants_owned.has(pet_id)
		var pet_status: String
		if variant_owned:
			pet_status = "%s (variant ✦)" % monster.pet.display_name
		elif owned:
			pet_status = monster.pet.display_name
		else:
			pet_status = "%s (locked)" % monster.pet.display_name
		lines.append("Pet: %s" % pet_status)
	return "\n".join(lines)


## Best-effort lookup of Peniber's first-catch line for this species.
## The narrator uses StringName trigger ids of the form
## `on_first_catch_<monster_id>` per [docs/peniber-voice.md]; if no
## matching DialogueLineResource is registered, returns "".
func _peniber_first_catch_line(monster_id: StringName) -> String:
	if not Engine.has_singleton("Narrator") and not has_node("/root/Narrator"):
		return ""
	var narrator := get_node_or_null("/root/Narrator")
	if narrator == null:
		return ""
	if not narrator.has_method("first_catch_line_for"):
		return ""
	return String(narrator.call("first_catch_line_for", monster_id))
