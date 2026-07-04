## The main catch screen: tap monsters, watch the auto-net work, advance tiers.
extends Control

const _MONSTER_INSTANCE_SCENE := preload("res://game/scenes/catching/monster_instance.tscn")
const _FLOATING_NUMBER_SCENE := preload("res://game/scenes/ui/floating_number.tscn")
const _BACKGROUND_SCENE := preload("res://game/scenes/catching/catching_background.tscn")
const _NEXT_GOAL_CHIP := preload("res://game/scenes/ui/next_goal_chip.tscn")
const _SPAWN_INTERVAL_SECONDS := 1.2
const _TIER_COMPLETE_CATCH_THRESHOLD := 25
## v0.15.9 — gated on OS.is_debug_build() so the per-tap / per-catch
## console spam stays available in the editor + debug exports (incl. the
## Maestro CI APK) but is SILENT in exported release builds. Was an
## unconditional `true` (a Phase-2 dev aid that shipped on in release).
static var _DEBUG_LOG := OS.is_debug_build()
## Live runtime toggle (F2 in main.gd flips Settings.debug_fast_pets). When on:
## tier completion fires after just _TIER_DEBUG_THRESHOLD catches per species
## (default 2) instead of 25, and every pet variant roll auto-succeeds.
const _TIER_DEBUG_THRESHOLD := 2

var _spawn_root: Node2D
var _spawn_bounds: Rect2 = Rect2(40, 200, 640, 900)
var _spawn_timer: float = 0.0
var _auto_accumulator: float = 0.0
var _instance_counter: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _drops_2x_button: Button   # rewarded-video bonus toggle
# v0.15.17 — passive "Idle ≈ N gold/min" readout, bottom-left (opposite the
# drops-2x button). Refreshed on a 1 s accumulator rather than by signal:
# there is no net-equipped signal to hook, and a once-a-second walk of the
# ≤60-monster pool is far cheaper than the per-signal work the dirty-flag
# convention exists to coalesce.
var _idle_rate_label: Label
var _idle_rate_accumulator: float = 0.0

# Phase 12b — hold-to-tap state. While `_hold_active`, _process
# accumulates time and fires synthetic tap-resolves at the rate set
# in Settings. `_hold_pos` retains the last known finger position so
# moving the finger across multiple monsters still resolves taps on
# whatever's under it.
var _hold_active: bool = false
var _hold_pos: Vector2 = Vector2.ZERO
var _hold_accumulator: float = 0.0


func _ready() -> void:
	ContentRegistry.ensure_loaded()
	_rng.randomize()
	# Hit-test taps via this Control's _gui_input rather than relying on
	# Area2D physics picking — the latter is unreliable inside a TabContainer
	# because the Control hierarchy consumes the event before the physics
	# layer sees it. STOP means we get _gui_input; IGNORE would miss it.
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Phase 10b: parallax background. CanvasLayer-based; renders at layer=-2
	# behind everything else. Owns its own gentle horizontal scroll and
	# tier-driven sky modulation, so we don't need to drive it from here.
	add_child(_BACKGROUND_SCENE.instantiate())
	_spawn_root = Node2D.new()
	_spawn_root.name = "SpawnRoot"
	add_child(_spawn_root)
	EventBus.tier_completed.connect(_on_tier_completed_shake)
	EventBus.first_shiny_caught.connect(_on_first_shiny_shake)
	# Configure spawn bounds based on the catching_view's OWN rect
	# (not the full viewport — Phase 13c.3 introduced a left-side
	# nav rail in landscape, so viewport.x can be wider than the
	# catching_view actually occupies). resized fires after the
	# layout settles, so the initial bounds are recomputed there.
	_recompute_spawn_bounds()
	resized.connect(_on_resized)
	_build_drops_2x_button()
	_build_next_goal_chip()
	_build_idle_rate_label()
	AdsManager.rewarded_completed.connect(_on_rewarded_completed)
	AdsManager.rewarded_failed.connect(_on_rewarded_failed)
	# Seed: if there's no active net, the catch screen still works (taps only).
	set_process(true)


func _on_resized() -> void:
	_recompute_spawn_bounds()


## Spawn area = catching_view's own rect minus reserved padding for
## widgets anchored inside it: 80 px reserved at top for the
## next_goal_chip, 80 px at bottom for the drops_2x_button. Reading
## `size` (catching_view's own rect, since this Control is the root
## of the scene) instead of viewport_size means landscape's left-rail
## nav doesn't push monsters off the right edge.
func _recompute_spawn_bounds() -> void:
	var rect_size: Vector2 = size
	if rect_size.x <= 0.0 or rect_size.y <= 0.0:
		# Pre-layout: fall back to viewport so the very first spawn
		# tick has SOMETHING. _on_resized fires once the real rect
		# settles and corrects this.
		rect_size = Vector2(get_viewport().get_visible_rect().size)
	_spawn_bounds = Rect2(
			20,
			80,
			max(40.0, rect_size.x - 40),
			max(120.0, rect_size.y - 160))


func _process(delta: float) -> void:
	_handle_spawning(delta)
	_handle_auto_catch(delta)
	_handle_hold_to_tap(delta)
	_handle_idle_rate_refresh(delta)


## Phase 12b: while a hold is active, fire repeat taps at the rate
## configured in Settings. Accumulator-based so the rate stays steady
## even if frame deltas vary.
func _handle_hold_to_tap(delta: float) -> void:
	if not _hold_active or not Settings.hold_to_tap_enabled:
		return
	var rate: float = max(0.5, float(Settings.hold_tap_rate_hz))
	var period: float = 1.0 / rate
	_hold_accumulator += delta
	while _hold_accumulator >= period:
		_resolve_tap_at(_hold_pos)
		_hold_accumulator -= period


## Detect taps and hit-test against on-screen monster instances. We use
## _gui_input rather than Area2D.input_event because Area2D physics picking
## doesn't reliably fire when the Area2D lives under a TabContainer's content
## Control — the GUI consumes the click before the picking pass.
##
## v0.12.1 (Phase 12b): also tracks hold-to-tap state. Press starts
## hold-mode; release ends it. Movement updates the tracked position
## so dragging across multiple monsters still hits whatever's under
## the finger. The actual tap repeats fire from `_process` rather
## than here so the rate is decoupled from input event frequency.
func _gui_input(event: InputEvent) -> void:
	# Press → resolve tap immediately + arm hold (if enabled).
	if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) \
			or (event is InputEventScreenTouch and event.pressed):
		_resolve_tap_at(event.position)
		if Settings.hold_to_tap_enabled:
			_hold_active = true
			_hold_pos = event.position
			_hold_accumulator = 0.0
		return
	# Release → end hold.
	if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed) \
			or (event is InputEventScreenTouch and not event.pressed):
		_hold_active = false
		return
	# Drag — update tracked position so the next hold-tap fires at the
	# new spot (dragging across monsters resolves them in turn).
	if _hold_active and event is InputEventMouseMotion:
		_hold_pos = event.position
	elif _hold_active and event is InputEventScreenDrag:
		_hold_pos = event.position


## Resolve a tap at the given local position. Extracted from
## _gui_input so the hold-to-tap path can call it directly without
## fabricating a fake InputEvent.
func _resolve_tap_at(click_local: Vector2) -> void:
	if _DEBUG_LOG:
		print("[catch] tap @ %s, %d on-screen monsters" % [
			click_local, _spawn_root.get_child_count() if _spawn_root != null else 0,
		])
	var hit: Node2D = _find_monster_at(click_local)
	if hit == null:
		_spawn_miss_tap_ripple(click_local)
		AudioManager.play_miss_tap_sfx()
		return
	accept_event()
	_on_monster_tapped(hit)


func _find_monster_at(local_pos: Vector2) -> Node2D:
	if _spawn_root == null:
		return null
	# 32×32 sprite at scale 3 = 96×96 hit box centered on monster.position.
	var half: Vector2 = Vector2(48, 48)
	# Iterate in reverse so the topmost-rendered (last child) wins.
	var children: Array = _spawn_root.get_children()
	for i in range(children.size() - 1, -1, -1):
		var inst = children[i]
		if not inst.has_method("play_catch_and_despawn"):
			continue
		var rect: Rect2 = Rect2(inst.position - half, half * 2.0)
		if rect.has_point(local_pos):
			return inst
	return null


func _handle_spawning(delta: float) -> void:
	_spawn_timer += delta
	if _spawn_timer < _SPAWN_INTERVAL_SECONDS:
		return
	_spawn_timer = 0.0
	var net := _active_net()
	var max_on_screen: int = net.spawn_max if net != null else 3
	if _spawn_root.get_child_count() >= max_on_screen:
		return
	_spawn_one(net)


func _handle_auto_catch(delta: float) -> void:
	var net := _active_net()
	if net == null:
		_auto_accumulator = 0.0
		return
	var auto_speed_mult: float = GameState.multiplier(&"auto_speed")
	var result := CatchingSystem.auto_catch_count(_auto_accumulator, delta, net.catches_per_second, auto_speed_mult)
	_auto_accumulator = result["accumulator"]
	for i in int(result["count"]):
		var inst := _pick_random_on_screen_monster()
		if inst == null:
			# Try to spawn one inline so the auto-catch doesn't sit idle.
			_spawn_one(net)
			inst = _pick_random_on_screen_monster()
			if inst == null:
				return
		_resolve_auto_catch(inst)


func _active_net() -> NetResource:
	var id_str: String = GameState.active_net
	if id_str == "":
		# Fall back to the default net if owned but not equipped (shouldn't happen).
		if GameState.nets_owned.size() > 0:
			id_str = GameState.nets_owned[0]
		else:
			return null
	return ContentRegistry.net(StringName(id_str))


func _spawn_one(net: NetResource) -> void:
	var pool := ContentRegistry.monsters()
	# If no net is equipped yet, allow tap-only spawning of tier-1 monsters
	# so the player isn't stuck on first launch.
	var effective_net := net
	if effective_net == null:
		var fallback := NetResource.new()
		fallback.targets_tiers = [1] as Array[int]
		fallback.spawn_max = 3
		fallback.catches_per_second = 0.0
		effective_net = fallback
	var picked := CatchingSystem.pick_spawn(pool, GameState.current_max_tier, effective_net, _rng)
	if picked == null:
		return
	_instance_counter += 1
	var inst: Node2D = _MONSTER_INSTANCE_SCENE.instantiate()
	inst.monster = picked
	inst.instance_id = _instance_counter
	inst.bounds = _spawn_bounds
	var x: float = randf_range(_spawn_bounds.position.x + 32, _spawn_bounds.position.x + _spawn_bounds.size.x - 32)
	var y: float = randf_range(_spawn_bounds.position.y + 32, _spawn_bounds.position.y + _spawn_bounds.size.y - 32)
	inst.position = Vector2(x, y)
	_spawn_root.add_child(inst)
	inst.tapped.connect(_on_monster_tapped)
	EventBus.monster_spawned.emit(String(picked.id), _instance_counter)


func _pick_random_on_screen_monster() -> Node:
	var children := _spawn_root.get_children()
	if children.is_empty():
		return null
	# Filter out any actively-being-caught instances (input disabled).
	var alive: Array = []
	for c in children:
		if c.has_method("play_catch_and_despawn"):
			alive.append(c)
	if alive.is_empty():
		return null
	return alive[_rng.randi_range(0, alive.size() - 1)]


func _on_monster_tapped(inst: Node2D) -> void:
	GameState.record_tap()
	# v0.14.6 (Phase 13f): the per-tap 40ms haptic moved to
	# HapticManager._on_monster_tapped — fires off `EventBus.monster_tapped`
	# which we emit a few lines below. Centralising the dispatch
	# means catches/tier-ups/etc. can layer their own pulses without
	# duplicating the platform + Settings checks.
	# Trigger feedback now so the player sees their click registered even if
	# this tap doesn't yet cross the catch difficulty.
	if inst.has_method("play_tap_feedback"):
		inst.play_tap_feedback()
	if inst.monster != null:
		EventBus.monster_tapped.emit(String(inst.monster.id), inst.instance_id)
	var monster: MonsterResource = inst.monster
	var outcome := CatchingSystem.resolve_tap(
			monster,
			inst.tap_progress,
			_rng,
			GameState.multiplier(&"tap_speed"),
			GameState.multiplier(&"drop_amount"),
			GameState.multiplier(&"gold_mult"),
			GameState.multiplier(&"shiny_rate"))
	if not bool(outcome["caught"]):
		inst.tap_progress = float(outcome["tap_progress"])
		return
	_apply_catch_rewards(monster, outcome, "tap")
	_spawn_floating_gold(inst.position, outcome["gold"], bool(outcome["is_shiny"]))
	inst.play_catch_and_despawn()
	EventBus.monster_caught.emit(String(monster.id), inst.instance_id, bool(outcome["is_shiny"]), "tap")


func _resolve_auto_catch(inst: Node2D) -> void:
	var monster: MonsterResource = inst.monster
	var outcome := CatchingSystem.resolve_auto(
			monster,
			_rng,
			GameState.multiplier(&"drop_amount"),
			GameState.multiplier(&"gold_mult"),
			GameState.multiplier(&"shiny_rate"))
	_apply_catch_rewards(monster, outcome, "net")
	_spawn_floating_gold(inst.position, outcome["gold"], bool(outcome["is_shiny"]))
	inst.play_catch_and_despawn()
	EventBus.monster_caught.emit(String(monster.id), inst.instance_id, bool(outcome["is_shiny"]), "net")


func _spawn_floating_gold(at_position: Vector2, gold: BigNumber, is_shiny: bool) -> void:
	var label: Label = _FLOATING_NUMBER_SCENE.instantiate()
	# Position above the monster sprite. Random 12px x-jitter so stacked
	# catches don't perfectly overlap.
	label.position = at_position + Vector2(randf_range(-12.0, 12.0), -48.0)
	label.size = Vector2(120, 28)
	add_child(label)
	# `Label` exposes configure() at runtime via the floating_number script.
	# v0.15.10: pass a magnitude band (0..4) so bigger payouts render
	# bigger/brighter. Both the tap and net catch paths route through here,
	# so the idle stream gets the magnitude treatment too.
	if label.has_method("configure"):
		label.call("configure", gold.format(), is_shiny, false, _gold_magnitude_band(gold))


## v0.15.10 — maps a gold amount's order of magnitude to a floating-number
## size band. BigNumber._normalize keeps mantissa in [1,10), so `exponent`
## is exactly the order of magnitude (digits − 1).
##   < 1K → 0 · 1K–999K → 1 · 1M–999M → 2 · 1B–999B → 3 · 1T+ → 4 (milestone)
func _gold_magnitude_band(gold: BigNumber) -> int:
	if gold == null or gold.is_zero():
		return 0
	var e: int = gold.exponent
	if e < 3:
		return 0
	if e < 6:
		return 1
	if e < 9:
		return 2
	if e < 12:
		return 3
	return 4


## Phase 10b: spawn a one-shot ripple of particles at the tap location.
## Confirms a miss-tap registered without granting the player anything;
## also useful as a debugging aid for hit-rect mismatches on mobile.
func _spawn_miss_tap_ripple(at_local: Vector2) -> void:
	var ripple := CPUParticles2D.new()
	ripple.position = at_local
	ripple.emitting = false
	ripple.one_shot = true
	ripple.amount = 14
	ripple.lifetime = 0.3
	ripple.explosiveness = 1.0
	ripple.spread = 180.0
	ripple.initial_velocity_min = 50.0
	ripple.initial_velocity_max = 90.0
	ripple.gravity = Vector2.ZERO
	ripple.scale_amount_min = 0.6
	ripple.scale_amount_max = 1.4
	ripple.color = Color(0.93, 0.88, 0.74, 0.85)   # parchment, semi-translucent
	ripple.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(ripple)
	ripple.restart()
	# Auto-clean after the burst plus a small grace window for fade-out.
	var grace: SceneTreeTimer = get_tree().create_timer(ripple.lifetime + 0.1)
	grace.timeout.connect(func() -> void:
		if is_instance_valid(ripple):
			ripple.queue_free())


func _on_tier_completed_shake(_tier: int) -> void:
	_shake_spawn_root(8.0, 0.45)


func _on_first_shiny_shake(_monster_id: String) -> void:
	_shake_spawn_root(4.0, 0.25)


## Brief positional jitter on the spawn root — gives a tactile feel to
## tier-ups and first-shiny moments without disturbing the UI layout
## (Control children sit on the catching_view, not on _spawn_root).
##
## v0.11.1 (Phase 11b) honours `Settings.reduce_motion` — players who
## flag motion sensitivity get the celebration without the screen
## kicking around them.
func _shake_spawn_root(intensity: float, duration: float) -> void:
	if _spawn_root == null:
		return
	if Settings.reduce_motion:
		return
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	var original := _spawn_root.position
	var step_count: int = max(2, int(duration * 30.0))   # ~30 jitters/sec
	for i in step_count:
		var t: float = float(i) / float(step_count)
		var falloff: float = 1.0 - t
		var offset := Vector2(
				randf_range(-intensity, intensity) * falloff,
				randf_range(-intensity, intensity) * falloff)
		tween.tween_property(_spawn_root, "position", original + offset, duration / float(step_count))
	tween.tween_property(_spawn_root, "position", original, 0.05)


func _apply_catch_rewards(monster: MonsterResource, outcome: Dictionary, source: String) -> void:
	GameState.record_catch(monster.id, bool(outcome["is_shiny"]), source)
	if outcome.has("drop_item_id") and outcome["drop_item_id"] != &"":
		var amount: int = int(outcome["drop_amount"])
		# Rewarded-video bonus: doubles drop_amount for the next N catches
		# after a REWARD_DROPS_2X_NEXT_10 ad.
		if GameState.transient_drops_2x_remaining > 0:
			amount *= 2
			GameState.transient_drops_2x_remaining -= 1
			_update_drops_2x_button()
		GameState.add_item(outcome["drop_item_id"], amount)
	GameState.add_gold(outcome["gold"])
	if _DEBUG_LOG:
		var gold: BigNumber = outcome["gold"]
		print("[catch] resolved: %s caught via %s, +%s gold, +%d %s%s" % [
			String(monster.id),
			source,
			gold.format(),
			int(outcome.get("drop_amount", 0)),
			String(outcome.get("drop_item_id", "")),
			"  ✨SHINY" if bool(outcome.get("is_shiny", false)) else "",
		])
	_check_tier_progression(monster.tier)


func _check_tier_progression(catch_tier: int) -> void:
	# Only fire on the player's leading edge tier.
	if catch_tier != GameState.current_max_tier:
		return
	if GameState.tiers_completed.has(catch_tier):
		return
	var threshold: int = _TIER_DEBUG_THRESHOLD if Settings.debug_fast_pets else _TIER_COMPLETE_CATCH_THRESHOLD
	var status := CatchingSystem.tier_completion_status(
			ContentRegistry.monsters(),
			GameState.monsters_caught,
			catch_tier,
			threshold)
	if not bool(status["is_complete"]):
		return
	_award_tier_completion(catch_tier)


## Side-effect-only: applies tier_completed to GameState, awards every
## species' pet in that tier (variant rolls per-pet), advances current_max_tier.
## Idempotent — add_pet skips already-owned pets.
func _award_tier_completion(catch_tier: int) -> void:
	if not GameState.tiers_completed.has(catch_tier):
		GameState.tiers_completed.append(catch_tier)
		# v0.15.12 — emit BEFORE recording the one-time RP bonus so the
		# celebration handler (which reads tiers_rp_awarded) can tell a
		# first-ever completion from a post-prestige replay. emit() is
		# synchronous, so every listener runs before the append below.
		EventBus.tier_completed.emit(catch_tier)
		# Permanent, prestige-surviving RP bonus for completing the tier's
		# collection (scales with tier). Granted ONCE per tier EVER —
		# tiers_rp_awarded persists across prestige while tiers_completed
		# resets (and monsters_caught is kept, so tiers re-complete on the
		# first post-prestige catch). Without this gate that would be a
		# free ~210 RP farm every prestige. Forward-looking: tiers completed
		# before this update don't retroactively pay out.
		if not GameState.tiers_rp_awarded.has(catch_tier):
			GameState.tiers_rp_awarded.append(catch_tier)
			var rp_bonus: int = CatchingSystem.tier_completion_rp(catch_tier)
			if rp_bonus > 0:
				GameState.add_rancher_points(rp_bonus, "tier_complete:%d" % catch_tier)
	if _DEBUG_LOG:
		print("[catch] TIER %d COMPLETE — awarding pets" % catch_tier)
	# Use the catching view's already-seeded _rng for variant rolls.
	# v0.10.7 fix: the prior code created a NEW RandomNumberGenerator
	# inside the loop and called randomize() each iteration. When the
	# loop iterations all land in the same microsecond (common — three
	# pets per tier completion), randomize()'s time-based seed is
	# identical across iterations, making every roll the SAME random
	# value. Result: with variant_rate=0.02, players got either all
	# three variants (2 % chance) or none — exactly the "one pet
	# unlocks all variants" symptom in user saves. A single shared,
	# already-randomized RNG gives independent rolls per pet.
	for pet in CatchingSystem.pets_to_award_for_tier(ContentRegistry.monsters(), catch_tier):
		var roll_ceiling: float = 1.0 if Settings.debug_fast_pets else pet.variant_rate
		var is_variant: bool = _rng.randf() < roll_ceiling
		var added: bool = GameState.add_pet(pet.id, is_variant)
		if _DEBUG_LOG:
			print("[catch]   pet awarded: %s (variant=%s, new=%s)" % [
				String(pet.id), is_variant, added,
			])
	if GameState.current_max_tier <= catch_tier:
		GameState.current_max_tier = catch_tier + 1
		EventBus.tier_unlocked.emit(GameState.current_max_tier)


## Phase 11d: surface tier-completion progress so the player always
## knows what they're working toward. The widget renders the current
## tier + how close the player is to completing every species at that
## tier; it self-subscribes to EventBus.
##
## Phase 14c: the widget was reskinned from a compact top-right chip
## into a full-width "tier ribbon" per styles.css `.tier-ribbon`,
## which sits below the currency bar. Anchoring is now full-width at
## the top of the catching view (12 px gutter L/R, fixed ~40 px tall)
## so the badge + name + progress bar can lay out left-to-right.
func _build_next_goal_chip() -> void:
	var chip: PanelContainer = _NEXT_GOAL_CHIP.instantiate()
	chip.anchor_left = 0.0
	chip.anchor_top = 0.0
	chip.anchor_right = 1.0
	chip.anchor_bottom = 0.0
	chip.offset_left = 12
	chip.offset_top = 12
	chip.offset_right = -12
	chip.offset_bottom = 52
	add_child(chip)


func _build_drops_2x_button() -> void:
	# Anchored bottom-right of the catching view. Explicit anchor+offsets
	# (set_anchors_preset + manual position is fragile with Control siblings).
	# Mouse-filter STOP so taps on the button do not fall through to
	# _gui_input as a monster click.
	#
	# v0.14.5 (Phase 13d): height is `UiScale.tap_target()` (48 dp) +
	# 20 dp gesture-bar margin, so the button never falls under
	# Material's accessibility floor regardless of density. Pre-fix the
	# height was hardcoded at 44 dp (offset_top = -64, offset_bottom = -20).
	var bottom_margin: int = 20
	_drops_2x_button = Button.new()
	_drops_2x_button.anchor_left = 1.0
	_drops_2x_button.anchor_top = 1.0
	_drops_2x_button.anchor_right = 1.0
	_drops_2x_button.anchor_bottom = 1.0
	_drops_2x_button.offset_left = -220
	_drops_2x_button.offset_top = -float(UiScale.tap_target() + bottom_margin)
	_drops_2x_button.offset_right = -20
	_drops_2x_button.offset_bottom = -float(bottom_margin)
	_drops_2x_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_drops_2x_button.pressed.connect(_on_drops_2x_pressed)
	add_child(_drops_2x_button)
	_update_drops_2x_button()


## v0.15.17 — bottom-left idle-income readout. Sits inside the 80 px band
## _recompute_spawn_bounds already reserves at the bottom for widgets, so
## it never overlaps spawned monsters. Non-interactive: mouse-filter IGNORE
## so a mis-tap near it still falls through to _gui_input as a monster tap.
func _build_idle_rate_label() -> void:
	_idle_rate_label = Label.new()
	_idle_rate_label.anchor_left = 0.0
	_idle_rate_label.anchor_top = 1.0
	_idle_rate_label.anchor_right = 0.0
	_idle_rate_label.anchor_bottom = 1.0
	_idle_rate_label.offset_left = 20
	_idle_rate_label.offset_top = -48
	_idle_rate_label.offset_right = 320
	_idle_rate_label.offset_bottom = -20
	_idle_rate_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Screen-reader label (Phase 13g convention: tooltip_text doubles as
	# the TalkBack name for informational surfaces).
	_idle_rate_label.tooltip_text = "Estimated gold per minute from your net while idle or away"
	_apply_idle_rate_font()
	Settings.accessibility_settings_changed.connect(_apply_idle_rate_font)
	add_child(_idle_rate_label)
	_refresh_idle_rate()


## Inline UiScale sizes are frozen at apply-time, so re-apply on the
## accessibility slider (the v0.15.13 next_goal_chip badge pattern).
func _apply_idle_rate_font() -> void:
	if _idle_rate_label == null:
		return
	_idle_rate_label.add_theme_font_size_override("font_size", UiScale.size(12))


func _handle_idle_rate_refresh(delta: float) -> void:
	_idle_rate_accumulator += delta
	if _idle_rate_accumulator < 1.0:
		return
	_idle_rate_accumulator = 0.0
	_refresh_idle_rate()


func _refresh_idle_rate() -> void:
	if _idle_rate_label == null:
		return
	# Resolve via _active_net() (with its nets_owned[0] fallback), NOT
	# GameState.active_net directly: a cloud merge can union nets_owned
	# while taking active_net="" last-write-wins, and in that state the
	# auto-catcher (which uses _active_net()) is visibly earning — the
	# readout must agree with what the player watches, not with the
	# offline path (whose no-fallback divergence predates this label and
	# is noted for the cloud-merge hardening follow-up).
	var net: NetResource = _active_net()
	var rate: float = 0.0
	if net != null:
		rate = OfflineProgressSystem.idle_gold_per_second(
				ContentRegistry.monsters(),
				net,
				GameState.current_max_tier,
				GameState.multiplier(&"auto_speed"),
				GameState.multiplier(&"gold_mult"))
	if rate <= 0.0:
		# Taps-only players (no net yet) get a clean screen, not a zero.
		_idle_rate_label.visible = false
		return
	_idle_rate_label.visible = true
	_idle_rate_label.text = "Idle ≈ %s gold/min" % BigNumber.from_float(rate * 60.0).format()


func _update_drops_2x_button() -> void:
	if _drops_2x_button == null:
		return
	var remaining: int = GameState.transient_drops_2x_remaining
	if remaining > 0:
		_drops_2x_button.text = "2× drops: %d left" % remaining
		_drops_2x_button.disabled = true
		_drops_2x_button.visible = true
	elif AdsManager.is_available():
		_drops_2x_button.text = "Watch ad: 2× drops × %d" % AdsManager.DROPS_2X_CATCH_COUNT
		_drops_2x_button.disabled = false
		_drops_2x_button.visible = true
	else:
		_drops_2x_button.visible = false


func _on_drops_2x_pressed() -> void:
	if _drops_2x_button != null:
		_drops_2x_button.disabled = true
	AdsManager.show_rewarded(AdsManager.REWARD_DROPS_2X_NEXT_10)


func _on_rewarded_completed(reward_id: String, granted: bool) -> void:
	if reward_id != AdsManager.REWARD_DROPS_2X_NEXT_10:
		return
	EventBus.rewarded_video_completed.emit(reward_id, granted)
	if granted:
		GameState.transient_drops_2x_remaining += AdsManager.DROPS_2X_CATCH_COUNT
	_update_drops_2x_button()


func _on_rewarded_failed(reward_id: String, _reason: String) -> void:
	if reward_id != AdsManager.REWARD_DROPS_2X_NEXT_10:
		return
	_update_drops_2x_button()
