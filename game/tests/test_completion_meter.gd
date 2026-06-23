## v0.15.12 — bestiary completion meter + scaling tier-completion RP bonus.
##
## Covers:
##   - CatchingSystem.bestiary_completion (pure species-caught count)
##   - CatchingSystem.tier_completion_rp (scaling, clamped at 0)
##   - The tier-completion RP grant (+tier RP, once per tier, survives reload)
##   - The Bestiary header meter label + bar reflecting the caught count
##   - The Ledger "Species catalogued" echo row
extends GutTest

const _BESTIARY := preload("res://game/scenes/bestiary/bestiary_view.tscn")
const _LEDGER := preload("res://game/scenes/ledger/ledger_view.tscn")
const _CATCHING := preload("res://game/scenes/catching/catching_view.tscn")


func before_each() -> void:
	GameState.from_dict({})
	ContentRegistry.ensure_loaded()


# region — pure helpers

func test_bestiary_completion_counts_caught_species() -> void:
	var monsters := ContentRegistry.monsters()
	var c0: Dictionary = CatchingSystem.bestiary_completion(monsters, {})
	assert_eq(int(c0["caught"]), 0, "nothing caught → 0")
	assert_eq(int(c0["total"]), monsters.size())
	assert_almost_eq(float(c0["fraction"]), 0.0, 0.001)

	var caught: Dictionary = {}
	caught[String(monsters[0].id)] = {"normal": 1, "shiny": 0}   # normal counts
	caught[String(monsters[1].id)] = {"normal": 0, "shiny": 2}   # shiny-only counts
	var c2: Dictionary = CatchingSystem.bestiary_completion(monsters, caught)
	assert_eq(int(c2["caught"]), 2)
	assert_almost_eq(float(c2["fraction"]), 2.0 / float(monsters.size()), 0.001)

	# A logged-but-zero entry must NOT count as caught.
	caught[String(monsters[2].id)] = {"normal": 0, "shiny": 0}
	var c2b: Dictionary = CatchingSystem.bestiary_completion(monsters, caught)
	assert_eq(int(c2b["caught"]), 2, "a zero-count entry must not count toward completion")


func test_tier_completion_rp_scales_and_clamps() -> void:
	assert_eq(CatchingSystem.tier_completion_rp(1), 1)
	assert_eq(CatchingSystem.tier_completion_rp(10), 10)
	assert_eq(CatchingSystem.tier_completion_rp(20), 20)
	assert_eq(CatchingSystem.tier_completion_rp(0), 0)
	assert_eq(CatchingSystem.tier_completion_rp(-4), 0, "negative tier clamps to 0 RP")

# endregion


# region — tier-completion RP grant

func test_tier_completion_grants_scaling_rp() -> void:
	var view: Control = _CATCHING.instantiate()
	add_child_autofree(view)
	await wait_frames(1)
	var before: int = GameState.current_rancher_points()
	view._award_tier_completion(5)
	assert_eq(GameState.current_rancher_points(), before + 5,
			"completing tier 5 must grant +5 RP")


func test_tier_completion_rp_not_double_granted() -> void:
	var view: Control = _CATCHING.instantiate()
	add_child_autofree(view)
	await wait_frames(1)
	view._award_tier_completion(3)
	var after_first: int = GameState.current_rancher_points()
	# Re-running the award for an already-completed tier (the idempotent
	# reconcile path) must NOT re-grant the RP.
	view._award_tier_completion(3)
	assert_eq(GameState.current_rancher_points(), after_first,
			"re-completing an already-completed tier must not re-grant RP")


func test_tier_rp_not_regranted_after_prestige_reset() -> void:
	# The exploit guard: prestige resets tiers_completed (player re-climbs)
	# but keeps monsters_caught, so tiers re-complete on the first catch.
	# The one-time RP ledger (tiers_rp_awarded) must stop a re-payout.
	var view: Control = _CATCHING.instantiate()
	add_child_autofree(view)
	await wait_frames(1)
	view._award_tier_completion(4)
	var after_first: int = GameState.current_rancher_points()
	assert_true(GameState.tiers_rp_awarded.has(4), "first completion records the RP award")
	# Simulate the prestige reset of per-run tier progress.
	GameState.tiers_completed.clear()
	view._award_tier_completion(4)
	assert_eq(GameState.current_rancher_points(), after_first,
			"re-completing a tier after a prestige reset must NOT re-grant the RP")


func test_tiers_rp_awarded_persists_across_prestige() -> void:
	GameState.tiers_rp_awarded = [1, 5, 10]
	GameState.total_gold_earned_this_run = BigNumber.from_float(4_000_000.0).to_dict()
	GameState.currencies["gold"] = BigNumber.from_float(4_000_000.0).to_dict()
	GameState.perform_prestige()
	assert_eq(GameState.tiers_rp_awarded, [1, 5, 10],
			"the one-time tier-RP ledger must survive prestige (tiers stay paid)")


func test_tiers_rp_awarded_round_trips_through_save() -> void:
	GameState.tiers_rp_awarded = [2, 7]
	var snap: Dictionary = GameState.to_dict()
	GameState.from_dict({})
	assert_eq(GameState.tiers_rp_awarded, [], "a fresh save clears the ledger")
	GameState.from_dict(snap)
	assert_eq(GameState.tiers_rp_awarded, [2, 7], "the ledger restores from save")


func test_tier_completed_emits_before_rp_is_recorded() -> void:
	# The "+N RP" celebration line is shown only on a first-ever completion.
	# The handler reads tiers_rp_awarded during the tier_completed emit, so
	# the emit MUST fire before the grant records the tier — otherwise a
	# post-prestige replay would falsely claim "+RP". Pin that ordering.
	var view: Control = _CATCHING.instantiate()
	add_child_autofree(view)
	await wait_frames(1)
	var awarded_at_emit: Array = [null]
	var probe: Callable = func(t: int) -> void:
		awarded_at_emit[0] = GameState.tiers_rp_awarded.has(t)
	EventBus.tier_completed.connect(probe)
	view._award_tier_completion(6)
	EventBus.tier_completed.disconnect(probe)
	assert_eq(awarded_at_emit[0], false,
			"at tier_completed emit time the tier must NOT yet be in tiers_rp_awarded (first completion → celebration shows +RP)")
	assert_true(GameState.tiers_rp_awarded.has(6),
			"after the grant the tier is recorded (a replay would read true → no +RP shown)")

# endregion


# region — Bestiary header meter

func test_bestiary_meter_reflects_caught_count() -> void:
	var view: Control = _BESTIARY.instantiate()
	add_child_autofree(view)
	view.size = Vector2(720, 1100)
	await wait_frames(2)
	var monsters := ContentRegistry.monsters()
	for i in 3:
		GameState.monsters_caught[String(monsters[i].id)] = {"normal": 1, "shiny": 0}
	view._update_completion_meter(false)
	assert_string_contains(view._completion_label.text, "3 / %d" % monsters.size(),
			"meter label must show caught / total species")
	assert_almost_eq(view._completion_bar.value, 3.0 / float(monsters.size()), 0.001,
			"meter bar value must equal the caught fraction")


func test_bestiary_meter_starts_at_zero() -> void:
	var view: Control = _BESTIARY.instantiate()
	add_child_autofree(view)
	view.size = Vector2(720, 1100)
	await wait_frames(2)
	assert_string_contains(view._completion_label.text, "0 /",
			"a fresh save shows 0 species caught")
	assert_almost_eq(view._completion_bar.value, 0.0, 0.001)

# endregion


# region — Ledger echo

func test_ledger_shows_species_catalogued_row() -> void:
	var monsters := ContentRegistry.monsters()
	GameState.monsters_caught[String(monsters[0].id)] = {"normal": 1, "shiny": 0}
	var view: Control = _LEDGER.instantiate()
	add_child_autofree(view)
	view.size = Vector2(720, 1100)
	await wait_frames(2)
	view._refresh()
	assert_true(_tree_has_label_containing(view, "Species catalogued"),
			"the Ledger must show a 'Species catalogued' row")

# endregion


func _tree_has_label_containing(root: Node, needle: String) -> bool:
	if root is Label and String((root as Label).text).contains(needle):
		return true
	for child in root.get_children():
		if _tree_has_label_containing(child, needle):
			return true
	return false
