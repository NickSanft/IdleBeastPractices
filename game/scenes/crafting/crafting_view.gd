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

## v0.14.4 (Phase 13c.4) — _list is now a GridContainer that
## reflows from 1 to N columns based on the view's own width. A
## recipe card's minimum comfortable width is ~320 design dp, so:
##
##   - Phone portrait (~720 dp wide): 2 cols
##   - Phone landscape (~1200 dp wide after rail): 3 cols
##   - Tablet portrait (~900 dp): 2 cols
##   - Tablet landscape / foldable open (~1700+ dp): 5+ cols
var _list: GridContainer

const _RECIPE_CARD_MIN_DP := 320.0

# v0.13.6 — visibility-gated refresh. currency_changed and item_gained
# both fire per caught tap; full-rebuilding the recipe list while the
# crafting tab is hidden was a major contributor to the Android tap
# freeze. The cards repaint when the player actually opens the tab.
var refresh_count: int = 0
var _dirty: bool = false


func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = GridContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("h_separation", 12)
	_list.add_theme_constant_override("v_separation", 12)
	_list.columns = UiScale.columns(size.x, _RECIPE_CARD_MIN_DP)
	scroll.add_child(_list)

	resized.connect(_on_resized)
	visibility_changed.connect(_on_visibility_changed)
	EventBus.currency_changed.connect(_on_state_changed)
	EventBus.item_gained.connect(_on_state_changed_string_int)
	EventBus.item_spent.connect(_on_state_changed_string_int)
	EventBus.item_crafted.connect(_on_recipe_crafted)
	EventBus.tier_unlocked.connect(_on_tier_changed)
	EventBus.tier_completed.connect(_on_tier_changed)
	EventBus.game_loaded.connect(_mark_dirty_or_refresh)
	_refresh()


func _on_resized() -> void:
	if _list != null:
		_list.columns = UiScale.columns(size.x, _RECIPE_CARD_MIN_DP)


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


func _on_state_changed(_id: String, _v: Variant) -> void:
	_mark_dirty_or_refresh()


func _on_state_changed_string_int(_id: String, _amount: int) -> void:
	_mark_dirty_or_refresh()


func _on_recipe_crafted(_recipe_id: String, _output_id: String) -> void:
	_mark_dirty_or_refresh()


func _on_tier_changed(_t: int) -> void:
	_mark_dirty_or_refresh()


func _refresh() -> void:
	if not is_instance_valid(_list):
		return
	refresh_count += 1
	for child in _list.get_children():
		child.queue_free()
	var visible_count: int = 0
	var next_locked_tier: int = -1
	for r in ContentRegistry.recipes():
		# Hide recipes whose tier requirement is more than 1 above current
		# max — the player shouldn't see things that don't yet exist as content.
		if int(r.tier_required) > int(GameState.current_max_tier) + 1:
			# Track the smallest tier_required among hidden recipes so
			# the empty-state hint can tell the player when the next
			# unlock arrives.
			if next_locked_tier < 0 or int(r.tier_required) < next_locked_tier:
				next_locked_tier = int(r.tier_required)
			continue
		_list.add_child(_build_recipe_card(r))
		visible_count += 1
	# Phase 11d: empty-state hint when no recipes are visible. The
	# crafting tab should never feel like an empty void; tell the
	# player when their next unlock arrives.
	if visible_count == 0:
		_list.add_child(_build_empty_state_card(next_locked_tier))


## Phase 11d empty-state card. Shown when no recipes are currently
## available to craft (typically pre-tier-1-completion). Tells the
## player when their next recipe unlocks and offers a tab-jump back
## to the catch view so they can grind toward it.
func _build_empty_state_card(next_locked_tier: int) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margins := MarginContainer.new()
	margins.add_theme_constant_override("margin_left", 16)
	margins.add_theme_constant_override("margin_right", 16)
	margins.add_theme_constant_override("margin_top", 16)
	margins.add_theme_constant_override("margin_bottom", 16)
	card.add_child(margins)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margins.add_child(vbox)

	var heading := Label.new()
	heading.text = "Nothing crafted here yet"
	heading.add_theme_font_size_override("font_size", UiScale.size(18))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(heading)

	var hint := Label.new()
	if next_locked_tier > 0:
		hint.text = "Recipes start unlocking at tier %d. Catch monsters to advance." % next_locked_tier
	else:
		hint.text = "Recipes will unlock as you progress through tiers."
	hint.modulate = Color(0.85, 0.85, 0.85)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	var to_catch_btn := Button.new()
	to_catch_btn.text = "Go to Catch"
	to_catch_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	to_catch_btn.pressed.connect(func() -> void:
		EventBus.tab_switch_requested.emit("Catch"))
	vbox.add_child(to_catch_btn)
	return card


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
	name_label.add_theme_font_size_override("font_size", UiScale.size(20))
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

	# Phase 12a: bulk crafting buttons. Craft 1 / 5 / Max — Max
	# computes the cap from material + gold floors at click time.
	# Disabled buttons grey out via the theme but keep their layout
	# slot so the row width stays consistent across recipe states.
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)
	hbox.add_child(btn_row)

	var btn_one := Button.new()
	btn_one.text = "Craft"
	btn_one.disabled = not bool(status["can"])
	btn_one.pressed.connect(func() -> void: _on_craft_n_pressed(recipe, 1))
	btn_row.add_child(btn_one)

	var btn_five := Button.new()
	btn_five.text = "x5"
	btn_five.disabled = not bool(status["can"])
	btn_five.pressed.connect(func() -> void: _on_craft_n_pressed(recipe, 5))
	btn_row.add_child(btn_five)

	var btn_max := Button.new()
	btn_max.text = "Max"
	btn_max.disabled = not bool(status["can"])
	btn_max.pressed.connect(func() -> void:
		var cap: int = _max_craftable(recipe)
		if cap > 0:
			_on_craft_n_pressed(recipe, cap))
	btn_row.add_child(btn_max)
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
	# Backwards-compat shim — still exists in case other call sites
	# reference it. New callers go through _on_craft_n_pressed.
	_on_craft_n_pressed(recipe, 1)


## Phase 12a — bulk craft. Loops `try_craft` up to `count` times,
## stopping early if a craft fails (insufficient materials/gold).
## A single `_refresh` at the end keeps the UI from flickering
## through N intermediate states.
func _on_craft_n_pressed(recipe: CraftingRecipeResource, count: int) -> void:
	var crafted: int = 0
	for i in count:
		var result: Dictionary = GameState.try_craft(recipe)
		if not bool(result["success"]):
			if crafted == 0:
				print("[craft] failed: %s reason=%s" % [String(recipe.id), String(result["reason"])])
			break
		crafted += 1
	if crafted > 1:
		print("[craft] bulk: %s × %d" % [String(recipe.id), crafted])
	_refresh()


## Returns the max number of times this recipe can be crafted given
## current materials + gold. Used by the "Max" button to compute the
## cap once at click time. Returns 0 if any material or gold floor is
## unmet.
func _max_craftable(recipe: CraftingRecipeResource) -> int:
	# `cap` named to avoid shadowing the global `floor()` builtin.
	var cap: int = -1
	for entry in recipe.inputs:
		if not (entry is Dictionary):
			continue
		var item_id_str: String = String(entry.get("item_id", ""))
		var needed: int = int(entry.get("amount", 0))
		if item_id_str == "" or needed <= 0:
			continue
		var have: int = int(GameState.inventory.get(item_id_str, 0))
		@warning_ignore("integer_division")
		var support: int = have / needed
		if cap < 0 or support < cap:
			cap = support
	# Gold cap — divide current gold by recipe's gold cost.
	var cost := BigNumber.from_dict(recipe.gold_cost)
	if not cost.is_zero():
		var have_g: BigNumber = GameState.current_gold()
		# BigNumber doesn't support div-to-int directly; round-trip via
		# float. Safe for typical gold scales (< 1e15) which the bulk-
		# crafting use case lives well within.
		var gold_support: int = int(floor(have_g.divide(cost).to_float()))
		if cap < 0 or gold_support < cap:
			cap = gold_support
	if cap < 0:
		return 0
	return max(0, cap)
