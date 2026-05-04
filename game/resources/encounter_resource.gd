## Phase 10e.2 — single encounter inside a [BattleStageResource].
##
## An encounter is one wave of enemies that materializes at the
## engagement line. Up to 3 monsters spawn simultaneously. The player
## team (with carry-over HP) must defeat them before the next
## encounter materializes.
class_name EncounterResource
extends Resource

## StringName ids of the monsters that spawn in this encounter.
## Looked up via `ContentRegistry.monster(id)` at simulation time.
## Up to 3 entries; extras are clamped by [BattleSystem].
@export var monster_ids: Array[StringName] = []

## Optional Peniber line fired when this encounter starts. Empty
## StringName = no line. Resolved via `Narrator.try_speak(trigger_id)`.
@export var narrator_line_id: StringName = &""
