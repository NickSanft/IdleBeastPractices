# IdleBeastPractices — Implementation Plan


This document is the authoritative implementation plan for the project. It is written as a handoff to an agentic coding assistant (Claude Code). Each phase has a goal, an explicit file inventory, schemas where relevant, and acceptance criteria. Phases must be completed in order; earlier phases establish abstractions that later phases depend on.

For the process, please look at the feedback_phase_workflow memory that is from GameMasterEncounterMapBuilder.

---

## 1. Project summary

An idle monster-catching game with three currency layers (items → Rancher Points → prestige), a pet auto-battler, a bestiary, monster-part crafting, and a grumpy in-world narrator. Targets: Android (primary), Windows, and Web. iOS planned for a later phase.

Design pillars:
- **Production-quality engineering** with versioned saves, big-number math, deterministic battle simulation, and a CI/CD pipeline that produces signed builds.
- **"Poorly made by its creator" comedic charm** layered over a fully functional game (carry-over from prior project), expressed primarily through the narrator (Peniber) and the Ledger.
- **Authoring-driven content scale**: 20 tiers of monsters/pets/nets must be addable by editing `.tres` files, not by writing code.

---

## 2. Tech stack (locked)

| Concern | Choice | Notes |
|---|---|---|
| Engine | Godot 4.x (latest stable at start of work) | Pin exact version in `project.godot` |
| Language | GDScript | C# only if a specific subsystem demands it; document in an ADR if so |
| UI | Godot Control nodes + custom theme | No third-party UI lib |
| Testing | GUT (Godot Unit Testing) | Headless CI runs |
| Big-number math | Custom mantissa/exponent `BigNumber` class | See §6.3 |
| Save format | Versioned JSON, migration chain | See §6.2 |
| CI/CD | GitHub Actions | Reuse pattern from prior project |
| Ads (Phase 6) | Poing Studios AdMob plugin | Rewarded video only |
| Cloud sync (Phase 7) | Google Play Games Services first, then Game Center | Backend-swappable from day one |

---

## 3. Repository layout

```
.
├── .github/workflows/         # CI/CD
├── docs/
│   ├── adr/                   # Architecture Decision Records (MADR format)
│   ├── peniber-voice.md       # Narrator voice guide + corpus seed
│   └── android-emulator.md    # Local emulator workflow
├── game/
│   ├── autoloads/             # Singletons (registered in project.godot)
│   ├── data/
│   │   ├── monsters/          # MonsterResource .tres files
│   │   ├── pets/              # PetResource .tres files
│   │   ├── nets/              # NetResource .tres files
│   │   ├── items/             # ItemResource .tres files
│   │   ├── upgrades/          # UpgradeResource .tres files
│   │   ├── recipes/           # CraftingRecipeResource .tres files
│   │   └── dialogue/          # DialogueLineResource .tres files
│   ├── systems/               # Pure logic, no scene deps
│   ├── scenes/
│   │   ├── main.tscn          # Root scene + tab navigation
│   │   ├── catching/          # Single-screen catch view
│   │   ├── battle/            # Pet auto-battler
│   │   ├── bestiary/
│   │   ├── crafting/
│   │   ├── prestige/
│   │   ├── ledger/            # Peniber's Ledger
│   │   └── ui/                # Reusable Control components
│   ├── resources/             # Resource class scripts (schemas)
│   ├── assets/
│   │   ├── sprites/           # Pixel art (placeholders initially)
│   │   ├── audio/
│   │   └── fonts/
│   └── tests/                 # GUT tests, mirrors systems/ layout
├── export_presets.cfg         # Checked in (no secrets)
├── project.godot
├── .gitignore
├── .gitattributes
└── README.md
```

**Naming conventions:**
- Files: `snake_case`
- Classes: `PascalCase`
- Constants: `SCREAMING_SNAKE_CASE`
- Resource IDs: `snake_case`, globally unique within their type (e.g. `green_wisplet`, `centiphantom_jelly`, `basic_net`)
- Signals: `past_tense_verb` (e.g. `monster_caught`, `tier_unlocked`)

---

## 4. Architecture

### 4.1 Autoloads (singletons)

Registered in `project.godot` in this order (load-order matters for dependencies):

| Autoload | Responsibility |
|---|---|
| `Settings` | User preferences (audio, accessibility). Loads first. |
| `EventBus` | Global signals. No state. |
| `SaveManager` | Serialize/deserialize `GameState`; backend-swappable interface. |
| `TimeManager` | Authoritative game time, offline duration calculation, anti-cheat clock checks. |
| `GameState` | Live in-memory game state. The save target. |
| `AudioManager` | SFX/music dispatch. Listens to `EventBus`. |
| `Narrator` | Peniber. Listens to `EventBus`, selects dialogue, displays UI. |

Autoloads communicate via `EventBus` signals where possible. Direct calls are allowed for state queries (`GameState.get_currency(...)`) but state mutations should flow through systems, which emit events.

### 4.2 Event bus catalog

These signals must be defined in `game/autoloads/event_bus.gd` in Phase 0, even if no emitter exists yet:

```gdscript
# Catching
signal monster_spawned(monster_id: String, instance_id: int)
signal monster_caught(monster_id: String, instance_id: int, is_shiny: bool, source: String) # source: "tap" | "net"
signal monster_despawned(monster_id: String, instance_id: int)
signal first_catch_of_species(monster_id: String)
signal first_shiny_caught(monster_id: String)

# Inventory & currency
signal item_gained(item_id: String, amount: int)
signal item_spent(item_id: String, amount: int)
signal currency_changed(currency_id: String, new_value) # new_value can be int or BigNumber
signal gold_milestone_reached(milestone: BigNumber)

# Progression
signal tier_unlocked(tier: int)
signal tier_completed(tier: int)
signal upgrade_purchased(upgrade_id: String)

# Pets & battle
signal pet_acquired(pet_id: String, is_variant: bool)
signal battle_started(battle_id: String)
signal battle_tick(battle_id: String, state: Dictionary)
signal battle_ended(battle_id: String, won: bool, rewards: Dictionary)
signal rancher_points_earned(amount: int, source: String)

# Prestige
signal prestige_available(rp_on_reset: int)
signal prestige_triggered(rp_gained: int, prestige_count: int)

# Crafting
signal recipe_unlocked(recipe_id: String)
signal item_crafted(recipe_id: String, output_item_id: String)

# Lifecycle
signal game_loaded()
signal game_saved()
signal offline_progress_calculated(summary: Dictionary)
signal idle_too_long(seconds: float)

# Narrator (drives Peniber UI)
signal narrator_line_chosen(line_id: String, text: String, mood: String)
```

### 4.3 Content as Resources

Every monster, pet, net, item, upgrade, recipe, and dialogue line is a `.tres` file. This is the single biggest lever for content scale and is non-negotiable.

Resource class scripts live in `game/resources/`. Examples below — implement these in Phase 0 even if only Tier 1 instances exist yet.

**`MonsterResource`** (`game/resources/monster_resource.gd`):
```gdscript
class_name MonsterResource extends Resource
@export var id: StringName
@export var display_name: String
@export var tier: int                          # 1..20
@export var sprite: Texture2D
@export var shiny_sprite: Texture2D            # Optional; tinted at runtime if null
@export var spawn_weight: float = 1.0
@export var base_catch_difficulty: float = 1.0 # Used as BigNumber base
@export var drop_item: ItemResource
@export var drop_amount_min: int = 1
@export var drop_amount_max: int = 1
@export var shiny_rate: float = 0.05
@export var pet: PetResource                   # Awarded on tier completion
@export var flavor_text: String                # Shown in bestiary
```

**`PetResource`** (`game/resources/pet_resource.gd`):
```gdscript
class_name PetResource extends Resource
@export var id: StringName
@export var display_name: String
@export var source_monster_id: StringName
@export var sprite: Texture2D
@export var variant_sprite: Texture2D          # Unique pet variant (separate from shiny)
@export var variant_rate: float = 0.02
@export var base_attack: float
@export var base_defense: float
@export var base_hp: float
@export var ability_id: StringName             # References an ability registry
```

**`NetResource`**, **`ItemResource`**, **`UpgradeResource`**, **`CraftingRecipeResource`**, **`DialogueLineResource`**: define analogously. Schemas detailed in §6.

### 4.4 Systems layer

`game/systems/` contains plain GDScript classes with **no scene or autoload dependencies**. They take `GameState` (or relevant slices) as input and return new state or events. This is what makes the game testable.

| System | Responsibility |
|---|---|
| `BigNumber` | Mantissa/exponent arithmetic. |
| `CatchingSystem` | Spawn schedule, catch resolution, drop calculation. |
| `OfflineProgressSystem` | Given delta seconds + state, compute earned items/currency. |
| `BattleSystem` | Deterministic auto-battle simulation given seed + teams. |
| `PrestigeSystem` | Compute RP gain on reset; perform reset preserving permanent upgrades. |
| `CraftingSystem` | Validate recipe, consume inputs, produce outputs. |
| `UpgradeEffectsSystem` | Aggregate active upgrade effects into multipliers. |

---

## 5. Save system

### 5.1 Format

Versioned JSON, written to `user://save.json` (Godot's per-user writable path). Atomic write: write to `save.json.tmp`, then rename.

```json
{
  "version": 1,
  "last_saved_unix": 1714492800,
  "session_id": "uuid-v4",
  "currencies": {
    "gold": {"m": 1.234, "e": 5},
    "rancher_points": 42
  },
  "inventory": {
    "wisplet_ectoplasm": 247,
    "centiphantom_jelly": 13
  },
  "monsters_caught": {
    "green_wisplet": {"normal": 247, "shiny": 3}
  },
  "pets_owned": ["green_wisplet_pet"],
  "pet_variants_owned": [],
  "nets_owned": ["basic_net"],
  "active_net": "basic_net",
  "upgrades_purchased": [],
  "current_max_tier": 2,
  "tiers_completed": [1],
  "current_battle": null,
  "prestige_count": 0,
  "ledger": {
    "total_catches": 247,
    "total_taps": 1500,
    "total_shinies": 3,
    "session_count": 12,
    "total_play_seconds": 3942,
    "total_offline_seconds_credited": 1800,
    "prestige_count": 0,
    "first_launch_unix": 1714400000,
    "peniber_quotes_seen": 47
  },
  "narrator_state": {
    "lines_seen": {"on_first_catch": 1, "on_milestone_100": 1},
    "last_line_unix": 1714492700
  }
}
```

### 5.2 Migration chain

`SaveManager` must implement:

```gdscript
const CURRENT_VERSION := 1

func load_save() -> Dictionary
func save(state: Dictionary) -> void

# Migrations are pure functions: Dictionary -> Dictionary, advancing version by 1.
# Registered in an ordered list. Loading runs all migrations from save.version up to CURRENT_VERSION.
func _migrate_v1_to_v2(data: Dictionary) -> Dictionary
```

Even with only v1, the migration chain framework must be in place from Phase 0. Add a unit test that fakes a v0 save and confirms migration runs without data loss.

### 5.3 Backend interface

```gdscript
class_name SaveBackend extends RefCounted
func read() -> String: return ""
func write(data: String) -> bool: return false
func exists() -> bool: return false
```

Implementations:
- `LocalFileBackend` — Phase 0
- `CloudBackend` — Phase 7 (Google Play Games Services / iCloud)

`SaveManager` holds a backend reference. Swap is one line.

---

## 6. Key technical specs

### 6.1 BigNumber

`game/systems/big_number.gd`:

```gdscript
class_name BigNumber extends RefCounted

var mantissa: float  # always normalized to 1.0 <= |m| < 10.0 (or 0.0)
var exponent: int

static func from_float(v: float) -> BigNumber
static func from_dict(d: Dictionary) -> BigNumber  # {"m": float, "e": int}
static func zero() -> BigNumber
static func one() -> BigNumber

func add(other: BigNumber) -> BigNumber
func subtract(other: BigNumber) -> BigNumber
func multiply(other: BigNumber) -> BigNumber
func multiply_float(f: float) -> BigNumber
func divide(other: BigNumber) -> BigNumber
func pow_int(n: int) -> BigNumber

func compare(other: BigNumber) -> int  # -1, 0, 1
func gte(other: BigNumber) -> bool
func lte(other: BigNumber) -> bool
func is_zero() -> bool

func to_dict() -> Dictionary
func format() -> String  # "1.23K", "4.56M", ..., then "1.23aa", "1.23ab" beyond decillion
```

Suffix scheme: `K, M, B, T, Qa, Qi, Sx, Sp, Oc, No, Dc`, then `aa, ab, ac, ...` (Antimatter Dimensions style). Document in code comment.

**Tests required (Phase 0):** addition with mixed exponents, multiplication overflow, comparison edge cases, round-trip via `to_dict`/`from_dict`, formatter output for representative values.

### 6.2 Offline progress

`OfflineProgressSystem.compute(state, elapsed_seconds)`:
- Cap `elapsed_seconds` at 3600 (1 hour).
- Compute catches per second from active net + upgrades.
- Distribute catches across currently spawnable monsters by spawn weight.
- Roll shinies probabilistically using expected count + variance (don't iterate per-catch — too slow at high rates).
- Return a summary `Dictionary` for the "Welcome back" UI: `{seconds, catches_by_species, items_gained, gold_gained, shinies_caught}`.

Anti-cheat: `TimeManager` records last save's wall-clock time. If on resume the device clock is *earlier* than the last save time, treat elapsed as 0 and log a warning. Don't punish the user — just don't credit time.

### 6.3 Battle system

Deterministic, seeded RNG. Same seed + same teams → identical battle outcome.

```gdscript
class_name BattleSystem extends RefCounted

# Pure simulation: returns full battle log; UI plays it back.
static func simulate(seed: int, player_team: Array[PetState], enemy_team: Array[MonsterState]) -> BattleLog
```

`BattleLog` is an array of frames `{tick, action, actor, target, damage, hp_remaining, status_changes}`. The UI reads frames at a configurable speed (Egg-Inc style: visible animations, but you can leave the screen and progress is the same on return because it's recomputed deterministically from seed).

**Tests:** same seed produces same log, different seeds produce different logs, edge cases (empty teams, instant KO, draw conditions).

---

## 7. Phases

Each phase ends with all acceptance criteria green and a tagged commit (`phase-N-complete`).

### Phase 0 — Foundation

**Goal:** an empty game runs on Windows, Web, and Android emulator. Save/load round-trips. BigNumber tests pass. CI builds all three.

**Files to create:**
- `project.godot` with autoloads registered (stubs OK)
- `.gitignore` (Godot defaults + `/exports/`, `/.godot/`)
- `.gitattributes` (LFS for `*.png`, `*.wav`, `*.ogg`)
- `.github/workflows/build.yml` (jobs: test, build-windows, build-web, build-android-debug)
- `.github/workflows/release.yml` (on tag: signed AAB, GitHub Release with artifacts)
- `README.md`
- `docs/adr/0001-engine-selection.md` … `0007-content-authoring.md` (MADR format)
- All autoload scripts in `game/autoloads/` (with the EventBus catalog from §4.2 fully populated; other autoloads can be stubs with TODOs)
- `game/resources/*.gd` for all resource schemas listed in §4.3
- `game/systems/big_number.gd` (full implementation)
- `game/systems/save_manager_helpers.gd` (migration framework)
- `game/scenes/main.tscn` with placeholder text "Critterancher"
- `game/tests/test_big_number.gd`
- `game/tests/test_save_migration.gd`
- `addons/gut/` (vendor GUT)

**Acceptance:**
- `godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://game/tests/` exits 0
- Windows export runs and shows the placeholder
- Web export runs in a browser
- Android debug APK installs on an emulator and launches
- Saving and loading round-trips a populated `GameState` correctly
- ADRs 1–7 written and committed

### Phase 1 — MVP catch loop

**Goal:** 20 minutes of fun. Single screen, three tiers, taps + nets, items accumulate, offline progress works.

**Content to author:**
- 3 tiers of monsters (Tier 1: green/red/blue wisplet; Tier 2: dust/dawn/dusk centiphantom; Tier 3: name TBD — pick 3 species)
- 1 item per species (wisplet_ectoplasm, centiphantom_jelly, etc.)
- 1 basic net (`basic_net`) purchasable with gold
- Gold drop curve seeded for the first three tiers

**Files:**
- `game/scenes/catching/catching_view.tscn` + `.gd` — single-screen monster spawner
- `game/scenes/catching/monster_instance.tscn` — animated sprite that wanders, can be tapped
- `game/scenes/ui/inventory_panel.tscn`
- `game/scenes/ui/currency_bar.tscn`
- `game/scenes/ui/net_shop.tscn`
- `game/scenes/ui/welcome_back_dialog.tscn`
- `game/systems/catching_system.gd`
- `game/systems/offline_progress_system.gd`
- `game/data/monsters/tier1_*.tres`, `tier2_*.tres`, `tier3_*.tres`
- `game/data/items/*.tres`
- `game/data/nets/basic_net.tres`
- `game/tests/test_catching_system.gd`
- `game/tests/test_offline_progress.gd`

**Acceptance:**
- Tapping a monster catches it, plays a satisfying SFX, increments inventory, awards gold
- Buying the basic net auto-catches monsters at a configurable rate
- Closing the game and reopening after >1 minute shows the welcome-back dialog with offline gains, capped at 1 hour
- All three tiers are reachable in a 20-minute play session

### Phase 2 — Pets and battles

**Goal:** complete a tier, get a pet, send it into auto-battle, earn Rancher Points, buy a permanent upgrade.

**Files:**
- `game/scenes/battle/battle_view.tscn` + `.gd` — Egg-Inc-style auto-battler
- `game/scenes/battle/team_select.tscn`
- `game/systems/battle_system.gd`
- `game/systems/upgrade_effects_system.gd`
- `game/data/pets/*.tres` (one per Tier 1 species)
- `game/data/upgrades/*.tres` (5 starter upgrades: catch speed, gold mult, drop mult, shiny rate, offline cap extender)
- `game/scenes/ui/upgrade_tree.tscn`
- `game/tests/test_battle_system.gd`
- `game/tests/test_upgrade_effects.gd`

**Acceptance:**
- Completing tier 1 awards a pet (`pet_acquired` fires)
- Battle screen plays a deterministic battle from a seed; leaving and returning shows correct end state
- Battle wins emit `rancher_points_earned`
- Upgrades persist across prestige (Phase 3 will validate this)

### Phase 3 — Prestige

**Goal:** reset progression for Rancher Points, multiplier-based progression bonuses persist.

**Files:**
- `game/scenes/prestige/prestige_view.tscn` + `.gd`
- `game/systems/prestige_system.gd`
- `game/data/upgrades/prestige_*.tres` (separate tree)
- `game/tests/test_prestige_system.gd`

**Acceptance:**
- Prestige preview shows projected RP gain
- Triggering prestige resets currencies, inventory, current tier, but preserves: upgrades, pets owned, bestiary entries, prestige count, ledger stats
- RP earned from prestige is additive to RP earned from battles

### Phase 4 — Bestiary, shinies, crafting

**Files:**
- `game/scenes/bestiary/bestiary_view.tscn` + `.gd`
- `game/scenes/crafting/crafting_view.tscn` + `.gd`
- `game/systems/crafting_system.gd`
- `game/data/recipes/*.tres` (5 starter recipes: 3 net upgrades, 2 pet equipment items)
- Shiny logic in `CatchingSystem`
- Pet variant logic in tier-completion reward flow
- `game/tests/test_crafting_system.gd`

**Acceptance:**
- Bestiary fills as species are caught; shows normal/shiny/variant slots per species
- ~5% of catches are shiny (configurable per species)
- Pet variants drop at their independent rate on tier completion
- Crafting consumes inputs and produces outputs

### Phase 5 — Peniber and polish

**Files:**
- `game/autoloads/narrator.gd` (full implementation)
- `game/scenes/ui/narrator_overlay.tscn` (Peniber's portrait + text bubble)
- `game/scenes/ledger/ledger_view.tscn` + `.gd`
- `game/data/dialogue/*.tres` (~150 lines, see §8)
- `docs/peniber-voice.md` (voice guide for future content)
- Visual polish pass: catch particles, screen shake, currency-gain numbers floating up, button satisfaction
- 20-tier monster/pet/net/item content seeded (placeholder sprites OK)
	- Sprite sheets for the first two creatures can be found in assets\sprites
- Difficulty curve balanced

**Acceptance:**
- Peniber comments on first catch of a species, every 100/1000/10000 catches, first shiny, tier completion, prestige, idle >5 min, returning after offline
- Ledger tab shows all statistics with Peniber's editorialized labels
- All 20 tiers reachable end-to-end (with grinding); no runtime errors

### Phase 6 — Android and ads

**Files:**
- `addons/admob/` (Poing Studios plugin)
- `game/autoloads/ads_manager.gd` (interface + AdMob impl)
- `.github/workflows/release.yml` updated for signed AAB
- `docs/android-emulator.md` (AVD setup, `adb install` workflow, signing key generation steps)
- Test ad unit IDs in dev builds; production IDs from CI secrets

**Ad placement (strict):**
- Rewarded video for: 2× offline catches (offered on the welcome-back dialog), instant-finish on a battle, double drops on next 10 catches
- All rewarded video is **fully optional**; no gameplay is gated behind ads
- No banners, no interstitials

**Acceptance:**
- Signed AAB builds in CI on tag push
- Rewarded video plays on a real Android device (not just emulator) and grants its reward exactly once per view
- Play Store internal track upload documented

### Phase 7 — Cloud sync (deferred but planned)

Implement `CloudBackend`, conflict resolution (last-write-wins with ledger merge), Play Games Services sign-in.

### Phase 8 — iOS (deferred)

Apple Developer enrollment, Game Center sync, App Store submission.

---

## 8. Peniber dialogue corpus seed

Voice: verbose, condescending, archaic, secretly invested. Full name `Peniber Perspicacious Similacrus, Agonothetes of the Sortilege Synod` appears once on first launch only.

Trigger taxonomy (each is a `DialogueLineResource` with `trigger_id`, `weight`, `max_uses`, `text`, `mood`, optional `conditions`):

| Trigger | Lines needed | Notes |
|---|---|---|
| `on_first_launch` | 1 | Introduces himself, full title |
| `on_first_catch_ever` | 1 | |
| `on_first_catch_of_species` | 20 | One per species, can be templated |
| `on_milestone_catches` | 12 | Milestones at 10/100/1000/10000 of any species |
| `on_first_shiny` | 1 | |
| `on_subsequent_shiny` | 5 | Pool, weighted random, max 1 use per session |
| `on_first_pet_acquired` | 1 | |
| `on_pet_acquired` | 5 | Pool |
| `on_first_battle_win` | 1 | |
| `on_battle_loss` | 8 | Rotating insults |
| `on_tier_completed` | 20 | One per tier |
| `on_first_prestige` | 1 | |
| `on_prestige` | 5 | Pool |
| `on_idle_too_long` | 10 | Triggered after 5 min no input |
| `on_offline_return_short` | 4 | <10 min |
| `on_offline_return_long` | 4 | >30 min |
| `on_first_net_purchase` | 1 | |
| `on_first_craft` | 1 | |
| `on_ledger_opened` | 6 | Pool |

Total ~106 lines for v1; pad to ~150 with bonus pool entries during Phase 5.

Selection algorithm: filter by trigger + conditions, exclude lines whose `max_uses` is reached, weighted-random pick from remainder. Maintain a "recently said" sliding window of length 5 to avoid clustering.

---

## 9. CI/CD specifics

`.github/workflows/build.yml`:
- Trigger: push to `main`, PRs
- Jobs:
  - `test` — Ubuntu, Godot headless, run GUT
  - `build-windows` — export Windows
  - `build-web` — export HTML5
  - `build-android-debug` — export unsigned debug APK
- Artifacts uploaded to workflow run

`.github/workflows/release.yml`:
- Trigger: tag matching `v*`
- Jobs above + `build-android-release` (signed AAB using keystore secrets)
- Creates a GitHub Release with all artifacts attached

**Required secrets:**
- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `ADMOB_APP_ID` (Phase 6)
- `ADMOB_REWARDED_UNIT_ID` (Phase 6)

Document keystore generation in `docs/android-emulator.md`.

---

## 10. Testing strategy

- **Unit tests (GUT)** for everything in `game/systems/`. Target ≥80% coverage on systems.
- **Smoke tests** for each scene: instantiate, verify no errors on `_ready()`.
- **Save migration tests:** for each schema version, a fixture old-version save and an assertion the migrated result matches the expected new shape.
- **Battle determinism test:** same seed + same teams produces byte-identical `BattleLog`.

CI fails if any test fails or if coverage drops below threshold (set threshold in Phase 1 once a baseline exists).

---

## 11. Definition of done (per phase)

A phase is done when:
1. All listed files exist and are non-stubs
2. All acceptance criteria are demonstrable
3. All tests pass in CI
4. Builds succeed for Windows, Web, and Android
5. Relevant ADRs are written or updated
6. The commit is tagged `phase-N-complete`

---

## 12. Risks and mitigations

| Risk | Mitigation |
|---|---|
| BigNumber bugs cause silent currency corruption | Comprehensive unit tests Phase 0; property-based tests for arithmetic identities |
| Save format changes break players | Migration framework mandatory from Phase 0; v1 of save format is locked once Phase 1 ships |
| Battle simulation drift between sessions | Deterministic seeded RNG; `BattleLog` is the source of truth, UI is replay only |
| Offline progress exploited via clock manipulation | Anti-cheat clock check in `TimeManager`; cap is short (1hr) so payoff is low anyway |
| Android signing keys leak | Keystore in GitHub Secrets only, never in repo; `.gitignore` blocks `*.keystore` |
| Content scaling pain at 20 tiers | Resource-driven from day one; a content-authoring smoke test that fails if a `.tres` is missing required fields |
| Peniber's tone drifts as more lines are written | `docs/peniber-voice.md` voice guide with sample lines as ground truth |

---

## 13. Out of scope (do not build)

- Multiplayer, leaderboards, friends lists
- IAP / shop with real currency
- Push notifications
- User accounts (cloud sync uses platform identity)
- Localization beyond English (string table is structured for it; translation deferred)
- Achievements (Phase 7 candidate, not before)

---

## 14. First commands for Claude Code

When starting Phase 0:

1. Initialize the repo with the layout from §3.
2. Pin the Godot version in `project.godot` and add a `README.md` line stating the version.
3. Vendor GUT into `addons/gut/`.
4. Implement `BigNumber` and its tests **first** — everything else depends on it.
5. Implement `SaveManager` with `LocalFileBackend` and the migration framework.
6. Wire all autoloads with the full `EventBus` signal catalog from §4.2.
7. Stand up the GitHub Actions workflows.
8. Write ADRs 1–7.
9. Tag `phase-0-complete`.

Do not begin Phase 1 until Phase 0's acceptance criteria are all green in CI.