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

# Status effects
var burn_dps := 0.0
var burn_t := 0.0
var chill_t := 0.0
var chill_slow := 0.0
var frozen_t := 0.0
var poison_stacks := 0
var poison_dps := 0.0
var poison_t := 0.0
var _dot_acc := 0.0
var _last_attacker: Node2D = null
var dot_damage_taken := 0

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

func is_frozen() -> bool:
	return frozen_t > 0.0

func is_chilled() -> bool:
	return chill_t > 0.0

func is_burning() -> bool:
	return burn_t > 0.0

func apply_burn(dps: float, duration: float, attacker: Node2D) -> void:
	burn_dps = maxf(burn_dps if burn_t > 0.0 else 0.0, dps)
	burn_t = duration
	_last_attacker = attacker

func apply_chill(slow: float, duration: float) -> void:
	chill_slow = slow
	chill_t = maxf(chill_t, duration)

func apply_freeze(duration: float) -> void:
	if frozen_t <= 0.0:
		FloatText.spawn(get_parent(), global_position + Vector2(0, -size.y - 14), "FROZEN", Combat.element_color("frost"), 0.9)
	frozen_t = maxf(frozen_t, duration)
	velocity = Vector2.ZERO

func thaw() -> void:
	frozen_t = 0.0
	chill_t = 0.0

func add_poison(dps_per_stack: float, max_stacks: int, duration: float, attacker: Node2D) -> void:
	poison_stacks = mini(poison_stacks + 1, max_stacks)
	poison_dps = dps_per_stack
	poison_t = duration
	_last_attacker = attacker

func clear_poison() -> void:
	poison_stacks = 0
	poison_t = 0.0

func clear_statuses() -> void:
	burn_t = 0.0
	chill_t = 0.0
	frozen_t = 0.0
	clear_poison()
	_dot_acc = 0.0

## Burn and poison tick once per second.
func _tick_statuses(delta: float) -> void:
	chill_t = maxf(chill_t - delta, 0.0)
	frozen_t = maxf(frozen_t - delta, 0.0)
	if burn_t <= 0.0 and poison_t <= 0.0:
		_dot_acc = 0.0
		return
	_dot_acc += delta
	while _dot_acc >= 1.0 and alive:
		_dot_acc -= 1.0
		if burn_t > 0.0:
			_take_dot(int(round(burn_dps)), "fire")
		if poison_t > 0.0 and alive:
			_take_dot(int(round(poison_dps * poison_stacks)), "poison")
	burn_t = maxf(burn_t - delta, 0.0)
	poison_t = maxf(poison_t - delta, 0.0)
	if poison_t <= 0.0:
		poison_stacks = 0

func _take_dot(amount: int, element: String) -> void:
	if amount <= 0:
		return
	hp -= amount
	dot_damage_taken += amount
	_hp_bar_time = 3.0
	FloatText.spawn(get_parent(), global_position + Vector2(randf_range(-6, 6), -size.y - 4), str(amount), Combat.element_color(element), 0.7)
	if hp <= 0:
		_die(_last_attacker)

func is_alive() -> bool:
	return alive

func hurt_rect() -> Rect2:
	return Rect2(global_position + Vector2(-size.x / 2.0, -size.y), size)

func _physics_process(delta: float) -> void:
	if not alive:
		return
	_tick_statuses(delta)
	if not alive:
		return
	_flash = max(_flash - delta, 0.0)
	_hp_bar_time = max(_hp_bar_time - delta, 0.0)
	_hop_cd = max(_hop_cd - delta, 0.0)
	_squash = move_toward(_squash, 0.0, delta * 4.0)
	velocity.y += _gravity * delta

	var speed := float(data.speed) * (1.0 - chill_slow if chill_t > 0.0 else 1.0)
	if frozen_t > 0.0:
		velocity.x = 0.0
		velocity.y += _gravity * delta
		move_and_slide()
		queue_redraw()
		return
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
			velocity.y = -float(data.hop_velocity) * randf_range(0.6, 1.0) * (0.6 if chill_t > 0.0 else 1.0)
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
	if frozen_t > 0.0:
		return
	for p in get_tree().get_nodes_in_group("player"):
		var pr := Rect2(p.global_position + Vector2(-Player.W / 2.0, -Player.H), Vector2(Player.W, Player.H))
		if pr.intersects(hurt_rect().grow(-1)):
			p.take_damage(int(data.touch_damage), global_position.x)

func take_hit(amount: int, crit: bool, from_dir: int, attacker: Node2D, knockback := 120.0, element := "physical") -> void:
	if not alive:
		return
	hp -= amount
	_flash = 0.12
	_hp_bar_time = 3.0
	_aggro = attacker
	_last_attacker = attacker
	if knockback > 0.0:
		velocity = Vector2(from_dir * knockback, -60.0 - knockback * 0.4)
	var col := Color("#ffb347") if crit and element == "physical" else Combat.element_color(element)
	if crit and element != "physical":
		col = col.lightened(0.35)
	FloatText.spawn(get_parent(), global_position + Vector2(0, -size.y - 6), ("%d!" % amount) if crit else str(amount), col)
	Log.dbg("%s took %d (%s), %d/%d hp" % [data.name, amount, "crit" if crit else "hit", max(hp, 0), max_hp])
	if hp <= 0:
		_die(attacker)

func _die(attacker: Node2D) -> void:
	alive = false
	visible = false
	clear_statuses()
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
	dot_damage_taken = 0
	clear_statuses()
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
	if chill_t > 0.0 and _flash <= 0.0:
		c = c.lerp(Color("#9fe0ff"), 0.45)
	if burn_t > 0.0 and _flash <= 0.0:
		c = c.lerp(Color("#ff8a3d"), 0.3)
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
	_draw_statuses(body)
	if _hp_bar_time > 0.0:
		var w := maxf(s.x, 20.0)
		var y := -s.y - 5
		draw_rect(Rect2(-w / 2.0, y, w, 3), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(-w / 2.0, y, w * clampf(float(hp) / max_hp, 0.0, 1.0), 3), Color("#e04848"))

func _draw_statuses(body: Rect2) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	_draw_status_pips(body)
	if frozen_t > 0.0:
		var ice := body.grow(2)
		draw_rect(ice, Color(0.75, 0.92, 1.0, 0.45))
		draw_rect(ice, Color(0.85, 0.97, 1.0, 0.9), false, 1.0)
		draw_line(ice.position + Vector2(2, 2), ice.position + Vector2(6, 6), Color(1, 1, 1, 0.8), 1.0)
	if burn_t > 0.0:
		for k in 3:
			var ph := fmod(t * 2.0 + k * 0.33, 1.0)
			var px := body.position.x + body.size.x * (0.15 + 0.3 * k)
			var fy := body.position.y - ph * 12.0
			draw_rect(Rect2(px, fy, 3, 3), Color(1.0, 0.45 + 0.4 * ph, 0.05, 1.0 - ph))
			draw_rect(Rect2(px + 1, fy - 2, 1, 2), Color(1.0, 0.9, 0.3, 1.0 - ph))
	if poison_t > 0.0:
		for k in poison_stacks:
			var ph := fmod(t * 1.3 + k * 0.21, 1.0)
			var px := body.position.x + fmod(k * 5.3, body.size.x)
			var bp := Vector2(px, body.position.y - ph * 9.0)
			draw_circle(bp, 2.0, Color(0.15, 0.3, 0.1, (1.0 - ph) * 0.8))
			draw_circle(bp, 1.4, Color(0.6, 1.0, 0.35, 1.0 - ph))

## A row of small status icons above the HP bar, readable at a glance on any mob color.
func _draw_status_pips(body: Rect2) -> void:
	var pips: Array = []
	if burn_t > 0.0:
		pips.append([Color("#ff8a3d"), 0])
	if frozen_t > 0.0:
		pips.append([Color("#e8f8ff"), 0])
	elif chill_t > 0.0:
		pips.append([Color("#7fcfff"), 0])
	if poison_stacks > 0:
		pips.append([Color("#7ed957"), poison_stacks])
	if pips.is_empty():
		return
	var y := -size.y - 13.0
	var x := -(pips.size() * 7.0 - 2.0) / 2.0
	for pip in pips:
		draw_rect(Rect2(x - 1, y - 1, 7, 7), Color(0, 0, 0, 0.75))
		draw_rect(Rect2(x, y, 5, 5), pip[0])
		for k in int(pip[1]):
			draw_rect(Rect2(x + k * 1.0, y + 6, 1, 1), pip[0])
		x += 7.0
