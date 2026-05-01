## Crafting tab: list of recipes, with cost preview, prereq state, and Craft
## button. Hides recipes whose tier_required is unreachable.
extends PanelContainer

const _REASON_LABELS := {
	"ok": "Ready",
	"tier_locked": "Tier locked",
	"missing_prereq": "Missing prerequisite recipe",
	"insufficient_input": "Need more materials",
	"insufficient_gold": "Need more gold",
	"no_output": "Recipe broken",
}

var _list: VBoxContainer


func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_list)

	EventBus.currency_changed.connect(_on_state_changed)
	EventBus.item_gained.connect(_on_state_changed_string_int)
	EventBus.item_spent.connect(_on_state_changed_string_int)
	EventBus.item_crafted.connect(_on_recipe_crafted)
	EventBus.tier_unlocked.connect(_on_tier_changed)
	EventBus.tier_completed.connect(_on_tier_changed)
	EventBus.game_loaded.connect(_refresh)
	_refresh()


func _on_state_changed(_id: String, _v: Variant) -> void:
	_refresh()


func _on_state_changed_string_int(_id: String, _amount: int) -> void:
	_refresh()


func _on_recipe_crafted(_recipe_id: String, _output_id: String) -> void:
	_refresh()


func _on_tier_changed(_t: int) -> void:
	_refresh()


func _refresh() -> void:
	if not is_instance_valid(_list):
		return
	for child in _list.get_children():
		child.queue_free()
	for r in ContentRegistry.recipes():
		# Hide recipes whose tier requirement is more than 1 above current
		# max — the player shouldn't see things that don't yet exist as content.
		if int(r.tier_required) > int(GameState.current_max_tier) + 1:
			continue
		_list.add_child(_build_recipe_card(r))


func _build_recipe_card(recipe: CraftingRecipeResource) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.clip_contents = true
	var margins := MarginContainer.new()
	margins.add_theme_constant_override("margin_left", 10)
	margins.add_theme_constant_override("margin_right", 10)
	margins.add_theme_constant_override("margin_top", 8)
	margins.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margins)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margins.add_child(vbox)

	var name_label := Label.new()
	name_label.text = recipe.display_name
	name_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = recipe.description
	desc_label.modulate = Color(0.85, 0.85, 0.85)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(desc_label)

	# Inputs / cost line — RichTextLabel so BBCode color tags render.
	var inputs_label := RichTextLabel.new()
	inputs_label.bbcode_enabled = true
	inputs_label.fit_content = true
	inputs_label.text = _format_inputs_line(recipe)
	inputs_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(inputs_label)

	var hbox := HBoxContainer.new()
	vbox.add_child(hbox)

	var status := CraftingSystem.can_craft(
			recipe,
			GameState.inventory,
			GameState.current_gold(),
			GameState.current_max_tier,
			GameState.recipes_crafted)
	var status_label := Label.new()
	status_label.text = String(_REASON_LABELS.get(status["reason"], status["reason"]))
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(status_label)

	var btn := Button.new()
	btn.text = "Craft"
	btn.disabled = not bool(status["can"])
	btn.pressed.connect(func() -> void: _on_craft_pressed(recipe))
	hbox.add_child(btn)
	return card


func _format_inputs_line(recipe: CraftingRecipeResource) -> String:
	var parts: Array[String] = []
	for entry in recipe.inputs:
		if not (entry is Dictionary):
			continue
		var item_id_str: String = String(entry.get("item_id", ""))
		var needed: int = int(entry.get("amount", 0))
		if item_id_str == "" or needed <= 0:
			continue
		var item_res := ContentRegistry.item(StringName(item_id_str))
		var item_name: String = item_res.display_name if item_res != null else item_id_str
		var have: int = int(GameState.inventory.get(item_id_str, 0))
		var color: String = "#aaffaa" if have >= needed else "#ffaaaa"
		parts.append("%s [color=%s]%d[/color]/%d" % [item_name, color, have, needed])
	var cost := BigNumber.from_dict(recipe.gold_cost)
	if not cost.is_zero():
		var have_g: BigNumber = GameState.current_gold()
		var color: String = "#aaffaa" if have_g.gte(cost) else "#ffaaaa"
		parts.append("[color=%s]%s g[/color]" % [color, cost.format()])
	if parts.is_empty():
		return "(no cost)"
	return "Need: " + ", ".join(parts)


func _on_craft_pressed(recipe: CraftingRecipeResource) -> void:
	var result: Dictionary = GameState.try_craft(recipe)
	# Phase 5 polish will toast the result; for now refresh visually.
	if not bool(result["success"]):
		print("[craft] failed: %s reason=%s" % [String(recipe.id), String(result["reason"])])
	_refresh()
