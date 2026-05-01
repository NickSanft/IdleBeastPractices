## Live, in-memory game state. The save target.
##
## Mirrors the v1 save schema 1:1. Mutations are typically performed by systems;
## this class is a Dictionary-of-truth with helpers for round-trip serialization.
extends Node

# Currencies: gold is BigNumber dict {"m": float, "e": int}; rancher_points is plain int.
var currencies: Dictionary = {
	"gold": {"m": 0.0, "e": 0},
	"rancher_points": 0,
}

var inventory: Dictionary = {}                  # {item_id (String): count (int)}
var monsters_caught: Dictionary = {}            # {monster_id: {"normal": int, "shiny": int}}
var pets_owned: Array[String] = []
var pet_variants_owned: Array[String] = []
var nets_owned: Array[String] = []
var active_net: String = ""
var upgrades_purchased: Array[Dictionary] = []  # [{"id": StringName, "level": int}]
var current_max_tier: int = 1
var tiers_completed: Array[int] = []
var current_battle: Variant = null              # Dictionary or null
var prestige_count: int = 0

var ledger: Dictionary = {
	"total_catches": 0,
	"total_taps": 0,
	"total_shinies": 0,
	"session_count": 0,
	"total_play_seconds": 0,
	"total_offline_seconds_credited": 0,
	"prestige_count": 0,
	"first_launch_unix": 0,
	"peniber_quotes_seen": 0,
}

var narrator_state: Dictionary = {
	"lines_seen": {},
	"last_line_unix": 0,
}

# Populated from save on load; consulted by TimeManager for offline calc.
var last_saved_unix: int = 0
var session_id: String = ""


func to_dict() -> Dictionary:
	return {
		"version": SaveManager.CURRENT_VERSION,
		"last_saved_unix": last_saved_unix,
		"session_id": session_id,
		"currencies": currencies.duplicate(true),
		"inventory": inventory.duplicate(true),
		"monsters_caught": monsters_caught.duplicate(true),
		"pets_owned": pets_owned.duplicate(),
		"pet_variants_owned": pet_variants_owned.duplicate(),
		"nets_owned": nets_owned.duplicate(),
		"active_net": active_net,
		"upgrades_purchased": upgrades_purchased.duplicate(true),
		"current_max_tier": current_max_tier,
		"tiers_completed": tiers_completed.duplicate(),
		"current_battle": current_battle,
		"prestige_count": prestige_count,
		"ledger": ledger.duplicate(true),
		"narrator_state": narrator_state.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	_reset_to_defaults()
	if data.is_empty():
		_seed_first_launch()
		return
	last_saved_unix = int(data.get("last_saved_unix", 0))
	session_id = String(data.get("session_id", ""))
	currencies = data.get("currencies", currencies).duplicate(true)
	inventory = data.get("inventory", {}).duplicate(true)
	monsters_caught = data.get("monsters_caught", {}).duplicate(true)
	pets_owned = _to_string_array(data.get("pets_owned", []))
	pet_variants_owned = _to_string_array(data.get("pet_variants_owned", []))
	nets_owned = _to_string_array(data.get("nets_owned", []))
	active_net = String(data.get("active_net", ""))
	upgrades_purchased = _to_dict_array(data.get("upgrades_purchased", []))
	current_max_tier = int(data.get("current_max_tier", 1))
	tiers_completed = _to_int_array(data.get("tiers_completed", []))
	current_battle = data.get("current_battle", null)
	prestige_count = int(data.get("prestige_count", 0))
	ledger = data.get("ledger", ledger).duplicate(true)
	narrator_state = data.get("narrator_state", narrator_state).duplicate(true)


func _seed_first_launch() -> void:
	ledger["first_launch_unix"] = TimeManager.now_unix()


func _reset_to_defaults() -> void:
	currencies = {
		"gold": {"m": 0.0, "e": 0},
		"rancher_points": 0,
	}
	inventory = {}
	monsters_caught = {}
	pets_owned = []
	pet_variants_owned = []
	nets_owned = []
	active_net = ""
	upgrades_purchased = []
	current_max_tier = 1
	tiers_completed = []
	current_battle = null
	prestige_count = 0
	ledger = {
		"total_catches": 0,
		"total_taps": 0,
		"total_shinies": 0,
		"session_count": 0,
		"total_play_seconds": 0,
		"total_offline_seconds_credited": 0,
		"prestige_count": 0,
		"first_launch_unix": 0,
		"peniber_quotes_seen": 0,
	}
	narrator_state = {
		"lines_seen": {},
		"last_line_unix": 0,
	}
	last_saved_unix = 0
	session_id = ""


func _to_string_array(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if v is Array:
		for item in v:
			out.append(String(item))
	return out


func _to_int_array(v: Variant) -> Array[int]:
	var out: Array[int] = []
	if v is Array:
		for item in v:
			out.append(int(item))
	return out


func _to_dict_array(v: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if v is Array:
		for item in v:
			if item is Dictionary:
				out.append((item as Dictionary).duplicate(true))
	return out


# region — gameplay mutators
# Helpers used by Phase 1+ gameplay scenes. They mutate state and emit
# EventBus signals; tests bypass by calling the underlying fields directly.

func current_gold() -> BigNumber:
	return BigNumber.from_dict(currencies["gold"])


func current_rancher_points() -> int:
	return int(currencies["rancher_points"])


func add_gold(amount: BigNumber) -> void:
	if amount == null or amount.is_zero():
		return
	var current: BigNumber = current_gold()
	var new_total: BigNumber = current.add(amount)
	currencies["gold"] = new_total.to_dict()
	EventBus.currency_changed.emit("gold", new_total)


func try_spend_gold(amount: BigNumber) -> bool:
	if amount == null or amount.is_zero():
		return true
	var current: BigNumber = current_gold()
	if current.lt(amount):
		return false
	var new_total: BigNumber = current.subtract(amount)
	currencies["gold"] = new_total.to_dict()
	EventBus.currency_changed.emit("gold", new_total)
	return true


func add_rancher_points(amount: int, source: String = "") -> void:
	if amount <= 0:
		return
	currencies["rancher_points"] = int(currencies["rancher_points"]) + amount
	EventBus.currency_changed.emit("rancher_points", currencies["rancher_points"])
	EventBus.rancher_points_earned.emit(amount, source)


func add_item(item_id: StringName, amount: int) -> void:
	if amount <= 0:
		return
	var key: String = String(item_id)
	var existing: int = int(inventory.get(key, 0))
	inventory[key] = existing + amount
	EventBus.item_gained.emit(key, amount)


func record_tap() -> void:
	ledger["total_taps"] = int(ledger["total_taps"]) + 1


func record_catch(monster_id: StringName, is_shiny: bool, _source: String) -> void:
	# `_source` reserved for per-source counters (tap vs net) post-Phase-1.
	var key: String = String(monster_id)
	var seen_before: bool = monsters_caught.has(key)
	if not seen_before:
		monsters_caught[key] = {"normal": 0, "shiny": 0}
		EventBus.first_catch_of_species.emit(key)
	if is_shiny:
		var prior_shinies: int = int(monsters_caught[key].get("shiny", 0))
		monsters_caught[key]["shiny"] = prior_shinies + 1
		ledger["total_shinies"] = int(ledger["total_shinies"]) + 1
		if int(ledger["total_shinies"]) == 1:
			EventBus.first_shiny_caught.emit(key)
	else:
		var prior_normals: int = int(monsters_caught[key].get("normal", 0))
		monsters_caught[key]["normal"] = prior_normals + 1
	ledger["total_catches"] = int(ledger["total_catches"]) + 1


func purchase_net(net: NetResource) -> bool:
	if net == null:
		return false
	var net_id: String = String(net.id)
	if nets_owned.has(net_id):
		# Already owned; just equip.
		active_net = net_id
		return true
	var cost: BigNumber = BigNumber.from_dict(net.cost)
	if not try_spend_gold(cost):
		return false
	nets_owned.append(net_id)
	active_net = net_id
	return true


func get_active_net_id() -> String:
	return active_net


func has_caught_species(monster_id: StringName) -> bool:
	return monsters_caught.has(String(monster_id))


func total_catches() -> int:
	return int(ledger["total_catches"])

# endregion
