## List of nets the player can buy. Each card shows name, description, cost,
## and a Buy / Equip button. Refreshes on currency change and game load.
##
## Phase 12a: nets the player doesn't yet own and can afford show a
## stat-delta line vs the currently-equipped net (e.g.
## "+1 spawn_max · +0.3 catches/s · targets tier 2"). Helps the
## player decide whether the upgrade is worth the gold without
## comparing two screens of stats by hand.
extends PanelContainer

const _PALETTE := preload("res://game/resources/palette_colors.gd")

var _list: VBoxContainer

# v0.13.6 — visibility-gated refresh (currency_changed fires per caught tap).
var refresh_count: int = 0
var _dirty: bool = false


func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_list)

	visibility_changed.connect(_on_visibility_changed)
	EventBus.currency_changed.connect(_on_currency_changed)
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


func _on_currency_changed(_currency_id: String, _new_value: Variant) -> void:
	_mark_dirty_or_refresh()


func _refresh() -> void:
	if not is_instance_valid(_list):
		return
	refresh_count += 1
	for child in _list.get_children():
		child.queue_free()
	for net_res in ContentRegistry.nets():
		_list.add_child(_build_net_card(net_res))


func _build_net_card(net_res: NetResource) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	var name_label := Label.new()
	name_label.text = net_res.display_name
	name_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = net_res.description
	desc_label.modulate = Color(0.85, 0.85, 0.85)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(desc_label)

	# Phase 12a stat-delta line. Only shown for nets the player
	# doesn't own (no point comparing equipped to itself). Hidden when
	# there's no equipped net to compare against.
	var delta_text := _format_stat_delta(net_res)
	if delta_text != "":
		var delta_label := RichTextLabel.new()
		delta_label.bbcode_enabled = true
		delta_label.fit_content = true
		delta_label.text = delta_text
		delta_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(delta_label)

	var hbox := HBoxContainer.new()
	vbox.add_child(hbox)

	var owned: bool = GameState.nets_owned.has(String(net_res.id))
	var equipped: bool = GameState.active_net == String(net_res.id)
	var cost := BigNumber.from_dict(net_res.cost)

	var cost_label := Label.new()
	cost_label.text = "Cost: %s g" % cost.format() if not owned else "Owned"
	cost_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(cost_label)

	var btn := Button.new()
	if equipped:
		btn.text = "Equipped"
		btn.disabled = true
	elif owned:
		btn.text = "Equip"
	else:
		btn.text = "Buy"
		btn.disabled = GameState.current_gold().lt(cost)
	btn.pressed.connect(func() -> void: _on_net_button_pressed(net_res))
	hbox.add_child(btn)

	return card


func _on_net_button_pressed(net_res: NetResource) -> void:
	if GameState.purchase_net(net_res):
		_refresh()


## Phase 12a — stat-delta string vs the currently equipped net.
## Returns "" when there's nothing meaningful to compare (e.g. when
## the candidate IS the equipped net, or no net is equipped at all,
## or the candidate is already owned). Positive deltas tint sage
## green, negative tint blood ruby; this is the canonical idle-game
## "+1 / -0.3" preview pattern.
func _format_stat_delta(net_res: NetResource) -> String:
	if GameState.nets_owned.has(String(net_res.id)):
		return ""
	var active_id: String = String(GameState.active_net)
	if active_id == "":
		return ""
	var active: NetResource = ContentRegistry.net(StringName(active_id))
	if active == null or active == net_res:
		return ""

	var parts: Array[String] = []
	var spawn_diff: int = int(net_res.spawn_max) - int(active.spawn_max)
	if spawn_diff != 0:
		parts.append(_signed_part("spawn_max", spawn_diff))
	var rate_diff: float = float(net_res.catches_per_second) - float(active.catches_per_second)
	if absf(rate_diff) > 0.0001:
		parts.append(_signed_float_part("catches/s", rate_diff))
	var tap_diff: float = float(net_res.catch_speed_multiplier) - float(active.catch_speed_multiplier)
	if absf(tap_diff) > 0.0001:
		parts.append(_signed_float_part("tap mult", tap_diff))
	# Tier coverage — surface a "targets tier N" hint if this net
	# unlocks a higher tier than the equipped net does. Drop the
	# detail line if the new net's coverage is a subset.
	var max_active_tier: int = _max_targeted_tier(active.targets_tiers)
	var max_new_tier: int = _max_targeted_tier(net_res.targets_tiers)
	if max_new_tier > max_active_tier:
		parts.append("[color=#%s]targets tier %d[/color]" % [
				_PALETTE.SAGE_GREEN.to_html(false),
				max_new_tier,
		])
	if parts.is_empty():
		return ""
	return "vs %s: %s" % [active.display_name, " · ".join(parts)]


func _signed_part(label: String, diff: int) -> String:
	var color: String = _PALETTE.SAGE_GREEN.to_html(false) if diff > 0 else _PALETTE.BLOOD_RUBY.to_html(false)
	var sign_str: String = "+" if diff > 0 else ""
	return "[color=#%s]%s%d %s[/color]" % [color, sign_str, diff, label]


func _signed_float_part(label: String, diff: float) -> String:
	var color: String = _PALETTE.SAGE_GREEN.to_html(false) if diff > 0.0 else _PALETTE.BLOOD_RUBY.to_html(false)
	var sign_str: String = "+" if diff > 0.0 else ""
	return "[color=#%s]%s%.2f %s[/color]" % [color, sign_str, diff, label]


func _max_targeted_tier(targets: Array) -> int:
	var max_tier: int = 0
	for t in targets:
		var ti: int = int(t)
		if ti > max_tier:
			max_tier = ti
	return max_tier
