## Phase 14 — Dusk pixel-RPG palette tokens.
##
## Source of truth: `docs/design_handoff_theming/reference_files/styles.css`
## (the README's Design Tokens table mirrors these exactly). Three named
## palettes — Amethyst (default), Twilight Teal, Embered Plum — each
## emit the same 17 token slots so theme code can ask for `.gold` /
## `.card` / etc. without conditional branches per palette.
##
## Used by:
##   - `assets/themes/dusk/amethyst.tres`, `twilight.tres`, `ember.tres`
##     (theme construction reads these via `palette()`)
##   - Future view code that needs runtime palette switches (e.g. a
##     "Theme" picker in Settings) — `Settings.theme_id` would key into
##     `Palette.by_id()`.
##
## Keep names + values aligned with the CSS variables. If you bump a
## hex value here, also bump it in styles.css and the README's Design
## Tokens table so the handoff docs stay accurate.
class_name PaletteDusk
extends RefCounted


enum Id { AMETHYST, TWILIGHT, EMBER }


## Returns the full palette dict for a given Id. Keys mirror the CSS
## variable names (with hyphen → underscore). Every palette returns
## the same set of keys so callers can index without checking.
static func palette(p_id: int) -> Dictionary:
	match p_id:
		Id.TWILIGHT: return _twilight()
		Id.EMBER: return _ember()
	return _amethyst()


## Returns the default Amethyst palette. Equivalent to `palette(Id.AMETHYST)`.
static func amethyst() -> Dictionary:
	return _amethyst()


static func twilight() -> Dictionary:
	return _twilight()


static func ember() -> Dictionary:
	return _ember()


## Lookup by string id ("amethyst" / "twilight" / "ember"). Used by
## the future Settings.theme_id persistence path. Falls back to
## Amethyst on unknown id.
static func by_id(id_str: String) -> Dictionary:
	match id_str:
		"twilight": return _twilight()
		"ember": return _ember()
	return _amethyst()


## Phase 14f — returns the palette dict matching the currently-active
## Dusk variant (`Settings.theme_id`). New code should prefer
## `PaletteDusk.active()` over `PaletteDusk.amethyst()` so a theme
## switch in Settings actually swaps the inline color overrides at
## runtime. Existing code that hardcodes `amethyst()` will continue to
## render Amethyst-colored highlights regardless of theme_id — those
## sites migrate to `.active()` as scenes are touched in 14f / 14g.
static func active() -> Dictionary:
	# Defensive: Settings is an autoload + always available in-game,
	# but unit tests / one-off SceneTree runs may instantiate a
	# PaletteDusk before autoloads are registered. Fall back to
	# Amethyst (the default theme_id) in that case.
	if not Engine.has_singleton("Settings") and not _settings_is_loaded():
		return _amethyst()
	var id: String = Settings.theme_id if _settings_is_loaded() else "amethyst"
	return by_id(id)


## Detect whether the `Settings` autoload is actually attached to the
## scene tree. `Engine.has_singleton` would only return true for
## native singletons; for GDScript autoloads we check the root via
## `_settings_is_loaded`. Wrapped so the editor-time tooling that
## reads palette tokens at .tres-build time doesn't crash.
static func _settings_is_loaded() -> bool:
	var root := Engine.get_main_loop()
	if root == null:
		return false
	if not (root is SceneTree):
		return false
	var st: SceneTree = root
	return st.root.has_node("Settings")


# region — palette definitions

static func _amethyst() -> Dictionary:
	# Tokens copied verbatim from styles.css ":root". Hex values from
	# the README's Design Tokens table; either can be edited but they
	# must stay in sync.
	return {
		"bg_deep":     Color("#0c0820"),
		"bg":          Color("#15102e"),
		"bg_2":        Color("#1d1640"),
		"card":        Color("#251b52"),
		"card_2":      Color("#2f2364"),
		"border":      Color("#4a3a8a"),
		"border_soft": Color("#3a2d6f"),
		"ink":         Color("#ece4ff"),
		"ink_dim":     Color("#b6a8de"),
		"ink_mute":    Color("#8576b6"),
		"gold":        Color("#f5c46b"),
		"gold_dark":   Color("#b8862e"),
		"teal":        Color("#5fd3c2"),
		"teal_dark":   Color("#2e8a82"),
		"magenta":     Color("#d96fb8"),
		"rose":        Color("#ef6f8a"),
		"danger":      Color("#ff6b6b"),
		"bezel":       Color("#0a0617"),
	}


static func _twilight() -> Dictionary:
	# Twilight overrides Amethyst's cool-purple base with deep teal.
	# Tokens NOT specified in the README's Twilight section inherit
	# from Amethyst — we copy them through so a Theme built from
	# `twilight()` doesn't have any null colors.
	var p := _amethyst()
	p["bg_deep"]     = Color("#061518")
	p["bg"]          = Color("#0a2024")
	p["bg_2"]        = Color("#0f2c32")
	p["card"]        = Color("#143a40")
	p["card_2"]      = Color("#1a4a52")
	p["border"]      = Color("#2e7a82")
	p["border_soft"] = Color("#1f5a62")
	p["ink"]         = Color("#e0f7f4")
	p["ink_dim"]     = Color("#94d0c8")
	p["ink_mute"]    = Color("#5e8c87")
	p["gold"]        = Color("#f0b95a")
	p["magenta"]     = Color("#ff89a8")
	# teal stays the same in this palette.
	return p


static func _ember() -> Dictionary:
	# Ember swaps in a warm rose/plum base with the same gold accent
	# moved slightly more orange.
	var p := _amethyst()
	p["bg_deep"]     = Color("#1a0814")
	p["bg"]          = Color("#2a1020")
	p["bg_2"]        = Color("#381a2c")
	p["card"]        = Color("#4a2238")
	p["card_2"]      = Color("#5e2d48")
	p["border"]      = Color("#8a3f6a")
	p["border_soft"] = Color("#6e3354")
	p["ink"]         = Color("#ffe8f4")
	p["ink_dim"]     = Color("#e0a8c8")
	p["ink_mute"]    = Color("#a07590")
	p["gold"]        = Color("#ffb84d")
	p["magenta"]     = Color("#ff7090")
	return p

# endregion


## Convenience: shadow color used by every "chunky pixel-UI" drop —
## styles.css uses `0 4px 0 0 #00000080` (50% black, 4-px offset).
## Theme construction pulls this through StyleBoxFlat.shadow_color.
static func shadow_color() -> Color:
	# #00000080 = rgba(0, 0, 0, 0.5)
	return Color(0.0, 0.0, 0.0, 0.5)


## The inset 2-px black border each pixel-card carries on top of the
## visible border. styles.css: `inset 0 0 0 2px rgba(0,0,0,0.35)`.
static func inset_shadow_color() -> Color:
	return Color(0.0, 0.0, 0.0, 0.35)
