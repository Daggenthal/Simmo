class_name Fx
extends Node2D
## Short-lived visual effects drawn in code: lightning arcs and bursts.

var kind := ""
var points := PackedVector2Array()
var radius := 0.0
var color := Color.WHITE
var life := 0.25
var _t := 0.0
var front := true      # warp: which half of the rings this layer draws
var inbound := false   # warp: arriving (fade rings out) or leaving (build up)

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
	# Light along the bolt: it lights its whole path for a moment.
	for k in [0.15, 0.5, 0.85]:
		Lighting.flash(parent, from.lerp(to, k), col.lightened(0.3), 90.0, 1.4, 0.25, k == 0.5)
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
	Lighting.flash(parent, at, col, r * 2.2 + 30.0, 1.1, 0.3)
	return fx

## A fading cone from `at` toward `dir` (Arcane Cataclysm's blast).
static func cone(parent: Node, at: Vector2, dir: Vector2, length: float, half_angle: float, col: Color) -> Fx:
	var fx := Fx.new()
	fx.kind = "cone"
	fx.color = col
	fx.life = 0.45
	fx.position = at
	var pts := PackedVector2Array([Vector2.ZERO])
	for k in 9:
		pts.append(dir.rotated(lerpf(-half_angle, half_angle, k / 8.0)) * length)
	fx.points = pts
	fx.z_index = 55
	parent.add_child(fx)
	return fx

## A dark see-through copy of an actor left behind by a blink (Shadow Dance).
static func afterimage(parent: Node, at: Vector2, col: Color) -> Fx:
	var fx := Fx.new()
	fx.kind = "afterimage"
	fx.color = col
	fx.life = 0.35
	fx.position = at
	fx.z_index = 4
	parent.add_child(fx)
	return fx

## Zone warp around an actor (.hack style): glowing rings slide up and down the body
## inside a column of light. Two layers so the rings wrap around: one behind, one in front.
static func warp(actor: Node2D, duration: float, arriving: bool, col: Color) -> void:
	for is_front in [false, true]:
		var fx := Fx.new()
		fx.kind = "warp"
		fx.color = col
		fx.life = duration
		fx.front = is_front
		fx.inbound = arriving
		fx.show_behind_parent = not is_front
		actor.add_child(fx)
	var l := Lighting.add(actor, col, 80.0, 0.0)
	if l:
		l.position = Vector2(0, -14)
		var tw := l.create_tween()
		tw.tween_property(l, "energy", 1.2, duration * 0.5)
		tw.tween_property(l, "energy", 0.0, duration * 0.5)
		tw.tween_callback(l.queue_free)

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
		"warp":
			_draw_warp()
		"cone":
			draw_colored_polygon(points, Color(color, 0.35 * a))
			draw_polyline(points + PackedVector2Array([points[0]]), Color(color.lightened(0.3), a), 2.0)
		"afterimage":
			draw_rect(Rect2(-6, -24, 12, 24), Color(color, 0.5 * a))
			draw_circle(Vector2(0, -18), 6.5, Color(color, 0.5 * a))
		"burst":
			var r := radius * (0.4 + 0.6 * _t / life)
			draw_circle(Vector2.ZERO, r, Color(color, 0.25 * a))
			draw_arc(Vector2.ZERO, r, 0, TAU, 24, Color(color, a), 2.0)

func _draw_warp() -> void:
	var t := _t / life
	# Strength: builds up while leaving, dies down while arriving.
	var k := (t if not inbound else 1.0 - t)
	var glow := clampf(k * 1.4, 0.0, 1.0)
	if not inbound and t > 0.85:
		glow *= (1.0 - t) / 0.15 * 0.5 + 0.5
	var col := color
	if not front:
		# Column of light behind the body.
		var h := 40.0 + 60.0 * glow
		for i in 6:
			var w := 18.0 - i * 2.5
			draw_rect(Rect2(-w / 2.0, -h, w, h), Color(col, 0.08 * glow))
	var speed := 5.0 + 9.0 * glow
	for i in 4:
		var y := -12.0 + sin(_t * speed + i * 1.7) * 18.0 * (0.6 + 0.4 * glow)
		var r := 15.0 + 3.0 * sin(_t * 3.0 + i)
		var a0 := PI if not front else 0.0
		draw_set_transform(Vector2(0, y), 0.0, Vector2(1.0, 0.3))
		draw_arc(Vector2.ZERO, r, a0, a0 + PI, 16, Color(col, 0.45 * glow), 5.0)
		draw_arc(Vector2.ZERO, r, a0, a0 + PI, 16, Color(col.lightened(0.6), glow), 2.0)
		draw_set_transform(Vector2.ZERO)
	if front:
		for i in 6:
			var ph := fmod(_t * 1.5 + i * 0.17, 1.0)
			var x := sin(i * 2.3) * 9.0
			draw_rect(Rect2(x, -ph * 50.0, 1.5, 1.5), Color(1, 1, 1, (1.0 - ph) * glow))
