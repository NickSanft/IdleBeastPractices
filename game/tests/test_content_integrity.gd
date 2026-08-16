## Content integrity — authored goals must be reachable with shipped content.
##
## Motivated by two live defects that shared one shape: a goal whose target
## could never be met, sitting in a slot that only releases on completion.
##
##   1. `long_pets_10` asked for 10 pets in a game that contains 3.
##   2. `long_prestige_25` asked for 25 prestiges while `GameState
##      .prestige_count` was pinned at 1 (it lived in `_reset_to_defaults`,
##      which doubles as the post-prestige reset, so `prestige_count += 1`
##      always ran against a freshly-zeroed field).
##
## `QuestLog._pick_for_slot` sorts eligible ids alphabetically and takes the
## first, and a slot holds its pick until that quest completes — so either
## defect pins its slot for the lifetime of the save and starves every quest
## that sorts after it. Between them they starved 12 of the 20 SHORT/MEDIUM/
## LONG quests.
##
## The pre-existing quest tests could not catch this because they drive the
## evaluator with hand-built fixtures (test_quest_log.gd:166 *assigns*
## `active_quests = {2: "long_prestige_1"}` and asserts it round-trips) —
## they never ask the picker what it would choose from real content, and
## never advance a quest through its own source. This file checks the
## shipped DATA and the real completion path instead.
##
## Two axes are covered, because the two defects are genuinely different:
##   - supply:  threshold <= what the content can ever supply.
##   - plumbing: the counter a quest reads actually advances in live play.
extends GutTest

## Sources whose value is an unbounded counter — no amount of authored
## content caps them, so `threshold <= supply` is not a meaningful question.
## Kept as an EXPLICIT list rather than a default branch: a newly added
## bounded source must be classified deliberately (see
## `test_every_quest_source_is_classified`) instead of silently falling
## through and never being checked. That silent-skip is exactly what hid
## the `prestige_5` / `prestige_25` gap.
const _UNBOUNDED_QUEST_SOURCES: Array[int] = [
	QuestResource.Source.LEDGER_FIELD,
	QuestResource.Source.PRESTIGE_COUNT,
	QuestResource.Source.RUN_GOLD_EARNED,
]
const _UNBOUNDED_ACHIEVEMENT_SOURCES: Array[int] = [
	AchievementResource.Source.LEDGER_FIELD,
	AchievementResource.Source.PRESTIGE_COUNT,
]

## Achievements deliberately unreachable with today's content.
##
## Unlike a quest, an unmet achievement blocks nothing — `Achievements`
## evaluates every entry independently, so it simply stays locked rather
## than pinning a slot.
##
## Empty since Phase 15a. The sole entry was `pet_10` (100 RP), held as
## aspirational content "that becomes earnable the moment a pet-progression
## system grows the roster past 3" — which it now is: pets exist for every
## tier 1-20, so the supply is 60. `test_exempt_achievements_are_still_
## actually_unreachable` is what caught the staleness.
const _UNREACHABLE_ACHIEVEMENT_EXEMPTIONS: Array[StringName] = []

## Mirrors ContentRegistry's directory constants. Duplicated deliberately:
## the uniqueness test must observe ids BEFORE the registry indexes them
## into a Dictionary, because that indexing is what hides duplicates.
const _CONTENT_DIRS := {
	"monsters": "res://game/data/monsters",
	"items": "res://game/data/items",
	"nets": "res://game/data/nets",
	"pets": "res://game/data/pets",
	"upgrades": "res://game/data/upgrades",
	"recipes": "res://game/data/recipes",
	"dialogue": "res://game/data/dialogue",
	"battle_stages": "res://game/data/battle_stages",
	"equipment": "res://game/data/equipment",
	"achievements": "res://game/data/achievements",
	"quests": "res://game/data/quests",
}


func before_each() -> void:
	GameState._reset_to_defaults()
	GameState.active_quests = {0: "", 1: "", 2: ""}
	GameState.quests_completed = {}
	ContentRegistry.ensure_loaded()


func after_each() -> void:
	GameState._reset_to_defaults()
	GameState.active_quests = {0: "", 1: "", 2: ""}
	GameState.quests_completed = {}


# region — supply helpers

## Distinct pets the player can ever own. Pets are granted only from
## monsters carrying a non-null `pet` reference (`CatchingSystem
## .pets_to_award_for_tier`), and `GameState.add_pet` keys `pets_owned` by
## pet id — so duplicates and variants collapse to a single entry.
func _pet_supply() -> int:
	var ids: Dictionary = {}
	for m in ContentRegistry.monsters():
		if m.pet == null:
			continue
		ids[StringName(m.pet.id)] = true
	return ids.size()


func _net_supply() -> int:
	return ContentRegistry.nets().size()


## Recipes that can actually be crafted. `CraftingSystem.can_craft` rejects
## any recipe with no output at all ("no_output"), which keeps the
## `recipe_tier4_net` tombstone out of `recipes_crafted` forever.
func _craftable_recipes() -> Array:
	var out: Array = []
	for r in ContentRegistry.recipes():
		if r.output_item == null and r.output_net == null and r.output_equipment == null:
			continue
		out.append(r)
	return out


func _max_tier_supply() -> int:
	var best: int = 0
	for m in ContentRegistry.monsters():
		best = maxi(best, int(m.tier))
	return best


## Supply ceiling for a bounded source; -1 for sources this helper does not
## bound. Callers must treat -1 as "unclassified" and cross-check it against
## the explicit unbounded lists rather than silently skipping.
func _supply_for_source(source: int) -> int:
	match source:
		QuestResource.Source.PETS_OWNED_COUNT:
			return _pet_supply()
		QuestResource.Source.NETS_OWNED_COUNT:
			return _net_supply()
		QuestResource.Source.RECIPES_CRAFTED_COUNT:
			return _craftable_recipes().size()
		QuestResource.Source.CURRENT_MAX_TIER:
			return _max_tier_supply()
	return -1

# endregion


# region — every source is deliberately classified

## Forces an author decision on any newly added Source: it must either be
## given a supply bound above or be listed as unbounded. Without this, a new
## bounded source falls through `_supply_for_source`'s -1 and is never
## reachability-checked — silently, and forever.
func test_every_quest_source_is_classified() -> void:
	for name in QuestResource.Source.keys():
		var value: int = QuestResource.Source[name]
		var is_bounded: bool = _supply_for_source(value) >= 0
		var is_unbounded: bool = _UNBOUNDED_QUEST_SOURCES.has(value)
		assert_true(
			is_bounded != is_unbounded,
			"QuestResource.Source.%s must be exactly one of {supply-bounded, explicitly unbounded} — it is neither or both" % name)


func test_every_achievement_source_is_classified() -> void:
	for name in AchievementResource.Source.keys():
		var value: int = AchievementResource.Source[name]
		var is_bounded: bool = _supply_for_source(value) >= 0
		var is_unbounded: bool = _UNBOUNDED_ACHIEVEMENT_SOURCES.has(value)
		assert_true(
			is_bounded != is_unbounded,
			"AchievementResource.Source.%s must be exactly one of {supply-bounded, explicitly unbounded} — it is neither or both" % name)


## `_supply_for_source` is written against QuestResource.Source ordinals but
## is also fed AchievementResource.Source values. That is safe only while the
## two enums agree on the ordinals they share — and .tres files serialise
## `source` as a bare integer, so a divergence would silently repoint shipped
## content. Pin the overlap.
func test_quest_and_achievement_source_ordinals_agree() -> void:
	for name in AchievementResource.Source.keys():
		assert_true(
			QuestResource.Source.has(name),
			"AchievementResource.Source.%s has no QuestResource counterpart" % name)
		if QuestResource.Source.has(name):
			assert_eq(
				int(AchievementResource.Source[name]), int(QuestResource.Source[name]),
				"ordinal mismatch for Source.%s — shipped .tres files store the raw int" % name)

# endregion


# region — supply reachability

func test_every_quest_with_a_bounded_source_is_reachable() -> void:
	var checked: int = 0
	for q in ContentRegistry.quests():
		var supply: int = _supply_for_source(q.source)
		if supply < 0:
			continue
		checked += 1
		assert_true(
			int(q.threshold) <= supply,
			"quest '%s' needs %d but content supplies only %d — an unsatisfiable quest permanently deadlocks its QuestLog slot"
					% [String(q.id), int(q.threshold), supply])
	assert_gt(checked, 0, "expected at least one bounded-source quest to check")


func test_every_achievement_with_a_bounded_source_is_reachable() -> void:
	var checked: int = 0
	for a in ContentRegistry.achievements():
		var supply: int = _supply_for_source(a.source)
		if supply < 0:
			continue
		if _UNREACHABLE_ACHIEVEMENT_EXEMPTIONS.has(StringName(a.id)):
			continue
		checked += 1
		assert_true(
			int(a.threshold) <= supply,
			"achievement '%s' needs %d but content supplies only %d — its reward is unobtainable"
					% [String(a.id), int(a.threshold), supply])
	assert_gt(checked, 0, "expected at least one bounded-source achievement to check")


## Guards the exemption list against going stale: an entry that has BECOME
## reachable should be promoted back into the assertion above.
func test_exempt_achievements_are_still_actually_unreachable() -> void:
	# The list is empty as of Phase 15a. Assert that explicitly rather than
	# letting the loop below no-op, which GUT reports as a Risky
	# (assertion-free) test and which would hide a future entry being added
	# and then silently skipped.
	if _UNREACHABLE_ACHIEVEMENT_EXEMPTIONS.is_empty():
		assert_true(true, "no achievements are exempt — every one is reachable")
		return
	for id in _UNREACHABLE_ACHIEVEMENT_EXEMPTIONS:
		var a: AchievementResource = ContentRegistry.achievement(id)
		assert_not_null(a, "exempt achievement '%s' no longer exists — drop it from the list" % String(id))
		if a == null:
			continue
		var supply: int = _supply_for_source(a.source)
		assert_true(
			supply >= 0 and int(a.threshold) > supply,
			"achievement '%s' is now reachable (needs %d, supply %d) — remove the exemption"
					% [String(id), int(a.threshold), supply])


## A LEDGER_FIELD threshold is unbounded, but its KEY is not: `_evaluate_value`
## returns `ledger.get(key, 0)`, so a typo'd key reads 0 forever and pins its
## slot exactly like an impossible threshold. Checked against the DEFAULT
## ledger — an authoring-time guard, not a runtime invariant (`from_dict`
## replaces the dict wholesale with no key union).
func test_ledger_field_goals_reference_real_ledger_keys() -> void:
	var valid: Array = GameState.ledger.keys()
	assert_gt(valid.size(), 0, "default ledger should be populated in before_each")
	for q in ContentRegistry.quests():
		if q.source != QuestResource.Source.LEDGER_FIELD:
			continue
		assert_true(
			valid.has(String(q.ledger_field)),
			"quest '%s' reads ledger key '%s', which does not exist — it would evaluate 0 forever"
					% [String(q.id), String(q.ledger_field)])
	for a in ContentRegistry.achievements():
		if a.source != AchievementResource.Source.LEDGER_FIELD:
			continue
		assert_true(
			valid.has(String(a.ledger_field)),
			"achievement '%s' reads ledger key '%s', which does not exist"
					% [String(a.id), String(a.ledger_field)])

# endregion


# region — the counters quests read must actually advance

## The plumbing axis. `prestige_count` shipped pinned at 1 because
## `perform_prestige` calls `_reset_to_defaults()` (which zeroes it) and then
## increments — so every PRESTIGE_COUNT goal above 1 was unreachable no
## matter how the content was authored. Drive the REAL prestige path; a
## supply-style data check cannot see this class of defect.
func test_prestige_count_accumulates_across_real_prestiges() -> void:
	for i in 3:
		GameState.add_gold(BigNumber.from_float(2_000_000.0))
		GameState.perform_prestige()
	assert_eq(GameState.prestige_count, 3,
			"prestige_count must survive the post-prestige reset — quests, achievements and narrator gating all read it")
	assert_eq(int(GameState.ledger.get("prestige_count", 0)), 3,
			"the ledger mirror must stay in step with the root counter")


## Saves written before prestige_count joined the keep-list have a root field
## of 1 and a truthful ledger. Loading one must heal the root field rather
## than stranding a veteran two rungs from the LONG quests they earned.
func test_legacy_save_heals_prestige_count_from_the_ledger() -> void:
	GameState.from_dict({
		"prestige_count": 1,
		"ledger": {"prestige_count": 30},
	})
	assert_eq(GameState.prestige_count, 30,
			"a pre-fix save should take the ledger's lifetime total")


func test_healing_never_lowers_a_healthy_prestige_count() -> void:
	GameState.from_dict({
		"prestige_count": 12,
		"ledger": {"prestige_count": 0},
	})
	assert_eq(GameState.prestige_count, 12, "the heal is a MAX, never a downgrade")

# endregion


# region — slot drain regressions

## `long_pets_10` sorts first among LONG quests, so it is always the opening
## pick. With the roster owned it must CLEAR and hand the slot on; before the
## threshold fix it was picked, never satisfied, and pinned the slot forever.
func test_long_slot_advances_past_the_pet_quest_with_a_full_roster() -> void:
	for pet in ContentRegistry.pets():
		GameState.pets_owned.append(String(pet.id))

	QuestLog._initial_fill()
	QuestLog.evaluate_progress()

	assert_true(
		GameState.quests_completed.has("long_pets_10"),
		"'long_pets_10' should complete with the full roster owned, not pin the slot")
	var now_active: String = String(GameState.active_quests.get(QuestLog.SLOT_LONG, ""))
	assert_ne(now_active, "", "LONG slot should refill after the pet quest clears")
	assert_ne(now_active, "long_pets_10", "LONG slot should have moved on")


## Put the player in a state where every authored goal is genuinely met, then
## pump the evaluator and require the whole pool to drain.
##
## The earlier draft of this test hand-wrote `quests_completed[qid] = true` to
## advance the picker, which made it threshold-independent — it passed against
## the very data it claimed to guard. This version never touches
## `quests_completed`; each quest must complete through `evaluate_progress`
## reading its own source, so an unsatisfiable threshold stalls the drain and
## the assertion names it.
func _satisfy_every_source() -> void:
	for pet in ContentRegistry.pets():
		GameState.pets_owned.append(String(pet.id))
	for net in ContentRegistry.nets():
		GameState.nets_owned.append(String(net.id))
	for r in _craftable_recipes():
		GameState.recipes_crafted.append(String(r.id))
	GameState.current_max_tier = _max_tier_supply()
	GameState.prestige_count = 10_000
	GameState.ledger["prestige_count"] = 10_000
	for key in ["total_catches", "total_taps", "total_shinies"]:
		GameState.ledger[key] = 1_000_000_000
	# Comfortably above the largest authored gold threshold (1M) but well
	# inside int64: `_evaluate_value` funnels RUN_GOLD_EARNED through
	# `int(BigNumber.to_float())`, and an astronomically large value overflows
	# the cast instead of satisfying the quest.
	GameState.total_gold_earned_this_run = BigNumber.from_float(1.0e12).to_dict()


func _assert_tier_drains(quest_tier: int, tier_label: String) -> void:
	var expected: Dictionary = {}
	for q in ContentRegistry.quests():
		if q.quest_tier == quest_tier:
			expected[String(q.id)] = true

	_satisfy_every_source()
	# One evaluate per quest is enough (each pass completes the slot's quest
	# and refills), plus slack for ladder hops.
	for _i in expected.size() * 2 + 4:
		QuestLog.evaluate_progress()

	for id in expected.keys():
		assert_true(
			GameState.quests_completed.has(id),
			"%s quest '%s' never completed even with every source maxed — it is unsatisfiable and pins its slot"
					% [tier_label, id])


func test_every_long_quest_completes_from_a_fully_satisfied_state() -> void:
	_assert_tier_drains(QuestResource.QuestTier.LONG, "LONG")


func test_every_medium_quest_completes_from_a_fully_satisfied_state() -> void:
	_assert_tier_drains(QuestResource.QuestTier.MEDIUM, "MEDIUM")


func test_every_short_quest_completes_from_a_fully_satisfied_state() -> void:
	_assert_tier_drains(QuestResource.QuestTier.SHORT, "SHORT")

# endregion


# region — registry integrity

## Ids must be observed BEFORE ContentRegistry indexes them: `_load_dir`
## writes `target[StringName(id)] = res`, so a duplicate silently clobbers
## its predecessor and only one entry ever reaches the accessor arrays. A
## scan of the registry therefore cannot see duplicates at all — this walks
## the directories directly, mirroring `_load_dir`'s file filter and its
## `.remap` trim so exported layouts do not double-count.
func _ids_on_disk(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	var seen_files: Dictionary = {}
	dir.list_dir_begin()
	while true:
		var entry: String = dir.get_next()
		if entry == "":
			break
		if dir.current_is_dir():
			continue
		if not entry.ends_with(".tres") and not entry.ends_with(".tres.remap") and not entry.ends_with(".res"):
			continue
		if entry.ends_with(".remap"):
			entry = entry.trim_suffix(".remap")
		if seen_files.has(entry):
			continue
		seen_files[entry] = true
		var res: Resource = load("%s/%s" % [dir_path, entry])
		if res == null:
			continue
		var id_value: Variant = res.get("id")
		if id_value == null:
			continue
		out.append(String(id_value))
	dir.list_dir_end()
	return out


func test_ids_are_unique_and_non_blank_within_each_category() -> void:
	var total: int = 0
	for category in _CONTENT_DIRS.keys():
		var seen: Dictionary = {}
		for id in _ids_on_disk(_CONTENT_DIRS[category]):
			total += 1
			assert_false(id.is_empty(), "%s: a resource has a blank id (ContentRegistry drops it silently)" % category)
			assert_false(seen.has(id), "%s: duplicate id '%s' — the later file clobbers the earlier one at load" % [category, id])
			seen[id] = true
	assert_gt(total, 0, "expected to scan at least one content resource")

# endregion
