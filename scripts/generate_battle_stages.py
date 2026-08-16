#!/usr/bin/env python3
"""Generate per-tier battle-stage .tres files (v0.15.19).

One stage per tier with a wave shape measured as winnable by
tools/simulate_stage_winrates.gd (fully-equipped 3-pet roster, 20 seeds):

    tiers 3-20: solo/duo/trio (100% bare and equipped, all 20 tiers)

Phase 15a made the roster scale: pets are awarded for every tier, and
BattleView fields GameState.battle_team(3) — the strongest three owned.
The pre-15a table thinned its waves (tier 4 solo/duo, tier 5 solo/solo,
tier 6 solo) and then stopped, because a static three-pet tier-1 roster
could not survive deeper waves. That constraint is gone, so every tier
gets the full shape. bonus_rp_on_clear stays 0
(per-encounter RP already scales with monster tier, and stage RP is granted
on EVERY clear, so a flat bonus would be farmable).

Usage:
    python scripts/generate_battle_stages.py

Writes tiers 3..20 (1-2 are hand-authored). If pet power ever changes, re-run
the simulator, update SHAPES, and re-generate — BattleView auto-picks the
highest unlocked stage (no picker exists), so an unwinnable top stage would
brick the battler for late players.
"""
import re
import sys
import glob
import os
import collections

# tier -> list of wave sizes (1=solo, 2=duo, 3=trio), from the simulator.
#
# Phase 15a re-derived this table. The thinning shapes above tier 3 existed
# only because the roster was STATIC — three tier-1 pets walking into
# tier-scaled enemies — so the waves had to get lighter to stay winnable,
# and past tier 6 no shape was winnable at all. Now that pets are awarded
# for every tier, tools/simulate_stage_winrates.gd reports 100% on the
# richest solo/duo/trio shape at EVERY tier 1-20, bare and equipped, so
# every tier gets the full shape and the band runs to the tier cap.
SHAPES = {t: [1, 2, 3] for t in range(3, 21)}

# Peniber-flavored "Family Place" names, one per tier — the same pattern as
# the hand-authored "Wisplet Hollows" / "Centiphantom Drifts".
STAGE_NAMES = {
    3: "Hush Thicket",
    4: "Wraith Slagfields",
    5: "Golem Quarry",
    6: "Surge Shallows",
    7: "Glimmer Brood",
    8: "Hedge Warrens",
    9: "Gleam Foundry",
    10: "Drift Floes",
    11: "Scour Ashlands",
    12: "Muddler Stacks",
    13: "Refrain Gallery",
    14: "Knot Loomery",
    15: "Vigil Chapel",
    16: "Refract Prismarium",
    17: "Palimpsest Archive",
    18: "Whisper Cloister",
    19: "Hollow Verge",
    20: "Nadir Spire",
}

def build_tres(stage_id: str, name: str, tier: int, ids: list, wave_sizes: list) -> str:
    """Mirror the hand-authored stage .tres format exactly.

    load_steps follows the existing files' pattern (2 ext + 3 sub -> 8),
    i.e. 2 + 2 * num_encounters.
    """
    # Waves rotate through the tier's three species, sorted for determinism:
    # solo = ids[0]; duo = ids[1], ids[2]; trio = all three; a second solo
    # wave (tier 5's solo/solo) uses ids[1] so both waves differ.
    wave_members = {1: [[ids[0]], [ids[1]]], 2: [[ids[1], ids[2]]], 3: [[ids[0], ids[1], ids[2]]]}
    used_solo = 0
    lines = [
        f'[gd_resource type="Resource" script_class="BattleStageResource" load_steps={2 + 2 * len(wave_sizes)} format=3]',
        "",
        '[ext_resource type="Script" path="res://game/resources/battle_stage_resource.gd" id="1_stage"]',
        '[ext_resource type="Script" path="res://game/resources/encounter_resource.gd" id="2_enc"]',
        "",
    ]
    enc_refs = []
    for i, size in enumerate(wave_sizes, start=1):
        if size == 1:
            members = wave_members[1][min(used_solo, 1)]
            used_solo += 1
        else:
            members = wave_members[size][0]
        mids = ", ".join(f'&"{m}"' for m in members)
        lines += [
            f'[sub_resource type="Resource" id="enc_{i}"]',
            'script = ExtResource("2_enc")',
            f"monster_ids = [{mids}]",
            'narrator_line_id = &""',
            "",
        ]
        enc_refs.append(f'SubResource("enc_{i}")')
    lines += [
        "[resource]",
        'script = ExtResource("1_stage")',
        f'id = &"{stage_id}"',
        f'display_name = "{name}"',
        f"tier = {tier}",
        f"encounters = [{', '.join(enc_refs)}]",
        'narrator_stage_clear_id = &"on_stage_cleared"',
        "bonus_rp_on_clear = 0",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    # Run from the repo root regardless of invocation CWD.
    os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    tiers = collections.defaultdict(list)
    for path in sorted(glob.glob("game/data/monsters/*.tres")):
        text = open(path, encoding="utf-8").read()
        mid = re.search(r'^id = &"([^"]+)"', text, re.M).group(1)
        tier = int(re.search(r"^tier = (\d+)", text, re.M).group(1))
        tiers[tier].append(mid)

    out_dir = "game/data/battle_stages"
    written = []
    for tier, wave_sizes in sorted(SHAPES.items()):
        ids = sorted(tiers[tier])
        if len(ids) != 3:
            print(f"tier {tier}: expected 3 species, found {len(ids)} — skipped")
            continue
        name = STAGE_NAMES[tier]
        stage_id = name.lower().replace(" ", "_")
        content = build_tres(stage_id, name, tier, ids, wave_sizes)
        path = os.path.join(out_dir, f"{stage_id}.tres")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(content)
        written.append(path)
        print(f"wrote {path} (waves {wave_sizes})")
    print(f"{len(written)} stages written")
    if len(written) != len(SHAPES):
        print("ERROR: expected one file per SHAPES entry — check monster data")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
