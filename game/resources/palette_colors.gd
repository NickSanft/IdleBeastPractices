## Named palette for the Phase 10 polish theme.
##
## Reference these constants instead of hardcoding hex literals when
## scripts need a Color value (e.g. modulating a sprite, painting a
## ColorRect, drawing a vector overlay). The Theme resource at
## `res://game/resources/main_theme.tres` is the source of truth for
## widget styling — this script exists for the cases that don't go
## through Theme.
class_name PaletteColors
extends RefCounted

# Backgrounds and surfaces.
const PARCHMENT       := Color(0.93, 0.88, 0.74, 1.0)  # base panel fill
const PARCHMENT_DEEP  := Color(0.84, 0.78, 0.62, 1.0)  # nested panel / pressed button
const PARCHMENT_LIGHT := Color(0.97, 0.93, 0.81, 1.0)  # hovered surface
const VELLUM          := Color(0.88, 0.82, 0.66, 1.0)  # progress bar background

# Inks and borders.
const SEPIA_DARK   := Color(0.31, 0.22, 0.13, 1.0)  # body text on parchment
const SEPIA_MID    := Color(0.46, 0.34, 0.20, 1.0)  # secondary text
const INK_BLACK    := Color(0.10, 0.07, 0.05, 1.0)  # high-contrast headings
const BRASS_ACCENT := Color(0.72, 0.55, 0.20, 1.0)  # borders, accents, currency tint
const BRASS_DEEP   := Color(0.50, 0.36, 0.10, 1.0)  # pressed accents

# Semantic.
const BLOOD_RUBY := Color(0.65, 0.16, 0.22, 1.0)  # warnings, prestige
const SAGE_GREEN := Color(0.40, 0.55, 0.36, 1.0)  # success, RP gain
const DUSK_BLUE  := Color(0.36, 0.42, 0.58, 1.0)  # rancher points, info

# Translucent overlays.
const SHADOW_SOFT := Color(0.10, 0.07, 0.05, 0.18)
