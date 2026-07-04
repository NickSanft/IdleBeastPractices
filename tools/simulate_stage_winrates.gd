## Balance tool: win rates for hypothetical per-tier battle stages.
##
## For each tier 1..20, builds the established stage shape (solo → duo →
## trio of that tier's three species) and runs BattleSystem.simulate_stage
## over many seeds with the full 3-pet roster, bare and fully equipped.
## Prints a per-tier win-rate table. Used to pick the stage band shipped in
## v0.15.19 (pets are static — stages beyond the winnable band would make
## the auto-picked battle a guaranteed loss).
##
## Run:
##   godot --headless --path . -s tools/simulate_stage_winrates.gd
extends SceneTree

## Modest seed count: unwinnable stages run every encounter to the tick
## cap, so each additional seed on a lost cause is expensive. 20 seeds
## separates "comfortably winnable" from "wall" well enough for banding.
const SEEDS := 20

## Watchdog: if _initialize aborts on a script error, quit() never runs and
## the SceneTree idles forever (with the music autoload playing to nobody —
## learned the hard way). SceneTree._process returning true exits the loop.
var _deadline_msec: int = 0


func _process(_delta: float) -> bool:
	return _deadline_msec > 0 and Time.get_ticks_msec() > _deadline_msec


func _initialize() -> void:
	_deadline_msec = Time.get_ticks_msec() + 30 * 60 * 1000
	# NOTE: a `-s` entry script (and its compile-time dependencies) compiles
	# BEFORE autoload globals register, so neither `GameState` nor any script
	# that mentions it (battle_system.gd does, at compile time) can be a
	# compile-time reference here. Resolve the autoload via the tree and
	# load BattleSystem at RUNTIME — by _initialize, autoloads exist, so the
	# dependent script compiles fine.
	var game_state: Node = root.get_node_or_null("GameState")
	if game_state == null:
		push_error("GameState autoload not present — run with --path <project>")
		quit(1)
		return
	var battle_system: GDScript = load("res://game/systems/battle_system.gd")
	ContentRegistry.ensure_loaded()
	var pets: Array[PetResource] = ContentRegistry.pets()
	pets.sort_custom(func(a, b): return String(a.id) < String(b.id))
	print("pets: ", pets.map(func(p): return String(p.id)))

	# Group monsters by tier.
	var by_tier: Dictionary = {}
	for m in ContentRegistry.monsters():
		if not by_tier.has(m.tier):
			by_tier[m.tier] = []
		by_tier[m.tier].append(m.id)
	for t in by_tier.keys():
		(by_tier[t] as Array).sort_custom(func(a, b): return String(a) < String(b))

	# Full-equip loadout: best-in-slot (the tier-2 trio) on every pet. This
	# is ACHIEVABLE as of v0.15.19: all three have recipes (tier_required
	# 3-4, materials from tier-3/4 drops) and _grant_equipment's Pareto
	# upgrade rule replaces earlier tier-1 gear, so any craft history can
	# reach this loadout. Banding must always use an obtainable loadout —
	# the first draft of this tool used gear that had NO recipe, and the
	# adversarial review caught tiers 5-6 shipping as unwinnable.
	var equipped := {
		"red_wisplet_pet": {"head": "seer_circlet", "body": "silver_collar", "trinket": "rending_fang"},
		"green_wisplet_pet": {"head": "seer_circlet", "body": "silver_collar", "trinket": "rending_fang"},
		"blue_wisplet_pet": {"head": "seer_circlet", "body": "silver_collar", "trinket": "rending_fang"},
	}

	# Wave shapes, richest first. Per tier we report the equipped win% of
	# each shape; the generator's SHAPES table ships the richest shape that
	# held 100% equipped over SEEDS (see scripts/generate_battle_stages.py).
	# (Tier-scaled enemies vs static pets: the full solo/duo/trio shape is
	# only winnable through tier 3 — lighter waves extend the band.)
	var shapes: Dictionary = {
		"solo/duo/trio": func(ids: Array) -> Array: return [[ids[0]], [ids[1], ids[2]], [ids[0], ids[1], ids[2]]],
		"solo/duo": func(ids: Array) -> Array: return [[ids[0]], [ids[1], ids[2]]],
		"solo/solo": func(ids: Array) -> Array: return [[ids[0]], [ids[1]]],
		"solo": func(ids: Array) -> Array: return [[ids[0]]],
	}

	print("tier | shape          | bare win% | equipped win%")
	var consecutive_zero: int = 0
	for tier in range(1, 21):
		if not by_tier.has(tier):
			continue
		if consecutive_zero >= 2:
			print("%4d | (skipped — two consecutive all-zero tiers above)" % tier)
			continue
		var ids: Array = by_tier[tier]
		var best_equipped: float = 0.0
		for shape_name in shapes.keys():
			var waves: Array = (shapes[shape_name] as Callable).call(ids)
			var stage := BattleStageResource.new()
			stage.id = StringName("sim_tier_%d" % tier)
			stage.tier = tier
			var encounters: Array[EncounterResource] = []
			for wave in waves:
				var enc := EncounterResource.new()
				var mids: Array[StringName] = []
				for mid in wave:
					mids.append(mid)
				enc.monster_ids = mids
				encounters.append(enc)
			stage.encounters = encounters

			var results: Array[float] = []
			for loadout in [false, true]:
				game_state.pet_equipment = equipped.duplicate(true) if loadout else {}
				var wins: int = 0
				for s in SEEDS:
					var log: Dictionary = battle_system.simulate_stage(1000 + s, pets, stage)
					if String(log.get("winner", "")) == "player":
						wins += 1
				results.append(100.0 * wins / SEEDS)
			game_state.pet_equipment = {}
			print("%4d | %-14s | %8.1f%% | %12.1f%%" % [tier, shape_name, results[0], results[1]])
			best_equipped = max(best_equipped, results[1])
		consecutive_zero = consecutive_zero + 1 if best_equipped <= 0.0 else 0

	quit()
