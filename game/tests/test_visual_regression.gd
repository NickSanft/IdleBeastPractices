## v0.15.1.1 — visual-regression structural assertions.
##
## Catches the two bug classes the user reported just before this
## test landed:
##
##   1. **Theme not propagating** — main.tscn had a scene-level
##      `theme = main_theme.tres` export that shadowed the Dusk
##      theme assigned at runtime. Dusk reached the window but
##      never reached Main's subtree, so the live UI stayed
##      parchment-colored even though `_apply_mobile_default_theme`
##      had loaded amethyst.tres.
##
##   2. **Phantom safe-area margins** — DeviceLayout._ready called
##      `_recompute()` BEFORE setting `Window.content_scale_factor`,
##      so the cached `safe_area` was sized at the raw
##      viewport_width × viewport_height (720×1280). When
##      content_scale_factor (0.85) later expanded the effective
##      viewport to 847×1505 design dp, the
##      `_apply_safe_area_margins` math:
##         right = view_size.x - (safe.position.x + safe.size.x)
##                = 847 - (0 + 720) = 127 px phantom margin
##      produced 127×225 px parchment bands on the right + bottom.
##
## Both bugs are visible the moment you boot the app — but neither
## had a GUT-level test guarding them. These tests instantiate
## main.tscn and assert STRUCTURAL invariants that would fail if
## either regression slipped back:
##
##   - `Main.theme.resource_path` points at the Dusk theme file.
##   - All four `_safe_margin` constants are 0 on a non-mobile
##     test runner (gated; mobile may legitimately have insets).
##   - `_orientation_root.size` matches the safe_margin's inner
##     content rect (no leftover blank band).
##   - The persistent Background ColorRect is fully covered by the
##     orientation root (i.e., parchment won't bleed through).
##
## These are cheaper than render-snapshot diffs but catch the same
## class of bug. PHASED_RESKIN_PLAN.md describes the heavier
## PNG-diff approach for per-phase cosmetic verification.
extends GutTest

const _MAIN_SCENE := preload("res://game/scenes/main.tscn")
const _DUSK_AMETHYST_PATH := "res://assets/themes/dusk/amethyst.tres"


func before_each() -> void:
	# Other tests in the suite call DeviceLayout._test_set_safe_area
	# and don't always reset. Recompute from the live viewport here
	# so the next `_instantiate_main()` reads the correct, current
	# safe-area (full viewport on this non-mobile test runner).
	DeviceLayout.recompute()


func _instantiate_main() -> Node:
	var main: Node = _MAIN_SCENE.instantiate()
	add_child_autofree(main)
	return main


# region — bug 1: theme propagation

func test_main_node_carries_dusk_theme_after_ready() -> void:
	var main: Node = _instantiate_main()
	# `theme` on Main is the load-bearing assignment — Main's whole
	# subtree (currency_bar, tabs, all 10 tab views) inherits from
	# Main's `theme` property, not the window root's.
	var t: Theme = (main as Control).theme
	assert_not_null(t, "Main must have a theme assigned after _ready")
	assert_eq(t.resource_path, _DUSK_AMETHYST_PATH,
		"Main.theme must point at the Dusk Amethyst theme — got %s" % t.resource_path)


func test_main_scene_tscn_does_not_export_legacy_theme() -> void:
	# Belt-and-braces: the .tscn used to declare `theme = main_theme.tres`
	# at scene-export time, which shadowed whatever we set at runtime.
	# Read the .tscn file directly and assert no parchment theme ext_resource
	# remains. If a future maintainer re-adds an inline theme= line on
	# Main, this test fails by name.
	var f := FileAccess.open("res://game/scenes/main.tscn", FileAccess.READ)
	assert_not_null(f, "main.tscn must be readable")
	var content: String = f.get_as_text()
	f.close()
	assert_false(content.contains("main_theme.tres"),
		"main.tscn must NOT reference the legacy parchment main_theme.tres — strip the theme export from the .tscn")
	assert_false(content.contains("theme = ExtResource"),
		"main.tscn must NOT export a scene-level theme — runtime assignment is the source of truth")


func test_window_root_also_carries_dusk_theme() -> void:
	# `get_tree().root.theme` is what popup Windows (welcome-back,
	# language picker, etc.) inherit from — they're siblings of Main,
	# not children. Setting only Main.theme would leave popups
	# parchment-styled. Verify both are set.
	var _main: Node = _instantiate_main()
	var root_theme: Theme = get_tree().root.theme
	assert_not_null(root_theme, "window root must also receive the Dusk theme so popups inherit it")
	assert_eq(root_theme.resource_path, _DUSK_AMETHYST_PATH)

# endregion


# region — bug 2: no phantom safe-area bands on desktop

func test_safe_margin_has_zero_margins_on_desktop() -> void:
	# After _ready, on a non-mobile test environment, the safe area
	# equals the full viewport (no notch / status bar) so every
	# margin must be 0. If any is non-zero, content gets pushed into
	# a smaller rect with a parchment-colored band on the edge — the
	# exact user-visible bug.
	assert_false(OS.has_feature("mobile"),
		"GUT runs in headless / non-mobile mode where this assertion applies")
	var main: Node = _instantiate_main()
	# Drain any deferred layout apply.
	main._process(0.0)
	var margin: MarginContainer = main.get("_safe_margin")
	assert_not_null(margin)
	for side in ["margin_top", "margin_bottom", "margin_left", "margin_right"]:
		var v: int = margin.get_theme_constant(side)
		assert_eq(v, 0,
			"_safe_margin.%s must be 0 on desktop (got %d → would be a %d-px parchment band on that edge)" % [side, v, v])


func test_device_layout_safe_area_matches_post_scale_factor_viewport() -> void:
	# The init-order bug had DeviceLayout._recompute running BEFORE
	# Window.content_scale_factor was set. Result: cached safe_area
	# was sized against the raw viewport (720×1280), then the actual
	# viewport grew to 847×1505 design dp post-scale-factor, leaving
	# the safe_area stale.
	#
	# Pin the post-fix invariant: safe_area.size == viewport_size,
	# and safe_area.position is at origin.
	# (On mobile the position can be non-zero — status bar inset —
	# but this is a non-mobile test so origin is the contract.)
	var _main: Node = _instantiate_main()
	var view_size: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	assert_eq(DeviceLayout.safe_area.position, Vector2.ZERO,
		"safe_area.position must be (0,0) on desktop after _ready")
	assert_eq(DeviceLayout.safe_area.size, view_size,
		"safe_area.size must equal the post-scale-factor viewport size (got %v, expected %v)" % [
			DeviceLayout.safe_area.size, view_size,
		])

# endregion


# region — popups + window-subtypes use the Dusk theme, not parchment
#
# v0.15.1.2 — 9 popup / dialog / overlay scripts explicitly preloaded
# `res://game/resources/main_theme.tres` (the parchment theme) and
# assigned it via `theme = preload(...)`. This was the v0.10.4 fix —
# Window subtypes don't inherit Control theme cascade, so each popup
# had to set its own theme. v0.15.1.2 swept all 9 references to the
# Dusk theme. A future maintainer who re-introduces parchment in a
# popup fails this lint test by file:line.

func test_no_scene_script_loads_legacy_parchment_theme() -> void:
	# Walks every `.gd` under `game/scenes/` for the literal
	# `main_theme.tres` substring. Comment mentions are filtered out
	# by checking for the `preload(` / `load(` prefix on the same line.
	var roots: Array[String] = ["res://game/scenes"]
	var offending: Array[String] = []
	for r in roots:
		_walk_for_legacy_theme(r, offending)
	assert_true(offending.is_empty(),
		"Found scripts still loading res://game/resources/main_theme.tres — sweep to res://assets/themes/dusk/amethyst.tres:\n%s" % "\n".join(offending))


func _walk_for_legacy_theme(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var entry: String = dir.get_next()
		if entry == "":
			break
		if entry.begins_with("."):
			continue
		var full: String = "%s/%s" % [dir_path, entry]
		if dir.current_is_dir():
			_walk_for_legacy_theme(full, out)
			continue
		if not entry.ends_with(".gd"):
			continue
		var f := FileAccess.open(full, FileAccess.READ)
		if f == null:
			continue
		var line_no: int = 0
		while not f.eof_reached():
			line_no += 1
			var line: String = f.get_line()
			# We only care about LOAD/PRELOAD references — comment
			# mentions are fine for historical context.
			if (line.contains("preload(") or line.contains("load(")) and line.contains("main_theme.tres"):
				out.append("  %s:%d  %s" % [full, line_no, line.strip_edges()])
		f.close()
	dir.list_dir_end()

# endregion


# region — Phase 14c chip + ribbon styling sticks
#
# v0.15.2 — the Dusk-era currency chip (`.currency`) and tier ribbon
# (`.tier-ribbon`) replace the parchment-era texture-icon chip and
# top-right next-goal pill. The visible bug class these tests catch:
#
#   - currency_chip rebuilt with `theme_type_variation` ("DisplaySmall"
#     for glyph, "UiTiny" for the UPPERCASE lbl). A future maintainer
#     who drops the variation would silently render with the default
#     Silkscreen 11 font, losing the pixel-RPG glyph effect.
#   - The colored glyph cell must retint per accent_color via the
#     per-instance StyleBoxFlat in `_apply_glyph_stylebox`. If that
#     wiring breaks, every chip falls back to the theme's panel bg
#     (uniform dark purple) and the gold/teal/magenta identity is lost.
#   - The tier ribbon must hold its `_bar_fill` ColorRect (not a Godot
#     ProgressBar) — the styles.css fill is a custom teal→magenta
#     gradient, which a vanilla ProgressBar can't render cleanly. If a
#     refactor switches back to ProgressBar, the gradient handoff
#     intent is lost; this test fails on the type check.
#
# These are structural assertions, not pixel diffs — they survive
# tiny render-engine changes while still catching the regression.

const _CURRENCY_CHIP_SCENE := preload("res://game/scenes/ui/currency_chip.tscn")
const _NEXT_GOAL_CHIP_SCENE := preload("res://game/scenes/ui/next_goal_chip.tscn")


func test_currency_chip_glyph_uses_displaysmall_variation() -> void:
	var chip: PanelContainer = _CURRENCY_CHIP_SCENE.instantiate()
	add_child_autofree(chip)
	chip.configure("G", Color("#f5c46b"), "Gold", "")
	await wait_frames(1)
	# The glyph cell renders the chunky Press Start 2P character per
	# styles.css `.currency .glyph`. Pinning the theme_type_variation
	# guards against the variation getting dropped during a refactor —
	# default Silkscreen 11 would visually flatten the chip.
	assert_eq(chip._glyph_label.theme_type_variation, &"DisplaySmall",
		"currency_chip glyph must use DisplaySmall variation (Press Start 2P) per styles.css")
	assert_eq(chip._lbl_label.theme_type_variation, &"UiTiny",
		"currency_chip lbl must use UiTiny variation (Silkscreen 7px) per styles.css")


func test_currency_chip_retints_glyph_cell_per_accent_color() -> void:
	# Three chips with three different accents — each must paint its
	# glyph cell with the requested color. Catches a regression where
	# `_apply_glyph_stylebox` stops getting called on configure().
	var gold: PanelContainer = _CURRENCY_CHIP_SCENE.instantiate()
	add_child_autofree(gold)
	gold.configure("G", Color("#f5c46b"), "Gold", "")
	var teal: PanelContainer = _CURRENCY_CHIP_SCENE.instantiate()
	add_child_autofree(teal)
	teal.configure("R", Color("#5fd3c2"), "Rancher", "")
	var magenta: PanelContainer = _CURRENCY_CHIP_SCENE.instantiate()
	add_child_autofree(magenta)
	magenta.configure("P", Color("#d96fb8"), "Prestige", "")
	await wait_frames(1)
	var gold_sb: StyleBoxFlat = gold._glyph_panel.get_theme_stylebox("panel")
	var teal_sb: StyleBoxFlat = teal._glyph_panel.get_theme_stylebox("panel")
	var magenta_sb: StyleBoxFlat = magenta._glyph_panel.get_theme_stylebox("panel")
	assert_eq(gold_sb.bg_color, Color("#f5c46b"),
		"gold chip glyph cell must paint with the gold accent")
	assert_eq(teal_sb.bg_color, Color("#5fd3c2"),
		"teal chip glyph cell must paint with the teal accent")
	assert_eq(magenta_sb.bg_color, Color("#d96fb8"),
		"magenta chip glyph cell must paint with the magenta accent")


func test_tier_ribbon_uses_colorrect_fill_not_progressbar() -> void:
	# styles.css `.tier-ribbon` fill is a teal→magenta linear gradient,
	# which a vanilla Godot ProgressBar can't paint. Pin the type so a
	# future refactor doesn't quietly downgrade to ProgressBar and
	# strand the gradient intent in 14g polish.
	var ribbon: PanelContainer = _NEXT_GOAL_CHIP_SCENE.instantiate()
	add_child_autofree(ribbon)
	await wait_frames(1)
	assert_true(ribbon._bar_fill is ColorRect,
		"tier ribbon fill must be a ColorRect (anchor_right-tweened) to leave room for a gradient texture overlay in 14g")
	assert_true(ribbon._name_label is RichTextLabel,
		"tier ribbon name label must be RichTextLabel so the gold-highlight bbcode renders")


func test_tier_ribbon_badge_renders_with_displaysmall_variation() -> void:
	# styles.css `.tier-ribbon .badge` uses the chunky Press Start 2P
	# font for the T-badge. DisplaySmall (Press Start 2P 10px) is the
	# correct variation per dusk_theme_builder.
	var ribbon: PanelContainer = _NEXT_GOAL_CHIP_SCENE.instantiate()
	add_child_autofree(ribbon)
	await wait_frames(1)
	assert_eq(ribbon._badge_label.theme_type_variation, &"DisplaySmall",
		"tier ribbon badge must use DisplaySmall variation (Press Start 2P) per styles.css")

# endregion


# region — Phase 14d catching bg + monster card + bestiary palette
#
# v0.15.3 — Phase 14d brings the catching-screen visuals to Dusk:
# stripe + scanline + radial-glow background, 92-px pixel-card chrome
# around each monster, and the bestiary card sweep that the v0.15.1.3
# screenshot user-report flagged but didn't fix.
#
# Structural assertions catch the regression class where someone
# reverts to the parchment-era palette references without going through
# the styles.css source of truth.

const _MONSTER_INSTANCE_SCENE := preload("res://game/scenes/catching/monster_instance.tscn")
const _BESTIARY_CARD_SCENE := preload("res://game/scenes/bestiary/bestiary_card.tscn")


func test_monster_instance_renders_pixel_card_name_label() -> void:
	# styles.css `.mon .label`: 8-px Silkscreen UPPERCASE on a 70%-black
	# bg with a 1-px border. Pin the typography variation + the text
	# format so a refactor can't silently drop the chrome.
	var inst: Node2D = _MONSTER_INSTANCE_SCENE.instantiate()
	var m := MonsterResource.new()
	m.id = &"test_mon"
	m.display_name = "Wisplet"
	m.tier = 2
	m.tint = Color.WHITE
	inst.monster = m
	add_child_autofree(inst)
	await wait_frames(2)
	assert_not_null(inst._name_card, "monster_instance must build a name card label")
	assert_not_null(inst._name_card_panel, "name card must be wrapped in a PanelContainer")
	assert_eq(inst._name_card.theme_type_variation, &"UiTiny",
		"name card label must use UiTiny variation (Silkscreen 7px) per styles.css")
	assert_eq(inst._name_card.text, "WISPLET · T2",
		"name card text format must be 'UPPERCASE · T<tier>' per styles.css `.mon .label`")


func test_monster_instance_name_card_panel_has_dark_bg_with_dusk_border() -> void:
	# styles.css: rgba(0,0,0,0.7) bg + 1-px var(--border) (Dusk border).
	# Catches a regression where the panel stylebox falls back to the
	# theme default (which would paint a card bg + 2-px border — wrong
	# affordance for a small in-world label).
	var inst: Node2D = _MONSTER_INSTANCE_SCENE.instantiate()
	var m := MonsterResource.new()
	m.id = &"test_mon"
	m.display_name = "Test"
	m.tier = 1
	inst.monster = m
	add_child_autofree(inst)
	await wait_frames(2)
	var sb: StyleBoxFlat = inst._name_card_panel.get_theme_stylebox("panel")
	assert_not_null(sb, "name card panel must override its stylebox to match styles.css")
	assert_almost_eq(sb.bg_color.a, 0.7, 0.01,
		"name card panel bg must be 70%% transparent (styles.css `.mon .label`)")
	# Border color must be the Dusk border token, not the theme default.
	var expected_border: Color = PaletteDusk.amethyst()["border"]
	assert_eq(sb.border_color, expected_border,
		"name card border must use the Dusk `border` token")
	assert_eq(sb.border_width_top, 1,
		"name card border must be 1 px (styles.css `.mon .label`)")


func test_catching_background_uses_dusk_bg_palette() -> void:
	# Phase 14d shader uniform `bg_color` must come from
	# `PaletteDusk.amethyst()["bg"]`, not a parchment hardcoded color.
	# This catches a regression where the parchment sky shader leaks back.
	var bg_scene := preload("res://game/scenes/catching/catching_background.tscn")
	var bg = bg_scene.instantiate()
	add_child_autofree(bg)
	await wait_frames(1)
	bg._apply_tier_palette(1)
	var bg_color: Color = bg._map_material.get_shader_parameter("bg_color")
	var expected: Color = PaletteDusk.amethyst()["bg"]
	assert_almost_eq(bg_color.r, expected.r, 0.001,
		"map shader bg_color must match the Dusk `bg` palette token")
	assert_almost_eq(bg_color.g, expected.g, 0.001)
	assert_almost_eq(bg_color.b, expected.b, 0.001)


func test_bestiary_card_does_not_load_parchment_palette() -> void:
	# v0.15.1.3 user-report screenshot 2 flagged bestiary entries still
	# parchment-colored. Phase 14d sweeps both bestiary scripts to
	# `_DUSK`. Pin the file contents directly so a future maintainer
	# who re-adds `palette_colors.gd` fails by name. Mirrors the
	# popup-sweep test above.
	for path in [
		"res://game/scenes/bestiary/bestiary_card.gd",
		"res://game/scenes/bestiary/bestiary_card_detail.gd",
	]:
		var f := FileAccess.open(path, FileAccess.READ)
		assert_not_null(f, "%s must exist" % path)
		var content: String = f.get_as_text()
		f.close()
		assert_false(content.contains("palette_colors.gd"),
			"%s must NOT preload the parchment palette_colors.gd — use PaletteDusk instead" % path)


func test_bestiary_card_tier_ribbon_paints_dusk_accent() -> void:
	# styles.css drives the tier ribbon via the Dusk palette accents,
	# not the parchment brass/silver/gold/obsidian set. A tier-1 card's
	# ribbon must paint the teal accent (band 0 — early Bog Hollow cool).
	ContentRegistry.ensure_loaded()
	var card: PanelContainer = _BESTIARY_CARD_SCENE.instantiate()
	add_child_autofree(card)
	# Build a tier-1 stub monster — avoids depending on a specific
	# content-registry id that might shift across content seeds.
	var m := MonsterResource.new()
	m.id = &"test_t1"
	m.display_name = "Test"
	m.tier = 1
	card.set_monster(m)
	await wait_frames(2)
	var expected: Color = PaletteDusk.amethyst()["teal"]
	assert_eq(card._ribbon.color, expected,
		"tier 1 ribbon must paint the Dusk `teal` accent (band 0)")

# endregion


# region — Phase 14e Peniber ribbon + intro overlay typography
#
# v0.15.4 — Phase 14e brings the Peniber dialog ribbon (formerly
# `narrator_overlay`) and the new first-launch intro overlay up to
# the Dusk pixel-RPG look. These tests pin the typography variations
# styles.css specifies — a regression that drops the variation would
# silently render with default Silkscreen 11, losing the gold name
# pin / VT323 body / Press Start 2P title identity.

const _NARRATOR_OVERLAY_SCENE := preload("res://game/scenes/ui/narrator_overlay.tscn")
const _PENIBER_INTRO_SCENE := preload("res://game/scenes/ui/peniber_intro_overlay.tscn")


func test_peniber_ribbon_name_uses_displaysmall_variation() -> void:
	# styles.css `.peniber .name`: Press Start 2P 10 px gold. Pin the
	# variation so a refactor can't silently flatten the name to default
	# Silkscreen.
	var ribbon: Control = _NARRATOR_OVERLAY_SCENE.instantiate()
	add_child_autofree(ribbon)
	await wait_frames(1)
	assert_eq(ribbon._name_label.theme_type_variation, &"DisplaySmall",
		"PENIBER name must use DisplaySmall (Press Start 2P) per styles.css `.peniber .name`")


func test_peniber_ribbon_body_uses_bodytext_variation() -> void:
	# styles.css `.peniber .text`: VT323 17 px ink.
	var ribbon: Control = _NARRATOR_OVERLAY_SCENE.instantiate()
	add_child_autofree(ribbon)
	await wait_frames(1)
	assert_eq(ribbon._text_label.theme_type_variation, &"BodyText",
		"body must use BodyText (VT323) per styles.css `.peniber .text`")


func test_peniber_ribbon_caret_is_dusk_gold_colorrect() -> void:
	# styles.css `.peniber .caret`: 6×14 filled gold block — must be a
	# ColorRect (not a Label) so blink toggles don't trigger text-shaping.
	var ribbon: Control = _NARRATOR_OVERLAY_SCENE.instantiate()
	add_child_autofree(ribbon)
	await wait_frames(1)
	assert_true(ribbon._caret_label is ColorRect,
		"caret must be a ColorRect per styles.css `.peniber .caret`")
	assert_eq(ribbon._caret_label.color, PaletteDusk.amethyst()["gold"],
		"caret color must be the Dusk gold token")


func test_peniber_intro_title_uses_displayheading_variation() -> void:
	# styles.css `.intro-overlay .title h1`: Press Start 2P 18 px gold.
	# Without DisplayHeading variation the title falls back to default
	# Silkscreen 11 — half the intended size + wrong font.
	TutorialState.reset()
	var o: CanvasLayer = _PENIBER_INTRO_SCENE.instantiate()
	add_child_autofree(o)
	await wait_frames(1)
	assert_eq(o._title_label.theme_type_variation, &"DisplayHeading",
		"intro title must use DisplayHeading (Press Start 2P 18) per styles.css")


func test_peniber_intro_bubble_uses_bodyintro_variation() -> void:
	# styles.css `.intro-overlay .pen-bubble .text`: VT323 19 px.
	TutorialState.reset()
	var o: CanvasLayer = _PENIBER_INTRO_SCENE.instantiate()
	add_child_autofree(o)
	await wait_frames(1)
	assert_eq(o._bubble_text.theme_type_variation, &"BodyIntro",
		"intro bubble must use BodyIntro (VT323 19) per styles.css")


func test_peniber_intro_dot_count_matches_beats() -> void:
	# Page dots are one per PENIBER_INTRO beat. styles.css mockup has 4.
	# Catches a regression where the BEATS array grows but the dots row
	# doesn't follow.
	TutorialState.reset()
	var o: CanvasLayer = _PENIBER_INTRO_SCENE.instantiate()
	add_child_autofree(o)
	await wait_frames(1)
	assert_eq(o._bubble_dot_rects.size(), 4,
		"page dots row must have one ColorRect per PENIBER_INTRO beat")

# endregion


# region — Phase 14f bottom nav repaint + Settings theme picker
#
# v0.15.5 — Phase 14f swaps the parchment-era flat tab bar for the
# styles.css `.tabbar` look (bg-deep base + per-state gold inset bar
# on the active tab) and adds a 3-button palette switcher in Settings.
# Structural assertions catch the regression class where someone
# reverts the styleboxes or forgets to subscribe to theme_changed.


func test_nav_buttons_paint_with_dusk_bg_deep_stylebox() -> void:
	# styles.css `.tabbar` bg: var(--bg-deep). After main._ready, every
	# primary nav button must have a `normal` stylebox sourced from
	# the active palette's bg_deep. A regression that drops the
	# stylebox override falls back to the theme's default button bg
	# (card_2) — visible as a much-brighter tab bar.
	Settings.theme_id = Settings.THEME_AMETHYST
	var main: Node = _instantiate_main()
	await wait_frames(2)
	var nav_buttons: Dictionary = main._nav_buttons
	var expected: Color = PaletteDusk.amethyst()["bg_deep"]
	for btn_name in nav_buttons:
		var btn: Button = nav_buttons[btn_name]
		var sb: StyleBoxFlat = btn.get_theme_stylebox("normal")
		assert_eq(sb.bg_color, expected,
			"%s nav button normal stylebox must paint bg_deep per styles.css `.tabbar`" % btn_name)


func test_nav_active_button_paints_with_gold_top_border() -> void:
	# styles.css `.tabbar button[data-active=true]`:
	#   box-shadow: inset 0 2px 0 var(--gold)
	# In Godot terms: pressed stylebox has a 2-px gold top border.
	Settings.theme_id = Settings.THEME_AMETHYST
	var main: Node = _instantiate_main()
	await wait_frames(2)
	var nav_buttons: Dictionary = main._nav_buttons
	var expected_gold: Color = PaletteDusk.amethyst()["gold"]
	for btn_name in nav_buttons:
		var btn: Button = nav_buttons[btn_name]
		var sb: StyleBoxFlat = btn.get_theme_stylebox("pressed")
		assert_eq(sb.border_color, expected_gold,
			"%s pressed stylebox border must be Dusk gold per styles.css `[data-active=true]`" % btn_name)
		assert_eq(sb.border_width_top, 2,
			"%s pressed stylebox must have a 2-px top border (gold inset bar)" % btn_name)


func test_settings_view_does_not_load_parchment_palette() -> void:
	# v0.15.5 sweep: settings_view's parchment _PALETTE refs are gone.
	# Mirrors the popup-sweep lint test above so a future maintainer
	# who re-introduces palette_colors.gd fails by file:line.
	var f := FileAccess.open("res://game/scenes/ui/settings_view.gd", FileAccess.READ)
	assert_not_null(f)
	var content: String = f.get_as_text()
	f.close()
	assert_false(content.contains("palette_colors.gd"),
		"settings_view must NOT preload the parchment palette_colors.gd — use PaletteDusk")


func test_palette_dusk_active_reads_settings_theme_id() -> void:
	# PaletteDusk.active() is the central indirection that lets a
	# Settings palette swap reach inline color overrides. If a
	# refactor removes the Settings.theme_id read, this test fails.
	Settings.theme_id = Settings.THEME_TWILIGHT
	var active: Dictionary = PaletteDusk.active()
	assert_eq(active["bg_deep"], PaletteDusk.twilight()["bg_deep"])
	Settings.theme_id = Settings.THEME_AMETHYST

# endregion


# region — Phase 14g polish: L-brackets + float-gain + catch anim + toast
#
# v0.15.6 — Phase 14g completes the Dusk pixel-RPG look with the
# deferred polish: gold L-bracket corners on every pixel-card, a
# scale-punch float-gain animation, a scale+rotate catch despawn,
# and a gold-bordered toast. These tests pin the structural contracts.

const _GOLD_BRACKETS_SCRIPT := preload("res://game/scenes/ui/gold_brackets.gd")
const _FLOATING_NUMBER_SCENE_14G := preload("res://game/scenes/ui/floating_number.tscn")
const _TOAST_SCENE := preload("res://game/scenes/ui/toast.tscn")


func test_currency_chip_carries_gold_brackets() -> void:
	# Every currency pill is a pixel-card per styles.css; the gold
	# L-bracket corner trim is part of the chrome. A refactor that
	# drops the brackets falls back to a card with no RPG-window trim.
	var chip: PanelContainer = _CURRENCY_CHIP_SCENE.instantiate()
	add_child_autofree(chip)
	chip.configure("G", Color("#f5c46b"), "Gold", "")
	await wait_frames(1)
	assert_not_null(chip._brackets,
		"currency_chip must carry a gold-brackets decoration child")
	assert_eq(chip._brackets.get_script(), _GOLD_BRACKETS_SCRIPT,
		"_brackets must be a GoldBrackets Control")


func test_floating_number_uses_uitiny_variation() -> void:
	# styles.css `.float-gain`: var(--font-ui) 11 px. UiTiny is the
	# Silkscreen variation in dusk_theme_builder.
	var label: Label = _FLOATING_NUMBER_SCENE_14G.instantiate()
	add_child_autofree(label)
	label.call("configure", "1", false)
	await wait_frames(1)
	assert_eq(label.theme_type_variation, &"UiTiny",
		"float-gain must use UiTiny (Silkscreen) variation per styles.css")


func test_toast_repaints_on_theme_changed() -> void:
	# The toast banner's stylebox (card bg + 2-px gold border) reads
	# from PaletteDusk.active() and must update on Settings.theme_changed.
	# A regression that drops the subscription would leave the toast
	# painted with the previous palette after a Settings swap.
	Settings.theme_id = Settings.THEME_AMETHYST
	var toast: CanvasLayer = _TOAST_SCENE.instantiate()
	add_child_autofree(toast)
	await wait_frames(1)
	var sb0: StyleBoxFlat = toast._banner.get_theme_stylebox("panel")
	assert_eq(sb0.bg_color, PaletteDusk.amethyst()["card"])
	Settings.set_theme_id(Settings.THEME_EMBER)
	await wait_frames(1)
	var sb1: StyleBoxFlat = toast._banner.get_theme_stylebox("panel")
	assert_eq(sb1.bg_color, PaletteDusk.ember()["card"],
		"toast must repaint its bg with the new palette's card token on theme_changed")
	# Reset for following tests.
	Settings.set_theme_id(Settings.THEME_AMETHYST)


func test_tier_ribbon_repaints_on_theme_changed() -> void:
	# Phase 14g migration: the tier ribbon's badge bg + bar fill +
	# ribbon border are now sourced from PaletteDusk.active(). A
	# palette swap must update the cached stylebox bg_color +
	# _bar_fill.color so the ribbon visually matches the new palette.
	Settings.theme_id = Settings.THEME_AMETHYST
	var ribbon: PanelContainer = _NEXT_GOAL_CHIP_SCENE.instantiate()
	add_child_autofree(ribbon)
	await wait_frames(2)
	assert_eq(ribbon._bar_fill.color, PaletteDusk.amethyst()["teal"])
	Settings.set_theme_id(Settings.THEME_EMBER)
	await wait_frames(1)
	assert_eq(ribbon._bar_fill.color, PaletteDusk.ember()["teal"],
		"tier ribbon fill must repaint with the new palette's teal on theme_changed")
	Settings.set_theme_id(Settings.THEME_AMETHYST)


func test_catching_background_repaints_on_theme_changed() -> void:
	# Map shader uniforms (bg / accent) must follow palette swaps.
	Settings.theme_id = Settings.THEME_AMETHYST
	var bg_scene := preload("res://game/scenes/catching/catching_background.tscn")
	var bg = bg_scene.instantiate()
	add_child_autofree(bg)
	await wait_frames(1)
	Settings.set_theme_id(Settings.THEME_TWILIGHT)
	await wait_frames(1)
	var bg_color: Color = bg._map_material.get_shader_parameter("bg_color")
	assert_almost_eq(bg_color.r, PaletteDusk.twilight()["bg"].r, 0.001,
		"map shader bg_color must follow Settings.theme_id after theme_changed")
	Settings.set_theme_id(Settings.THEME_AMETHYST)

# endregion


# region — Phase 14h palette switcher reach: bestiary / monster / peniber / currency_bar
#
# v0.15.7 — Phase 14h completes the Settings palette switcher's
# visible reach. Each scene below caches palette tokens at build
# time; without a `theme_changed` subscription, a Settings palette
# swap leaves the cached chrome painted with the previous palette.
# These tests pin that each scene actually retints on swap.

func test_bestiary_card_repaints_ribbon_on_theme_changed() -> void:
	ContentRegistry.ensure_loaded()
	Settings.theme_id = Settings.THEME_AMETHYST
	var card_scene := preload("res://game/scenes/bestiary/bestiary_card.tscn")
	var card: PanelContainer = card_scene.instantiate()
	add_child_autofree(card)
	var m := MonsterResource.new()
	m.id = &"test_bestiary_t1"
	m.display_name = "Test"
	m.tier = 1
	card.set_monster(m)
	await wait_frames(2)
	assert_eq(card._ribbon.color, PaletteDusk.amethyst()["teal"])
	Settings.set_theme_id(Settings.THEME_EMBER)
	await wait_frames(1)
	assert_eq(card._ribbon.color, PaletteDusk.ember()["teal"],
		"bestiary card ribbon must repaint with the new palette's teal on theme_changed")
	Settings.set_theme_id(Settings.THEME_AMETHYST)


func test_monster_instance_name_card_repaints_on_theme_changed() -> void:
	# Name card border is sourced from PaletteDusk.active()["border"];
	# a swap must update the cached stylebox.
	Settings.theme_id = Settings.THEME_AMETHYST
	var inst: Node2D = _MONSTER_INSTANCE_SCENE.instantiate()
	var m := MonsterResource.new()
	m.id = &"test_mon_themechange"
	m.display_name = "Test"
	m.tier = 1
	inst.monster = m
	add_child_autofree(inst)
	await wait_frames(2)
	var sb0: StyleBoxFlat = inst._name_card_panel.get_theme_stylebox("panel")
	assert_eq(sb0.border_color, PaletteDusk.amethyst()["border"])
	Settings.set_theme_id(Settings.THEME_TWILIGHT)
	await wait_frames(1)
	var sb1: StyleBoxFlat = inst._name_card_panel.get_theme_stylebox("panel")
	assert_eq(sb1.border_color, PaletteDusk.twilight()["border"],
		"monster_instance name card border must follow the active palette")
	Settings.set_theme_id(Settings.THEME_AMETHYST)


func test_peniber_ribbon_repaints_bubble_on_theme_changed() -> void:
	# Bubble bg / border + caret gold + name gold are cached at build
	# time. The new theme_changed handler must walk them all to the
	# new palette's tokens.
	Settings.theme_id = Settings.THEME_AMETHYST
	var ribbon: Control = _NARRATOR_OVERLAY_SCENE.instantiate()
	add_child_autofree(ribbon)
	await wait_frames(2)
	var sb0: StyleBoxFlat = ribbon._bubble.get_theme_stylebox("panel")
	assert_eq(sb0.bg_color, PaletteDusk.amethyst()["card"])
	Settings.set_theme_id(Settings.THEME_TWILIGHT)
	await wait_frames(1)
	var sb1: StyleBoxFlat = ribbon._bubble.get_theme_stylebox("panel")
	assert_eq(sb1.bg_color, PaletteDusk.twilight()["card"],
		"Peniber ribbon bubble bg must follow the active palette")
	assert_eq(ribbon._caret_label.color, PaletteDusk.twilight()["gold"],
		"Peniber ribbon caret must repaint on theme_changed")
	Settings.set_theme_id(Settings.THEME_AMETHYST)


func test_currency_bar_repaints_chips_on_theme_changed() -> void:
	# Each chip's glyph cell uses the palette's accent token (gold /
	# teal / magenta). Currency bar must re-call `configure()` on a
	# palette swap so the per-instance StyleBoxFlat retints.
	Settings.theme_id = Settings.THEME_AMETHYST
	var bar_scene := preload("res://game/scenes/ui/currency_bar.tscn")
	var bar: PanelContainer = bar_scene.instantiate()
	add_child_autofree(bar)
	await wait_frames(2)
	var gold_sb0: StyleBoxFlat = bar._gold_chip._glyph_panel.get_theme_stylebox("panel")
	assert_eq(gold_sb0.bg_color, PaletteDusk.amethyst()["gold"])
	Settings.set_theme_id(Settings.THEME_EMBER)
	await wait_frames(1)
	var gold_sb1: StyleBoxFlat = bar._gold_chip._glyph_panel.get_theme_stylebox("panel")
	assert_eq(gold_sb1.bg_color, PaletteDusk.ember()["gold"],
		"currency_bar gold chip must repaint with the new palette's gold accent")
	Settings.set_theme_id(Settings.THEME_AMETHYST)


func test_bestiary_card_carries_gold_brackets() -> void:
	# Phase 14h adds L-brackets to bestiary cards (pixel-card class).
	ContentRegistry.ensure_loaded()
	var card_scene := preload("res://game/scenes/bestiary/bestiary_card.tscn")
	var card: PanelContainer = card_scene.instantiate()
	add_child_autofree(card)
	var m := MonsterResource.new()
	m.id = &"test_bestiary_brackets"
	m.display_name = "Test"
	m.tier = 1
	card.set_monster(m)
	await wait_frames(2)
	var found_brackets: bool = false
	for child in card.get_children():
		if child.get_script() == preload("res://game/scenes/ui/gold_brackets.gd"):
			found_brackets = true
			break
	assert_true(found_brackets,
		"bestiary card must carry a GoldBrackets decoration child per styles.css `.pixel-card::before`")


func test_peniber_ribbon_carries_gold_brackets() -> void:
	# Phase 14h adds L-brackets to the Peniber dialog ribbon (pixel-card class).
	var ribbon: Control = _NARRATOR_OVERLAY_SCENE.instantiate()
	add_child_autofree(ribbon)
	await wait_frames(2)
	# Brackets are added as a child of the bubble (so they slide with it).
	var found_brackets: bool = false
	for child in ribbon._bubble.get_children():
		if child.get_script() == preload("res://game/scenes/ui/gold_brackets.gd"):
			found_brackets = true
			break
	assert_true(found_brackets,
		"Peniber ribbon must carry a GoldBrackets decoration child per styles.css `.pixel-card::before`")

# endregion


# region — orientation root fills safe margin

func test_orientation_root_fills_safe_margin_horizontally() -> void:
	# The composition root (HBox in landscape, VBox in portrait) sits
	# inside _safe_margin. If anything inside has a fixed width that
	# doesn't honor SIZE_EXPAND_FILL, the orientation_root won't fill
	# its parent — a parchment-coloured Background ColorRect would
	# show through on the right edge.
	#
	# Assert the orientation_root's WIDTH matches the safe_margin's
	# width to within a 1-px tolerance (rounding).
	var main: Node = _instantiate_main()
	# Force a layout pass so anchors / EXPAND_FILL settle.
	main._process(0.0)
	await wait_frames(2)
	var safe_margin: MarginContainer = main.get("_safe_margin")
	var orientation_root: Control = main.get("_orientation_root")
	assert_not_null(safe_margin)
	assert_not_null(orientation_root)
	# safe_margin's inner content rect is safe_margin.size minus its
	# four margin theme constants. With desktop margins == 0 (proven
	# by the test above) that equals safe_margin.size.
	var expected_inner_width: float = safe_margin.size.x
	var actual_width: float = orientation_root.size.x
	assert_almost_eq(actual_width, expected_inner_width, 1.0,
		"orientation_root must fill _safe_margin horizontally (parchment Background would bleed through otherwise)")


func test_orientation_root_fills_safe_margin_vertically() -> void:
	var main: Node = _instantiate_main()
	main._process(0.0)
	await wait_frames(2)
	var safe_margin: MarginContainer = main.get("_safe_margin")
	var orientation_root: Control = main.get("_orientation_root")
	var expected_inner_height: float = safe_margin.size.y
	var actual_height: float = orientation_root.size.y
	assert_almost_eq(actual_height, expected_inner_height, 1.0,
		"orientation_root must fill _safe_margin vertically (parchment band on bottom otherwise)")

# endregion
