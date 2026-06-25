## Phase 14c — tier ribbon (formerly `next_goal_chip`) behaviour.
##
## The ribbon should:
##   1. Report missing-species count when not every species at the
##      current tier has been seen yet.
##   2. Switch to "X / N catches" mode once every species is seen.
##   3. Advance its fill bar as `max_count` grows toward the threshold.
##   4. Clamp the bar fill at 1.0 even past the threshold.
##   5. Render the correct T-badge for the current max tier.
##   6. Use the styles.css tier names for tiers 1–3.
##
## 14c rewrite notes: the old chip used a single `_label` + Godot
## `ProgressBar` (`_bar`). The Dusk ribbon splits into `_badge_label`,
## `_name_label` (RichTextLabel with bbcode), `_bar_fill` (ColorRect
## anchored fill), and `_pct_label`. Tests now assert against each
## piece independently.
extends GutTest

const _SCENE := preload("res://game/scenes/ui/next_goal_chip.tscn")


func before_each() -> void:
	GameState.from_dict({})
	ContentRegistry.ensure_loaded()
	Settings.debug_fast_pets = false
	# Reset the accessibility slider so the live-rescale test below doesn't
	# leak its 1.5× into other tests' badge-size expectations.
	Settings.font_scale = 1.0


func after_each() -> void:
	# The live-rescale test bumps font_scale to 1.5; reset it so the value
	# never leaks into a later test FILE (before_each only guards this file).
	Settings.font_scale = 1.0


func test_starts_with_species_left_message() -> void:
	# Fresh state — no monsters caught means every tier-1 species is
	# "left to find". Ribbon should report that count, not catch progress.
	var chip: PanelContainer = _SCENE.instantiate()
	add_child_autofree(chip)
	await wait_frames(2)
	assert_string_contains(chip._name_label.text, "species left",
			"ribbon should report missing-species count when none are seen")


func test_shows_catch_progress_after_seeing_each_species() -> void:
	# Catch one of each tier-1 species so missing list is empty —
	# ribbon should switch to catch progress mode.
	for m in ContentRegistry.monsters():
		if m.tier == 1:
			GameState.record_catch(m.id, false, "tap")
	var chip: PanelContainer = _SCENE.instantiate()
	add_child_autofree(chip)
	await wait_frames(2)
	assert_string_contains(chip._name_label.text, "/ 25 catches",
			"ribbon should switch to catch progress once every species is seen")


func test_progress_bar_advances_with_catches() -> void:
	# Catch many of one species — bar should track max_count / threshold.
	# Catch 1 of each first to clear the missing-species gate.
	for m in ContentRegistry.monsters():
		if m.tier == 1:
			GameState.record_catch(m.id, false, "tap")
	# Then 14 more of green_wisplet (so max_count = 15 of 25 = 0.6).
	for i in 14:
		GameState.record_catch(&"green_wisplet", false, "tap")
	var chip: PanelContainer = _SCENE.instantiate()
	add_child_autofree(chip)
	await wait_frames(2)
	# 14c: the fill is a ColorRect whose `anchor_right` is tweened
	# 0..1. Assert against that, not the (now-removed) ProgressBar.
	assert_almost_eq(chip._bar_fill.anchor_right, 15.0 / 25.0, 0.05,
			"bar fill should reflect max_count / threshold (15/25 ≈ 0.6)")
	# Percent label should round to the same fraction.
	assert_string_contains(chip._pct_label.text, "60",
			"pct label should display 60%% at 15/25 catches")


func test_bar_clamps_at_one() -> void:
	# Catch past the threshold — fill shouldn't overflow.
	for m in ContentRegistry.monsters():
		if m.tier == 1:
			for i in 30:
				GameState.record_catch(m.id, false, "tap")
	var chip: PanelContainer = _SCENE.instantiate()
	add_child_autofree(chip)
	await wait_frames(2)
	assert_almost_eq(chip._bar_fill.anchor_right, 1.0, 0.001,
			"bar fill must cap at 1.0 even when max_count exceeds threshold")
	# 100% should also render in the pct label.
	assert_string_contains(chip._pct_label.text, "100",
			"pct label should display 100%% past the threshold")


func test_badge_shows_current_max_tier() -> void:
	# styles.css `.tier-ribbon .badge` renders the current tier as
	# "T1", "T2", etc. The ribbon reads GameState.current_max_tier.
	GameState.current_max_tier = 2
	var chip: PanelContainer = _SCENE.instantiate()
	add_child_autofree(chip)
	await wait_frames(2)
	assert_eq(chip._badge_label.text, "T2",
			"badge should render 'T%%d' for the current max tier")


func test_tier_name_lookup_uses_styles_css_labels() -> void:
	# styles.css names tiers 1–3: Bog Hollow, Whisper Glade, Ash Reach.
	# Beyond 3 we fall back to "Tier N".
	GameState.current_max_tier = 1
	var chip: PanelContainer = _SCENE.instantiate()
	add_child_autofree(chip)
	await wait_frames(2)
	assert_string_contains(chip._name_label.text, "Bog Hollow",
			"tier 1 should display as 'Bog Hollow' per styles.css")

	# Direct unit-test of the lookup helper to cover the other two tiers
	# without having to swap GameState in three separate ribbon builds.
	assert_eq(chip._tier_name(1), "Bog Hollow")
	assert_eq(chip._tier_name(2), "Whisper Glade")
	assert_eq(chip._tier_name(3), "Ash Reach")
	assert_eq(chip._tier_name(7), "Tier 7",
			"tiers past the named 3 should fall back to 'Tier N'")


func test_badge_font_rescales_with_accessibility_slider() -> void:
	# v0.15.13 — the T-badge font size is an inline UiScale.size(9) override
	# (a single Label can't be sized by a theme variation), so it must be
	# re-applied live when the accessibility slider moves. Otherwise the
	# badge stays small while the tier % beside it grows — visibly mismatched.
	var chip: PanelContainer = _SCENE.instantiate()
	add_child_autofree(chip)
	await wait_frames(2)
	assert_true(chip._badge_label.has_theme_font_size_override("font_size"),
			"badge must carry an inline font_size override")
	# get_theme_font_size resolves the local override first, so it returns
	# the inline value the chip set.
	var base_size: int = chip._badge_label.get_theme_font_size("font_size")
	assert_eq(base_size, UiScale.size(9),
			"badge should start at the 1.0× scaled 9-px size")
	# Bump the slider — the chip subscribes to accessibility_settings_changed
	# and re-applies UiScale.size(9), which reads the new font_scale. Use the
	# emitting setter (a bare `font_scale =` assignment changes the value but
	# fires no signal, so the chip would never re-apply).
	Settings.set_font_scale(1.5)
	await wait_frames(1)
	var scaled_size: int = chip._badge_label.get_theme_font_size("font_size")
	assert_eq(scaled_size, UiScale.size(9),
			"badge font size must follow the live font_scale (UiScale.size(9) at 1.5×)")
	assert_gt(scaled_size, base_size,
			"badge font must actually grow when the accessibility slider increases")
