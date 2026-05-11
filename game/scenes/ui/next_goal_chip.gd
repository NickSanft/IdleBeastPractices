## Phase 14c — Dusk tier ribbon.
##
## Reskinned per `docs/design_handoff_theming/reference_files/styles.css`
## `.tier-ribbon` block. Sits below the currency bar on the catching
## screen; surfaces the current tier and how close the player is to
## completing every species at that tier.
##
## Layout (left-to-right):
##
##   ┌──────┬────────────────────────────┬────────────────┬────┐
##   │ [T2] │ Whisper Glade · 6/9 SPECIES │ progress bar  │ 67%│
##   └──────┴────────────────────────────┴────────────────┴────┘
##
## - `T2` badge: Press Start 2P 9-px on card_2 background, 1-px border.
## - Name + sub: Silkscreen 11-px Ink with the highlight word in gold.
## - Progress bar: 8-px tall, inset-black bg, teal→magenta gradient
##   fill (styles.css: `linear-gradient(90deg, var(--teal), var(--magenta))`).
## - % text: 9-px Silkscreen ink_dim right-aligned.
##
## The class still exists at the old path (`next_goal_chip.gd`) so
## the catching_view's preload + anchoring code keeps working without
## a path change in 14c. A path rename can land in Phase 14g polish.
extends PanelContainer

const _TIER_COMPLETE_CATCH_THRESHOLD := 25
const _TIER_DEBUG_THRESHOLD := 2
const _DUSK := preload("res://assets/themes/dusk/palette_dusk.gd")

var _badge_label: Label
var _name_label: RichTextLabel
## `_bar_bg` is a plain `Panel`, NOT a `PanelContainer`. Containers in
## Godot force-fit their child controls via `fit_child_in_rect`, so a
## child ColorRect's `anchor_right` gets overwritten every frame. Using
## `Panel` (a non-Container Control) preserves anchor-based fill so
## `_bar_fill.anchor_right` can drive the 0→1 progress tween.
var _bar_bg: Panel
var _bar_fill: ColorRect
var _pct_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(180, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Override the default Panel stylebox with a slim variant — the
	# tier ribbon sits between the currency bar and the map; a heavy
	# 2-px border + drop shadow would crowd the layout. Linear-gradient
	# bg from styles.css (`rgba(0,0,0,0.5) → rgba(0,0,0,0.2)`) is
	# approximated as a flat translucent black; the chunky pixel-card
	# treatment is reserved for the currency pills + cards proper.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.4)
	sb.border_color = _DUSK.amethyst()["border_soft"]
	sb.border_width_bottom = 2
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(hbox)

	# T-badge — Press Start 2P 9-px on card_2, 1-px border. Per
	# styles.css `.tier-ribbon .badge`.
	_badge_label = Label.new()
	_badge_label.theme_type_variation = "DisplaySmall"
	_badge_label.text = "T1"
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge_label.custom_minimum_size = Vector2(28, 22)
	_badge_label.add_theme_color_override("font_color", _DUSK.amethyst()["ink"])
	_badge_label.add_theme_font_size_override("font_size", UiScale.size(9))
	# Wrap the label in a PanelContainer so the 1-px border + card_2 bg
	# of `.badge` is faithful to styles.css. The badge stylebox is
	# distinct from the ribbon stylebox above.
	var badge_panel := PanelContainer.new()
	var badge_sb := StyleBoxFlat.new()
	badge_sb.bg_color = _DUSK.amethyst()["card_2"]
	badge_sb.border_color = _DUSK.amethyst()["border"]
	badge_sb.set_border_width_all(1)
	badge_sb.set_corner_radius_all(0)
	badge_sb.content_margin_left = 6.0
	badge_sb.content_margin_right = 6.0
	badge_sb.content_margin_top = 4.0
	badge_sb.content_margin_bottom = 4.0
	badge_panel.add_theme_stylebox_override("panel", badge_sb)
	badge_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge_panel.add_child(_badge_label)
	hbox.add_child(badge_panel)

	# Name + sub. styles.css uses a single label with `<b>` for the
	# highlight word in gold; we use RichTextLabel + bbcode for that.
	# `mouse_filter = IGNORE` is load-bearing: RichTextLabel defaults
	# to STOP, and test_tap_targets walks every Control with STOP +
	# a gui_input listener (which RichTextLabel auto-wires when
	# bbcode is enabled, for [url] handling). Without IGNORE the
	# 15-px-tall label fails the 58-dp Material floor sweep.
	_name_label = RichTextLabel.new()
	_name_label.bbcode_enabled = true
	_name_label.fit_content = true
	_name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_name_label.scroll_active = false
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(_name_label)

	# Progress bar — 8-px tall, teal→magenta gradient. Built as a
	# plain `Panel` (not `PanelContainer`!) with a child `ColorRect`
	# fill. PanelContainer is a Container and would force-fit the
	# ColorRect every frame, breaking the `anchor_right` tween that
	# drives the 0→1 progress sweep. The teal→magenta gradient is
	# deferred to 14g polish (via a GradientTexture1D + TextureRect
	# overlay that the fill rect clips); 14c ships a flat teal fill.
	_bar_bg = Panel.new()
	_bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar_bg.custom_minimum_size = Vector2(60, 8)
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_bg_sb := StyleBoxFlat.new()
	bar_bg_sb.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	bar_bg_sb.border_color = _DUSK.amethyst()["border_soft"]
	bar_bg_sb.set_border_width_all(1)
	bar_bg_sb.set_corner_radius_all(0)
	# `Panel` reads `panel` from its own theme cascade; override the
	# stylebox locally so we don't pick up the theme's default
	# Panel stylebox (chunky border + drop shadow).
	_bar_bg.add_theme_stylebox_override("panel", bar_bg_sb)
	hbox.add_child(_bar_bg)

	_bar_fill = ColorRect.new()
	_bar_fill.color = _DUSK.amethyst()["teal"]
	_bar_fill.anchor_left = 0.0
	_bar_fill.anchor_top = 0.0
	_bar_fill.anchor_right = 0.0   # bar is 0% wide until _refresh sets it
	_bar_fill.anchor_bottom = 1.0
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_bg.add_child(_bar_fill)

	# % text right of the bar — styles.css `.tier-ribbon .pct`.
	_pct_label = Label.new()
	_pct_label.theme_type_variation = "UiCaption"
	_pct_label.text = "0%"
	_pct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pct_label.custom_minimum_size = Vector2(36, 0)
	_pct_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(_pct_label)

	EventBus.monster_caught.connect(_on_monster_caught)
	EventBus.tier_completed.connect(_on_tier_completed)
	EventBus.game_loaded.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if EventBus.monster_caught.is_connected(_on_monster_caught):
		EventBus.monster_caught.disconnect(_on_monster_caught)
	if EventBus.tier_completed.is_connected(_on_tier_completed):
		EventBus.tier_completed.disconnect(_on_tier_completed)
	if EventBus.game_loaded.is_connected(_refresh):
		EventBus.game_loaded.disconnect(_refresh)


func _on_monster_caught(_id: String, _ix: int, _is_shiny: bool, _src: String) -> void:
	_refresh()


func _on_tier_completed(_tier: int) -> void:
	_refresh()


func _refresh() -> void:
	var tier: int = int(GameState.current_max_tier)
	var threshold: int = _TIER_DEBUG_THRESHOLD if Settings.debug_fast_pets else _TIER_COMPLETE_CATCH_THRESHOLD
	var status: Dictionary = CatchingSystem.tier_completion_status(
			ContentRegistry.monsters(),
			GameState.monsters_caught,
			tier,
			threshold)
	var max_count: int = int(status.get("max_count", 0))
	var missing: Array = status.get("missing_species", [])
	var displayed: int = min(max_count, threshold)
	var fraction: float = float(displayed) / float(threshold)
	_bar_fill.anchor_right = clamp(fraction, 0.0, 1.0)
	_pct_label.text = "%d%%" % int(round(fraction * 100.0))

	_badge_label.text = "T%d" % tier
	# Name line — surface tier name + remaining-species count. styles.css
	# uses gold for the highlighted token; we wrap the remaining-count
	# number in [color=...] to match.
	var tier_name: String = _tier_name(tier)
	var gold_hex: String = _DUSK.amethyst()["gold"].to_html(false)
	if missing.size() > 0:
		_name_label.text = "%s · [color=#%s]%d species left[/color]" % [tier_name, gold_hex, missing.size()]
	else:
		_name_label.text = "%s · [color=#%s]%d / %d catches[/color]" % [tier_name, gold_hex, displayed, threshold]


## Static map: tier number → display name. Mirrors data.js's TIERS
## list; for tiers beyond the named 3, falls back to "Tier N".
func _tier_name(tier: int) -> String:
	match tier:
		1: return "Bog Hollow"
		2: return "Whisper Glade"
		3: return "Ash Reach"
	return "Tier %d" % tier
