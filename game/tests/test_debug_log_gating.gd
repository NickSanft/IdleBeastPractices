## v0.15.9 — guards against per-tap/per-catch debug logging shipping in
## release builds again.
##
## `catching_view.gd` and `monster_instance.gd` each declare a `_DEBUG_LOG`
## flag that gates `print()` calls on every tap / catch / despawn. Both
## shipped as an unconditional `const _DEBUG_LOG := true`, so release
## (Play Store) builds spammed the console on the hottest path in the
## game. The fix gates the flag on `OS.is_debug_build()` so it stays a
## dev aid in the editor + debug exports but is silent in release.
##
## A value-level assertion can't catch a regression here: GUT runs in a
## debug build, so `OS.is_debug_build()` is true and a hardcoded `true`
## would compare equal. Instead we lint the source text — the same
## approach test_visual_regression uses for the legacy-theme sweep.
extends GutTest

const _GATED_FILES: Array[String] = [
	"res://game/scenes/catching/catching_view.gd",
	"res://game/scenes/catching/monster_instance.gd",
]


func _debug_log_decl_line(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "%s must be readable" % path)
	var found: String = ""
	while not f.eof_reached():
		var line: String = f.get_line()
		var stripped: String = line.strip_edges()
		# The DECLARATION line, not the `if _DEBUG_LOG:` usage sites.
		if stripped.contains("_DEBUG_LOG :=") or stripped.contains("_DEBUG_LOG="):
			found = stripped
			break
	f.close()
	return found


func test_debug_log_is_build_gated_not_hardcoded() -> void:
	for path in _GATED_FILES:
		var decl: String = _debug_log_decl_line(path)
		assert_ne(decl, "", "%s must declare a _DEBUG_LOG flag" % path)
		assert_true(decl.contains("OS.is_debug_build()"),
			"%s must gate _DEBUG_LOG on OS.is_debug_build() so release builds stay silent — got: %s" % [path, decl])
		# Belt-and-braces: an unconditional `:= true` must never come back.
		assert_false(decl.contains(":= true"),
			"%s must NOT hardcode `_DEBUG_LOG := true` (per-tap console spam in release) — got: %s" % [path, decl])
