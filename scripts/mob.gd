class_name Mob
extends CharacterBody2D
## Placeholder mob. Wanders on its platform, turns aggressive when hit,
## damages the player on touch, drops XP on death and respawns later.

signal killed(mob: Mob)

var id := ""
var data: Dictionary
var hp := 1
var max_hp := 1
var alive := true
var size := Vector2(16, 11)
var color := Color.GREEN
var home := Vector2.ZERO
var wander_range := 60.0

var _gravity := 900.0
var _dir := 1
var _think := 0.0
var _hop_cd := 0.0
var _flash := 0.0
var _hp_bar_time := 0.0
var _aggro: Node2D = null
var _squash := 0.0
## Edges of the platform this mob lives on; knockback and wandering stop here.
var bound_x0 := -INF
var bound_x1 := INF
var bound_y := INF

func setup(mob_id: String, mob_data: Dictionary, spawn: Vector2, gravity: float) -> void:
	id = mob_id
	data = mob_data
	max_hp = int(data.hp)
	hp = max_hp
	size = Vector2(data.size[0], data.size[1])
	color = Color(data.color)
	home = spawn
	position = spawn
	_gravity = gravity

## Keep this mob on its home surface (MapleStory style: knockback stops at the ledge).
func set_bounds(nav: Nav) -> void:
	var sid := nav.surface_at(home.x, home.y)
	if sid < 0:
		return
	var surf: Dictionary = nav.surfaces[sid]
	bound_x0 = surf.x0 + size.x / 2.0
	bound_x1 = surf.x1 - size.x / 2.0
	bound_y = surf.y

func _ready() -> void:
	add_to_group("mobs")
	collision_layer = 0
	collision_mask = Player.LAYER_GROUND | Player.LAYER_PLATFORMS
	var shape := RectangleShape2D.new()
	shape.size = size
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = Vector2(0, -size.y / 2.0)
	add_child(col)
	_dir = 1 if randf() < 0.5 else -1
	_think = randf_range(0.5, 2.0)

func is_alive() -> bool:
	return alive

func hurt_rect() -> Rect2:
	return Rect2(global_position + Vector2(-size.x / 2.0, -size.y), size)

func _physics_process(delta: float) -> void:
	if not alive:
		return
	_flash = max(_flash - delta, 0.0)
	_hp_bar_time = max(_hp_bar_time - delta, 0.0)
	_hop_cd = max(_hop_cd - delta, 0.0)
	_squash = move_toward(_squash, 0.0, delta * 4.0)
	velocity.y += _gravity * delta

	var speed := float(data.speed)
	if is_instance_valid(_aggro):
		_dir = 1 if _aggro.global_position.x > global_position.x else -1
		speed *= 1.4
	else:
		_aggro = null
		_think -= delta
		if _think <= 0.0:
			_think = randf_range(1.0, 3.0)
			_dir = [-1, 0, 1].pick_random()
		if absf(global_position.x - home.x) > wander_range:
			_dir = 1 if global_position.x < home.x else -1

	if is_on_floor():
		velocity.x = move_toward(velocity.x, _dir * speed, 400.0 * delta)
		if float(data.hop_velocity) > 0.0 and _dir != 0 and _hop_cd <= 0.0:
			velocity.y = -float(data.hop_velocity) * randf_range(0.6, 1.0)
			_hop_cd = randf_range(0.6, 1.4)
			_squash = 1.0
	if is_on_wall():
		_dir = -_dir

	move_and_slide()
	# Stay on the home platform: clamp at its edges while at platform height.
	if absf(global_position.y - bound_y) < 14.0:
		var cx := clampf(global_position.x, bound_x0, bound_x1)
		if cx != global_position.x:
			global_position.x = cx
			velocity.x = 0.0
			_dir = -_dir
	_touch_player()
	queue_redraw()

func _touch_player() -> void:
	for p in get_tree().get_nodes_in_group("player"):
		var pr := Rect2(p.global_position + Vector2(-Player.W / 2.0, -Player.H), Vector2(Player.W, Player.H))
		if pr.intersects(hurt_rect().grow(-1)):
			p.take_damage(int(data.touch_damage), global_position.x)

func take_hit(amount: int, crit: bool, from_dir: int, attacker: Node2D, knockback := 120.0) -> void:
	if not alive:
		return
	hp -= amount
	_flash = 0.12
	_hp_bar_time = 3.0
	_aggro = attacker
	velocity = Vector2(from_dir * knockback, -60.0 - knockback * 0.4)
	var col := Color("#ffb347") if crit else Color("#ffffff")
	FloatText.spawn(get_parent(), global_position + Vector2(0, -size.y - 6), ("%d!" % amount) if crit else str(amount), col)
	Log.dbg("%s took %d (%s), %d/%d hp" % [data.name, amount, "crit" if crit else "hit", max(hp, 0), max_hp])
	if hp <= 0:
		_die(attacker)

func _die(attacker: Node2D) -> void:
	alive = false
	visible = false
	set_physics_process(false)
	collision_mask = 0
	if attacker and attacker.has_method("gain_xp"):
		FloatText.spawn(get_parent(), global_position + Vector2(0, -size.y - 16), "+%d XP" % int(data.xp), Color("#9be37d"))
		attacker.gain_xp(int(data.xp))
		attacker.kills += 1
	killed.emit(self)

func respawn() -> void:
	alive = true
	visible = true
	hp = max_hp
	_aggro = null
	position = home
	velocity = Vector2.ZERO
	collision_mask = Player.LAYER_GROUND | Player.LAYER_PLATFORMS
	set_physics_process(true)

func _draw() -> void:
	var s := size
	var squash := Vector2(1.0 + _squash * 0.25, 1.0 - _squash * 0.25)
	var body := Rect2(Vector2(-s.x / 2.0 * squash.x, -s.y * squash.y), Vector2(s.x * squash.x, s.y * squash.y))
	var c := Color.WHITE if _flash > 0.0 else color
	if id == "stump":
		draw_rect(body, c)
		draw_rect(Rect2(body.position + Vector2(0, 0), Vector2(body.size.x, 4)), c.darkened(0.3))
		draw_rect(Rect2(Vector2(-6, -s.y + 7), Vector2(3, 2)), Color("#2b1a0e"))
		draw_rect(Rect2(Vector2(3, -s.y + 7), Vector2(3, 2)), Color("#2b1a0e"))
		draw_line(Vector2(-5, -s.y + 6), Vector2(-2, -s.y + 7), Color("#2b1a0e"), 1.0)
		draw_line(Vector2(5, -s.y + 6), Vector2(2, -s.y + 7), Color("#2b1a0e"), 1.0)
	else:
		draw_rect(Rect2(body.position + Vector2(1, 2), body.size - Vector2(2, 2)), c)
		draw_rect(Rect2(body.position + Vector2(3, 0), Vector2(body.size.x - 6, 3)), c)
		draw_rect(Rect2(body.position + Vector2(3, 3), Vector2(3, 2)), c.lightened(0.5))
		var ex := 2.0 * (_dir if _dir != 0 else 1)
		draw_rect(Rect2(Vector2(-4 + ex, body.position.y + 4), Vector2(2, 3)), Color("#1c1c1c"))
		draw_rect(Rect2(Vector2(2 + ex, body.position.y + 4), Vector2(2, 3)), Color("#1c1c1c"))
	if _hp_bar_time > 0.0:
		var w := maxf(s.x, 20.0)
		var y := -s.y - 5
		draw_rect(Rect2(-w / 2.0, y, w, 3), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(-w / 2.0, y, w * clampf(float(hp) / max_hp, 0.0, 1.0), 3), Color("#e04848"))
