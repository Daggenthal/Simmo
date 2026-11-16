class_name Mob
extends CharacterBody2D
## Placeholder mob. Wanders on its platform, turns aggressive when hit,
## damages players and SimPlayers on touch, respawns later (World hands out the XP).
## Some types are aggressive (aggro_range) and some resist elements (resist).

signal killed(mob: Mob, attacker: Node2D)

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
var stun_t := 0.0
# Bosses (data.boss): big, chase the party, telegraphed slams, an enrage timer (the DPS check).
var is_boss := false
var boss_cfg: Dictionary = {}
var boss_time := 0.0       # seconds since it appeared
var enraged := false
var slam_t := 0.0          # > 0 while a slam is winding up (telegraph)
var _slam_cd := 4.0
var slams := 0
var _last_attacker: Node2D = null
var dot_damage_taken := 0
var level := 1
var shape_kind := "slime"
var _font: Font

func setup(mob_id: String, mob_data: Dictionary, spawn: Vector2, gravity: float) -> void:
	id = mob_id
	data = mob_data
	level = int(data.get("level", 1))
	shape_kind = String(data.get("shape", "slime"))
	is_boss = bool(data.get("boss", false))
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
	_font = ThemeDB.fallback_font
	collision_layer = 0
	collision_mask = Actor.LAYER_GROUND | Actor.LAYER_PLATFORMS
	var shape := RectangleShape2D.new()
	shape.size = size
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = Vector2(0, -size.y / 2.0)
	add_child(col)
	_dir = 1 if randf() < 0.5 else -1
	_think = randf_range(0.5, 2.0)

## Share of `element` damage this mob shrugs off (0 = none, 1 = immune).
func resist(element: String) -> float:
	return clampf(float(data.get("resist", {}).get(element, 0.0)), 0.0, 1.0)

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
	if is_boss:
		return  # and freezes (chill still slows them)
	if frozen_t <= 0.0:
		FloatText.spawn(get_parent(), global_position + Vector2(0, -size.y - 14), "FROZEN", Combat.element_color("frost"), 0.9)
	frozen_t = maxf(frozen_t, duration)
	velocity = Vector2.ZERO

## Stunned: can't move or hurt anyone by touch (Titan's Wrath). Stars spin over its head.
func apply_stun(duration: float) -> void:
	if is_boss:
		return  # bosses shrug off stuns
	stun_t = maxf(stun_t, duration)
	velocity.x = 0.0

func is_stunned() -> bool:
	return stun_t > 0.0

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
	stun_t = 0.0
	clear_poison()
	_dot_acc = 0.0

## Burn and poison tick once per second.
func _tick_statuses(delta: float) -> void:
	chill_t = maxf(chill_t - delta, 0.0)
	frozen_t = maxf(frozen_t - delta, 0.0)
	stun_t = maxf(stun_t - delta, 0.0)
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

	var speed := float(data.speed) * (1.0 - chill_slow * (0.5 if is_boss else 1.0) if chill_t > 0.0 else 1.0)
	if is_boss:
		speed *= _boss_tick(delta)
		if slam_t > 0.0:
			velocity.x = 0.0
			move_and_slide()
			queue_redraw()
			return
	if frozen_t > 0.0 or stun_t > 0.0:
		velocity.x = 0.0
		velocity.y += _gravity * delta
		move_and_slide()
		queue_redraw()
		return
	_update_aggro()
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

## Aggressive mobs pick up anyone close on their level; everyone drops a target that left or went down.
func _update_aggro() -> void:
	var r := float(data.get("aggro_range", 0.0))
	if is_instance_valid(_aggro):
		if not _aggro.is_inside_tree() or not _aggro.visible or (r > 0.0 and _aggro.global_position.distance_to(global_position) > r * 3.0):
			_aggro = null
	if _aggro != null or r <= 0.0:
		return
	var best := r
	for a in get_tree().get_nodes_in_group("actors"):
		var d: float = absf(a.global_position.x - global_position.x)
		if a.visible and d <= best and absf(a.global_position.y - global_position.y) < 30.0:
			best = d
			_aggro = a

func _touch_player() -> void:
	if frozen_t > 0.0 or stun_t > 0.0 or int(data.touch_damage) <= 0:
		return
	for p in get_tree().get_nodes_in_group("actors"):
		var pr := Rect2(p.global_position + Vector2(-Actor.W / 2.0, -Actor.H), Vector2(Actor.W, Actor.H))
		if pr.intersects(hurt_rect().grow(-1)):
			p.take_damage(touch_damage(), global_position.x)

func touch_damage() -> int:
	return int(round(float(data.touch_damage) * (float(boss_cfg.get("enrage_damage", 1.0)) if enraged else 1.0)))

## Seconds left before the boss enrages (0 once enraged).
func enrage_left() -> float:
	return maxf(float(boss_cfg.get("enrage_time", 90.0)) - boss_time, 0.0)

## Boss timers: enrage, picking the closest party member, telegraphed slams. Returns the speed factor.
func _boss_tick(delta: float) -> float:
	boss_time += delta
	if not enraged and boss_time >= float(boss_cfg.get("enrage_time", 90.0)):
		enraged = true
		ChatLog.add("warning", "%s is ENRAGED! It hits much harder now." % data.name)
		Sfx.play("boss_roar")
		FloatText.spawn(get_parent(), global_position + Vector2(0, -size.y - 20), "ENRAGED!", Color("#ff3a3a"), 2.0)
	# Always on the nearest party member.
	var best := 1e9
	for a in get_tree().get_nodes_in_group("actors"):
		var d: float = a.global_position.distance_to(global_position)
		if a.visible and d < best:
			best = d
			_aggro = a
	# Slam: wind up (the telegraph ring), then a shockwave along the ground. Jump to dodge.
	var every := float(boss_cfg.get("slam_every", 7.0)) * (0.5 if enraged else 1.0)
	if slam_t > 0.0:
		slam_t -= delta
		if slam_t <= 0.0:
			_slam()
	else:
		_slam_cd -= delta
		var r := float(boss_cfg.get("slam_radius", 110.0))
		if _slam_cd <= 0.0 and is_instance_valid(_aggro) and best < r * 0.9 and is_on_floor():
			_slam_cd = every
			slam_t = float(boss_cfg.get("slam_telegraph", 1.0))
	return float(boss_cfg.get("enrage_speed", 1.0)) if enraged else 1.0

func _slam() -> void:
	slams += 1
	var r := float(boss_cfg.get("slam_radius", 110.0))
	Fx.burst(get_parent(), global_position, r, Color("#ff7a3a"))
	Lighting.flash(get_parent(), global_position + Vector2(0, -8), Color("#ff9a5a"), r * 1.6, 1.4, 0.4)
	Sfx.play("ultimate", 0.7, 0.6)
	var dmg := int(round(touch_damage() * float(boss_cfg.get("slam_damage_mult", 1.5))))
	for a in get_tree().get_nodes_in_group("actors"):
		if a.visible and a.is_on_floor() and absf(a.global_position.x - global_position.x) <= r and absf(a.global_position.y - global_position.y) < 30.0:
			a.take_damage(dmg, global_position.x)

func take_hit(amount: int, crit: bool, from_dir: int, attacker: Node2D, knockback := 120.0, element := "physical") -> void:
	if not alive:
		return
	hp -= amount
	_flash = 0.12
	_hp_bar_time = 3.0
	_aggro = attacker
	_last_attacker = attacker
	knockback *= float(data.get("knockback_mult", 1.0))  # heavy mobs barely budge
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
	Sfx.play("mob_die", 0.7, randf_range(0.85, 1.15))
	killed.emit(self, attacker)

func respawn() -> void:
	alive = true
	visible = true
	hp = max_hp
	dot_damage_taken = 0
	clear_statuses()
	_aggro = null
	position = home
	velocity = Vector2.ZERO
	collision_mask = Actor.LAYER_GROUND | Actor.LAYER_PLATFORMS
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
	if is_boss:
		_draw_boss_under(body)
	if enraged and _flash <= 0.0:
		c = c.lerp(Color("#ff3a2a"), 0.35 + 0.1 * sin(Time.get_ticks_msec() / 120.0))
	_draw_body(body, c, s)
	if is_boss and bool(data.get("crown", false)):
		var top := body.position.y
		draw_colored_polygon(PackedVector2Array([Vector2(-10, top + 2), Vector2(-10, top - 6), Vector2(-5, top - 2), Vector2(0, top - 9), Vector2(5, top - 2), Vector2(10, top - 6), Vector2(10, top + 2)]), Color("#e8c34a"))
		draw_circle(Vector2(0, top - 4), 1.5, Color("#c43b3b"))
	_draw_statuses(body)
	if _hp_bar_time > 0.0:
		var w := maxf(s.x, 20.0)
		var y := -s.y - 5
		draw_rect(Rect2(-w / 2.0, y, w, 3), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(-w / 2.0, y, w * clampf(float(hp) / max_hp, 0.0, 1.0), 3), Color("#e04848"))
	_draw_label()

## Boss extras under the body: the slam telegraph (a red ring growing to the slam's reach) and an enrage aura.
func _draw_boss_under(body: Rect2) -> void:
	if slam_t > 0.0:
		var r := float(boss_cfg.get("slam_radius", 110.0))
		var t := 1.0 - slam_t / float(boss_cfg.get("slam_telegraph", 1.0))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.18))
		draw_circle(Vector2.ZERO, r, Color(1.0, 0.2, 0.1, 0.12))
		draw_arc(Vector2.ZERO, r * t, 0, TAU, 40, Color(1.0, 0.3, 0.2, 0.8), 3.0)
		draw_arc(Vector2.ZERO, r, 0, TAU, 40, Color(1.0, 0.3, 0.2, 0.5), 1.5)
		draw_set_transform(Vector2.ZERO)
	if enraged:
		draw_circle(Vector2(0, body.position.y + body.size.y / 2.0), body.size.x * 0.7, Color(1.0, 0.15, 0.1, 0.12))

## "Lv.N" under the feet, colored by how dangerous the mob is for the player; the name shows while hurt.
func _draw_label() -> void:
	if _font == null:
		return
	var pl_level := level
	var pl := get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	if pl:
		pl_level = pl.level
	var label := "Lv.%d" % level
	if _hp_bar_time > 0.0:
		label = "Lv.%d %s" % [level, data.get("name", id)]
	var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
	var pos := Vector2(-w / 2.0, 9)
	draw_string_outline(_font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, 3, Color(0, 0, 0, 0.75))
	draw_string(_font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Scaling.level_color(level, pl_level))

func _draw_eyes(y: float, col := Color("#1c1c1c")) -> void:
	var ex := 2.0 * (_dir if _dir != 0 else 1)
	draw_rect(Rect2(Vector2(-4 + ex, y), Vector2(2, 3)), col)
	draw_rect(Rect2(Vector2(2 + ex, y), Vector2(2, 3)), col)

func _draw_body(body: Rect2, c: Color, s: Vector2) -> void:
	var f := float(_dir if _dir != 0 else 1)
	match shape_kind:
		"stump":
			draw_rect(body, c)
			draw_rect(Rect2(body.position, Vector2(body.size.x, 4)), c.darkened(0.3))
			draw_rect(Rect2(Vector2(-6, -s.y + 7), Vector2(3, 2)), Color("#2b1a0e"))
			draw_rect(Rect2(Vector2(3, -s.y + 7), Vector2(3, 2)), Color("#2b1a0e"))
			draw_line(Vector2(-5, -s.y + 6), Vector2(-2, -s.y + 7), Color("#2b1a0e"), 1.0)
			draw_line(Vector2(5, -s.y + 6), Vector2(2, -s.y + 7), Color("#2b1a0e"), 1.0)
		"mushroom":
			var stem := Rect2(Vector2(-body.size.x * 0.3, body.position.y + body.size.y * 0.45), Vector2(body.size.x * 0.6, body.size.y * 0.55))
			draw_rect(stem, Color("#f2e6c8"))
			draw_rect(Rect2(body.position, Vector2(body.size.x, body.size.y * 0.5)), c)
			draw_rect(Rect2(body.position + Vector2(2, -2), Vector2(body.size.x - 4, 2)), c)
			draw_circle(body.position + Vector2(4, 3), 1.5, Color(1, 1, 1, 0.8))
			draw_circle(body.position + Vector2(body.size.x - 5, 4), 1.5, Color(1, 1, 1, 0.8))
			_draw_eyes(stem.position.y + 2)
			if id == "horny_shroom":
				draw_line(body.position + Vector2(3, 0), body.position + Vector2(1, -5), Color("#f2e6c8"), 2.0)
				draw_line(body.position + Vector2(body.size.x - 3, 0), body.position + Vector2(body.size.x - 1, -5), Color("#f2e6c8"), 2.0)
		"boar":
			draw_rect(Rect2(body.position + Vector2(0, 2), body.size - Vector2(0, 6)), c)
			draw_rect(Rect2(body.position + Vector2(2, 0), Vector2(body.size.x - 8, 3)), c.darkened(0.25))
			for lx in [-9.0, -4.0, 3.0, 8.0]:
				draw_rect(Rect2(Vector2(lx, -4), Vector2(2, 4)), c.darkened(0.35))
			var snout := Vector2(f * (body.size.x / 2.0), body.position.y + body.size.y * 0.45)
			draw_rect(Rect2(snout + Vector2(-2 if f > 0 else -2, -2), Vector2(4, 4)), c.lightened(0.2))
			draw_line(snout + Vector2(0, 2), snout + Vector2(f * 4, -2), Color("#f5f0e0"), 1.5)
			draw_rect(Rect2(snout + Vector2(-f * 6 - 1, -4), Vector2(2, 2)), Color("#1c1c1c"))
		"imp":
			draw_rect(Rect2(body.position + Vector2(2, 4), body.size - Vector2(4, 6)), c)
			draw_circle(Vector2(0, body.position.y + 5), body.size.x / 2.5, c)
			draw_line(Vector2(-4, body.position.y + 2), Vector2(-6, body.position.y - 4), Color("#3a1a10"), 2.0)
			draw_line(Vector2(4, body.position.y + 2), Vector2(6, body.position.y - 4), Color("#3a1a10"), 2.0)
			_draw_eyes(body.position.y + 4, Color("#ffe66b"))
			var t := Time.get_ticks_msec() / 1000.0
			draw_rect(Rect2(Vector2(-1, body.position.y - 6 - fmod(t * 8.0, 3.0)), Vector2(2, 3)), Color(1.0, 0.7, 0.2, 0.8))
		"golem":
			draw_rect(Rect2(body.position + Vector2(3, 0), Vector2(body.size.x - 6, body.size.y * 0.4)), c)
			draw_rect(Rect2(body.position + Vector2(0, body.size.y * 0.35), Vector2(body.size.x, body.size.y * 0.45)), c.darkened(0.12))
			draw_rect(Rect2(Vector2(-body.size.x / 2.0 + 2, -body.size.y * 0.2), Vector2(5, body.size.y * 0.2)), c.darkened(0.3))
			draw_rect(Rect2(Vector2(body.size.x / 2.0 - 7, -body.size.y * 0.2), Vector2(5, body.size.y * 0.2)), c.darkened(0.3))
			draw_rect(Rect2(body.position + Vector2(body.size.x / 2.0 - 5 + f * 2, 5), Vector2(10, 2)), Color("#ffd36b") if id == "rock_golem" else Color("#e8f8ff"))
			draw_line(body.position + Vector2(5, body.size.y * 0.5), body.position + Vector2(9, body.size.y * 0.65), c.darkened(0.4), 1.0)
		"skeleton":
			var bone := c
			draw_circle(Vector2(0, body.position.y + 4), 4.5, bone)
			draw_rect(Rect2(Vector2(-2 + f, body.position.y + 3), Vector2(2, 2)), Color("#1c1c1c"))
			draw_rect(Rect2(Vector2(1 + f, body.position.y + 3), Vector2(2, 2)), Color("#1c1c1c"))
			draw_rect(Rect2(Vector2(-1, body.position.y + 8), Vector2(2, body.size.y - 14)), bone)
			for k in 3:
				draw_rect(Rect2(Vector2(-4, body.position.y + 10 + k * 3), Vector2(8, 1)), bone)
			draw_line(Vector2(-1, -6), Vector2(-4, 0), bone, 1.5)
			draw_line(Vector2(1, -6), Vector2(4, 0), bone, 1.5)
			draw_line(Vector2(f * 3, body.position.y + 11), Vector2(f * 9, body.position.y + 6), Color("#9aa3ad"), 1.5)
		_:
			draw_rect(Rect2(body.position + Vector2(1, 2), body.size - Vector2(2, 2)), c)
			draw_rect(Rect2(body.position + Vector2(3, 0), Vector2(body.size.x - 6, 3)), c)
			draw_rect(Rect2(body.position + Vector2(3, 3), Vector2(3, 2)), c.lightened(0.5))
			_draw_eyes(body.position.y + 4)

func _draw_statuses(body: Rect2) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	_draw_status_pips(body)
	if stun_t > 0.0:
		for k in 3:
			var a := t * 5.0 + k * TAU / 3.0
			var sp := Vector2(cos(a) * 7.0, body.position.y - 6 + sin(a) * 2.0)
			draw_rect(Rect2(sp - Vector2(1.5, 1.5), Vector2(3, 3)), Color("#ffe66b"))
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
