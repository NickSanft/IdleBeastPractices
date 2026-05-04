## Deterministic seeded auto-battle simulation.
##
## simulate(seed, player_pets, enemy_monsters) -> BattleLog
##
## BattleLog is a Dictionary:
##   {
##     seed:     int,
##     winner:   "player" | "enemy" | "draw",
##     ticks:    int,                 # number of ticks elapsed before end
##     frames:   Array[Dictionary],   # tick-ordered events for the UI
##     rewards:  {rancher_points: int} or {} for non-player wins
##   }
##
## Rules:
##   - One tick = 0.25 seconds of in-game time. Cap at 600 ticks (2.5 min real time).
##   - Per tick: status effects tick, then each living combatant acts in
##     initiative order (player team first, by index; then enemy team).
##   - If ability_cooldown == 0 and the combatant has an ability, fire it
##     via AbilityRegistry. Otherwise basic attack:
##         damage = max(1, attacker.atk - effective_def(target)) × variance(0.85, 1.15)
##         target = lowest-HP enemy
##   - KO check after every action; if a side wipes, end immediately.
##   - On player win: rancher_points = floor(sum(enemy.tier))
##     × upgrade_multiplier("rp_mult"); emitted by the caller, not here.
class_name BattleSystem
extends RefCounted

const TICK_CAP := 600


## Player-side: build combatants from owned PetResource list.
## enemy_monsters: Array[MonsterResource]; HP scaled by tier so the fight is
## meaningful but not insurmountable. Returns the BattleLog dictionary.
static func simulate(
		battle_seed: int,
		player_pets: Array[PetResource],
		enemy_monsters: Array[MonsterResource],
		rp_mult: float = 1.0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = battle_seed

	var player_team: Array = []
	for i in player_pets.size():
		player_team.append(_make_combatant_from_pet(player_pets[i], i, "player"))

	return _simulate_encounter(rng, player_team, enemy_monsters, rp_mult, battle_seed)


## Phase 10e.2 — multi-encounter stage simulation.
##
## Drives `_simulate_encounter` for each encounter in the stage, threading
## the player team's HP through so survivors retain damage between waves.
## Stage ends early when the player team wipes (later encounters return
## an empty BattleLog with winner="enemy" so the UI can render a
## consistent "stage failed" view without indexing into nothing).
##
## Returns a StageLog:
##   {
##     stage_id: StringName,
##     seed: int,
##     winner: "player" | "enemy" | "draw",
##     last_encounter_index: int,           # 0-based, last one simulated
##     encounters: Array[BattleLog],        # one per stage encounter
##     rewards: {rancher_points: int},      # SUM of per-encounter RP
##                                          # plus stage.bonus_rp_on_clear
##                                          # if winner == "player"
##   }
##
## Determinism: same (seed, stage, player_pets) → byte-identical StageLog.
## RNG state carries between encounters (single rng instance) so a tweak
## to encounter 1's pet team meaningfully shifts encounter 2's variance.
static func simulate_stage(
		battle_seed: int,
		player_pets: Array[PetResource],
		stage: BattleStageResource,
		rp_mult: float = 1.0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = battle_seed

	var player_team: Array = []
	for i in player_pets.size():
		player_team.append(_make_combatant_from_pet(player_pets[i], i, "player"))

	var encounter_logs: Array[Dictionary] = []
	var stage_winner: String = "player"
	var rp_total: int = 0
	var last_index: int = -1

	for enc_index in stage.encounters.size():
		last_index = enc_index
		var encounter: EncounterResource = stage.encounters[enc_index]
		# Resolve monster ids via the registry. Skip-and-warn on lookup
		# failures so a bad stage entry doesn't crash a live battle.
		var enemy_monsters: Array[MonsterResource] = []
		for mid in encounter.monster_ids:
			var m: MonsterResource = ContentRegistry.monster(mid)
			if m == null:
				push_warning("BattleSystem.simulate_stage: unknown monster_id %s in stage %s encounter %d" % [
					String(mid), String(stage.id), enc_index,
				])
				continue
			enemy_monsters.append(m)
		if enemy_monsters.is_empty():
			# Treat an empty wave as auto-win — keeps the stage moving.
			encounter_logs.append({
				"seed": battle_seed,
				"winner": "player",
				"ticks": 0,
				"frames": [] as Array[Dictionary],
				"rewards": {},
			})
			continue

		# Per-encounter seed embeds the encounter index so the rng's
		# internal state shifts deterministically even if two encounters
		# share an identical enemy lineup.
		var enc_log: Dictionary = _simulate_encounter(
				rng, player_team, enemy_monsters, rp_mult, battle_seed)
		encounter_logs.append(enc_log)
		var enc_rewards: Dictionary = enc_log.get("rewards", {})
		rp_total += int(enc_rewards.get("rancher_points", 0))

		if String(enc_log.get("winner", "")) != "player":
			stage_winner = "enemy"
			break

	var stage_rewards: Dictionary = {}
	if stage_winner == "player":
		rp_total += max(0, int(stage.bonus_rp_on_clear))
		rp_total = int(floor(float(rp_total) * rp_mult))
		stage_rewards["rancher_points"] = max(0, rp_total)

	return {
		"stage_id": stage.id,
		"seed": battle_seed,
		"winner": stage_winner,
		"last_encounter_index": last_index,
		"encounters": encounter_logs,
		"rewards": stage_rewards,
	}


## Internal: run a single encounter using a pre-built player_team and
## enemy_monsters list. Mutates `player_team` in place so HP carries
## across calls.
static func _simulate_encounter(
		rng: RandomNumberGenerator,
		player_team: Array,
		enemy_monsters: Array[MonsterResource],
		rp_mult: float,
		battle_seed: int) -> Dictionary:
	var enemy_team: Array = []
	for i in enemy_monsters.size():
		enemy_team.append(_make_combatant_from_monster(enemy_monsters[i], i, "enemy"))

	var frames: Array[Dictionary] = []
	var winner: String = "draw"
	var ticks_elapsed: int = TICK_CAP

	for tick in range(TICK_CAP):
		_tick_statuses(player_team)
		_tick_statuses(enemy_team)

		for c in player_team:
			if float(c["hp"]) <= 0.0:
				continue
			_act(tick, c, player_team, enemy_team, frames, rng)
			if _all_dead(enemy_team):
				break
		if _all_dead(enemy_team):
			winner = "player"
			ticks_elapsed = tick + 1
			break
		for c in enemy_team:
			if float(c["hp"]) <= 0.0:
				continue
			_act(tick, c, enemy_team, player_team, frames, rng)
			if _all_dead(player_team):
				break
		if _all_dead(player_team):
			winner = "enemy"
			ticks_elapsed = tick + 1
			break

	var rewards: Dictionary = {}
	if winner == "player":
		var rp_total: int = 0
		for m in enemy_monsters:
			rp_total += int(m.tier)
		rp_total = int(floor(float(rp_total) * rp_mult))
		rewards["rancher_points"] = max(0, rp_total)

	return {
		"seed": battle_seed,
		"winner": winner,
		"ticks": ticks_elapsed,
		"frames": frames,
		"rewards": rewards,
	}


# region — combatant construction

static func _make_combatant_from_pet(pet: PetResource, index: int, team: String) -> Dictionary:
	return {
		"team": team,
		"index": index,
		"id": String(pet.id),
		"hp": pet.base_hp,
		"max_hp": pet.base_hp,
		"atk": pet.base_attack,
		"def": pet.base_defense,
		"ability_id": pet.ability_id,
		"ability_cooldown": 2,           # short startup so abilities aren't t=0
		"status_effects": [],
	}


static func _make_combatant_from_monster(monster: MonsterResource, index: int, team: String) -> Dictionary:
	# Monsters in battle: stats derived from tier so the fight is meaningful.
	var tier: int = max(1, monster.tier)
	return {
		"team": team,
		"index": index,
		"id": String(monster.id),
		"hp": float(20 * tier + 10),
		"max_hp": float(20 * tier + 10),
		"atk": float(4 * tier + 4),
		"def": float(2 * tier),
		"ability_id": StringName(""),    # monsters basic-attack only
		"ability_cooldown": 0,
		"status_effects": [],
	}

# endregion


# region — tick processing

static func _tick_statuses(team: Array) -> void:
	for c in team:
		if c["ability_cooldown"] > 0:
			c["ability_cooldown"] = int(c["ability_cooldown"]) - 1
		var kept: Array = []
		for s in c["status_effects"]:
			if not (s is Dictionary):
				continue
			# Phase 12d: apply per-tick effects BEFORE decrementing
			# the duration. bleed deals magnitude damage each tick;
			# def_buff and taunted are passive (consulted elsewhere).
			if s.get("type", "") == "bleed":
				var dmg: int = int(s.get("magnitude", 0))
				if dmg > 0 and float(c["hp"]) > 0.0:
					c["hp"] = max(0.0, float(c["hp"]) - float(dmg))
			s["ticks_remaining"] = int(s["ticks_remaining"]) - 1
			if s["ticks_remaining"] > 0:
				kept.append(s)
		c["status_effects"] = kept


static func _act(
		tick: int,
		caster: Dictionary,
		allies: Array,
		enemies: Array,
		frames: Array[Dictionary],
		rng: RandomNumberGenerator) -> void:
	var ability_id: StringName = caster["ability_id"]
	if ability_id != StringName("") and int(caster["ability_cooldown"]) <= 0:
		var cb: Callable = AbilityRegistry.get_ability(ability_id)
		if cb.is_valid():
			var produced: Array[Dictionary] = cb.call(tick, caster, allies, enemies, rng)
			for f in produced:
				frames.append(f)
			return
	# Basic attack on lowest-HP enemy, but route through the taunt-
	# aware picker so a taunting enemy redirects all targeting onto
	# itself for the duration of its taunted status.
	var target: Dictionary = AbilityRegistry.pick_target_with_taunt(enemies)
	if target.is_empty():
		return
	var variance: float = rng.randf_range(0.85, 1.15)
	var damage: int = int(max(1.0, (float(caster["atk"]) - _effective_def(target)) * variance))
	target["hp"] = max(0.0, float(target["hp"]) - float(damage))
	frames.append({
		"tick": tick,
		"actor": "%s_%d" % [caster["team"], caster["index"]],
		"target": "%s_%d" % [target["team"], target["index"]],
		"action": "basic_attack",
		"damage": damage,
		"hp_remaining": int(target["hp"]),
		"status_changes": [],
	})


static func _pick_lowest_hp(team: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_hp: float = INF
	for c in team:
		if not (c is Dictionary):
			continue
		var hp: float = float(c["hp"])
		if hp <= 0.0:
			continue
		if hp < best_hp:
			best = c
			best_hp = hp
	return best


static func _effective_def(c: Dictionary) -> float:
	var base: float = float(c["def"])
	var bonus: float = 0.0
	for s in c.get("status_effects", []):
		if s is Dictionary and s.get("type", "") == "def_buff":
			bonus += base * float(s.get("magnitude", 0.0))
	return base + bonus


static func _all_dead(team: Array) -> bool:
	for c in team:
		if c is Dictionary and float(c["hp"]) > 0.0:
			return false
	return true

# endregion
