## Phase 14g — Dusk float-gain reskin.
##
## Reskinned per `docs/design_handoff_theming/reference_files/styles.css`
## `.float-gain` block. Replaces the parchment-era "+12 g" Label
## tween (drift-up + fade) with the pixel-RPG version: Silkscreen 11
## px, 1-px hard black drop-shadow, scale-punch + lift on spawn,
## drift-up + fade on exit. Item floats use teal (drops). Gold floats
## use gold (currency). Shiny gets an extra ✨ prefix per the existing
## `is_shiny` path.
##
## styles.css contract:
##   font: var(--font-ui), 11 px
##   color: var(--gold)   (currency)
##   color: var(--teal)   (`.float-gain.item` — item drops)
##   text-shadow: 1px 1px 0 #000, 2px 2px 0 #000000aa
##   animation: float-up 1100ms ease-out forwards
##
## @keyframes float-up:
##   0%:   translateY(0)   scale(0.7)   opacity(0)
##   20%:  translateY(-8)  scale(1.1)   opacity(1)
##   100%: translateY(-56) scale(1.0)   opacity(0)
##
## The pivot at `size * 0.5` is critical — without it the scale
## animation pivots from the top-left and the number sweeps off
## sideways. v0.10.b had this; preserved.
extends Label

const _DUSK := preload("res://assets/themes/dusk/palette_dusk.gd")

const _DURATION := 1.1   # styles.css 1100ms
const _DRIFT_PIXELS := 56.0   # styles.css final translateY -56
const _LIFT_PIXELS := 8.0     # styles.css 20% keyframe translateY -8

## v0.15.10 — magnitude bands. Bigger gold gains read as bigger events
## (the UX research's "make numbers-go-up stay satisfying" item). The
## caller maps a gold amount's order of magnitude to a band 0..4
## (see catching_view._gold_magnitude_band); the band drives base font
## size. styles.css `.float-gain` is single-size; this extends it.
##   band 0: < 1K   band 1: 1K–999K   band 2: 1M–999M
##   band 3: 1B–999B   band 4 (milestone): 1T+
## Steps are ≥3 design-px apart so each band is a clearly-felt jump.
const _MAGNITUDE_SIZES: Array[int] = [11, 14, 17, 20, 24]

## Configures the visual then returns self for fluent setup at the
## call site. `is_item` paints teal (drops) instead of gold; `is_shiny`
## adds a ✨ prefix; `magnitude` (0..4) scales size/colour by payout size.
##
## Backwards-compat: pre-14g callers pass `(gold_text, is_shiny)` and
## pre-v0.15.10 callers pass `(gold_text, is_shiny, is_item)`; both flags
## default so existing call sites are unaffected (magnitude 0 = base look).
func configure(gold_text: String, is_shiny: bool = false, is_item: bool = false, magnitude: int = 0) -> Label:
	var palette: Dictionary = _DUSK.active()
	# styles.css: `+N g` for currency, `+1 ItemName` for item drops.
	# Caller can already pass an item-formatted string for is_item=true;
	# we just don't add the trailing " g".
	if is_item:
		text = gold_text   # caller pre-formats: "+1 Mushroom" etc.
	else:
		text = "+" + gold_text + " g"
	if is_shiny:
		text = "✨ " + text

	# styles.css ink: gold for currency, teal for items. v0.15.10: large
	# gold gains brighten toward white-gold so a big payout reads as a
	# bigger event — a magnitude ramp on top of the single styles.css hue.
	# Items keep their flat teal (magnitude isn't meaningful for "+1 Item").
	var base_color: Color = palette["teal"] if is_item else palette["gold"]
	if not is_item and magnitude >= 2:
		# Graduated brighten so mid-game (1M+) gains get a subtle colour
		# cue and milestones (1T+) pop hardest.
		var brighten: float = 0.12 if magnitude == 2 else (0.25 if magnitude == 3 else 0.45)
		base_color = base_color.lerp(Color(1, 1, 1), brighten)
	add_theme_color_override("font_color", base_color)

	# 1-px hard drop shadow per styles.css `text-shadow: 1px 1px 0 #000`.
	# Milestone-magnitude (band 4) gains get a heavier 2-px shadow for
	# extra punch (approximates the styles.css second shadow layer).
	add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	var shadow_px: int = 2 if magnitude >= 4 else 1
	add_theme_constant_override("shadow_offset_x", shadow_px)
	add_theme_constant_override("shadow_offset_y", shadow_px)

	# Base size comes from the magnitude band; shiny adds +2 on top so a
	# rare big catch still reads as the biggest. Items use the base band.
	var band: int = clampi(magnitude, 0, _MAGNITUDE_SIZES.size() - 1)
	var base_size: int = _MAGNITUDE_SIZES[band]
	if is_shiny:
		base_size += 2
	add_theme_font_size_override("font_size", UiScale.size(base_size))

	# Use UiTiny (Silkscreen) variation per styles.css `font-ui`.
	theme_type_variation = &"UiTiny"
	return self


func _ready() -> void:
	z_index = 50
	# Center the scale + pivot transforms on the label's own midpoint,
	# not its top-left, so the scale animation feels like a punch out
	# of the catch point rather than a sweep off to the right.
	pivot_offset = size * 0.5

	# v0.11.1 (Phase 11b): reduce_motion users see the number for a
	# brief beat with NO scale punch and NO drift — same intent
	# (catch registered, gold awarded) without motion that triggers
	# vestibular sensitivity.
	if Settings.reduce_motion:
		_play_reduced_motion()
		return

	_play_full_motion()


## Phase 14g styles.css `float-up` keyframes:
##   0%:   translateY(0)   scale(0.7)   opacity(0)
##   20%:  translateY(-8)  scale(1.1)   opacity(1)  (~220 ms)
##   100%: translateY(-56) scale(1.0)   opacity(0)  (~1100 ms)
##
## Implementation: chain two parallel tweens. Phase 1 (0→20%) is the
## punch-out; phase 2 (20%→100%) is the drift-up + fade-out.
##
## ease-out applied to both phases so the punch decelerates and the
## drift slows as it rises.
func _play_full_motion() -> void:
	var start_y: float = position.y
	# Start state per 0% keyframe.
	scale = Vector2(0.7, 0.7)
	modulate.a = 0.0

	var t: Tween = create_tween()
	t.set_ease(Tween.EASE_OUT)

	# Phase 1 (0→20%, 0..220 ms): punch up to scale 1.1 + fade in +
	# small lift.
	var phase1: float = _DURATION * 0.2
	t.set_parallel(true)
	t.tween_property(self, "scale", Vector2(1.1, 1.1), phase1)
	t.tween_property(self, "modulate:a", 1.0, phase1)
	t.tween_property(self, "position:y", start_y - _LIFT_PIXELS, phase1)

	# Phase 2 (20→100%, 220..1100 ms): settle to scale 1.0, drift to
	# -56 px, fade to 0.
	var phase2: float = _DURATION * 0.8
	t.chain().set_parallel(true)
	t.tween_property(self, "scale", Vector2.ONE, phase2)
	t.tween_property(self, "position:y", start_y - _DRIFT_PIXELS, phase2)
	t.tween_property(self, "modulate:a", 0.0, phase2)

	# Free the node once everything settles. `set_parallel(false)` on a
	# fresh `chain()` segment so the callback fires AFTER the parallel
	# phase 2 finishes, not in parallel with it.
	t.chain().tween_callback(queue_free)


## reduce_motion path: hold the number at full opacity briefly, then
## fade. No scale punch, no drift. Same total duration as the full
## motion so the call site's timing assumptions hold.
func _play_reduced_motion() -> void:
	modulate.a = 1.0
	scale = Vector2.ONE
	var t: Tween = create_tween()
	t.tween_property(self, "modulate:a", 0.0, _DURATION * 0.4).set_delay(_DURATION * 0.6)
	t.tween_callback(queue_free)
