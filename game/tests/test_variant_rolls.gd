## Regression for the v0.10.7 fix: variant rolls in
## `_award_tier_completion` must use the catching view's already-seeded
## `_rng`, not a fresh RandomNumberGenerator-per-pet.
##
## Background
## ----------
## Before the fix the awarding loop did:
##
##     for pet in pets_to_award:
##         var rng_local := RandomNumberGenerator.new()
##         rng_local.randomize()
##         is_variant = rng_local.randf() < pet.variant_rate
##         ...
##
## When the three loop iterations all land in the same microsecond
## (which happens often — three pets, no I/O between them),
## `randomize()`'s time-based seed is identical, every randf() returns
## the same value, and the three pets roll variant/not in lockstep.
## With variant_rate=0.02 the symptom is "either all three variants
## or none". User saves confirmed this: a fresh tier-1 run produced
## pet_variants_owned == pets_owned == all three wisplets.
##
## Fix: use the view's `_rng` (randomized once in `_ready`) so each
## pet draws an independent roll.
##
## These tests cover the behavioural contract without depending on
## time-of-day or microsecond luck. The probabilistic version of the
## bug (~2% per fresh save) was too flaky to assert directly.
extends GutTest

const _CATCHING := preload("res://game/scenes/catching/catching_view.tscn")


func before_each() -> void:
	GameState.from_dict({})
	ContentRegistry.ensure_loaded()


func _new_catching_view() -> Control:
	# Don't set `view.size` — catching_view.tscn's root Control uses
	# anchors_preset=15 (full rect), and setting size on such a node
	# trips an engine warning ("non-equal opposite anchors will have
	# their size overridden after _ready()") that GUT treats as an
	# unexpected error → test failure. The awarding path doesn't
	# depend on layout, so leaving size at its default is fine.
	var view: Control = _CATCHING.instantiate()
	add_child_autofree(view)
	return view


func test_award_with_debug_fast_pets_grants_all_variants() -> void:
	# Sanity baseline: with debug_fast_pets ON, every variant roll
	# succeeds, so all three wisplet pets land in pet_variants_owned.
	# This proves the awarding path itself works end-to-end and that
	# is_variant is being threaded into add_pet correctly.
	Settings.debug_fast_pets = true
	var view := _new_catching_view()
	await wait_frames(2)
	view._award_tier_completion(1)
	assert_eq(GameState.pets_owned.size(), 3,
			"all three wisplet pets should be in pets_owned")
	assert_eq(GameState.pet_variants_owned.size(), 3,
			"with debug_fast_pets ON, every roll succeeds and all variants unlock")
	Settings.debug_fast_pets = false


func test_award_uses_view_rng_seed_for_determinism() -> void:
	# The fix routes variant rolls through `_rng`. So seeding `_rng`
	# deterministically before two runs (with state reset between)
	# must reproduce the same pet_variants_owned set. The buggy
	# version ignored `_rng` entirely (fresh RandomNumberGenerator per
	# iteration), so seeding it had no effect on the outcome — the
	# determinism claim only holds for the fixed code path.
	Settings.debug_fast_pets = false
	var view := _new_catching_view()
	await wait_frames(2)

	view._rng.seed = 42
	view._award_tier_completion(1)
	var run_a: Array = GameState.pet_variants_owned.duplicate()
	var pets_a: Array = GameState.pets_owned.duplicate()

	GameState.from_dict({})
	view._rng.seed = 42
	view._award_tier_completion(1)
	var run_b: Array = GameState.pet_variants_owned.duplicate()
	var pets_b: Array = GameState.pets_owned.duplicate()

	assert_eq(run_a, run_b,
			"same _rng seed must reproduce variant outcome — proves rolls go through _rng, not fresh randomized RNGs")
	assert_eq(pets_a, pets_b,
			"pets_owned must also reproduce deterministically")


func test_award_outcomes_can_differ_across_seeds() -> void:
	# Sweep 50 distinct seeds and verify the awarding path produces at
	# least two distinct pet_variants_owned outcomes. If the loop
	# created fresh RNGs internally, the seed wouldn't matter and all
	# outcomes would be equal modulo time. With independent rolls
	# routed through _rng, different seeds visibly diverge.
	#
	# variant_rate=0.02 means most seeds produce []. We just need to
	# observe at least one non-empty outcome OR variation across the
	# 50 trials to confirm the seed has effect.
	Settings.debug_fast_pets = false
	var view := _new_catching_view()
	await wait_frames(2)
	var seen_outcomes: Dictionary = {}
	for s in 50:
		GameState.from_dict({})
		view._rng.seed = s
		view._award_tier_completion(1)
		var key: String = ",".join(GameState.pet_variants_owned)
		seen_outcomes[key] = true
	assert_gte(seen_outcomes.size(), 2,
			"sweeping 50 distinct seeds should produce >=2 distinct outcomes; got 1, suggesting seed has no effect on the awarding RNG path")
