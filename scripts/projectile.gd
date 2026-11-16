class_name Projectile
extends Node2D
## Spell bolts (straight), lobbed globs and thrown weapons (arcing, with gravity).
## Hits the first live mob it touches; lobbed shots splash when they land.

var velocity := Vector2.ZERO
var gravity := 0.0
var element := "physical"
var look := "bolt"       # bolt, glob, kunai
var color := Color.WHITE
var damage := 1
var opts: Dictionary = {}
var attacker: Node2D
var splash := 0.0
var max_life := 2.0
var ground_y := 9999.0
var hits: Array = []     # mobs hit, for tests
var _life := 0.0
var _trail: Array = []

## Launch velocity that lobs from `from` to `to` with horizontal speed `speed`.
static func lob_velocity(from: Vector2, to: Vector2, speed: float, g: float) -> Vector2:
	var dx := to.x - from.x
	var t := maxf(absf(dx) / speed, 0.15)
	var vy := ((to.y - from.y) - 0.5 * g * t * t) / t
	return Vector2(signf(dx) * speed if dx != 0.0 else speed, clampf(vy, -340.0, 60.0))

func _ready() -> void:
	z_index = 40

func _physics_process(delta: float) -> void:
	_life += delta
	_trail.push_front(global_position)
	if _trail.size() > 6:
		_trail.pop_back()
	velocity.y += gravity * delta
	global_position += velocity * delta
	var box := Rect2(global_position - Vector2(4, 4), Vector2(8, 8))
	for mob in get_tree().get_nodes_in_group("mobs"):
		if mob.alive and box.intersects(mob.hurt_rect()):
			_impact(mob)
			return
	if global_position.y >= ground_y or _life >= max_life:
		if splash > 0.0 and global_position.y >= ground_y:
			_impact(null)
		else:
			queue_free()
	queue_redraw()

func _impact(direct: Mob) -> void:
	if direct:
		hits.append(direct)
		Combat.hit(direct, attacker, damage, element, opts)
	if splash > 0.0:
		Fx.burst(get_parent(), global_position, splash, color)
		for mob in get_tree().get_nodes_in_group("mobs"):
			if mob != direct and mob.alive and mob.global_position.distance_to(global_position) <= splash + 8.0:
				hits.append(mob)
				var o := opts.duplicate()
				o.knockback = 0.0
				Combat.hit(mob, attacker, maxi(1, damage / 2), element, o)
	queue_free()

func _draw() -> void:
	for i in _trail.size():
		var p: Vector2 = _trail[i] - global_position
		draw_circle(p, maxf(3.0 - i * 0.5, 0.5), Color(color, 0.35 - i * 0.05))
	match look:
		"kunai":
			var d := velocity.normalized()
			draw_line(-d * 5, d * 5, color, 2.0)
			draw_line(-d * 5, -d * 7, Color("#7a5232"), 2.0)
		"glob":
			draw_circle(Vector2.ZERO, 4.0, color)
			draw_circle(Vector2(-1, -1), 1.5, color.lightened(0.5))
		_:
			draw_circle(Vector2.ZERO, 4.5, color)
			draw_circle(Vector2.ZERO, 2.5, color.lightened(0.6))
