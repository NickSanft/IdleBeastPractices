## Floating "+12 g" feedback that tweens up and fades on every catch.
##
## Self-frees when the tween completes. The catching view spawns one of these
## per catch, parented near the monster's position.
extends Label

const _DRIFT_PIXELS := 56.0
const _DURATION := 1.0


func _ready() -> void:
	# Defaults; the spawner overrides text/modulate.
	add_theme_font_size_override("font_size", 18)
	z_index = 50
	pivot_offset = size * 0.5
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - _DRIFT_PIXELS, _DURATION)
	tween.tween_property(self, "modulate:a", 0.0, _DURATION).set_delay(_DURATION * 0.4)
	tween.chain().tween_callback(queue_free)


## Configures the visual based on the gold amount and shiny flag, then
## returns self for fluent setup at the call site.
func configure(gold_text: String, is_shiny: bool) -> Label:
	text = "+" + gold_text + " g"
	if is_shiny:
		text = "✨ " + text
		modulate = Color(1.0, 0.95, 0.55)
		add_theme_font_size_override("font_size", 22)
	else:
		modulate = Color(1.0, 0.86, 0.4)
	return self
