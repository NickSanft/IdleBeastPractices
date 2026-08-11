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

# Phase 3 prestige bookkeeping. Resets on prestige; PrestigeSystem reads it
# to compute RP gain. BigNumber dict shape so very-late-game runs don't
# overflow.
var total_gold_earned_this_run: Dictionary = {"m": 0.0, "e": 0}

var inventory: Dictionary = {}                  # {item_id (String): count (int)}
var monsters_caught: Dictionary = {}            # {monster_id: {"normal": int, "shiny": int}}
var pets_owned: Array[String] = []
var pet_variants_owned: Array[String] = []
## Phase 12e — equipment slots per owned pet.
##   pet_equipment[pet_id_str] = {"head": id_str, "body": id_str, "trinket": id_str}
## Missing slots default to "" (no equip). Persisted via save_v3.
## owned_equipment is the global stash of crafted-but-not-equipped
## items + items currently equipped (the equipped ones are duplicated
## here so unequipping doesn't need to mint anything from thin air).
var pet_equipment: Dictionary = {}
var owned_equipment: Array[String] = []
## Phase 12e — best-RP-this-run tracker, frozen at prestige time so
## the prestige_view's "vs your best" comparison has a value.
var best_rp_at_prestige: int = 0

## Phase 12f — achievement ids the player has unlocked. Persisted
## via save_v4. The Achievements autoload consults this dict to skip
## re-firing already-unlocked achievements.
var achievements_unlocked: Dictionary = {}
## Phase 12g — three-tier concurrent quest log.
## active_quests is indexed by slot int (0 SHORT, 1 MEDIUM, 2 LONG).
## Each slot stores either an empty string (no quest active) or the
## quest id. quests_completed is a set-style dict so non-repeatable
## quests don't get re-picked from the pool.
var active_quests: Dictionary = {0: "", 1: "", 2: ""}
var quests_completed: Dictionary = {}
var nets_owned: Array[String] = []
var active_net: String = ""
var upgrades_purchased: Array[Dictionary] = []  # [{"id": StringName, "level": int}]
var current_max_tier: int = 1
var tiers_completed: Array[int] = []
## v0.15.12 — persistent ledger of tiers that have EVER paid out their
## one-time completion RP bonus. Survives prestige (unlike tiers_completed,
## which resets so the player re-climbs). Without this, every prestige
## would re-grant the tier RP on re-completion (monsters_caught is kept,
## so tiers re-complete on the first catch) — a free RP farm.
var tiers_rp_awarded: Array[int] = []
## v0.15.14 — daily-login retention. `daily_login_last_day` is the LOCAL
## calendar-day index (DailyLoginSystem.local_day_index) of the most recent
## claim; 0 means never claimed. `daily_login_streak` is the current
## consecutive-day count. Both are account-level meta: they survive prestige
## (like achievements / tiers_rp_awarded) and MAX-merge on cloud conflict.
var daily_login_last_day: int = 0
var daily_login_streak: int = 0
## v0.15.15 — daily-resetting quest set (managed by the DailyQuests autoload).
## `daily_quests_reset_day` is the LOCAL day index of the current daily period;
## `daily_quests_active` is the day's chosen quest ids; `daily_quest_baselines`
## snapshots each tracked ledger counter at day-start (progress = current −
## baseline); `daily_quests_done` is the set completed today; and
## `daily_quests_bonus_claimed` gates the once-a-day complete-all RP bonus.
## All survive prestige (the ledger they delta against does too).
var daily_quests_reset_day: int = 0
## Untyped Array (not Array[String]) so DailyQuestsSystem.pick_for_day()'s
## generic Array result + test literals assign cleanly; elements are quest-id
## strings, always read via String(x).
var daily_quests_active: Array = []
var daily_quest_baselines: Dictionary = {}
var daily_quests_done: Dictionary = {}
var daily_quests_bonus_claimed: bool = false
var current_battle: Variant = null              # Dictionary or null
var prestige_count: int = 0
var recipes_crafted: Array[String] = []          # ids of recipes ever crafted (additive across prestiges)

# Transient (NOT persisted): rewarded-video bonus that doubles drop_amount on
# the next N catches. Set by AdsManager → REWARD_DROPS_2X_NEXT_10. Decrements
# in catching_view._apply_catch_rewards.
var transient_drops_2x_remaining: int = 0

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
		"total_gold_earned_this_run": total_gold_earned_this_run.duplicate(true),
		"inventory": inventory.duplicate(true),
		"monsters_caught": monsters_caught.duplicate(true),
		"pets_owned": pets_owned.duplicate(),
		"pet_variants_owned": pet_variants_owned.duplicate(),
		"nets_owned": nets_owned.duplicate(),
		"active_net": active_net,
		"upgrades_purchased": upgrades_purchased.duplicate(true),
		"current_max_tier": current_max_tier,
		"tiers_completed": tiers_completed.duplicate(),
		"tiers_rp_awarded": tiers_rp_awarded.duplicate(),
		"daily_login_last_day": daily_login_last_day,
		"daily_login_streak": daily_login_streak,
		"daily_quests_reset_day": daily_quests_reset_day,
		"daily_quests_active": daily_quests_active.duplicate(),
		"daily_quest_baselines": daily_quest_baselines.duplicate(true),
		"daily_quests_done": daily_quests_done.duplicate(true),
		"daily_quests_bonus_claimed": daily_quests_bonus_claimed,
		"current_battle": current_battle,
		"prestige_count": prestige_count,
		"recipes_crafted": recipes_crafted.duplicate(),
		"ledger": ledger.duplicate(true),
		"narrator_state": narrator_state.duplicate(true),
		"pet_equipment": pet_equipment.duplicate(true),
		"owned_equipment": owned_equipment.duplicate(),
		"best_rp_at_prestige": best_rp_at_prestige,
		"achievements_unlocked": achievements_unlocked.duplicate(true),
		"active_quests": active_quests.duplicate(true),
		"quests_completed": quests_completed.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	_reset_to_defaults()
	if data.is_empty():
		_seed_first_launch()
		return
	last_saved_unix = int(data.get("last_saved_unix", 0))
	session_id = String(data.get("session_id", ""))
	currencies = data.get("currencies", currencies).duplicate(true)
	total_gold_earned_this_run = (data.get("total_gold_earned_this_run", {"m": 0.0, "e": 0}) as Dictionary).duplicate(true)
	inventory = data.get("inventory", {}).duplicate(true)
	monsters_caught = data.get("monsters_caught", {}).duplicate(true)
	pets_owned = _to_string_array(data.get("pets_owned", []))
	pet_variants_owned = _to_string_array(data.get("pet_variants_owned", []))
	nets_owned = _to_string_array(data.get("nets_owned", []))
	active_net = String(data.get("active_net", ""))
	upgrades_purchased = _to_dict_array(data.get("upgrades_purchased", []))
	current_max_tier = int(data.get("current_max_tier", 1))
	tiers_completed = _to_int_array(data.get("tiers_completed", []))
	tiers_rp_awarded = _to_int_array(data.get("tiers_rp_awarded", []))
	daily_login_last_day = int(data.get("daily_login_last_day", 0))
	daily_login_streak = int(data.get("daily_login_streak", 0))
	daily_quests_reset_day = int(data.get("daily_quests_reset_day", 0))
	daily_quests_active = _to_string_array(data.get("daily_quests_active", []))
	daily_quest_baselines = (data.get("daily_quest_baselines", {}) as Dictionary).duplicate(true)
	daily_quests_done = (data.get("daily_quests_done", {}) as Dictionary).duplicate(true)
	daily_quests_bonus_claimed = bool(data.get("daily_quests_bonus_claimed", false))
	current_battle = data.get("current_battle", null)
	# Heal saves written before prestige_count joined the prestige keep-list.
	# Those saves have a root field pinned at 1 while ledger["prestige_count"]
	# holds the true lifetime total, so take the max: monotonic (the ledger can
	# only ever be >= the root field), retroactive for existing players, and a
	# no-op for saves written after the fix. Read the ledger straight out of
	# `data` — the `ledger` member is not assigned until below.
	var saved_ledger: Dictionary = data.get("ledger", {})
	prestige_count = maxi(
		int(data.get("prestige_count", 0)),
		int(saved_ledger.get("prestige_count", 0)))
	recipes_crafted = _to_string_array(data.get("recipes_crafted", []))
	ledger = data.get("ledger", ledger).duplicate(true)
	narrator_state = data.get("narrator_state", narrator_state).duplicate(true)
	# Phase 12e — equipment + best-run tracker. Default to empty when
	# loading a v2 save (the save_migrations chain takes care of
	# version-bumping; this just supplies field-level defaults).
	pet_equipment = (data.get("pet_equipment", {}) as Dictionary).duplicate(true)
	owned_equipment = _to_string_array(data.get("owned_equipment", []))
	best_rp_at_prestige = int(data.get("best_rp_at_prestige", 0))
	achievements_unlocked = (data.get("achievements_unlocked", {}) as Dictionary).duplicate(true)
	active_quests = _normalize_active_quests(data.get("active_quests", {}))
	quests_completed = (data.get("quests_completed", {}) as Dictionary).duplicate(true)


## Save format stores active_quests with string keys ("0","1","2")
## because JSON can't represent int-keyed dicts. Normalize back to
## int keys for in-memory use, ensuring all three slots are present.
func _normalize_active_quests(raw: Variant) -> Dictionary:
	var out: Dictionary = {0: "", 1: "", 2: ""}
	if raw is Dictionary:
		for key in (raw as Dictionary).keys():
			var slot: int = int(key)
			if slot >= 0 and slot <= 2:
				out[slot] = String(raw[key])
	return out


func _seed_first_launch() -> void:
	ledger["first_launch_unix"] = TimeManager.now_unix()


func _reset_to_defaults() -> void:
	currencies = {
		"gold": {"m": 0.0, "e": 0},
		"rancher_points": 0,
	}
	total_gold_earned_this_run = {"m": 0.0, "e": 0}
	inventory = {}
	monsters_caught = {}
	pets_owned = []
	pet_variants_owned = []
	nets_owned = []
	active_net = ""
	upgrades_purchased = []
	current_max_tier = 1
	tiers_completed = []
	tiers_rp_awarded = []
	daily_login_last_day = 0
	daily_login_streak = 0
	daily_quests_reset_day = 0
	daily_quests_active = []
	daily_quest_baselines = {}
	daily_quests_done = {}
	daily_quests_bonus_claimed = false
	current_battle = null
	prestige_count = 0
	recipes_crafted = []
	transient_drops_2x_remaining = 0
	pet_equipment = {}
	owned_equipment = []
	best_rp_at_prestige = 0
	achievements_unlocked = {}
	active_quests = {0: "", 1: "", 2: ""}
	quests_completed = {}
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
	# Track per-run earnings for prestige RP. Doesn't decrement on spend.
	var earned_this_run: BigNumber = BigNumber.from_dict(total_gold_earned_this_run).add(amount)
	total_gold_earned_this_run = earned_this_run.to_dict()
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


# Pet ownership

func add_pet(pet_id: StringName, is_variant: bool) -> bool:
	# Variants imply the base pet is also owned: pet_variants_owned is a
	# *subset* of pets_owned representing which pets have unlocked their
	# variant sprite. Without this, debug_fast_pets (which forces every
	# variant roll true) would route every drop into the variants list and
	# leave the battle roster empty. Returns true if any new entry landed.
	var key: String = String(pet_id)
	var newly_added: bool = false
	if not pets_owned.has(key):
		pets_owned.append(key)
		newly_added = true
	if is_variant and not pet_variants_owned.has(key):
		pet_variants_owned.append(key)
		newly_added = true
	if newly_added:
		EventBus.pet_acquired.emit(key, is_variant)
	return newly_added


func owned_pets() -> Array[PetResource]:
	var out: Array[PetResource] = []
	for pid in pets_owned:
		var p := ContentRegistry.pet(StringName(pid))
		if p != null:
			out.append(p)
	return out


## Saves predating the Phase 3 v1→v2 migration (or pinched by an earlier code
## path that mutated currencies.gold without going through add_gold) can land
## with `total_gold_earned_this_run < currencies.gold`. That's impossible
## under the live invariant: gross earnings must always be ≥ current balance
## because spending decrements only `currencies.gold`, never the tracker.
## Snap the tracker up to at least the current balance so the prestige RP
## formula gives a meaningful number for these saves rather than 0.
func reconcile_total_gold_earned_this_run() -> void:
	var current: BigNumber = current_gold()
	var tracked: BigNumber = BigNumber.from_dict(total_gold_earned_this_run)
	if tracked.lt(current):
		push_warning("GameState: total_gold_earned_this_run (%s) < currencies.gold (%s); snapping up." % [
			tracked.format(), current.format(),
		])
		total_gold_earned_this_run = current.to_dict()


## Idempotent reconciliation: for every tier in tiers_completed, ensure every
## pet that tier should have awarded is in pets_owned. Fixes saves where the
## tier-completion loop missed a pet (e.g. the monster's `pet` ref hadn't yet
## been wired when the tier first completed). Safe to call any time after
## ContentRegistry has loaded; add_pet skips already-owned entries.
func reconcile_pet_awards() -> void:
	var pool := ContentRegistry.monsters()
	for tier_value in tiers_completed:
		var pets := CatchingSystem.pets_to_award_for_tier(pool, int(tier_value))
		for pet in pets:
			add_pet(pet.id, false)


# Upgrades

func get_upgrade_level(upgrade_id: StringName) -> int:
	var key: String = String(upgrade_id)
	for entry in upgrades_purchased:
		if String(entry.get("id", "")) == key:
			return int(entry.get("level", 0))
	return 0


func try_purchase_upgrade(upgrade: UpgradeResource) -> Dictionary:
	# Returns {"success": bool, "new_level": int}.
	var current_level: int = get_upgrade_level(upgrade.id)
	if current_level >= upgrade.max_level:
		return {"success": false, "new_level": current_level, "reason": "max_level"}
	var cost: BigNumber = UpgradeEffectsSystem.cost_for_next_level(upgrade, current_level)
	if upgrade.cost_currency == UpgradeResource.Currency.GOLD:
		if not try_spend_gold(cost):
			return {"success": false, "new_level": current_level, "reason": "insufficient_gold"}
	elif upgrade.cost_currency == UpgradeResource.Currency.RANCHER_POINTS:
		var rp_cost: int = int(cost.to_float())
		if int(currencies["rancher_points"]) < rp_cost:
			return {"success": false, "new_level": current_level, "reason": "insufficient_rp"}
		currencies["rancher_points"] = int(currencies["rancher_points"]) - rp_cost
		EventBus.currency_changed.emit("rancher_points", currencies["rancher_points"])
	# Apply level increment.
	var new_level: int = current_level + 1
	var found: bool = false
	for entry in upgrades_purchased:
		if String(entry.get("id", "")) == String(upgrade.id):
			entry["level"] = new_level
			found = true
			break
	if not found:
		upgrades_purchased.append({"id": upgrade.id, "level": new_level})
	EventBus.upgrade_purchased.emit(String(upgrade.id))
	return {"success": true, "new_level": new_level}


func multiplier(effect_id: StringName) -> float:
	var base: float = UpgradeEffectsSystem.get_multiplier(
			effect_id,
			upgrades_purchased,
			ContentRegistry.upgrade_index())
	# v0.15.20 — weekend calendar boosts compose multiplicatively with the
	# player's upgrades. Fully derived from the clock (no save state, no
	# server); effect ids outside CalendarEventsSystem.EVENTS get 1.0, so
	# rp_mult / offline_cap / tap_speed are untouched. Every consumer of
	# this method (live catching, offline progress, drops, shinies) sees
	# the boost uniformly — an offline window claimed during an event is
	# boosted whole; a by-design trade documented in the CHANGELOG.
	return base * CalendarEventsSystem.event_multiplier(effect_id, _event_day_index())


# multiplier() runs on hot paths (per-frame auto-catch, per-tap resolve),
# and the OS timezone query behind local_day_index allocates — so the day
# index is cached and only re-derived when the clock leaves the cached
# local day (forwards OR backwards; tests jump both ways via
# _test_now_override). Re-deriving at the boundary also re-reads the tz
# bias, so a DST change heals at the next local midnight. Review-pass
# bonus: one cached instant per call means a single catch can no longer
# straddle midnight with a mixed multiplier set.
var _event_day_cache: int = -1
var _event_day_start_unix: int = 0
var _event_day_end_unix: int = 0


func _event_day_index() -> int:
	var now: int = TimeManager.now_unix()
	if _event_day_cache < 0 or now < _event_day_start_unix or now >= _event_day_end_unix:
		var tz: int = TimeManager.tz_bias_minutes()
		_event_day_cache = DailyLoginSystem.local_day_index(now, tz)
		_event_day_start_unix = _event_day_cache * 86400 - tz * 60
		_event_day_end_unix = _event_day_start_unix + 86400
	return _event_day_cache


# Crafting

func try_craft(recipe: CraftingRecipeResource) -> Dictionary:
	# Returns {success: bool, reason: String}.
	var check := CraftingSystem.can_craft(
			recipe,
			inventory,
			current_gold(),
			current_max_tier,
			recipes_crafted)
	if not bool(check["can"]):
		return {"success": false, "reason": String(check["reason"])}
	var deltas := CraftingSystem.compute_deltas(recipe)
	# Spend gold cost first (if any).
	var cost: BigNumber = deltas["gold_to_spend"]
	if not cost.is_zero():
		if not try_spend_gold(cost):
			return {"success": false, "reason": "insufficient_gold"}
	# Consume inputs.
	for entry in deltas["items_to_consume"]:
		var key: String = String(entry["item_id"])
		var amount: int = int(entry["amount"])
		var have: int = int(inventory.get(key, 0))
		var remaining: int = have - amount
		if remaining <= 0:
			inventory.erase(key)
		else:
			inventory[key] = remaining
		EventBus.item_spent.emit(key, amount)
	# Produce outputs.
	var output_amount: int = max(1, int(deltas["output_amount"]))
	if String(deltas["output_item_id"]) != "":
		add_item(StringName(deltas["output_item_id"]), output_amount)
		EventBus.item_crafted.emit(String(recipe.id), String(deltas["output_item_id"]))
	if String(deltas["output_net_id"]) != "":
		var net_id: String = String(deltas["output_net_id"])
		if not nets_owned.has(net_id):
			nets_owned.append(net_id)
			EventBus.recipe_unlocked.emit(net_id)
		EventBus.item_crafted.emit(String(recipe.id), net_id)
	# Phase 12e: equipment outputs auto-equip on the first eligible
	# pet (one with an empty matching slot). Falls back to adding to
	# owned_equipment if all pets are full or no pets are owned yet.
	if recipe.output_equipment != null:
		_grant_equipment(recipe.output_equipment)
		EventBus.item_crafted.emit(String(recipe.id), String(recipe.output_equipment.id))
	# Mark recipe as crafted-at-least-once for prereq chains.
	var recipe_id_str: String = String(recipe.id)
	if not recipes_crafted.has(recipe_id_str):
		recipes_crafted.append(recipe_id_str)
	return {"success": true, "reason": "ok"}


## Phase 12e — auto-equip a freshly-crafted equipment item.
## Walks the player's pets in order, picks the first one with an
## empty slot matching this item's slot, and equips it.
##
## v0.15.19 — if every matching slot is occupied, the item now UPGRADES
## the first occupant it strictly Pareto-dominates (>= every stat, > at
## least one), stashing the displaced item in `owned_equipment`. Without
## this, an early tier-1 craft locked the slot forever (there is no equip
## picker yet), which would have made the new tier-5/6 battle stages
## permanently unwinnable for players who crafted before tier 3.
## Falls back to the stash if nothing is empty or upgradeable.
func _grant_equipment(item: EquipmentResource) -> void:
	var slot_key: String = _slot_key_for(item.slot)
	for pet_id_str in pets_owned:
		var slots: Dictionary = pet_equipment.get(pet_id_str, {})
		if String(slots.get(slot_key, "")) == "":
			slots[slot_key] = String(item.id)
			pet_equipment[pet_id_str] = slots
			# Don't append to owned_equipment when equipped — the
			# pet_equipment dict is the source of truth for equipped
			# items. owned_equipment is the unequipped stash only.
			return
	for pet_id_str in pets_owned:
		var slots: Dictionary = pet_equipment.get(pet_id_str, {})
		var occupant_id: String = String(slots.get(slot_key, ""))
		if occupant_id == "" or occupant_id == String(item.id):
			continue
		var occupant: EquipmentResource = ContentRegistry.equipment(StringName(occupant_id))
		if occupant != null and _pareto_dominates(item, occupant):
			slots[slot_key] = String(item.id)
			pet_equipment[pet_id_str] = slots
			owned_equipment.append(occupant_id)
			return
	# Fallback: stash for later. Future picker can re-equip from here.
	owned_equipment.append(String(item.id))


## True iff `a` is at least as good as `b` in EVERY additive stat and
## strictly better in at least one. Conservative on purpose: mixed
## trade-offs (more atk, less def) never auto-replace — that judgment
## belongs to a future equip picker, not an auto-rule.
static func _pareto_dominates(a: EquipmentResource, b: EquipmentResource) -> bool:
	if a.attack_add < b.attack_add or a.defense_add < b.defense_add \
			or a.hp_add < b.hp_add \
			or a.ability_cooldown_reduction < b.ability_cooldown_reduction:
		return false
	return a.attack_add > b.attack_add or a.defense_add > b.defense_add \
			or a.hp_add > b.hp_add \
			or a.ability_cooldown_reduction > b.ability_cooldown_reduction


func _slot_key_for(slot: int) -> String:
	match slot:
		0: return "head"
		1: return "body"
		2: return "trinket"
		_: return "head"


## Returns the equipment item id equipped in `slot_key` on `pet_id_str`,
## or "" if none. Used by the Battle roster preview to show stat
## bonuses, and by tests.
func equipment_in_slot(pet_id_str: String, slot_key: String) -> String:
	var slots: Variant = pet_equipment.get(pet_id_str)
	if not (slots is Dictionary):
		return ""
	return String(slots.get(slot_key, ""))


## Returns the total stat bonuses from equipment on the given pet.
## Format: {atk: float, def: float, hp: float, cd: int}. Used by
## Battle roster row preview ("+5 ATK · +20 HP from equipment").
func equipment_stats_for(pet_id_str: String) -> Dictionary:
	var totals: Dictionary = {"atk": 0.0, "def": 0.0, "hp": 0.0, "cd": 0}
	var slots: Variant = pet_equipment.get(pet_id_str)
	if not (slots is Dictionary):
		return totals
	for slot_key in ["head", "body", "trinket"]:
		var item_id_str: String = String(slots.get(slot_key, ""))
		if item_id_str == "":
			continue
		var item: EquipmentResource = ContentRegistry.equipment(StringName(item_id_str))
		if item == null:
			continue
		totals["atk"] += float(item.attack_add)
		totals["def"] += float(item.defense_add)
		totals["hp"] += float(item.hp_add)
		totals["cd"] += int(item.ability_cooldown_reduction)
	return totals


# Prestige

func projected_rp_gain() -> int:
	return PrestigeSystem.compute_rp_gain(total_gold_earned_this_run, multiplier(&"rp_mult"))


## Reset progression for Rancher Points. Preserves upgrades flagged
## persists_through_prestige, pets, bestiary entries, ledger totals, and the
## RP balance (additive across prestiges). Returns the RP awarded.
func perform_prestige() -> int:
	var rp_gain: int = projected_rp_gain()
	# Snapshots of fields we want to keep.
	var keep_pets_owned := pets_owned.duplicate()
	var keep_pet_variants := pet_variants_owned.duplicate()
	var keep_monsters_caught := monsters_caught.duplicate(true)
	var keep_recipes_crafted := recipes_crafted.duplicate()
	var keep_ledger := ledger.duplicate(true)
	var keep_narrator_state := narrator_state.duplicate(true)
	var keep_rp: int = int(currencies.get("rancher_points", 0))
	var keep_persistent_upgrades := PrestigeSystem.filter_persistent_upgrades(
			upgrades_purchased,
			ContentRegistry.upgrade_index())
	var keep_first_launch: int = int(keep_ledger.get("first_launch_unix", 0))
	# Phase 12e: equipment carries through prestige. Pets persist, so
	# their gear should too. best_rp_at_prestige updates if this run
	# beats the previous record.
	var keep_pet_equipment := pet_equipment.duplicate(true)
	var keep_owned_equipment := owned_equipment.duplicate()
	var keep_best_rp: int = max(int(best_rp_at_prestige), rp_gain)
	# Phase 12f — achievements persist across prestige (they're meta-
	# progression rewards, not run rewards).
	var keep_achievements := achievements_unlocked.duplicate(true)
	# Phase 12g — quests_completed persists (it's the de-dupe set for
	# the picker; without it we'd re-issue completed one-shots every
	# prestige cycle). active_quests resets — slot picks fresh on the
	# next QuestLog tick because lots of state the quests track also
	# resets (run gold, pets, etc.).
	var keep_quests_completed := quests_completed.duplicate(true)
	# v0.15.12 — the one-time tier-completion RP ledger persists (like
	# achievements). tiers_completed resets so the player re-climbs, but
	# already-paid tiers must never pay their RP bonus again.
	var keep_tiers_rp_awarded := tiers_rp_awarded.duplicate()
	# v0.15.14 — daily-login streak is account-level meta; prestige (a run
	# reset) must not break the player's login streak.
	var keep_daily_login_last_day: int = daily_login_last_day
	var keep_daily_login_streak: int = daily_login_streak
	# v0.15.15 — daily quests delta against lifetime ledger counters (which
	# survive prestige), so a mid-day prestige must not wipe daily progress.
	var keep_dq_reset_day: int = daily_quests_reset_day
	var keep_dq_active := daily_quests_active.duplicate()
	var keep_dq_baselines := daily_quest_baselines.duplicate(true)
	var keep_dq_done := daily_quests_done.duplicate(true)
	var keep_dq_bonus: bool = daily_quests_bonus_claimed
	# prestige_count is a LIFETIME counter, not a per-run one. It lives in
	# _reset_to_defaults (which doubles as the post-prestige reset), so
	# without this keeper the `prestige_count += 1` below always ran against
	# a freshly-zeroed field and the value was pinned at 1 forever — making
	# every threshold above 1 permanently unreachable (long_prestige_5/25
	# deadlocked the LONG quest slot; the prestige_5/25 achievements and any
	# dialogue line gated on min_prestige_count >= 2 could never fire).
	var keep_prestige_count: int = prestige_count

	# Full reset, then re-apply keepers.
	_reset_to_defaults()
	prestige_count = keep_prestige_count
	pets_owned = _to_string_array(keep_pets_owned)
	pet_variants_owned = _to_string_array(keep_pet_variants)
	monsters_caught = keep_monsters_caught
	recipes_crafted = _to_string_array(keep_recipes_crafted)
	ledger = keep_ledger
	narrator_state = keep_narrator_state
	upgrades_purchased = keep_persistent_upgrades
	pet_equipment = keep_pet_equipment
	owned_equipment = _to_string_array(keep_owned_equipment)
	best_rp_at_prestige = keep_best_rp
	achievements_unlocked = keep_achievements
	quests_completed = keep_quests_completed
	tiers_rp_awarded = _to_int_array(keep_tiers_rp_awarded)
	daily_login_last_day = keep_daily_login_last_day
	daily_login_streak = keep_daily_login_streak
	daily_quests_reset_day = keep_dq_reset_day
	daily_quests_active = _to_string_array(keep_dq_active)
	daily_quest_baselines = keep_dq_baselines
	daily_quests_done = keep_dq_done
	daily_quests_bonus_claimed = keep_dq_bonus
	# Carry over RP and add the freshly-earned ones.
	currencies["rancher_points"] = keep_rp + rp_gain
	# Increment prestige counters.
	prestige_count += 1
	ledger["prestige_count"] = int(ledger.get("prestige_count", 0)) + 1
	ledger["first_launch_unix"] = keep_first_launch
	# Post-prestige bonus: Headstart upgrade equips the basic net.
	if get_upgrade_level(&"prestige_starting_net") >= 1:
		var basic := ContentRegistry.net(&"basic_net")
		if basic != null:
			var basic_id: String = String(basic.id)
			if not nets_owned.has(basic_id):
				nets_owned.append(basic_id)
			active_net = basic_id
	if rp_gain > 0:
		EventBus.currency_changed.emit("rancher_points", currencies["rancher_points"])
		EventBus.rancher_points_earned.emit(rp_gain, "prestige")
	EventBus.prestige_triggered.emit(rp_gain, prestige_count)
	return rp_gain

# endregion
