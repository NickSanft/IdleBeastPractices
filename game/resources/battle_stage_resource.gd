## Phase 10e.2 — multi-encounter battle stage.
##
## A stage is a sequence of [EncounterResource] waves the player team
## must clear in succession. Pet HP carries between encounters; the
## stage fails if the team wipes mid-stage. Rewards are emitted
## once at stage completion (not per-encounter).
##
## Layout convention:
##   - 1 stage per tier band (5 stages for 20 tiers initially).
##   - 3-5 encounters per stage. Difficulty within a stage scales
##     monotonically (e.g. wave 1 has tier-N monsters, wave 3 has
##     tier-N + minor variants).
class_name BattleStageResource
extends Resource

@export var id: StringName
@export var display_name: String
## Player tier this stage is unlocked at. `current_max_tier >= tier`
## means the stage is selectable from the BattleView's stage picker.
@export var tier: int = 1
@export var encounters: Array[EncounterResource] = []
## Optional Peniber line fired on stage completion. Empty = no line.
@export var narrator_stage_clear_id: StringName = &""

## Bonus Rancher Points awarded on stage clear, on top of the per-
## encounter RP totals BattleSystem already credits. Designers can
## leave at 0 and rely on per-encounter RP for balanced stages.
@export var bonus_rp_on_clear: int = 0
