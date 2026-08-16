#!/usr/bin/env python3
"""
Phase 15a pet-progression generator. Authors one PetResource .tres per
monster species for tiers 2-20 and wires the `pet` reference into each
source monster .tres. Idempotent — re-running overwrites the pet files
and re-patches the monsters (an already-patched monster is left alone).

Why this exists
---------------
Before Phase 15a the game shipped 60 monsters across 20 tiers but only
THREE pets, all tier 1. Because BattleSystem derives enemy stats from
tier (hp 20t+10, atk 4t+4, def 2t) and damage is a flat
`max(1, atk - def)`, a tier-1 pet (atk 9-16) cannot scratch a tier-20
enemy (def 40). scripts/generate_battle_stages.py records the
consequence: "tier 7+ is unwinnable in ANY shape - the band ends; more
stages need pet progression first."

Curve
-----
Stats mirror tier 1's ratios against the enemy curve so every tier plays
like tier 1 did rather than drifting easier or harder:

    base_attack(t)  = 8.667t + 3.333   # ~3 hits to drop a same-tier enemy
    base_defense(t) = 2.5t   + 3.5     # incoming hit stays ~3% of pet HP
    base_hp(t)      = 50t    + 12

Each tier's three species take the tier-1 role spread, keyed by
spawn_weight descending (1.0 / 0.85 / 0.70), which on tier 1 was
green=mid, red=glass, blue=tank:

    index 0 (weight 1.00) -> mid    atk x0.973  def x0.947  hp x0.973
    index 1 (weight 0.85) -> glass  atk x1.297  def x0.632  hp x0.811
    index 2 (weight 0.70) -> tank   atk x0.730  def x1.421  hp x1.216

Abilities rotate through the full 8-entry AbilityRegistry pool so every
ability sees play. The rotation is phased so that t=1 reproduces the
hand-authored tier-1 assignment exactly (heal / smite / shield), which
is the regression check that the formula matches shipped content.

Usage:
    python scripts/generate_pets.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MON_DIR = ROOT / "game" / "data" / "monsters"
PET_DIR = ROOT / "game" / "data" / "pets"

# Tiers 1 is hand-authored and must not be regenerated; it is the
# reference the curve is fitted to.
FIRST_GENERATED_TIER = 2
LAST_TIER = 20

VARIANT_RATE = 0.02

# Role spread, derived from tier 1 (avg atk 12.33 / def 6.33 / hp 61.67).
ROLES = (
    # (name, atk_mult, def_mult, hp_mult)
    ("mid",   0.973, 0.947, 0.973),
    ("glass", 1.297, 0.632, 0.811),
    ("tank",  0.730, 1.421, 1.216),
)

# Ability rotation per role. Phased so tier 1 -> (heal, smite, shield),
# matching the hand-authored tier-1 pets.
ROLE_ABILITIES = {
    "mid":   ("heal", "cleanse", "strike", "burst"),
    "glass": ("smite", "rend", "burst", "strike"),
    "tank":  ("shield", "taunt"),
}


def base_attack(tier: int) -> float:
    return 8.667 * tier + 3.333


def base_defense(tier: int) -> float:
    return 2.5 * tier + 3.5


def base_hp(tier: int) -> float:
    return 50.0 * tier + 12.0


def ability_for(role: str, tier: int) -> str:
    pool = ROLE_ABILITIES[role]
    return pool[(tier - 1) % len(pool)]


def _write(path: Path, text: str) -> None:
    """LF endings regardless of host OS — the .tres files are LF in git, and
    Python's default text mode would rewrite every one of them as CRLF."""
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def parse_monster(path: Path) -> dict:
    """Pull the fields we need out of a MonsterResource .tres."""
    text = path.read_text(encoding="utf-8")

    def scalar(field, pattern=r'(.+)'):
        m = re.search(r'^%s = %s$' % (re.escape(field), pattern), text, re.M)
        return m.group(1).strip() if m else None

    mid = scalar("id", r'&"(.+)"')
    if mid is None:
        return {}
    tier_raw = scalar("tier", r'(\d+)')
    display = scalar("display_name", r'"(.*)"')
    weight_raw = scalar("spawn_weight", r'([0-9.]+)')
    tint = scalar("tint", r'(Color\(.*\))') or "Color(1, 1, 1, 1)"

    # The sprite is an ExtResource; resolve its id back to a path.
    sprite_path = None
    sprite_ref = scalar("sprite", r'ExtResource\("(.+)"\)')
    if sprite_ref:
        m = re.search(
            r'^\[ext_resource type="Texture2D" path="([^"]+)" id="%s"\]$'
            % re.escape(sprite_ref), text, re.M)
        if m:
            sprite_path = m.group(1)

    return {
        "path": path,
        "text": text,
        "id": mid,
        "display_name": display or mid.replace("_", " ").title(),
        "tier": int(tier_raw) if tier_raw else 1,
        "spawn_weight": float(weight_raw) if weight_raw else 1.0,
        "tint": tint,
        "sprite_path": sprite_path,
        "has_pet": re.search(r'^pet = ExtResource', text, re.M) is not None,
    }


def pet_tres(mon: dict, role: str, atk: float, dfn: float, hp: float,
             ability: str) -> str:
    lines = [
        '[gd_resource type="Resource" script_class="PetResource" '
        'load_steps=3 format=3]',
        '',
        '[ext_resource type="Script" '
        'path="res://game/resources/pet_resource.gd" id="1_script"]',
        '[ext_resource type="Texture2D" path="%s" id="2_sprite"]'
        % mon["sprite_path"],
        '',
        '[resource]',
        'script = ExtResource("1_script")',
        'id = &"%s_pet"' % mon["id"],
        'display_name = "%s"' % mon["display_name"],
        'source_monster_id = &"%s"' % mon["id"],
        'sprite = ExtResource("2_sprite")',
        'tint = %s' % mon["tint"],
        'variant_rate = %s' % VARIANT_RATE,
        'base_attack = %.1f' % atk,
        'base_defense = %.1f' % dfn,
        'base_hp = %.1f' % hp,
        'ability_id = &"%s"' % ability,
        '',
    ]
    return "\n".join(lines)


def patch_monster(mon: dict) -> str:
    """Add the pet ext_resource + `pet =` assignment to a monster .tres."""
    text = mon["text"]
    if mon["has_pet"]:
        return text

    # Next free ext_resource id number.
    used = [int(m) for m in re.findall(r'id="(\d+)_', text)]
    next_id = (max(used) + 1) if used else 1
    ref = '%d_pet' % next_id

    # load_steps = number of ext_resources + 1.
    n_ext = len(re.findall(r'^\[ext_resource ', text, re.M))
    text = re.sub(r'load_steps=\d+', 'load_steps=%d' % (n_ext + 2), text, count=1)

    ext_line = ('[ext_resource type="Resource" '
                'path="res://game/data/pets/%s_pet.tres" id="%s"]'
                % (mon["id"], ref))
    # Insert after the last ext_resource line.
    ext_lines = list(re.finditer(r'^\[ext_resource .*\]$', text, re.M))
    last = ext_lines[-1]
    text = text[:last.end()] + "\n" + ext_line + text[last.end():]

    # Mirror tier 1's field order: `pet` goes right after `drop_item`
    # when present, else before drop_amount_min, else at block end.
    assign = 'pet = ExtResource("%s")' % ref
    if re.search(r'^drop_item = .*$', text, re.M):
        text = re.sub(r'^(drop_item = .*)$', r'\1\n' + assign, text,
                      count=1, flags=re.M)
    elif re.search(r'^drop_amount_min = .*$', text, re.M):
        text = re.sub(r'^(drop_amount_min = .*)$', assign + r'\n\1', text,
                      count=1, flags=re.M)
    else:
        text = text.rstrip("\n") + "\n" + assign + "\n"
    return text


def main() -> int:
    monsters = []
    for p in sorted(MON_DIR.glob("*.tres")):
        m = parse_monster(p)
        if m:
            monsters.append(m)
    if not monsters:
        print("no monsters parsed - wrong directory?", file=sys.stderr)
        return 1

    by_tier = {}
    for m in monsters:
        by_tier.setdefault(m["tier"], []).append(m)

    written = 0
    patched = 0
    for tier in range(FIRST_GENERATED_TIER, LAST_TIER + 1):
        group = by_tier.get(tier, [])
        if not group:
            print("  tier %2d: no monsters, skipping" % tier)
            continue
        # Species order: spawn_weight descending, id as deterministic
        # tie-break. Mirrors tier 1 (1.0 mid / 0.85 glass / 0.70 tank).
        group.sort(key=lambda m: (-m["spawn_weight"], m["id"]))
        for idx, mon in enumerate(group):
            role, am, dm, hm = ROLES[min(idx, len(ROLES) - 1)]
            if not mon["sprite_path"]:
                print("  ! %s has no resolvable sprite, skipping"
                      % mon["id"], file=sys.stderr)
                continue
            ability = ability_for(role, tier)
            atk = base_attack(tier) * am
            dfn = base_defense(tier) * dm
            hp = base_hp(tier) * hm

            out = PET_DIR / ("%s_pet.tres" % mon["id"])
            _write(out, pet_tres(mon, role, atk, dfn, hp, ability))
            written += 1

            new_text = patch_monster(mon)
            if new_text != mon["text"]:
                _write(mon["path"], new_text)
                patched += 1
        print("  tier %2d: %d pets (%s)"
              % (tier, len(group), ", ".join(m["id"] for m in group)))

    print("\nwrote %d pet .tres, patched %d monster .tres" % (written, patched))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
