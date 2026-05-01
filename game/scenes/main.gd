## Main scene: load save, compute offline progress, set up tabbed UI,
## save on quit. Replaces the Phase 0 placeholder.
extends Control

const _CURRENCY_BAR := preload("res://game/scenes/ui/currency_bar.tscn")
const _CATCHING_VIEW := preload("res://game/scenes/catching/catching_view.tscn")
const _BATTLE_VIEW := preload("res://game/scenes/battle/battle_view.tscn")
const _INVENTORY_PANEL := preload("res://game/scenes/ui/inventory_panel.tscn")
const _NET_SHOP := preload("res://game/scenes/ui/net_shop.tscn")
const _UPGRADE_TREE := preload("res://game/scenes/ui/upgrade_tree.tscn")
const _WELCOME_BACK_DIALOG := preload("res://game/scenes/ui/welcome_back_dialog.tscn")

var _welcome_back_dialog: AcceptDialog


func _ready() -> void:
	get_tree().root.close_requested.connect(_on_close_requested)
	ContentRegistry.ensure_loaded()
	_build_ui()
	var loaded: Dictionary = SaveManager.load_save()
	GameState.from_dict(loaded)
	_apply_offline_progress(loaded)
	_seed_default_net_if_needed()


func _build_ui() -> void:
	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_vbox.add_theme_constant_override("separation", 0)
	add_child(root_vbox)

	var currency_bar: Control = _CURRENCY_BAR.instantiate()
	currency_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(currency_bar)

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(tabs)

	var catch_tab: Control = _CATCHING_VIEW.instantiate()
	catch_tab.name = "Catch"
	tabs.add_child(catch_tab)

	var battle_tab: Control = _BATTLE_VIEW.instantiate()
	battle_tab.name = "Battle"
	tabs.add_child(battle_tab)

	var inventory_tab: Control = _INVENTORY_PANEL.instantiate()
	inventory_tab.name = "Inventory"
	tabs.add_child(inventory_tab)

	var shop_tab: Control = _NET_SHOP.instantiate()
	shop_tab.name = "Shop"
	tabs.add_child(shop_tab)

	var upgrades_tab: Control = _UPGRADE_TREE.instantiate()
	upgrades_tab.name = "Upgrades"
	tabs.add_child(upgrades_tab)


func _seed_default_net_if_needed() -> void:
	# Phase 1 first-launch QoL: if no nets are owned and no gold has been earned,
	# the player can't yet afford the basic net. We don't auto-grant — taps work
	# without a net. The net shop is reachable from the Shop tab.
	pass


func _apply_offline_progress(loaded: Dictionary) -> void:
	if loaded.is_empty():
		return
	var last_saved_unix: int = int(loaded.get("last_saved_unix", 0))
	if last_saved_unix <= 0:
		return
	var offline_cap_mult: float = GameState.multiplier(&"offline_cap")
	var cap: float = OfflineProgressSystem.DEFAULT_CAP_SECONDS * offline_cap_mult
	var elapsed: float = TimeManager.compute_offline_elapsed(last_saved_unix, cap)
	if elapsed <= 60.0:
		return  # Don't pop the dialog for sub-minute trips.
	var net_id_str: String = String(GameState.active_net)
	if net_id_str == "":
		return
	var net := ContentRegistry.net(StringName(net_id_str))
	if net == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var summary := OfflineProgressSystem.compute(
			ContentRegistry.monsters(),
			net,
			GameState.current_max_tier,
			elapsed,
			rng,
			offline_cap_mult,
			GameState.multiplier(&"auto_speed"),
			GameState.multiplier(&"drop_amount"),
			GameState.multiplier(&"gold_mult"),
			GameState.multiplier(&"shiny_rate"))
	EventBus.offline_progress_calculated.emit(summary)
	_show_welcome_back(summary)


func _show_welcome_back(summary: Dictionary) -> void:
	_welcome_back_dialog = _WELCOME_BACK_DIALOG.instantiate()
	add_child(_welcome_back_dialog)
	_welcome_back_dialog.claimed.connect(_on_welcome_back_claimed)
	_welcome_back_dialog.show_summary(summary)


func _on_welcome_back_claimed(summary: Dictionary) -> void:
	# Apply the offline rewards now that the player has acknowledged them.
	var gold: BigNumber = summary.get("gold_gained", BigNumber.zero())
	GameState.add_gold(gold)
	for item_id_str in summary.get("items_gained", {}).keys():
		var amount: int = int(summary["items_gained"][item_id_str])
		GameState.add_item(StringName(item_id_str), amount)
	for monster_id_str in summary.get("catches_by_species", {}).keys():
		var entry: Dictionary = summary["catches_by_species"][monster_id_str]
		for i in int(entry.get("normal", 0)):
			GameState.record_catch(StringName(monster_id_str), false, "offline")
		for i in int(entry.get("shiny", 0)):
			GameState.record_catch(StringName(monster_id_str), true, "offline")
	GameState.ledger["total_offline_seconds_credited"] = int(GameState.ledger["total_offline_seconds_credited"]) + int(summary.get("seconds", 0))


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_F2:
			Settings.debug_fast_pets = not Settings.debug_fast_pets
			print("[debug] FAST_PETS = %s (lowers tier threshold to 2 + forces variants when on)" % Settings.debug_fast_pets)
			get_viewport().set_input_as_handled()


func _on_close_requested() -> void:
	SaveManager.save(GameState.to_dict())
	get_tree().quit()
