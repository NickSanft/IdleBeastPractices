## Headless difficulty-curve simulator.
##
## Mimics a player progressing through tier 1-20 over a configurable number of
## simulated real-time hours. Reuses the real CatchingSystem / OfflineProgressSystem /
## UpgradeEffectsSystem / PrestigeSystem / GameState autoloads to avoid drift
## between sim and live-game logic.
##
## Run:
##   godot --headless --path . res://tests/sim/sim_runner.tscn -- \
##       --seed=42 --hours=336 --tick=60
##
## Outputs:
##   tests/sim/output/difficulty_curve.csv  (event log, one row per milestone)
##   tests/sim/output/difficulty_curve.md   (human-readable report)
##
## AI policy (greedy):
##   1. After each tick, check tier_completion_status for current_max_tier;
##      advance current_max_tier when complete.
##   2. Equip the best owned net whose targets_tiers includes current_max_tier
##      (highest catches_per_second wins).
##   3. Try to craft the next net up the chain when gold + items + prereqs
##      + tier_required all satisfied.
##   4. Buy any affordable upgrade (cheapest first, max-level skipped).
##      Prestige-currency upgrades only after first prestige.
##   5. Prestige when projected_rp_gain >= 1.5 × current_rp + 5.
##
## Limitations (documented in tests/sim/README.md):
##   - Auto-catch only; no tap-grinding modeled. Player is handed basic_net
##     at sim start to bypass the bootstrap.
##   - No battles. Battles award rancher points but don't advance gold-driven
##     prestige progression — sim leaves them out.
##   - OfflineProgressSystem.compute uses Poisson approximations for shiny
##     counts; sim inherits any approximation error.
extends Node


const SEED_DEFAULT := 42
const HOURS_DEFAULT := 336.0   # 14 days of simulated real-time
const TICK_SECONDS := 60.0
const TIER_COMPLETE_THRESHOLD := 25
const PRESTIGE_RP_GAIN_RATIO := 2.0
const PRESTIGE_RP_GAIN_FLOOR := 20
# Don't prestige until the player has made meaningful per-run progress.
# A greedy AI without this gate gets trapped in a prestige spiral: prestige at
# RP=5 → buy a cheap prestige upgrade → spend RP → threshold drops → prestige
# again. The player cycles at tier 1-4 forever. Real players with even minimal
# look-ahead don't do this; the patient gate models that intuition.
const PRESTIGE_MIN_MAX_TIER := 8

const OUTPUT_DIR := "res://tests/sim/output"
const CSV_PATH := "res://tests/sim/output/difficulty_curve.csv"
const REPORT_PATH := "res://tests/sim/output/difficulty_curve.md"

# Net upgrade chain in unlock order. recipe_tier4_net is a placeholder with
# no output_net (locked content) — wraith_net is the real tier-4 progression
# net, so the chain skips the dead recipe entry.
const NET_CHAIN: Array[StringName] = [
	&"basic_net",
	&"tier2_net",
	&"tier3_net",
	&"wraith_net",
	&"hedgewright_net",
	&"gleamwarp_net",
	&"refrain_net",
	&"vigil_net",
	&"nadir_net",
]

# Recipe id per output net (basic_net is the seed, no recipe needed).
const NET_RECIPES: Dictionary = {
	&"tier2_net": &"recipe_tier2_net",
	&"tier3_net": &"recipe_tier3_net",
	&"wraith_net": &"recipe_wraith_net",
	&"hedgewright_net": &"recipe_hedgewright_net",
	&"gleamwarp_net": &"recipe_gleamwarp_net",
	&"refrain_net": &"recipe_refrain_net",
	&"vigil_net": &"recipe_vigil_net",
	&"nadir_net": &"recipe_nadir_net",
}


## Sim time without any state-changing event before declaring the player
## permanently stalled. 24 sim-hours = 14400 ticks at 60s. If no first_catch /
## tier_complete / net_owned / upgrade_lvl / prestige fires in that window the
## sim terminates early — the player has hit a hard progression wall and
## continuing wastes compute and pollutes the report with idle-tier catches.
const STALL_TIMEOUT_SECONDS := 86400.0

## Highest tier_completion the content supports. Once
## current_max_tier exceeds this the player has cleared the design's
## final tier; any "stall" beyond that is the endgame plateau, not a
## progression wall. The runner exits cleanly with `endgame_reached`
## rather than firing a misleading STALLED diagnosis.
const MAX_DESIGNED_TIER := 20

var _seed: int = SEED_DEFAULT
var _max_seconds: float = HOURS_DEFAULT * 3600.0
var _tick: float = TICK_SECONDS

var _rng: RandomNumberGenerator
var _events: Array[Dictionary] = []
var _seen_species: Dictionary = {}        # String -> true (first-catch dedupe)
var _seen_nets: Dictionary = {}           # String -> true
var _seen_tier_complete: Dictionary = {}  # int -> true
var _last_max_tier: int = 1
var _last_event_t: float = 0.0
var _stalled: bool = false
var _endgame_reached: bool = false


func _ready() -> void:
	_parse_args()
	_rng = RandomNumberGenerator.new()
	_rng.seed = _seed

	ContentRegistry.ensure_loaded()
	_init_player_state()

	print("[sim] seed=%d hours=%.1f tick=%.0fs" % [
		_seed, _max_seconds / 3600.0, _tick,
	])
	_run_simulation()
	_write_csv()
	_write_report()
	print("[sim] done. wrote %s and %s" % [CSV_PATH, REPORT_PATH])
	get_tree().quit()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var s: String = String(arg)
		if s.begins_with("--seed="):
			_seed = int(s.substr(7))
		elif s.begins_with("--hours="):
			_max_seconds = float(s.substr(8)) * 3600.0
		elif s.begins_with("--tick="):
			_tick = float(s.substr(7))


func _init_player_state() -> void:
	# Fresh save, then hand the player basic_net so the bootstrap (need gold to
	# buy the first net, but no nets means no auto-catches) doesn't soft-lock
	# the auto-catch-only sim.
	GameState.from_dict({})
	GameState.nets_owned = ["basic_net"]
	GameState.active_net = "basic_net"
	_seen_nets["basic_net"] = true
	_log_event(0.0, "net_owned", "basic_net")


func _run_simulation() -> void:
	var t: float = 0.0
	while t < _max_seconds:
		# 1. Tier-completion check + advance.
		_check_tier_advance(t)

		# 2. Equip best owned net.
		_equip_best_net()

		# 3. Try to craft the next net up the chain.
		_try_craft_next_net(t)

		# 4. Buy any affordable upgrade (cheapest first).
		_try_buy_upgrades(t)

		# 5. Prestige if RP gain is favorable.
		_maybe_prestige(t)

		# 6. Advance time by one tick.
		_tick_offline_progress(t)
		t += _tick

		# 7. Endgame check: once current_max_tier exceeds the designed
		#    cap, the watchdog "stall" is just the post-endgame plateau
		#    (nothing left to catch beyond tier 20). Exit cleanly.
		if not _endgame_reached and GameState.current_max_tier > MAX_DESIGNED_TIER:
			_endgame_reached = true
			_log_event(t, "endgame_reached", "max_tier_%d" % MAX_DESIGNED_TIER)
			print("[sim] endgame reached at t=%.1fh (tier %d cleared) — terminating cleanly" % [
				t / 3600.0, MAX_DESIGNED_TIER,
			])
			return

		# 8. Stall check: 24 sim-hours with no event = hard wall.
		if t - _last_event_t > STALL_TIMEOUT_SECONDS:
			_stalled = true
			_log_event(t, "stalled", "no_progress_for_%.0fh" % (STALL_TIMEOUT_SECONDS / 3600.0))
			print("[sim] stalled at t=%.1fh — terminating early" % (t / 3600.0))
			return


func _check_tier_advance(t: float) -> void:
	var pool: Array[MonsterResource] = ContentRegistry.monsters()
	var status: Dictionary = CatchingSystem.tier_completion_status(
			pool,
			GameState.monsters_caught,
			GameState.current_max_tier,
			TIER_COMPLETE_THRESHOLD)
	if not bool(status["is_complete"]):
		return
	var tier: int = int(status["tier"])
	if not _seen_tier_complete.has(tier):
		_seen_tier_complete[tier] = true
		_log_event(t, "tier_complete", "tier_%d" % tier)
	if not GameState.tiers_completed.has(tier):
		GameState.tiers_completed.append(tier)
	if GameState.current_max_tier <= tier:
		GameState.current_max_tier = tier + 1
		_log_event(t, "max_tier_unlocked", "tier_%d" % GameState.current_max_tier)


func _equip_best_net() -> void:
	var current_tier: int = GameState.current_max_tier
	var best_net: NetResource = null
	var best_cps: float = -1.0
	for net_id in GameState.nets_owned:
		var net := ContentRegistry.net(StringName(net_id))
		if net == null:
			continue
		if not net.targets_tiers.has(current_tier):
			# Fall back to any net that still hits *any* tier the player can
			# spawn — better than nothing if no tier-current net is owned.
			continue
		if net.catches_per_second > best_cps:
			best_cps = net.catches_per_second
			best_net = net
	if best_net == null:
		# No net targets current_max_tier; equip the best one for any lower tier
		# so auto-catch keeps producing item drops + gold.
		for net_id in GameState.nets_owned:
			var net := ContentRegistry.net(StringName(net_id))
			if net != null and net.catches_per_second > best_cps:
				best_cps = net.catches_per_second
				best_net = net
	if best_net != null and GameState.active_net != String(best_net.id):
		GameState.active_net = String(best_net.id)


func _try_craft_next_net(t: float) -> void:
	# Walk the chain in order; first not-owned is the candidate.
	for net_id in NET_CHAIN:
		if GameState.nets_owned.has(String(net_id)):
			continue
		var recipe_id: StringName = NET_RECIPES.get(net_id, &"")
		if recipe_id == &"":
			return
		var recipe := ContentRegistry.recipe(recipe_id)
		if recipe == null:
			return
		var result: Dictionary = GameState.try_craft(recipe)
		if bool(result.get("success", false)):
			_seen_nets[String(net_id)] = true
			_log_event(t, "net_owned", String(net_id))
		# Stop after first attempt — don't skip ahead in the chain even if a
		# later net is somehow craftable. That would represent unrealistic
		# player behavior.
		return


func _try_buy_upgrades(t: float) -> void:
	# Sort all upgrades by next-level cost (in absolute terms via to_float)
	# and buy the cheapest affordable one. Loop until nothing is affordable.
	var upgrades: Array[UpgradeResource] = ContentRegistry.upgrades()
	var made_purchase: bool = true
	var safety: int = 0
	while made_purchase and safety < 20:
		safety += 1
		made_purchase = false
		var best: UpgradeResource = null
		var best_cost: float = INF
		for u in upgrades:
			var current_level: int = GameState.get_upgrade_level(u.id)
			if current_level >= u.max_level:
				continue
			# Skip RP upgrades pre-first-prestige (player has no RP yet).
			if u.cost_currency == UpgradeResource.Currency.RANCHER_POINTS \
					and GameState.prestige_count == 0 \
					and GameState.current_rancher_points() <= 0:
				continue
			# Skip prestige_starting_net: the sim hands the player basic_net at
			# every prestige start regardless (see _maybe_prestige). Buying this
			# in the sim is pure RP waste; the live game needs it because
			# basic_net comes from save state.
			if u.id == &"prestige_starting_net":
				continue
			var cost := UpgradeEffectsSystem.cost_for_next_level(u, current_level)
			var cost_f: float = cost.to_float()
			var affordable: bool = false
			if u.cost_currency == UpgradeResource.Currency.GOLD:
				affordable = GameState.current_gold().gte(cost)
			else:
				affordable = GameState.current_rancher_points() >= int(cost_f)
			if not affordable:
				continue
			if cost_f < best_cost:
				best_cost = cost_f
				best = u
		if best == null:
			break
		var prev_level: int = GameState.get_upgrade_level(best.id)
		var result: Dictionary = GameState.try_purchase_upgrade(best)
		if bool(result.get("success", false)):
			made_purchase = true
			_log_event(t, "upgrade_lvl", "%s_lvl_%d" % [String(best.id), prev_level + 1])


func _maybe_prestige(t: float) -> void:
	if GameState.current_max_tier < PRESTIGE_MIN_MAX_TIER:
		return
	var projected: int = GameState.projected_rp_gain()
	if projected <= 0:
		return
	var current_rp: int = GameState.current_rancher_points()
	var threshold: int = max(PRESTIGE_RP_GAIN_FLOOR, int(ceil(float(current_rp) * PRESTIGE_RP_GAIN_RATIO)))
	if projected < threshold:
		return
	var awarded: int = GameState.perform_prestige()
	# After prestige, GameState.nets_owned was reset (only persistent_starting_net
	# may have re-added basic_net). Make sure basic_net is present for the
	# next run-through; without it auto-catch dies.
	if not GameState.nets_owned.has("basic_net"):
		GameState.nets_owned = ["basic_net"]
		GameState.active_net = "basic_net"
	# tiers_completed is reset by perform_prestige() — let tier_complete fire
	# again on the new run since the player has to re-clear. Species first-catch
	# is a once-ever event in the live game (monsters_caught persists through
	# prestige), so don't clear _seen_species.
	_seen_tier_complete.clear()
	# Net-craft dedupe also re-fires: nets_owned reset means the player has to
	# re-craft everything. Real game state matches.
	_seen_nets.clear()
	_seen_nets["basic_net"] = true
	_log_event(t, "prestige", "rp_+%d" % awarded)


func _tick_offline_progress(t: float) -> void:
	var net := ContentRegistry.net(StringName(GameState.active_net))
	if net == null:
		return
	var summary: Dictionary = OfflineProgressSystem.compute(
			ContentRegistry.monsters(),
			net,
			GameState.current_max_tier,
			_tick,
			_rng,
			GameState.multiplier(&"offline_cap"),
			GameState.multiplier(&"auto_speed"),
			GameState.multiplier(&"drop_amount"),
			GameState.multiplier(&"gold_mult"),
			GameState.multiplier(&"shiny_rate"))
	# Apply summary to GameState manually (the live game does this in
	# main.gd's offline-resume flow; we replicate it here without dialogs).
	var catches_by_species: Dictionary = summary.get("catches_by_species", {})
	for sid in catches_by_species.keys():
		var counts: Dictionary = catches_by_species[sid]
		var normals: int = int(counts.get("normal", 0))
		var shinies: int = int(counts.get("shiny", 0))
		if normals == 0 and shinies == 0:
			continue
		var key: String = String(sid)
		var first_catch: bool = not _seen_species.has(key)
		if not GameState.monsters_caught.has(key):
			GameState.monsters_caught[key] = {"normal": 0, "shiny": 0}
		GameState.monsters_caught[key]["normal"] = int(GameState.monsters_caught[key].get("normal", 0)) + normals
		GameState.monsters_caught[key]["shiny"] = int(GameState.monsters_caught[key].get("shiny", 0)) + shinies
		GameState.ledger["total_catches"] = int(GameState.ledger.get("total_catches", 0)) + normals + shinies
		GameState.ledger["total_shinies"] = int(GameState.ledger.get("total_shinies", 0)) + shinies
		if first_catch:
			_seen_species[key] = true
			var monster := ContentRegistry.monster(StringName(key))
			var tier_str: String = "tier_%d_%s" % [monster.tier, key] if monster != null else key
			_log_event(t + _tick, "first_catch", tier_str)
	var items_gained: Dictionary = summary.get("items_gained", {})
	for iid in items_gained.keys():
		GameState.add_item(StringName(iid), int(items_gained[iid]))
	var gold_gained: BigNumber = summary["gold_gained"]
	if not gold_gained.is_zero():
		GameState.add_gold(gold_gained)


func _log_event(t: float, event_type: String, event_id: String) -> void:
	_events.append({
		"t_seconds": t,
		"t_hours": t / 3600.0,
		"event_type": event_type,
		"event_id": event_id,
		"gold_at": GameState.current_gold().format(),
		"rp_at": GameState.current_rancher_points(),
		"total_catches": int(GameState.ledger.get("total_catches", 0)),
		"max_tier": GameState.current_max_tier,
		"prestige_count": GameState.prestige_count,
		"active_net": GameState.active_net,
	})
	# Track latest max_tier for the report.
	if GameState.current_max_tier > _last_max_tier:
		_last_max_tier = GameState.current_max_tier
	# Stall detection: any logged event resets the watchdog. The "stalled"
	# event itself is excluded so that detection is one-shot.
	if event_type != "stalled":
		_last_event_t = t


func _write_csv() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var f := FileAccess.open(CSV_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[sim] could not open %s for writing" % CSV_PATH)
		return
	f.store_line("t_seconds,t_hours,event_type,event_id,gold_at,rp_at,total_catches,max_tier,prestige_count,active_net")
	for e in _events:
		f.store_line("%.1f,%.4f,%s,%s,%s,%d,%d,%d,%d,%s" % [
			e["t_seconds"],
			e["t_hours"],
			e["event_type"],
			e["event_id"],
			_csv_escape(String(e["gold_at"])),
			e["rp_at"],
			e["total_catches"],
			e["max_tier"],
			e["prestige_count"],
			e["active_net"],
		])
	f.close()


func _csv_escape(s: String) -> String:
	if s.contains(",") or s.contains("\"") or s.contains("\n"):
		return "\"%s\"" % s.replace("\"", "\"\"")
	return s


func _write_report() -> void:
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[sim] could not open %s for writing" % REPORT_PATH)
		return
	f.store_line("# Difficulty curve simulation — seed %d" % _seed)
	f.store_line("")
	f.store_line("Sim horizon: **%.1f hours** (%.1f days). Tick: %.0f s. Total events: %d." % [
		_max_seconds / 3600.0, _max_seconds / 86400.0, _tick, _events.size(),
	])
	f.store_line("")
	f.store_line("Final state: max tier **%d**, prestige count **%d**, total catches **%d**, RP **%d**, gold **%s**." % [
		_last_max_tier,
		GameState.prestige_count,
		int(GameState.ledger.get("total_catches", 0)),
		GameState.current_rancher_points(),
		GameState.current_gold().format(),
	])
	f.store_line("")
	if _endgame_reached:
		f.store_line("> **ENDGAME REACHED** — the player cleared tier %d (the design cap) and prestiged at least once. The catching progression curve has no further wall; remaining gameplay is prestige-cycle RP grind." % MAX_DESIGNED_TIER)
		f.store_line("")
	if _stalled:
		f.store_line("> **STALLED** — no progress event fired for %.0f sim-hours. The player has hit a hard progression wall. See the diagnosis at the bottom of this report." % (STALL_TIMEOUT_SECONDS / 3600.0))
		f.store_line("")

	# Tier-completion timeline.
	f.store_line("## Tier-completion timeline (first run)")
	f.store_line("")
	f.store_line("| Tier | First completed at | Δ from prior tier | Note |")
	f.store_line("|---|---|---|---|")
	var tier_complete_events: Array = []
	for e in _events:
		if String(e["event_type"]) == "tier_complete" and int(e["prestige_count"]) == 0:
			tier_complete_events.append(e)
	var prev_t: float = 0.0
	var deltas: Array[float] = []
	for e in tier_complete_events:
		var t: float = float(e["t_hours"])
		var delta: float = t - prev_t
		deltas.append(delta)
		prev_t = t
	# Median for wall/sprint detection.
	var median_delta: float = _median(deltas)
	for i in tier_complete_events.size():
		var e: Dictionary = tier_complete_events[i]
		var t: float = float(e["t_hours"])
		var delta: float = deltas[i]
		var note: String = ""
		if median_delta > 0.0 and i > 0:
			if delta > median_delta * 3.0:
				note = "**WALL** (%.1f× median)" % (delta / median_delta)
			elif delta < median_delta / 3.0:
				note = "*sprint* (%.2f× median)" % (delta / median_delta)
		f.store_line("| %s | %.2f h (%.2f d) | %.2f h | %s |" % [
			String(e["event_id"]).replace("tier_", "Tier "),
			t, t / 24.0, delta, note,
		])
	f.store_line("")

	# Prestige timeline.
	f.store_line("## Prestige timeline")
	f.store_line("")
	var prestige_events: Array = []
	for e in _events:
		if String(e["event_type"]) == "prestige":
			prestige_events.append(e)
	if prestige_events.is_empty():
		f.store_line("_No prestiges occurred within the sim horizon._")
	else:
		f.store_line("| Prestige # | At | RP awarded | Max tier reached pre-prestige |")
		f.store_line("|---|---|---|---|")
		for e in prestige_events:
			var t: float = float(e["t_hours"])
			# prestige_count was incremented by perform_prestige() before the
			# event was logged, so it already reflects the post-prestige count
			# (#1 after first prestige, #2 after second, ...).
			f.store_line("| %d | %.2f h | %s | tier %d |" % [
				int(e["prestige_count"]),
				t,
				String(e["event_id"]).replace("rp_+", "+"),
				int(e["max_tier"]),
			])
	f.store_line("")

	# Net-craft timeline.
	f.store_line("## Net-acquisition timeline (first run)")
	f.store_line("")
	f.store_line("| Net | Acquired at |")
	f.store_line("|---|---|")
	for e in _events:
		if String(e["event_type"]) == "net_owned" and int(e["prestige_count"]) == 0:
			f.store_line("| %s | %.2f h |" % [
				String(e["event_id"]),
				float(e["t_hours"]),
			])
	f.store_line("")

	# Notes.
	f.store_line("## Methodology")
	f.store_line("")
	f.store_line("- Auto-catch only via `OfflineProgressSystem.compute()`. Tap-grinding is not modeled — would speed up tiers 1-3 by minutes only, irrelevant past that.")
	f.store_line("- Player AI is greedy: equips best owned net, crafts next net when gold + items + prereqs all available, buys cheapest affordable upgrade each tick. Prestige policy is patient: only when current_max_tier ≥ %d AND projected_rp ≥ max(%d, %.1f × current_rp). The patient gate avoids a local minimum where a greedy AI cycles tier 1-4 forever (each prestige resets nets, threshold is met immediately, RP never stockpiles)." % [
		PRESTIGE_MIN_MAX_TIER, PRESTIGE_RP_GAIN_FLOOR, PRESTIGE_RP_GAIN_RATIO,
	])
	f.store_line("- `prestige_starting_net` upgrade is skipped: the sim re-equips `basic_net` at every prestige start regardless. In live play this upgrade is load-bearing.")
	f.store_line("- Battles are not simulated. Battle RP is a separate income stream that compounds prestige RP indirectly via rp_mult upgrades; sim under-reports total RP gain.")
	f.store_line("- Wall flags fire when a tier's Δ exceeds 3× the median tier-completion gap. Sprint flags fire below 1/3× median. Both ignore tier 1 (no prior delta).")
	f.store_line("- The **tier-2 wall flag is a known false positive** in this content layout: tier 2 requires the player to grind ~50 tier-1 drops + the gold cost to craft `tier2_net`, which inherently takes longer than later tiers (where the player has already accumulated resources mid-chain). Real walls — like the tier-3→tier-4 chicken-and-egg fixed in v0.13.4 by extending mid-tier net `targets_tiers` — show up as **multiple consecutive walls** or as a stall, not a single flagged tier.")
	f.store_line("- Re-run via `godot --headless --path . res://tests/sim/sim_runner.tscn -- --seed=N --hours=N --tick=N` to compare seeds.")

	# Stall diagnosis: when the sim terminates early, the diagnostic block
	# explains exactly what's blocking. This is the most useful section for
	# the user to act on.
	if _stalled:
		f.store_line("")
		f.store_line("## Stall diagnosis")
		f.store_line("")
		f.store_line("The simulator terminated early after a %.0f-hour silent window. State at stall:" % (STALL_TIMEOUT_SECONDS / 3600.0))
		f.store_line("")
		f.store_line("- Active net: `%s` (targets tiers `%s`)" % [
			GameState.active_net,
			str(ContentRegistry.net(StringName(GameState.active_net)).targets_tiers) if ContentRegistry.net(StringName(GameState.active_net)) != null else "?",
		])
		f.store_line("- current_max_tier: `%d`" % GameState.current_max_tier)
		f.store_line("- Gold available: `%s`" % GameState.current_gold().format())
		f.store_line("- Rancher Points: `%d`" % GameState.current_rancher_points())
		# Identify the next net the AI tried to craft.
		var next_recipe_id: StringName = &""
		var next_net_id: StringName = &""
		for nid in NET_CHAIN:
			if not GameState.nets_owned.has(String(nid)):
				next_net_id = nid
				next_recipe_id = NET_RECIPES.get(nid, &"")
				break
		if next_recipe_id != &"":
			var recipe := ContentRegistry.recipe(next_recipe_id)
			if recipe != null:
				f.store_line("")
				f.store_line("Next net the AI tried to craft: `%s` (recipe `%s`):" % [
					String(next_net_id), String(next_recipe_id),
				])
				f.store_line("")
				f.store_line("- Tier required: `%d` (current_max_tier %s)" % [
					recipe.tier_required,
					"OK" if GameState.current_max_tier >= recipe.tier_required else "**FAIL**",
				])
				f.store_line("- Gold cost: `%s` (have `%s`)" % [
					BigNumber.from_dict(recipe.gold_cost).format(),
					GameState.current_gold().format(),
				])
				if not recipe.inputs.is_empty():
					f.store_line("- Item inputs:")
					for entry in recipe.inputs:
						var item_id_str: String = String(entry.get("item_id", ""))
						var amount: int = int(entry.get("amount", 0))
						var have: int = int(GameState.inventory.get(item_id_str, 0))
						# Find what tier monsters drop this item.
						var dropper_tiers: Array[int] = []
						for m in ContentRegistry.monsters():
							if m.drop_item != null and m.drop_item.id == StringName(item_id_str):
								if not dropper_tiers.has(m.tier):
									dropper_tiers.append(m.tier)
						f.store_line("    - `%s` × `%d` (have `%d`) — drops from tiers %s" % [
							item_id_str, amount, have, str(dropper_tiers),
						])
				if not recipe.prereq_recipe_ids.is_empty():
					f.store_line("- Prereq recipes: %s" % str(recipe.prereq_recipe_ids))
		f.store_line("")
		f.store_line("**Likely root cause:** the only net targeting the input's source tier requires drops from monsters in that same tier. Tap-grinding does NOT bypass this in the live game — `CatchingSystem.pick_spawn` filters by `net.targets_tiers` for both auto-catch AND tap spawns ([catching_view.gd:154](../../game/scenes/catching/catching_view.gd:154)). The wall is real. Fix paths: (1) overlap net target ranges so e.g. `tier3_net` includes tier 4, (2) cross-tier item drops (lower-tier monsters occasionally drop the next-tier ingredient), (3) a shop or trade-in mechanic that converts lower-tier drops into higher-tier ones.")

	f.close()


func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var n: int = sorted.size()
	if n % 2 == 1:
		return sorted[n / 2]
	return (sorted[n / 2 - 1] + sorted[n / 2]) * 0.5
