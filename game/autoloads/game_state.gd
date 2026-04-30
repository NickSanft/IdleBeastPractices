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
