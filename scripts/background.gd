extends Node2D
## Placeholder parallax hills. Lives inside a Parallax2D.

@export var color := Color("#9fd18b")
@export var height := 80.0
@export var seed_offset := 0.0
@export var width := 2400.0
@export var kind := "hills"

func _draw() -> void:
	if kind == "clouds":
		_draw_clouds()
		return
	var pts := PackedVector2Array()
	pts.append(Vector2(-200, 400))
	var x := -200.0
	while x <= width:
		var y := 300.0 - height * (0.55 + 0.45 * sin(x * 0.006 + seed_offset) * cos(x * 0.0023 + seed_offset * 2.0))
		pts.append(Vector2(x, y))
		x += 16.0
	pts.append(Vector2(width, 400))
	draw_colored_polygon(pts, color)

func _draw_clouds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 14:
		var c := Vector2(rng.randf_range(-100, 1400), rng.randf_range(30, 170))
		var w := rng.randf_range(30, 70)
		var col := Color(1, 1, 1, rng.randf_range(0.6, 0.9))
		draw_rect(Rect2(c.x - w / 2.0, c.y, w, 8), col)
		draw_rect(Rect2(c.x - w / 3.0, c.y - 6, w * 0.5, 6), col)
		draw_rect(Rect2(c.x - w / 8.0, c.y - 10, w * 0.3, 4), col)
