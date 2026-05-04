## Phase 12c — first-time user tutorial state.
##
## Tracks which scripted onboarding steps the player has seen.
## Persisted to `user://tutorial.cfg` so steps don't replay across
## sessions. Steps unlock progressively per Pecorella's GDC framing
## ("the tutorial unlocks mechanics rather than explaining them") —
## each one fires when its trigger condition is met, not on a fixed
## timer.
##
## Steps:
##   1. tap_first_monster      — coachmark on the first wandering monster
##   2. buy_first_net          — fires at 100 gold owned + no net equipped
##   3. equip_net              — after first net purchase
##   4. complete_first_tier    — at ~5 catches into tier 1
##   5. enter_battle           — after first pet awarded
##   6. craft_first_recipe     — when first recipe unlocks (tier 2)
##
## Coachmarks consume tutorial step ids and decide whether to render
## via `should_show(step_id)`. Once dismissed, mark via
## `mark_seen(step_id)` so it never replays without a Replay-tutorial.
extends Node

const _PATH := "user://tutorial.cfg"

const STEP_TAP_FIRST_MONSTER := &"tap_first_monster"
const STEP_BUY_FIRST_NET := &"buy_first_net"
const STEP_EQUIP_NET := &"equip_net"
const STEP_COMPLETE_FIRST_TIER := &"complete_first_tier"
const STEP_ENTER_BATTLE := &"enter_battle"
const STEP_CRAFT_FIRST_RECIPE := &"craft_first_recipe"

const ALL_STEPS: Array[StringName] = [
	STEP_TAP_FIRST_MONSTER,
	STEP_BUY_FIRST_NET,
	STEP_EQUIP_NET,
	STEP_COMPLETE_FIRST_TIER,
	STEP_ENTER_BATTLE,
	STEP_CRAFT_FIRST_RECIPE,
]

## Set of step ids that have been completed. Persisted; consulted by
## should_show().
var steps_seen: Dictionary = {}


func _ready() -> void:
	load_from_disk()


func should_show(step_id: StringName) -> bool:
	return not steps_seen.has(String(step_id))


func mark_seen(step_id: StringName) -> void:
	if steps_seen.has(String(step_id)):
		return
	steps_seen[String(step_id)] = true
	save_to_disk()


## Reset all tutorial state — used by the Settings "Replay tutorial"
## button. After this, the next session shows steps from scratch.
func reset() -> void:
	steps_seen.clear()
	save_to_disk()


## Returns true if at least one tutorial step has been completed.
## Used by the Settings UI to decide whether to show the
## "Replay tutorial" button at all (no point showing it before the
## tutorial has run).
func has_any_progress() -> bool:
	return not steps_seen.is_empty()


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(_PATH)
	if err != OK:
		return
	if cfg.has_section_key("tutorial", "steps_seen"):
		var raw: Variant = cfg.get_value("tutorial", "steps_seen", {})
		if raw is Dictionary:
			steps_seen = raw


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("tutorial", "steps_seen", steps_seen)
	cfg.save(_PATH)
