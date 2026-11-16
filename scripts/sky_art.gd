class_name SkyArt
extends Control
## Sun, moon and stars behind everything. The sun rises at dawn and sets at dusk along an arc;
## the moon takes the other half of the day; stars fade in at night and twinkle.

var main: Node

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if main == null or main.weather == null:
		return
	var w: Weather = main.weather
	var vs := get_viewport_rect().size
	var n := w.night_amount()
	var clear := 1.0 - w.cloud * 0.85
	# Stars
	if n > 0.05:
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		for k in 90:
			var p := Vector2(rng.randf() * vs.x, rng.randf() * vs.y * 0.65)
			var tw := 0.6 + 0.4 * sin(WeatherState.clock * rng.randf_range(1.0, 3.0) + k)
			draw_rect(Rect2(p, Vector2(1, 1) * (1.0 if k % 7 else 2.0)), Color(1, 1, 1, n * tw * clear))
	# Sun: up from 0.25 to 0.75. Moon: the other half.
	var t := w.time_of_day
	for body in [["sun", (t - 0.25) / 0.5], ["moon", fmod(t + 0.25, 1.0) / 0.5]]:
		var u: float = body[1]
		if u < 0.0 or u > 1.0:
			continue
		var p := Vector2(lerpf(vs.x * 0.08, vs.x * 0.92, u), vs.y * 0.62 - sin(u * PI) * vs.y * 0.5)
		if body[0] == "sun":
			var warm := Color("#fff3b0").lerp(Color("#ffb070"), 1.0 - sin(u * PI))
			draw_circle(p, 26, Color(warm, 0.15 * clear))
			draw_circle(p, 16, Color(warm, 0.35 * clear))
			draw_circle(p, 11, Color(warm, clear))
		else:
			draw_circle(p, 18, Color(0.85, 0.9, 1.0, 0.12 * clear))
			draw_circle(p, 9, Color(0.92, 0.94, 1.0, clear))
			draw_circle(p + Vector2(3, -2), 7.5, Color(0.92, 0.94, 1.0, 0.0))
			draw_circle(p + Vector2(-3, -2), 1.5, Color(0.75, 0.78, 0.85, clear))
			draw_circle(p + Vector2(2, 3), 2.0, Color(0.75, 0.78, 0.85, clear))
