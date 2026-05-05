#!/usr/bin/env bash
# Phase 12f — emit the 20 starter achievement .tres files. Idempotent;
# re-running overwrites cleanly. Mirrors the script-emitted pattern
# the dialogue corpus used in v0.9.2.
#
# Usage:
#   bash scripts/generate_achievements.sh
set -euo pipefail

OUT_DIR="game/data/achievements"
mkdir -p "$OUT_DIR"

# Source enum values (must match AchievementResource.Source):
#   0 LEDGER_FIELD
#   1 PRESTIGE_COUNT
#   2 PETS_OWNED_COUNT
#   3 NETS_OWNED_COUNT
#   4 RECIPES_CRAFTED_COUNT
#   5 CURRENT_MAX_TIER
# Tier enum:
#   0 BRONZE  1 SILVER  2 GOLD

emit() {
	local id="$1"
	local display="$2"
	local desc="$3"
	local tier="$4"
	local source="$5"
	local ledger_field="$6"
	local threshold="$7"
	local rp_reward="$8"
	local file="$OUT_DIR/${id}.tres"
	cat > "$file" <<EOF
[gd_resource type="Resource" script_class="AchievementResource" load_steps=2 format=3]

[ext_resource type="Script" path="res://game/resources/achievement_resource.gd" id="1"]

[resource]
script = ExtResource("1")
id = &"${id}"
display_name = "${display}"
description = "${desc}"
tier = ${tier}
source = ${source}
ledger_field = &"${ledger_field}"
threshold = ${threshold}
rp_reward = ${rp_reward}
gold_reward = {"m": 0.0, "e": 0}
EOF
}

# Catching
emit "catch_100"   "First Hundred"      "Catch 100 monsters of any species."         0 0 "total_catches"  100   5
emit "catch_1000"  "Thousand Hands"     "Catch 1,000 monsters."                      1 0 "total_catches"  1000  25
emit "catch_10000" "Field Authority"    "Catch 10,000 monsters."                     2 0 "total_catches"  10000 100
emit "shiny_1"     "First Shimmer"      "Catch your first shiny."                    0 0 "total_shinies"  1     10
emit "shiny_25"    "Shimmer Hoarder"    "Catch 25 shinies."                          1 0 "total_shinies"  25    100

# Tapping
emit "tap_500"     "Persistent"         "Tap 500 times."                              0 0 "total_taps"     500   5
emit "tap_5000"    "Compulsive"         "Tap 5,000 times."                            1 0 "total_taps"     5000  50
emit "tap_50000"   "Dedicated"          "Tap 50,000 times."                           2 0 "total_taps"     50000 250

# Prestige
emit "prestige_1"  "Reset and Begin"    "Prestige once."                              0 1 ""               1     0
emit "prestige_5"  "Cycle Veteran"      "Prestige five times."                        1 1 ""               5     50
emit "prestige_25" "Cycle Master"       "Prestige 25 times."                          2 1 ""               25    500

# Pets
emit "pet_1"       "First Companion"    "Own your first pet."                         0 2 ""               1     5
emit "pet_3"       "Trio"               "Own 3 pets."                                  1 2 ""               3     25
emit "pet_10"      "Menagerie"          "Own 10 pets."                                 2 2 ""               10    100

# Nets
emit "net_2"       "Better Mesh"        "Own 2 different nets."                        0 3 ""               2     10
emit "net_5"       "Net Wright"         "Own 5 different nets."                        1 3 ""               5     50

# Crafting
emit "recipe_1"    "First Forge"        "Craft your first recipe."                    0 4 ""               1     5
emit "recipe_5"    "Tinkerer"           "Craft 5 different recipes."                  1 4 ""               5     25

# Tier
emit "tier_5"      "Mid-Range"          "Reach tier 5."                                1 5 ""               5     50
emit "tier_10"     "Highland"           "Reach tier 10."                               2 5 ""               10    200

echo "[generate_achievements] wrote 20 .tres files to $OUT_DIR"
