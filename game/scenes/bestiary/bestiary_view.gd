## Phase 10d — bestiary tab as a Pokédex of `bestiary_card` instances.
##
## Layout: a `GridContainer` of cards, one per registered monster,
## sorted by tier then by id. Column count adapts to viewport width:
## 1 column under 480px, 2 columns 480..900, 4 columns above 900.
##
## Tapping a card opens a `bestiary_card_detail` PopupPanel; closing
## the popup returns the user to their previous scroll position
## (PopupPanel doesn't disturb the host's scroll state).
##
## Backwards-compat: tests-and-other-screens have been observed to
## read `_list` as the cards container — kept as the GridContainer
## member name so the test suite keeps working.
extends PanelContainer

const _CARD_SCENE := preload("res://game/scenes/bestiary/bestiary_card.tscn")
const _DETAIL_SCENE := preload("res://game/scenes/bestiary/bestiary_card_detail.tscn")
const _DUSK := preload("res://assets/themes/dusk/palette_dusk.gd")

# Column-count breakpoints based on the bestiary view's own width.
# Phone (vertical 720): 2 columns; tablet portrait: 4 columns.
const _BREAKPOINT_2_COL: float = 480.0
const _BREAKPOINT_4_COL: float = 900.0

var _list: GridContainer
var _scroll: ScrollContainer
var _detail: PopupPanel
var _cards: Array[PanelContainer] = []
## v0.15.12 — overall completion meter ("X / Y species (Z%)") atop the
## grid. Ticks up on each catch; gives the player an always-visible
## "gotta-catch-'em-all" goal-gradient (the Bestiary had no header).
var _completion_label: Label
var _completion_bar: ProgressBar
var _completion_tween: Tween
## Last fraction the bar was driven to — skips re-tweening when a catch
## doesn't change the species count (auto-catch can fire several
## monster_caught per frame).
var _last_fraction: float = -1.0

## v0.13.6 — visibility-gated refresh.
##
## Pre-fix: every monster_caught (a per-tap signal on the catching
## screen) called _refresh_cards, which iterates 60 cards and each
## card's refresh() destroys + rebuilds its 4 pill Labels. That's
## 240 Label allocs + 240 destroys + 60 AtlasTexture allocs **per
## tap, while the bestiary tab is hidden** — directly responsible
## for the ~1s freeze users saw on Android.
##
## Now: signal handlers just set _dirty. _refresh_cards only fires
## when the tab is actually visible (or when it becomes visible
## after one or more dirty signals while hidden). Same pattern as
## ledger_view's `if visible: _refresh()`.
##
## Test/diagnostic counter for the regression suite. Reset between
## tests; live builds ignore it.
var refresh_count: int = 0
var _dirty: bool = false


func _ready() -> void:
	# v0.15.12 — wrap the scroll in a VBox so the completion meter sits
	# as a fixed header above the scrolling grid.
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	_build_completion_header(root)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)

	_list = GridContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("h_separation", 8)
	_list.add_theme_constant_override("v_separation", 8)
	_list.columns = _columns_for_width(size.x)
	_scroll.add_child(_list)

	_detail = _DETAIL_SCENE.instantiate()
	add_child(_detail)

	resized.connect(_on_resized)
	visibility_changed.connect(_on_visibility_changed)
	EventBus.monster_caught.connect(_on_monster_caught)
	EventBus.first_catch_of_species.connect(_on_first_catch)
	EventBus.first_shiny_caught.connect(_on_first_shiny)
	EventBus.pet_acquired.connect(_on_pet_acquired)
	EventBus.game_loaded.connect(_rebuild)
	# v0.15.12 — the header label carries an explicit font-size override
	# (so it must re-apply on the accessibility slider), and the bar's
	# styleboxes snapshot palette colors (so they must repaint on a live
	# theme swap). Mirrors bestiary_card.gd / next_goal_chip.gd.
	Settings.accessibility_settings_changed.connect(_apply_completion_font_sizes)
	Settings.theme_changed.connect(_on_theme_changed)
	_rebuild()   # builds cards + paints the meter (instant) at the end


func _exit_tree() -> void:
	if Settings.accessibility_settings_changed.is_connected(_apply_completion_font_sizes):
		Settings.accessibility_settings_changed.disconnect(_apply_completion_font_sizes)
	if Settings.theme_changed.is_connected(_on_theme_changed):
		Settings.theme_changed.disconnect(_on_theme_changed)


func _apply_completion_font_sizes() -> void:
	if _completion_label != null:
		_completion_label.add_theme_font_size_override("font_size", UiScale.size(18))


## Repaint the bar's snapshotted styleboxes when the player swaps palette.
func _on_theme_changed() -> void:
	if _completion_bar == null:
		return
	var palette: Dictionary = _DUSK.active()
	var bg_sb: StyleBoxFlat = _completion_bar.get_theme_stylebox("background")
	if bg_sb != null:
		var new_bg: StyleBoxFlat = bg_sb.duplicate()
		new_bg.border_color = palette["border_soft"]
		_completion_bar.add_theme_stylebox_override("background", new_bg)
	var fill_sb: StyleBoxFlat = _completion_bar.get_theme_stylebox("fill")
	if fill_sb != null:
		var new_fill: StyleBoxFlat = fill_sb.duplicate()
		new_fill.bg_color = palette["teal"]
		_completion_bar.add_theme_stylebox_override("fill", new_fill)


## v0.15.12 — overall "X / Y species (Z%)" header + teal progress bar.
func _build_completion_header(parent: Control) -> void:
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 3)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(header)

	_completion_label = Label.new()
	_completion_label.text = "Bestiary"
	_completion_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Wrap rather than overflow the view width at large accessibility
	# font scales on narrow phones.
	_completion_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_completion_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_completion_label.add_theme_font_size_override("font_size", UiScale.size(18))
	header.add_child(_completion_label)

	_completion_bar = ProgressBar.new()
	_completion_bar.show_percentage = false
	_completion_bar.min_value = 0.0
	_completion_bar.max_value = 1.0
	_completion_bar.value = 0.0
	_completion_bar.step = 0.0   # smooth, not snapped
	_completion_bar.custom_minimum_size = Vector2(0, 8)
	_completion_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Dusk-flavoured: teal fill on a dark inset, square corners (matches
	# the tier-ribbon progress bar).
	var palette: Dictionary = _DUSK.active()
	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = palette["teal"]
	fill_sb.set_corner_radius_all(0)
	_completion_bar.add_theme_stylebox_override("fill", fill_sb)
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = Color(0.0, 0.0, 0.0, 0.4)
	bg_sb.border_color = palette["border_soft"]
	bg_sb.set_border_width_all(1)
	bg_sb.set_corner_radius_all(0)
	_completion_bar.add_theme_stylebox_override("background", bg_sb)
	header.add_child(_completion_bar)


## Recompute the species-caught count and update the header. Animates
## the bar fill on a live catch (honours reduce_motion); snaps on load.
func _update_completion_meter(animate: bool = true) -> void:
	if _completion_label == null or _completion_bar == null:
		return
	var status: Dictionary = CatchingSystem.bestiary_completion(
			ContentRegistry.monsters(), GameState.monsters_caught)
	var caught: int = int(status["caught"])
	var total: int = int(status["total"])
	var fraction: float = float(status["fraction"])
	# Nothing changed (most catches don't cross a new species 0→1, and
	# auto-catch fires several per frame) — leave any in-flight tween alone
	# instead of restarting its easing for no visual gain.
	if is_equal_approx(fraction, _last_fraction):
		return
	_last_fraction = fraction
	_completion_label.text = "Bestiary — %d / %d species (%d%%)" % [
			caught, total, int(round(fraction * 100.0))]
	if animate and not Settings.reduce_motion:
		if _completion_tween != null and _completion_tween.is_valid():
			_completion_tween.kill()
		_completion_tween = create_tween()
		_completion_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_completion_tween.tween_property(_completion_bar, "value", fraction, 0.4)
	else:
		_completion_bar.value = fraction


func _on_resized() -> void:
	if _list != null:
		_list.columns = _columns_for_width(size.x)


func _on_visibility_changed() -> void:
	if visible and _dirty:
		_dirty = false
		_refresh_cards()


func _columns_for_width(w: float) -> int:
	if w >= _BREAKPOINT_4_COL:
		return 4
	if w >= _BREAKPOINT_2_COL:
		return 2
	return 1


# Catch / unlock signals just mark the grid dirty. The cards repaint
# only when the bestiary tab is actually visible (in _on_visibility_changed)
# — there's no point burning frames refreshing offscreen UI on every
# tap from the catching screen.
func _on_monster_caught(_id: String, _ix: int, _is_shiny: bool, _src: String) -> void:
	_mark_dirty()


func _on_first_catch(_id: String) -> void:
	_mark_dirty()


func _on_first_shiny(_id: String) -> void:
	_mark_dirty()


func _on_pet_acquired(_pet_id: String, _is_variant: bool) -> void:
	_mark_dirty()


func _mark_dirty() -> void:
	if visible:
		# Visible: refresh immediately so the player sees the catch
		# count tick up. Skips the dirty-flag dance.
		_refresh_cards()
	else:
		# Hidden: defer until the tab is opened.
		_dirty = true


## True iff at least one signal has been received while hidden and
## the cards are out-of-date. Public for the regression test that
## asserts the visibility gate.
func is_dirty() -> bool:
	return _dirty


func _refresh_cards() -> void:
	refresh_count += 1
	for card in _cards:
		if is_instance_valid(card):
			card.refresh()
	# v0.15.12 — tick the completion meter on each (visible) catch.
	_update_completion_meter(true)


# Full rebuild — used on first paint and on game_loaded (when the
# entire monster registry might have shifted).
func _rebuild() -> void:
	if not is_instance_valid(_list):
		return
	for child in _list.get_children():
		child.queue_free()
	_cards.clear()
	var monsters := ContentRegistry.monsters()
	monsters.sort_custom(func(a: MonsterResource, b: MonsterResource) -> bool:
		if a.tier != b.tier:
			return a.tier < b.tier
		return String(a.id) < String(b.id))
	for m in monsters:
		var card: PanelContainer = _CARD_SCENE.instantiate()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.set_monster(m)
		card.card_tapped.connect(_on_card_tapped)
		_list.add_child(card)
		_cards.append(card)
	# Refresh the meter after a full rebuild (e.g. on game_loaded).
	_update_completion_meter(false)


func _on_card_tapped(monster_id: StringName) -> void:
	var monster: MonsterResource = ContentRegistry.monster(monster_id)
	if monster == null:
		return
	_detail.bind_monster(monster)
	_detail.popup_centered(Vector2(420, 480))
