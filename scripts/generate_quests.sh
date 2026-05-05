#!/usr/bin/env bash
# Phase 12g — emit the starter quest .tres files. Idempotent;
# re-running overwrites cleanly. Mirrors the achievements generator
# pattern from 12f.
#
# Usage:
#   bash scripts/generate_quests.sh
set -euo pipefail

OUT_DIR="game/data/quests"
mkdir -p "$OUT_DIR"

# QuestTier:  0 SHORT  1 MEDIUM  2 LONG
# Source:     0 LEDGER_FIELD  1 PRESTIGE_COUNT  2 PETS_OWNED_COUNT
#             3 NETS_OWNED_COUNT  4 RECIPES_CRAFTED_COUNT  5 CURRENT_MAX_TIER
#             6 RUN_GOLD_EARNED

emit() {
	local id="$1"
	local display="$2"
	local desc="$3"
	local quest_tier="$4"
	local source="$5"
	local ledger_field="$6"
	local threshold="$7"
	local baseline="$8"
	local repeatable="$9"
	local next_id="${10}"
	local rp_reward="${11}"
	local gold_m="${12}"
	local gold_e="${13}"
	local file="$OUT_DIR/${id}.tres"
	cat > "$file" <<EOF
[gd_resource type="Resource" script_class="QuestResource" load_steps=2 format=3]

[ext_resource type="Script" path="res://game/resources/quest_resource.gd" id="1"]

[resource]
script = ExtResource("1")
id = &"${id}"
display_name = "${display}"
description = "${desc}"
quest_tier = ${quest_tier}
source = ${source}
ledger_field = &"${ledger_field}"
threshold = ${threshold}
baseline = ${baseline}
repeatable = ${repeatable}
next_quest_id = &"${next_id}"
rp_reward = ${rp_reward}
gold_reward = {"m": ${gold_m}, "e": ${gold_e}}
item_reward_id = &""
item_reward_amount = 0
EOF
}

# ─────────────────────────────────────────────────────────────────────────
# SHORT (10): catchable in a session minute. Most are repeatable ladders
# so the slot keeps cycling rather than emptying.
# ─────────────────────────────────────────────────────────────────────────

# Catching ladder (3 rungs). RP reward grows; gold reward modest.
emit "short_catch_25"   "Catch 25"          "Catch 25 monsters."             0 0 "total_catches"  25    0     true  "short_catch_100"  1 50.0 0
emit "short_catch_100"  "Catch 100"         "Catch 100 monsters."            0 0 "total_catches"  100   25    true  "short_catch_500"  3 200.0 0
emit "short_catch_500"  "Catch 500"         "Catch 500 monsters."            0 0 "total_catches"  500   100   false ""                 8 1.0 3

# Tap ladder (2 rungs).
emit "short_tap_100"    "Tap 100"           "Tap 100 times."                 0 0 "total_taps"     100   0     true  "short_tap_500"    1 25.0 0
emit "short_tap_500"    "Tap 500"           "Tap 500 times."                 0 0 "total_taps"     500   100   false ""                 4 100.0 0

# One-shot misc.
emit "short_first_shiny" "Find a Shiny"     "Catch any shiny monster."       0 0 "total_shinies"  1     0     false ""                 5 0.0 0
emit "short_recipe_any"  "Craft Anything"   "Craft any recipe once."         0 4 ""               1     0     false ""                 3 0.0 0
emit "short_pet_one"     "First Companion"  "Add a pet to your roster."      0 2 ""               1     0     false ""                 5 0.0 0

# Run-gold ladder (BigNumber thresholds stored as int via .to_float()
# at evaluation; keep these comfortably under 2^53).
emit "short_gold_1k"     "Earn 1k Gold"     "Earn 1,000 gold this run."      0 6 ""               1000     0     true  "short_gold_10k"   2 0.0 0
emit "short_gold_10k"    "Earn 10k Gold"    "Earn 10,000 gold this run."     0 6 ""               10000    1000  false ""                 6 0.0 0

# ─────────────────────────────────────────────────────────────────────────
# MEDIUM (12): session-spanning.
# ─────────────────────────────────────────────────────────────────────────

emit "med_tier_3"        "Reach Tier 3"     "Reach the 3rd catching tier."   1 5 ""               3     0     false ""                 10 500.0 0
emit "med_tier_5"        "Reach Tier 5"     "Reach the 5th catching tier."   1 5 ""               5     0     false ""                 25 1.0 3
emit "med_pet_3"         "Trio Roster"      "Own 3 different pets."          1 2 ""               3     0     false ""                 15 0.0 0
emit "med_pet_5"         "Five Companions"  "Own 5 different pets."          1 2 ""               5     0     false ""                 30 0.0 0
emit "med_nets_2"        "Better Mesh"      "Own 2 different nets."          1 3 ""               2     0     false ""                 10 0.0 0
emit "med_recipes_3"     "Tinkerer"         "Craft 3 different recipes."     1 4 ""               3     0     false ""                 15 0.0 0
emit "med_shinies_5"     "Shimmer Run"      "Catch 5 shinies this run."      1 0 "total_shinies"  5     0     false ""                 20 0.0 0
emit "med_catches_2k"    "Catch 2,000"      "Catch 2,000 monsters lifetime." 1 0 "total_catches"  2000  0     false ""                 25 1.0 3
emit "med_taps_5k"       "5,000 Taps"       "Tap 5,000 times lifetime."      1 0 "total_taps"     5000  0     false ""                 20 0.0 0
emit "med_gold_100k"     "Hundred Thousand" "Earn 100k gold this run."       1 6 ""               100000   0     false ""                 30 0.0 0
emit "med_gold_1m"       "Millionaire Run"  "Earn 1M gold this run."         1 6 ""               1000000  0     false ""                 60 0.0 0
emit "med_battle_stages" "Stage Conqueror"  "Reach tier 4 (battles unlocked)." 1 5 ""             4     0     false ""                 20 0.0 0

# ─────────────────────────────────────────────────────────────────────────
# LONG (8): prestige-cycle goals. Mostly one-shot per prestige.
# ─────────────────────────────────────────────────────────────────────────

emit "long_prestige_1"   "First Prestige"   "Prestige once."                 2 1 ""               1     0     false ""                 25  0.0 0
emit "long_prestige_5"   "Cycle Veteran"    "Prestige 5 times."              2 1 ""               5     0     false ""                 100 0.0 0
emit "long_prestige_25"  "Cycle Master"     "Prestige 25 times."             2 1 ""               25    0     false ""                 500 0.0 0
emit "long_tier_10"      "Highland"         "Reach tier 10."                 2 5 ""               10    0     false ""                 75  0.0 0
emit "long_tier_15"      "Sky Tier"         "Reach tier 15."                 2 5 ""               15    0     false ""                 200 0.0 0
emit "long_tier_20"      "Capstone"         "Reach tier 20 (the cap)."       2 5 ""               20    0     false ""                 500 0.0 0
emit "long_pets_10"      "Menagerie"        "Own 10 different pets."         2 2 ""               10    0     false ""                 100 0.0 0
emit "long_recipes_8"    "Master Crafter"   "Craft 8 different recipes."     2 4 ""               8     0     false ""                 75  0.0 0

echo "[generate_quests] wrote .tres files to $OUT_DIR"
