#!/usr/bin/env python3
"""
One-shot Phase 5c content generator. Writes 51 MonsterResource .tres,
17 ItemResource .tres, 6 NetResource .tres, and 6 CraftingRecipeResource
.tres files to game/data/. Idempotent — re-running overwrites.

Curve from DETAILED_PLAN.md §6:
  gold_base scales × 6.5 per tier from the prior tier's mid value.
  catch_difficulty scales × 2.8 per tier.

Names follow a thematic progression so authoring tier 21+ later is
mechanical. Sprites alternate between wisplet.png and centiphantom.png
for visual variety; tints get progressively cooler/darker as tiers
escalate.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MON_DIR = ROOT / "game" / "data" / "monsters"
ITEM_DIR = ROOT / "game" / "data" / "items"
NET_DIR = ROOT / "game" / "data" / "nets"
RECIPE_DIR = ROOT / "game" / "data" / "recipes"


# Tier theme: ((three species names), suffix, sprite_basename, drop_item_name, drop_item_id, drop_item_flavor)
TIER_THEMES = {
    4:  (("dross", "slag", "scoria"),     "wraith",     "wisplet",       "Wraith Cinder",     "wraith_cinder",     "Sooty residue from a captured wraith. Sticks to fingers. Sticks to thoughts."),
    5:  (("gravel", "agate", "geode"),    "golem",      "centiphantom",  "Golem Pebble",      "golem_pebble",      "Pebbles unaccountably warm to the touch and faintly indignant."),
    6:  (("tide", "swell", "ripple"),     "surge",      "wisplet",       "Surge Brine",       "surge_brine",       "Salt water that refuses to dry. The Synod hates this stuff."),
    7:  (("brood", "swarm", "molt"),      "glimmer",    "centiphantom",  "Glimmer Husk",      "glimmer_husk",      "A discarded shell that retains, faintly, the original creature's posture."),
    8:  (("thorn", "briar", "burr"),      "hedge",      "wisplet",       "Hedge Thorn",       "hedge_thorn",       "Thorns. They claim to have been provoked, though Peniber finds this exculpation thin."),
    9:  (("gild", "brass", "bronze"),     "gleam",      "centiphantom",  "Gleam Filing",      "gleam_filing",      "Metallic shavings. Allegedly precious, though no two assayers agree on which kind."),
    10: (("rime", "glaze", "floe"),       "drift",      "wisplet",       "Drift Crystal",     "drift_crystal",     "A crystal that hums one low note. Inadvisable to listen too long."),
    11: (("ember", "ash", "char"),        "scour",      "centiphantom",  "Scour Cinder",      "scour_cinder",      "Cinders that are still annoyed about something. Hot to the touch even at noon."),
    12: (("lore", "index", "scribe"),     "muddler",    "wisplet",       "Muddler Glyph",     "muddler_glyph",     "A glyph etched on bark, meaning roughly: 'this is information; please ignore it'."),
    13: (("psalm", "dirge", "canto"),     "refrain",    "centiphantom",  "Refrain Echo",      "refrain_echo",      "A trapped echo. The Synod's archivists insist they hear distant approval; Peniber hears nothing."),
    14: (("silk", "spun", "gossamer"),    "knot",       "wisplet",       "Knot Strand",       "knot_strand",       "A length of thread that ties itself into knots while you watch. Unhelpful."),
    15: (("candle", "wax", "wick"),       "vigil",      "centiphantom",  "Vigil Tallow",      "vigil_tallow",      "Tallow with an aftertaste. Nothing is sworn over it; nothing is forsworn over it."),
    16: (("prism", "mirror", "shard"),    "refract",    "wisplet",       "Refract Splinter",  "refract_splinter",  "A splinter that catches light from rooms it has never been in."),
    17: (("vellum", "parchment", "scroll"), "palimpsest", "centiphantom","Palimpsest Leaf",   "palimpsest_leaf",   "A leaf with three texts written over each other. None of them is the original."),
    18: (("cipher", "sigil", "glyph"),    "whisper",    "wisplet",       "Whisper Sigil",     "whisper_sigil",     "An incised symbol. Reading it costs five seconds you do not get back."),
    19: (("void", "null", "lacuna"),      "hollow",     "centiphantom",  "Hollow Cinder",     "hollow_cinder",     "Coal that does not weigh anything. The scales refuse to comment."),
    20: (("aether", "spire", "eon"),      "nadir",      "wisplet",       "Nadir Pollen",      "nadir_pollen",      "Pollen from no plant. The Synod's botanists are on extended sabbatical."),
}


# Within each tier, the three species use these spawn-weight / difficulty
# multipliers to mirror the tier-1 spread (1.0/0.85/0.7 weight; 1.0/1.2/1.5 diff).
SPECIES_WEIGHTS    = (1.0, 0.85, 0.70)
SPECIES_DIFF_MULT  = (1.0, 1.2, 1.5)
SPECIES_GOLD_MULT  = (1.0, 1.4, 1.9)   # roughly mirrors tier-1 (1, 2, 3 ≈ 1×, 1.4×, 1.9×).
SPECIES_DROP_MIN   = (1, 2, 1)
SPECIES_DROP_MAX   = (2, 3, 3)


# Tints: HSV-style sweep; tier-1 was (1,1,1) base. We escalate saturation
# and skew hue per tier to differentiate at-a-glance. Per-species variants
# within a tier swap red/blue emphasis like the original wisplets did.
def tier_tints(tier: int):
    # Base hue sweep: tier 4 starts pink-orange, marches through cyan
    # by tier 12, lands on deep purple by tier 20.
    # Crude: map tier 4..20 → hue 0.05 .. 0.85 around the wheel.
    import colorsys
    hue = (tier - 4) / 16.0 * 0.85 + 0.05
    sat = min(0.95, 0.45 + (tier - 4) * 0.04)
    val = min(1.6, 0.95 + (tier - 4) * 0.04)   # slight overshoot for late-game pop.
    base = colorsys.hsv_to_rgb(hue, sat, val)
    # The three species perturb the base: a (base), b (warmer), c (cooler).
    a = (base[0], base[1], base[2])
    b = (min(2.0, base[0] * 1.35), base[1] * 0.85, base[2] * 0.85)
    c = (base[0] * 0.85, base[1] * 0.85, min(2.0, base[2] * 1.35))
    return [a, b, c]


def round_int(x: float) -> int:
    return max(1, int(round(x)))


# Per-tier base values from the §6 curve, chained from tier 3 (mid 110, diff 14).
def tier_base_values():
    """Returns dict[tier] = (gold_mid, diff_mid, shiny_rate)."""
    out = {}
    gold = 110.0
    diff = 14.0
    for t in range(4, 21):
        gold *= 6.5
        diff *= 2.8
        # Shiny rate slowly decreases for higher tiers to keep them special.
        shiny = max(0.005, 0.03 - (t - 3) * 0.001)
        out[t] = (gold, diff, shiny)
    return out


def write_file(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8", newline="\n")


def gen_item(tier: int) -> tuple[str, Path]:
    _, _, _, item_name, item_id, flavor = TIER_THEMES[tier]
    sell_value = round_int(110 * (6.5 ** (tier - 3)))
    # Render BigNumber dict for sell_value.
    if sell_value < 10:
        m, e = float(sell_value), 0
    else:
        e = len(str(int(sell_value))) - 1
        m = sell_value / (10 ** e)
    content = f"""[gd_resource type="Resource" script_class="ItemResource" load_steps=2 format=3]

[ext_resource type="Script" path="res://game/resources/item_resource.gd" id="1"]

[resource]
script = ExtResource("1")
id = &"{item_id}"
display_name = "{item_name}"
description = "Drops from tier-{tier} catches."
category = 0
stack_max = 9999999
sell_value = {{"m": {m:.2f}, "e": {e}}}
flavor_text = "{flavor}"
"""
    path = ITEM_DIR / f"{item_id}.tres"
    return content, path


def gen_monster(tier: int, species_idx: int) -> tuple[str, Path]:
    species_names, suffix, sprite_basename, _, item_id, _ = TIER_THEMES[tier]
    species = species_names[species_idx]
    monster_id = f"{species}_{suffix}"
    display = f"{species.capitalize()} {suffix.capitalize()}"
    gold_mid, diff_mid, shiny = tier_base_values()[tier]
    gold_base = round_int(gold_mid * SPECIES_GOLD_MULT[species_idx])
    difficulty = round(diff_mid * SPECIES_DIFF_MULT[species_idx], 1)
    spawn_weight = SPECIES_WEIGHTS[species_idx]
    drop_min = SPECIES_DROP_MIN[species_idx]
    drop_max = SPECIES_DROP_MAX[species_idx]
    tint = tier_tints(tier)[species_idx]
    flavor = f"A tier-{tier} {species}-{suffix}. {('Volatile.' if species_idx == 1 else 'Slow.' if species_idx == 0 else 'Wary.')} Recommend gloves."
    content = f"""[gd_resource type="Resource" script_class="MonsterResource" load_steps=4 format=3]

[ext_resource type="Script" path="res://game/resources/monster_resource.gd" id="1_script"]
[ext_resource type="Texture2D" path="res://assets/sprites/{sprite_basename}.png" id="2_sprite"]
[ext_resource type="Resource" path="res://game/data/items/{item_id}.tres" id="3_drop"]

[resource]
script = ExtResource("1_script")
id = &"{monster_id}"
display_name = "{display}"
tier = {tier}
sprite = ExtResource("2_sprite")
tint = Color({tint[0]:.2f}, {tint[1]:.2f}, {tint[2]:.2f}, 1)
spawn_weight = {spawn_weight}
base_catch_difficulty = {difficulty}
drop_item = ExtResource("3_drop")
drop_amount_min = {drop_min}
drop_amount_max = {drop_max}
gold_base = {gold_base}
shiny_rate = {shiny:.4f}
flavor_text = "{flavor}"
"""
    path = MON_DIR / f"{monster_id}.tres"
    return content, path


# Nets: one per 3-tier band. The tier_required equals the lowest tier each
# net effectively hunts. Recipes consume tier-matching drops.
NET_BANDS = [
    ("wraith_net",     "Wraith Net",      "Pulls cinder-class targets too — useful through tier 6.",     4, [4, 5, 6],                1.6, 5),
    ("hedgewright_net","Hedgewright Net", "Bramble-tempered weave; works through tier 9.",               7, [4, 5, 6, 7, 8, 9],       2.0, 6),
    ("gleamwarp_net",  "Gleamwarp Net",   "Fine-mesh harvest gear for the fragile mid tiers.",          10, [7, 8, 9, 10, 11, 12],    2.6, 7),
    ("refrain_net",    "Refrain Net",     "Damps acoustic-class species. Strong through tier 15.",      13, [10, 11, 12, 13, 14, 15], 3.4, 8),
    ("vigil_net",      "Vigil Net",       "Long, patient sweeps for late-tier specimens.",              16, [13, 14, 15, 16, 17, 18], 4.4, 9),
    ("nadir_net",      "Nadir Net",       "Endgame mesh; pulls everything except the wisplets.",        19, [16, 17, 18, 19, 20],      5.6, 10),
]


def gen_net(net_id: str, display: str, desc: str, tier_required: int, tiers: list[int], cps: float, spawn_max: int) -> tuple[str, Path]:
    # Cost scales with tier_required, BigNumber dict.
    cost_int = round_int(110 * (6.5 ** (tier_required - 1)))
    e = len(str(cost_int)) - 1
    m = cost_int / (10 ** e)
    targets = ", ".join(str(t) for t in tiers)
    content = f"""[gd_resource type="Resource" script_class="NetResource" load_steps=2 format=3]

[ext_resource type="Script" path="res://game/resources/net_resource.gd" id="1_script"]

[resource]
script = ExtResource("1_script")
id = &"{net_id}"
display_name = "{display}"
description = "{desc}"
tier_required = {tier_required}
cost = {{"m": {m:.2f}, "e": {e}}}
catches_per_second = {cps}
catch_speed_multiplier = 1.0
spawn_max = {spawn_max}
targets_tiers = Array[int]({tiers})
"""
    path = NET_DIR / f"{net_id}.tres"
    return content, path


# Recipes for the new nets, gated by the previous tier's drop item count.
def gen_recipe(net_id: str, output_net_path: str, lower_tier: int, prev_recipe_id: str | None) -> tuple[str, Path]:
    recipe_id = f"recipe_{net_id}"
    drop_item_id = TIER_THEMES[lower_tier][4]   # tier_themes[t][4] is item_id
    needed = 50 + (lower_tier - 4) * 25
    gold_cost_int = round_int(110 * (6.5 ** (lower_tier - 2)))
    gold_e = len(str(gold_cost_int)) - 1
    gold_m = gold_cost_int / (10 ** gold_e)
    prereq = ""
    if prev_recipe_id:
        prereq = f'\nprereq_recipe_ids = Array[StringName]([&"{prev_recipe_id}"])'
    content = f"""[gd_resource type="Resource" script_class="CraftingRecipeResource" load_steps=3 format=3]

[ext_resource type="Script" path="res://game/resources/crafting_recipe_resource.gd" id="1_script"]
[ext_resource type="Resource" path="{output_net_path}" id="2_net"]

[resource]
script = ExtResource("1_script")
id = &"{recipe_id}"
display_name = "Craft {net_id.replace('_', ' ').title()}"
description = "Late-tier net, accessible after qualifying drops accumulate."
inputs = [{{"item_id": &"{drop_item_id}", "amount": {needed}}}]
output_net = ExtResource("2_net")
output_amount = 1
gold_cost = {{"m": {gold_m:.2f}, "e": {gold_e}}}
tier_required = {lower_tier}{prereq}
"""
    path = RECIPE_DIR / f"{recipe_id}.tres"
    return content, path


def main() -> int:
    written = 0
    # Items
    for tier in range(4, 21):
        c, p = gen_item(tier)
        write_file(p, c); written += 1
    # Monsters
    for tier in range(4, 21):
        for idx in range(3):
            c, p = gen_monster(tier, idx)
            write_file(p, c); written += 1
    # Nets
    prev_recipe = "recipe_tier3_net"
    for net_id, display, desc, tier_req, tiers, cps, spawn_max in NET_BANDS:
        c, p = gen_net(net_id, display, desc, tier_req, tiers, cps, spawn_max)
        write_file(p, c); written += 1
        # Recipe outputs this net.
        rc, rp = gen_recipe(net_id, str(p.relative_to(ROOT)).replace("\\", "/"), tier_req, prev_recipe)
        # Use res:// path in recipe.
        rc = rc.replace(str(p.relative_to(ROOT)).replace("\\", "/"), f"res://game/data/nets/{net_id}.tres")
        write_file(rp, rc); written += 1
        prev_recipe = f"recipe_{net_id}"
    print(f"Wrote {written} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
