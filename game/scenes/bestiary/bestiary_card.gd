## Phase 10d — single bestiary entry as a Pokédex-style card.
##
## Each card binds a `MonsterResource` and reads the player's catch
## state from `GameState.monsters_caught`. Layout:
##
##   ┌─────────────────────────┐
##   │ ▰ tier ribbon (band)   │   ← 1-5 brass, 6-10 silver,
##   ├─────────────────────────┤     11-15 gold, 16-20 obsidian
##   │      [sprite or         │
##   │       silhouette]       │
##   ├─────────────────────────┤
##   │ Name — Tier N           │
##   │ Caught × N · ✦ shiny    │
##   │ ◇ ✦ ✧ ⬢   (slot row)    │
##   └─────────────────────────┘
##
## Slot states drive a card-wide "perfected" upgrade: when all four
## slots are filled (seen + normal + shiny + variant) the card paints
## a gold border by overriding the panel StyleBox.
##
## Silhouettes for unseen species use a `ShaderMaterial` that samples
## texture alpha and outputs near-black RGB — works on top of the
## existing recolor placeholders without needing per-species art.
extends PanelContainer

signal card_tapped(monster_id: StringName)

const _PALETTE := preload("res://game/resources/palette_colors.gd")
const _SPRITE_FRAME_SIZE := Vector2(32, 32)
const _SPRITE_DISPLAY_SCALE := 2.0
const _SPRITE_BOX: Vector2 = _SPRITE_FRAME_SIZE * _SPRITE_DISPLAY_SCALE

# Silhouette shader: same texture, but RGB clamped to near-black with the
# original alpha preserved. Used when the player hasn't seen this species.
const _SILHOUETTE_SHADER := """
shader_type canvas_item;
void fragment() {
	vec4 src = texture(TEXTURE, UV);
	COLOR = vec4(0.06, 0.05, 0.07, src.a);
}
"""

# Tier-band colors (color the top ribbon by every-5-tiers band).
const _BAND_COLORS := {
	0: Color(0.72, 0.55, 0.20, 1.0),   # tiers 1-5  brass
	1: Color(0.75, 0.78, 0.82, 1.0),   # tiers 6-10 silver
	2: Color(0.95, 0.78, 0.30, 1.0),   # tiers 11-15 gold
	3: Color(0.20, 0.18, 0.22, 1.0),   # tiers 16-20 obsidian
}

enum SlotState { LOCKED, SEEN, CAPTURED, PERFECTED }

@export var monster: MonsterResource

var _ribbon: ColorRect
var _sprite_rect: TextureRect
var _qmark_label: Label
var _name_label: Label
var _count_label: Label
var _slot_row: HBoxContainer
var _silhouette_material: ShaderMaterial

# v0.13.6 — pills are built once in _build_layout and updated in
# refresh(). Pre-fix every refresh queue_freed and recreated all 4
# Labels, which compounded with bestiary_view's per-tap refresh into
# the Android freeze. See bestiary_view.gd for the full diagnosis.
var _pill_seen: Label
var _pill_normal: Label
var _pill_shiny: Label
var _pill_variant: Label

# Reused atlas; refresh() retargets it instead of allocating fresh.
var _atlas: AtlasTexture


func _ready() -> void:
	clip_contents = true
	custom_minimum_size = Vector2(0, 180)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_silhouette_material = _build_silhouette_material()
	_build_layout()
	if monster != null:
		refresh()
	# Phase 13a: live re-apply font sizes when the user moves the
	# accessibility slider. Without this, cards built once at scene
	# build time keep their old px sizes until the next full refresh.
	# The labels themselves stay; we just retarget their font_size
	# theme override.
	Settings.accessibility_settings_changed.connect(_apply_font_sizes)
	# v0.15.1 (Phase 14b): the DeviceLayout.layout_changed subscription
	# was load-bearing pre-v0.14.3, when UiScale.size() multiplied by
	# `dpi_bucket`. After v0.14.3 moved density to
	# `Window.content_scale_factor`, UiScale.size only depends on
	# `Settings.font_scale`. Subscribing to layout_changed would
	# unnecessarily re-apply 10 theme calls per card on every viewport
	# resize — for 60 bestiary cards × 60 burst emits the cost hit
	# ~2 s in the test_burst_resize_completes_under_100ms test.
	# Removed; the Settings handler above is sufficient.


func _apply_font_sizes() -> void:
	if _qmark_label != null:
		_qmark_label.add_theme_font_size_override("font_size", UiScale.size(36))
	if _name_label != null:
		_name_label.add_theme_font_size_override("font_size", UiScale.size(16))
	if _count_label != null:
		_count_label.add_theme_font_size_override("font_size", UiScale.size(12))
	for pill in [_pill_seen, _pill_normal, _pill_shiny, _pill_variant]:
		if pill != null:
			pill.add_theme_font_size_override("font_size", UiScale.size(18))


func set_monster(m: MonsterResource) -> void:
	monster = m
	if is_inside_tree():
		refresh()


func _build_layout() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	_ribbon = ColorRect.new()
	_ribbon.custom_minimum_size = Vector2(0, 6)
	_ribbon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_ribbon)

	# Sprite cell. Either a TextureRect (seen) or a "?" Label (locked).
	# Both are kept as children so refresh() can flip visibility instead
	# of rebuilding the subtree.
	var sprite_cell := CenterContainer.new()
	sprite_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sprite_cell.custom_minimum_size = Vector2(0, _SPRITE_BOX.y + 4)
	vbox.add_child(sprite_cell)

	_sprite_rect = TextureRect.new()
	_sprite_rect.custom_minimum_size = _SPRITE_BOX
	_sprite_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite_cell.add_child(_sprite_rect)

	_qmark_label = Label.new()
	_qmark_label.text = "?"
	_qmark_label.add_theme_font_size_override("font_size", UiScale.size(36))
	_qmark_label.modulate = Color(0.45, 0.4, 0.32)
	_qmark_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qmark_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_qmark_label.custom_minimum_size = _SPRITE_BOX
	sprite_cell.add_child(_qmark_label)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", UiScale.size(16))
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_name_label)

	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", UiScale.size(12))
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.modulate = _PALETTE.SEPIA_MID
	vbox.add_child(_count_label)

	_slot_row = HBoxContainer.new()
	_slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_slot_row.add_theme_constant_override("separation", 6)
	_slot_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_slot_row)

	# Build pills once. refresh() flips their fill state without
	# touching the scene tree. The glyph + tooltip text are static,
	# only modulate (filled vs dim) and the colorblind-mode suffix
	# change between refreshes.
	_pill_seen = _build_pill("◇", _PALETTE.SAGE_GREEN, "Seen")
	_pill_normal = _build_pill("✦", _PALETTE.BRASS_ACCENT, "Normal")
	_pill_shiny = _build_pill("✧", _PALETTE.BLOOD_RUBY, "Shiny")
	_pill_variant = _build_pill("⬢", _PALETTE.DUSK_BLUE, "Variant")
	_slot_row.add_child(_pill_seen)
	_slot_row.add_child(_pill_normal)
	_slot_row.add_child(_pill_shiny)
	_slot_row.add_child(_pill_variant)

	# Atlas is reused across refreshes — only the source texture
	# rotates if the monster.sprite ever changes (currently it doesn't
	# at runtime, but binding once keeps the tex pointer stable).
	_atlas = AtlasTexture.new()
	_atlas.region = Rect2(Vector2.ZERO, _SPRITE_FRAME_SIZE)


func _build_silhouette_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = _SILHOUETTE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat


func refresh() -> void:
	if monster == null or _name_label == null:
		return
	_ribbon.color = _band_color_for_tier(monster.tier)

	var key: String = String(monster.id)
	var entry: Dictionary = GameState.monsters_caught.get(key, {})
	var normal_count: int = int(entry.get("normal", 0))
	var shiny_count: int = int(entry.get("shiny", 0))
	var seen: bool = normal_count > 0 or shiny_count > 0
	var pet_id: String = String(monster.pet.id) if monster.pet != null else ""
	var variant_owned: bool = pet_id != "" and GameState.pet_variants_owned.has(pet_id)

	# Sprite vs silhouette. Use the SAME atlas region for both — the
	# silhouette material does the visual reduction. The AtlasTexture
	# itself is shared across refreshes (built once in _build_layout);
	# we just retarget its source.
	if monster.sprite != null:
		_atlas.atlas = monster.sprite
		_sprite_rect.texture = _atlas
		if seen:
			_sprite_rect.material = null
			_sprite_rect.modulate = monster.tint
			_sprite_rect.visible = true
			_qmark_label.visible = false
		else:
			_sprite_rect.material = _silhouette_material
			_sprite_rect.modulate = Color.WHITE
			_sprite_rect.visible = true
			_qmark_label.visible = false
	else:
		# No source art — fall back to the "?" label.
		_sprite_rect.visible = false
		_qmark_label.visible = true

	if seen:
		_name_label.text = "%s — Tier %d" % [monster.display_name, monster.tier]
		_name_label.modulate = _PALETTE.INK_BLACK
	else:
		_name_label.text = "??? — Tier %d" % monster.tier
		_name_label.modulate = _PALETTE.SEPIA_MID

	# Count line: only meaningful once seen. Phrasing matches the prior
	# tests' fixtures so the regression suite keeps passing.
	if normal_count > 0:
		_count_label.text = "Caught × %d" % normal_count
	elif seen:
		_count_label.text = "Caught"
	else:
		_count_label.text = "—"

	# Slot pills — four states (seen | normal | shiny | variant).
	# Built once in _build_layout; refresh() just flips fill state +
	# (when colorblind_mode is on) the redundant ✓/· suffix.
	_update_pill(_pill_seen, "◇", seen, _PALETTE.SAGE_GREEN)
	_update_pill(_pill_normal, "✦", normal_count > 0, _PALETTE.BRASS_ACCENT)
	_update_pill(_pill_shiny, "✧", shiny_count > 0, _PALETTE.BLOOD_RUBY)
	_update_pill(_pill_variant, "⬢", variant_owned, _PALETTE.DUSK_BLUE)

	# Perfected = all four slots filled. Border tint is overridden on
	# the panel via a StyleBoxFlat copy so the change is per-card,
	# not theme-wide.
	var perfected: bool = seen and normal_count > 0 and shiny_count > 0 and variant_owned
	_apply_perfected_border(perfected)


func _band_color_for_tier(tier: int) -> Color:
	# Integer division by design: tiers 1-5 → band 0, 6-10 → 1, etc.
	@warning_ignore("integer_division")
	var band: int = clamp((tier - 1) / 5, 0, _BAND_COLORS.size() - 1)
	return _BAND_COLORS[band]


## Returns the LOCKED/SEEN/CAPTURED/PERFECTED state given the monster
## and current GameState. Public so tests can inspect the state machine
## without scraping label text.
func slot_state() -> int:
	if monster == null:
		return SlotState.LOCKED
	var key: String = String(monster.id)
	var entry: Dictionary = GameState.monsters_caught.get(key, {})
	var normal_count: int = int(entry.get("normal", 0))
	var shiny_count: int = int(entry.get("shiny", 0))
	var seen: bool = normal_count > 0 or shiny_count > 0
	var pet_id: String = String(monster.pet.id) if monster.pet != null else ""
	var variant_owned: bool = pet_id != "" and GameState.pet_variants_owned.has(pet_id)
	if not seen:
		return SlotState.LOCKED
	if shiny_count > 0 and variant_owned:
		return SlotState.PERFECTED
	if normal_count > 0:
		return SlotState.CAPTURED
	return SlotState.SEEN


## v0.13.6 — split into "build once" (this) and "update existing"
## (`_update_pill`). The hot path uses _update_pill so refreshes
## don't allocate Labels or thrash the scene tree.
func _build_pill(glyph: String, color: Color, hint: String) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", UiScale.size(18))
	label.tooltip_text = hint
	# Initial unfilled state — refresh() will set the real state
	# the first time it runs.
	_update_pill(label, glyph, false, color)
	return label


func _update_pill(label: Label, glyph: String, filled: bool, color: Color) -> void:
	# Phase 12b colorblind mode: append a redundant shape token (✓ for
	# filled, · for unfilled) so the filled/unfilled state is readable
	# without distinguishing the modulate color from the dim outline.
	# Defaults off — only colorblind_mode users see the suffix.
	if Settings.colorblind_mode:
		label.text = "%s%s" % [glyph, "✓" if filled else "·"]
	else:
		label.text = glyph
	label.modulate = color if filled else Color(0.55, 0.5, 0.4, 0.45)


## Override the panel's StyleBox per-card so the perfected border
## colour change doesn't leak back into the theme.
func _apply_perfected_border(perfected: bool) -> void:
	if not perfected:
		# Drop any per-card override so the theme StyleBox shows through.
		remove_theme_stylebox_override("panel")
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = _PALETTE.PARCHMENT
	sb.border_color = _PALETTE.BRASS_ACCENT  # gold-ish brass
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_right = 4
	sb.corner_radius_bottom_left = 4
	sb.content_margin_left = 8.0
	sb.content_margin_top = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_bottom = 8.0
	add_theme_stylebox_override("panel", sb)


# Tap detection — gui_input is enough for both mouse and touch events
# on a Control with mouse_filter = STOP.
func _gui_input(event: InputEvent) -> void:
	var is_tap: bool = false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		is_tap = true
	elif event is InputEventScreenTouch and event.pressed:
		is_tap = true
	if not is_tap or monster == null:
		return
	accept_event()
	card_tapped.emit(monster.id)
