class_name Fx
extends Node2D
## Short-lived visual effects drawn in code: lightning arcs and bursts.

var kind := ""
var points := PackedVector2Array()
var radius := 0.0
var color := Color.WHITE
var life := 0.25
var _t := 0.0

static func lightning(parent: Node, from: Vector2, to: Vector2, col: Color) -> Fx:
	var fx := Fx.new()
	fx.kind = "lightning"
	fx.color = col
	fx.life = 0.22
	var pts := PackedVector2Array([from])
	var steps := 6
	for i in range(1, steps):
		var p := from.lerp(to, float(i) / steps)
		pts.append(p + Vector2(randf_range(-4, 4), randf_range(-7, 7)))
	pts.append(to)
	fx.points = pts
	fx.z_index = 60
	parent.add_child(fx)
	return fx

static func burst(parent: Node, at: Vector2, r: float, col: Color) -> Fx:
	var fx := Fx.new()
	fx.kind = "burst"
	fx.position = at
	fx.radius = r
	fx.color = col
	fx.life = 0.3
	fx.z_index = 55
	parent.add_child(fx)
	return fx

func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var a := 1.0 - _t / life
	match kind:
		"lightning":
			draw_polyline(points, Color(color, a), 2.0)
			draw_polyline(points, Color(1, 1, 1, a * 0.8), 1.0)
		"burst":
			var r := radius * (0.4 + 0.6 * _t / life)
			draw_circle(Vector2.ZERO, r, Color(color, 0.25 * a))
			draw_arc(Vector2.ZERO, r, 0, TAU, 24, Color(color, a), 2.0)
