## Phase 10c — top-of-screen currency display.
##
## Composes three `currency_chip` instances (Gold, Rancher Points,
## Prestige) into a horizontal strip. Subscribes to currency changes
## and prestige milestones; chips own their own tweening.
##
## Visibility:
##   - Gold:     always visible.
##   - RP:       hidden until earned for the first time, then sticky.
##   - Prestige: hidden until prestige_count > 0, then sticky.
##
## Each chip's tooltip exposes the BigNumber breakdown so a long-tap
## (or mouse-hover) reveals the underlying mantissa/exponent.
extends PanelContainer

const _CURRENCY_CHIP_SCENE := preload("res://game/scenes/ui/currency_chip.tscn")
const _PALETTE := preload("res://game/resources/palette_colors.gd")
const _COIN_ICON := preload("res://assets/sprites/icons/coin.png")
const _RP_ICON := preload("res://assets/sprites/icons/rancher_point.png")
const _PRESTIGE_ICON := preload("res://assets/sprites/icons/prestige.png")

var _gold_chip: PanelContainer
var _rp_chip: PanelContainer
var _prestige_chip: PanelContainer

# Snapshot of last-displayed values to drive tweens through the chips
# (chips themselves track their own from-state, this is for fast-path
# checks like "do nothing if nothing changed").
var _last_gold_e: int = -1
var _last_gold_m: float = -1.0
var _last_rp: int = 0
var _last_prestige: int = 0


func _ready() -> void:
	custom_minimum_size = Vector2(0, 64)
	# Chips lay out left-to-right with a small gap so they read as
	# separate cards rather than a single wide bar.
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	hbox.add_theme_constant_override("separation", 8)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(hbox)

	_gold_chip = _CURRENCY_CHIP_SCENE.instantiate()
	_gold_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_gold_chip)
	_gold_chip.configure(_COIN_ICON, _PALETTE.BRASS_ACCENT, "Gold", "")

	_rp_chip = _CURRENCY_CHIP_SCENE.instantiate()
	_rp_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rp_chip.visible = false
	hbox.add_child(_rp_chip)
	_rp_chip.configure(_RP_ICON, _PALETTE.DUSK_BLUE, "RP", "Rancher Points")

	_prestige_chip = _CURRENCY_CHIP_SCENE.instantiate()
	_prestige_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prestige_chip.visible = false
	hbox.add_child(_prestige_chip)
	_prestige_chip.configure(_PRESTIGE_ICON, _PALETTE.BLOOD_RUBY, "P", "Prestige cycles completed")

	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.prestige_triggered.connect(_on_prestige_triggered)
	EventBus.game_loaded.connect(_refresh_all)
	# Initial paint must NOT animate — otherwise we tween from 0 → loaded
	# value at startup, which feels like a jackpot for no reason.
	_refresh_all(false)


func _exit_tree() -> void:
	# Defensive: disconnect to avoid leaks if the bar is reinstantiated
	# (the test_currency_bar suite re-creates the bar repeatedly).
	if EventBus.currency_changed.is_connected(_on_currency_changed):
		EventBus.currency_changed.disconnect(_on_currency_changed)
	if EventBus.prestige_triggered.is_connected(_on_prestige_triggered):
		EventBus.prestige_triggered.disconnect(_on_prestige_triggered)
	if EventBus.game_loaded.is_connected(_refresh_all):
		EventBus.game_loaded.disconnect(_refresh_all)


func _on_currency_changed(_currency_id: String, _new_value: Variant) -> void:
	_refresh_all(true)


func _on_prestige_triggered(_rp_gained: int, _prestige_count: int) -> void:
	_refresh_all(true)


func _refresh_all(animate: bool = true) -> void:
	_refresh_gold(animate)
	_refresh_rp(animate)
	_refresh_prestige(animate)


func _refresh_gold(animate: bool) -> void:
	if not is_instance_valid(_gold_chip):
		return
	var gold: BigNumber = GameState.current_gold()
	_gold_chip.set_big_value(gold, animate)
	_gold_chip.set_progress_fraction(_gold_progress_to_next_decade(gold))
	# Tooltip: scientific breakdown so long-tap surfaces the underlying
	# mantissa/exponent.
	_gold_chip.tooltip_text = "%.3f × 10^%d  (%s)" % [
			gold.mantissa, gold.exponent, gold.format(),
	]
	_last_gold_m = gold.mantissa
	_last_gold_e = gold.exponent


## Returns 0.0..1.0 — fraction of the way from 10^e to 10^(e+1).
## Mantissa is normalized to [1.0, 10.0); progress within that decade
## is `(mantissa - 1.0) / 9.0`.
func _gold_progress_to_next_decade(gold: BigNumber) -> float:
	if gold == null or gold.is_zero():
		return 0.0
	# gold.mantissa lives in [1.0, 10.0). Map to [0.0, 1.0].
	var m: float = gold.mantissa
	if m < 1.0:
		return 0.0
	return clamp((m - 1.0) / 9.0, 0.0, 1.0)


func _refresh_rp(animate: bool) -> void:
	if not is_instance_valid(_rp_chip):
		return
	var rp: int = GameState.current_rancher_points()
	if rp <= 0 and _last_rp <= 0:
		_rp_chip.visible = false
		return
	_rp_chip.visible = true
	_rp_chip.set_int_value(rp, animate)
	_rp_chip.tooltip_text = "Rancher Points: %d (earned via battle wins and prestige)" % rp
	_last_rp = rp


func _refresh_prestige(animate: bool) -> void:
	if not is_instance_valid(_prestige_chip):
		return
	var p: int = GameState.prestige_count
	if p <= 0 and _last_prestige <= 0:
		_prestige_chip.visible = false
		return
	_prestige_chip.visible = true
	_prestige_chip.set_int_value(p, animate)
	_prestige_chip.tooltip_text = "Prestige cycles completed: %d" % p
	_last_prestige = p
