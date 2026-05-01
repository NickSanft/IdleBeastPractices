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

	var enemy_team: Array = []
	for i in enemy_monsters.size():
		enemy_team.append(_make_combatant_from_monster(enemy_monsters[i], i, "enemy"))

	var frames: Array[Dictionary] = []
	var winner: String = "draw"
	var ticks_elapsed: int = TICK_CAP

	for tick in range(TICK_CAP):
		# 1. Tick statuses + cooldowns.
		_tick_statuses(player_team)
		_tick_statuses(enemy_team)

		# 2. Each living combatant acts (player first, then enemy).
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
	# Basic attack on lowest-HP enemy.
	var target: Dictionary = _pick_lowest_hp(enemies)
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
