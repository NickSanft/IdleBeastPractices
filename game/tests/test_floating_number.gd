## Smoke tests for the FloatingNumber feedback popup.
extends GutTest

const _SCENE := preload("res://game/scenes/ui/floating_number.tscn")


func test_instantiates_and_configures() -> void:
	var label: Label = _SCENE.instantiate()
	add_child_autofree(label)
	var configured: Variant = label.call("configure", "1.23K", false)
	assert_eq(configured, label, "configure should return self for chaining")
	assert_eq(label.text, "+1.23K g")


func test_shiny_variant_prepends_sparkle() -> void:
	var label: Label = _SCENE.instantiate()
	add_child_autofree(label)
	label.call("configure", "5", true)
	assert_true(String(label.text).contains("✨"))
	assert_true(String(label.text).contains("+5 g"))


func test_drift_tween_fires_on_ready() -> void:
	# Just verifies that adding to the tree runs _ready and starts a tween
	# without erroring. Self-frees on tween completion; nothing to assert
	# beyond no-crash + the configure call working.
	var label: Label = _SCENE.instantiate()
	add_child_autofree(label)
	await wait_frames(1)
	# After 1 frame the tween has started; modulate.a should still be 1
	# (delay before fade is 40% of duration).
	assert_almost_eq(label.modulate.a, 1.0, 1.0e-6)
