class_name Player
extends CharacterBody2D
## Placeholder player: a capsule with a face, MapleStory-style movement.
## One-way platforms can be jumped through from below; Down + Jump drops through.

signal stats_changed
signal died

const LAYER_GROUND := 1
const LAYER_PLATFORMS := 2
const W := 12
const H := 24

var cfg: Dictionary
var level := 1
var xp := 0
var hp := 50
var max_hp := 50
var facing := 1
var kills := 0

var _coyote := 0.0
var _jump_buffer := 0.0
var _attack_cd := 0.0
var _swing_time := 0.0
var _invuln := 0.0
var _drop_timer := 0.0
var _auto_pause := 0.0
var _swing_len := 0.15
var _pending_hit := -1.0
var weapons: Dictionary = {}
var weapon: Dictionary = {}
var weapon_key := ""
var swings := 0
var last_projectile: Projectile = null
# Magic
var spells: Dictionary = {}
var mp := 40.0
var max_mp := 40
var spell_cd: Dictionary = {}   # spell id -> seconds left
var _cast_cd := 0.0
var imbue_element := ""
var casts := 0
var last_chain: Array = []
var cast_log: Array = []  # [physics frame, spell id] for tests and pacing checks
var _auto_retarget := 0.0
var _auto_target: Mob = null
var _auto_was_manual := false
var _nav_link: Dictionary = {}
var _chase_time := 0.0
var _ignored: Dictionary = {} # mob -> seconds left; targets auto-battle gave up on
var auto_battle := false
var world: World
var _spawn_point := Vector2.ZERO
var _body_color := Color("#f2c27b")
var _shirt_color := Color("#d9534f")

func setup(config: Dictionary, spawn: Vector2, weapon_table: Dictionary = {}, spell_table: Dictionary = {}) -> void:
	cfg = config
	spells = spell_table
	max_mp = int(cfg.get("max_mp", 40))
	mp = max_mp
	for k in spells:
		spell_cd[k] = 0.0
	weapons = weapon_table
	weapon_key = String(cfg.get("starting_weapon", ""))
	weapon = weapons.get(weapon_key, {})
	if weapon.is_empty() and not weapons.is_empty():
		weapon_key = weapons.keys()[0]
		weapon = weapons[weapon_key]
	_spawn_point = spawn
	position = spawn
	max_hp = int(cfg.max_hp)
	hp = max_hp

func _ready() -> void:
	add_to_group("player")
	collision_layer = 0
	collision_mask = LAYER_GROUND | LAYER_PLATFORMS
	var shape := CapsuleShape2D.new()
	shape.radius = W / 2.0
	shape.height = H
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = Vector2(0, -H / 2.0)
	add_child(col)
	floor_snap_length = 4.0

func xp_to_next() -> int:
	return int(round(float(cfg.xp_base) * pow(level, float(cfg.xp_exponent))))

func _physics_process(delta: float) -> void:
	_coyote = max(_coyote - delta, 0.0)
	_jump_buffer = max(_jump_buffer - delta, 0.0)
	_attack_cd = max(_attack_cd - delta, 0.0)
	_swing_time = max(_swing_time - delta, 0.0)
	if _pending_hit > 0.0:
		_pending_hit -= delta
		if _pending_hit <= 0.0:
			_land_attack()
	_invuln = max(_invuln - delta, 0.0)
	_auto_pause = max(_auto_pause - delta, 0.0)
	_cast_cd = max(_cast_cd - delta, 0.0)
	for k in spell_cd:
		spell_cd[k] = maxf(spell_cd[k] - delta, 0.0)
	mp = minf(mp + float(cfg.get("mp_regen", 0.0)) * delta, max_mp)
	if _drop_timer > 0.0:
		_drop_timer -= delta
		if _drop_timer <= 0.0:
			set_collision_mask_value(LAYER_PLATFORMS, true)

	var intent := _read_manual()
	if auto_battle:
		if intent.active:
			# Manual movement wins, but auto keeps swinging at anything in front of you.
			_auto_pause = float(cfg.auto_pause_after_input)
			_auto_was_manual = true
			if not intent.attack and _mob_in_front():
				intent.attack = true
		elif _auto_pause <= 0.0:
			if _auto_was_manual:
				# Pick a fresh target from wherever the player steered to.
				_auto_was_manual = false
				_auto_target = null
			intent = _auto_think(delta)
		elif _mob_in_front():
			intent.attack = true
	_apply(intent, delta)
	move_and_slide()
	queue_redraw()

## What the player is asking for this frame.
func _read_manual() -> Dictionary:
	var i := {
		"dir": Input.get_axis("move_left", "move_right"),
		"jump": Input.is_action_just_pressed("jump"),
		"jump_release": Input.is_action_just_released("jump"),
		"down": Input.is_action_pressed("move_down"),
		"attack": Input.is_action_pressed("attack"),
	}
	i.spell = ""
	for n in 4:
		if Input.is_action_pressed("spell_%d" % (n + 1)):
			i.spell = _spell_by_slot(n)
	i.active = i.dir != 0.0 or i.jump or i.down or i.attack or Input.is_action_pressed("jump") or i.spell != ""
	return i

func _spell_by_slot(n: int) -> String:
	var keys := spells.keys()
	return keys[n] if n < keys.size() else ""

func _apply(i: Dictionary, delta: float) -> void:
	var dir: float = i.dir
	if dir != 0.0:
		facing = int(signf(dir))

	if is_on_floor():
		_coyote = float(cfg.coyote_time)
	else:
		velocity.y = min(velocity.y + float(cfg.gravity) * delta, float(cfg.max_fall))

	var control := 1.0 if is_on_floor() else float(cfg.air_control)
	if dir != 0.0:
		velocity.x = move_toward(velocity.x, dir * float(cfg.speed), float(cfg.accel) * control * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, float(cfg.friction) * control * delta)

	if i.jump:
		_jump_buffer = float(cfg.jump_buffer)
	if _jump_buffer > 0.0:
		if i.down and is_on_floor() and _on_platform():
			_drop_through()
		elif _coyote > 0.0:
			velocity.y = -float(cfg.jump_velocity)
			_coyote = 0.0
			_jump_buffer = 0.0
	# Variable jump height: let go early for a short hop.
	if i.jump_release and velocity.y < 0.0:
		velocity.y *= 0.5

	# Spells first: a cast locks out the weapon for the global cooldown, so they can't fire together.
	if i.get("spell", "") != "":
		cast(i.spell)
	if i.attack and _attack_cd <= 0.0:
		attack()

func set_auto_battle(on: bool) -> void:
	auto_battle = on
	_auto_target = null
	_ignored.clear()
	_chase_time = 0.0
	_auto_pause = 0.0
	Log.info("Auto-battle %s" % ("on" if on else "off"))
	stats_changed.emit()

## Auto-battle: pick the nearest mob by real travel distance (nav graph),
## follow the route there (jump up, jump across, walk off, drop), then attack.
func _auto_think(delta: float) -> Dictionary:
	var i := {"dir": 0.0, "jump": false, "jump_release": false, "down": false, "attack": false, "spell": ""}
	_auto_retarget -= delta
	for m in _ignored.keys():
		_ignored[m] -= delta
		if _ignored[m] <= 0.0:
			_ignored.erase(m)
	# Give up on a target we've chased too long without landing a swing (unreachable).
	_chase_time += delta
	if _auto_target and _chase_time > float(cfg.auto_give_up_time):
		Log.dbg("auto-battle giving up on %s at %s" % [_auto_target.id, _auto_target.position])
		_ignored[_auto_target] = 4.0
		_auto_target = null
	var lost: bool = _auto_target == null or not is_instance_valid(_auto_target) or not _auto_target.alive
	# Once a target is wounded we stay on it until it dies (or we give up on it).
	var engaged: bool = not lost and _auto_target.hp < _auto_target.max_hp
	# Only re-plan while standing on something, so routes start from a known surface.
	if lost or (_auto_retarget <= 0.0 and is_on_floor() and not engaged):
		_auto_retarget = float(cfg.auto_retarget)
		var picked := _pick_target()
		if picked != _auto_target:
			_chase_time = 0.0
		_auto_target = picked
	var t: Mob = _auto_target
	if t == null:
		return i
	var x := global_position.x
	var dx := t.global_position.x - x
	var thrown: bool = weapon.get("thrown", false)
	var t_dy := absf(_mob_surface_y(t) - global_position.y)
	var weapon_can_hit: bool = thrown and absf(dx) <= float(weapon.range) and t_dy < 90.0
	# Weave: use the weapon whenever it's ready and in reach, spells in between.
	var weapon_ready := _attack_cd <= 0.0 and (weapon_can_hit or _mob_in_front())
	if bool(cfg.get("auto_use_spells", true)):
		# Combo finishers (lightning on frozen, fire on stacked poison) beat a weapon swing;
		# other spells wait until the weapon is busy.
		var pick := _auto_pick_spell(t)
		if pick != "" and (not weapon_ready or _is_combo_finisher(pick, t)):
			i.spell = pick
			_chase_time = 0.0
	# Thrown weapons attack from range, any height they can arc to,
	# and keep closing to a comfortable distance while the throw cools down.
	if thrown and is_on_floor() and weapon_can_hit:
		facing = 1 if dx >= 0.0 else -1
		if _attack_cd <= 0.0:
			i.attack = true
			_chase_time = 0.0
		var preferred := float(weapon.range) * float(cfg.get("thrown_preferred_range", 0.6))
		if absf(dx) > preferred and t_dy < 20.0:
			i.dir = signf(dx)
		return i
	# In the air: steer toward where the current move should land.
	if not is_on_floor():
		if not _nav_link.is_empty():
			var to_land: float = _nav_link.land_x - x
			i.dir = signf(to_land) if absf(to_land) > 3.0 else 0.0
		return i
	_nav_link = {}
	var t_y := _mob_surface_y(t)
	var my_s := world.nav.surface_at(x, global_position.y) if world else -1
	var t_s := world.nav.surface_at(t.global_position.x, t_y) if world else -1
	var reach := float(weapon.range) * 0.8 + W / 2.0 + t.size.x / 2.0
	if my_s == t_s or my_s < 0 or t_s < 0:
		if absf(dx) > reach:
			i.dir = signf(dx)
		elif absf(t_y - global_position.y) < 20.0:
			facing = 1 if dx >= 0.0 else -1
			i.attack = true
			_chase_time = 0.0
		return i
	var route: Dictionary = world.nav.find_route(my_s, x, t_s, t.global_position.x)
	if route.links.is_empty():
		i.dir = signf(dx)
		return i
	var l: Dictionary = route.links[0]
	var to_depart: float = l.depart_x - x
	if absf(to_depart) > 4.0 and not (l.kind == "walk_off" and signf(to_depart) != l.dir):
		i.dir = signf(to_depart)
		return i
	_nav_link = l
	match l.kind:
		"jump_up":
			i.jump = true
		"jump_across":
			i.jump = true
			i.dir = l.dir
		"walk_off":
			i.dir = l.dir
		"drop":
			i.down = true
			i.jump = true
	Log.dbg("auto: %s from surface %d to %d" % [l.kind, l.from, l.to])
	return i

func can_cast(id: String) -> bool:
	if not spells.has(id):
		return false
	return _cast_cd <= 0.0 and spell_cd[id] <= 0.0 and mp >= float(spells[id].mp)

## Cast a spell toward the aim target (or straight ahead). Returns true if it went off.
func cast(id: String) -> bool:
	if not can_cast(id):
		return false
	var sp: Dictionary = spells[id]
	mp -= float(sp.mp)
	spell_cd[id] = float(sp.cooldown)
	var gcd := float(cfg.get("global_cast_cooldown", 1.0))
	_cast_cd = gcd
	# Short cast animation locks the weapon; the full global cooldown only applies between spells.
	_attack_cd = maxf(_attack_cd, float(cfg.get("cast_locks_weapon", 0.4)))
	imbue_element = String(sp.element)
	casts += 1
	cast_log.append([Engine.get_physics_frames(), id])
	if cast_log.size() > 200:
		cast_log.pop_front()
	_swing_time = 0.18
	_swing_len = 0.18
	var target := _aim_target(float(sp.range))
	if target:
		facing = 1 if target.global_position.x >= global_position.x else -1
	var from := global_position + Vector2(facing * 8, -14)
	match String(sp.kind):
		"chain":
			_cast_chain(sp, target, from)
		_:
			var pr := Projectile.new()
			pr.element = String(sp.element)
			pr.color = Color(sp.color)
			pr.damage = roll_base_damage(sp)
			pr.attacker = self
			pr.opts = _hit_opts(30.0)
			pr.max_life = float(sp.range) / float(sp.speed) + 0.4
			if String(sp.kind) == "lob":
				pr.look = "glob"
				pr.gravity = float(sp.gravity)
				pr.splash = float(sp.get("splash", 0.0))
				var aim_at := target.global_position + Vector2(0, -target.size.y / 2.0) if target else from + Vector2(facing * float(sp.range) * 0.7, 16)
				pr.velocity = Projectile.lob_velocity(from, aim_at, float(sp.speed), pr.gravity)
				pr.ground_y = (target.global_position.y if target else global_position.y) + 2.0
				pr.max_life = 2.5
			else:
				pr.look = "bolt"
				var dir_v := Vector2(facing, 0)
				if target:
					dir_v = (target.global_position + Vector2(0, -target.size.y / 2.0) - from).normalized()
					if absf(dir_v.y) > 0.5:
						dir_v = Vector2(facing, 0)
				pr.velocity = dir_v * float(sp.speed)
			get_parent().add_child(pr)
			pr.global_position = from
			last_projectile = pr
	Log.dbg("cast %s (%d mp left)" % [sp.name, int(mp)])
	stats_changed.emit()
	return true

## Chain lightning: strike the target, then jump to the nearest un-hit mobs.
func _cast_chain(sp: Dictionary, target: Mob, from: Vector2) -> void:
	if target == null:
		Fx.lightning(get_parent(), from, from + Vector2(facing * float(sp.range) * 0.5, randf_range(-6, 6)), Color(sp.color))
		return
	var dmg := float(roll_base_damage(sp))
	var hit_list: Array = []
	var cur: Mob = target
	var prev_pos := from
	for jump in int(sp.chains) + 1:
		if cur == null:
			break
		var to := cur.global_position + Vector2(0, -cur.size.y / 2.0)
		Fx.lightning(get_parent(), prev_pos, to, Color(sp.color))
		hit_list.append(cur)
		Combat.hit(cur, self, int(round(dmg)), "lightning", _hit_opts(0.0))
		prev_pos = to
		dmg *= float(sp.chain_falloff)
		var next: Mob = null
		var best := float(sp.chain_range)
		for m in get_tree().get_nodes_in_group("mobs"):
			if m.alive and not hit_list.has(m):
				var d: float = m.global_position.distance_to(to + Vector2(0, cur.size.y / 2.0))
				if d <= best:
					best = d
					next = m
		cur = next
	last_chain = hit_list

## Which spell auto-battle should cast at `t` right now, or "" for none.
## Sets up combos: freeze then lightning, stack poison then ignite with fire.
func _auto_pick_spell(t: Mob) -> String:
	var dist := absf(t.global_position.x - global_position.x)
	var dy := absf(_mob_surface_y(t) - global_position.y)
	var wants: Array = []
	if t.is_frozen():
		wants.append("chain_lightning")
	if t.poison_stacks >= 3:
		wants.append("fireball")
	if not t.is_frozen() and not t.is_chilled():
		wants.append("frost_bolt")
	if t.poison_stacks < 3:
		wants.append("venom_glob")
	if not t.is_burning():
		wants.append("fireball")
	for id in wants:
		if not spells.has(id) or not can_cast(id):
			continue
		var sp: Dictionary = spells[id]
		var max_dy := 90.0 if sp.kind == "lob" else 22.0
		if dist <= float(sp.range) and dy <= max_dy:
			return id
	return ""

func _is_combo_finisher(id: String, t: Mob) -> bool:
	return (id == "chain_lightning" and t.is_frozen()) or (id == "fireball" and t.poison_stacks >= 3)

func _mob_surface_y(m: Mob) -> float:
	return m.global_position.y if m.is_on_floor() else m.home.y

## Nearest live mob by travel cost along the nav graph. Unreachable mobs are skipped.
func _pick_target() -> Mob:
	var best: Mob = null
	var best_cost := INF
	var my_s := world.nav.surface_at(global_position.x, global_position.y) if world else -1
	for m in get_tree().get_nodes_in_group("mobs"):
		if not m.alive or _ignored.has(m):
			continue
		var cost: float
		if world and my_s >= 0:
			var t_s := world.nav.surface_at(m.global_position.x, _mob_surface_y(m))
			cost = world.nav.find_route(my_s, global_position.x, t_s, m.global_position.x).cost
		else:
			cost = absf(m.global_position.x - global_position.x) + absf(_mob_surface_y(m) - global_position.y) * 3.0
		if cost == INF:
			continue
		# Finish wounded mobs first (hammer cleave leaves several), and stick with the current target.
		if m.hp < m.max_hp:
			cost -= float(cfg.get("auto_wounded_bonus", 150.0))
		if m == _auto_target:
			cost -= float(cfg.get("auto_stick_bonus", 40.0))
		if cost < best_cost:
			best_cost = cost
			best = m
	return best

func _on_platform() -> bool:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var body := c.get_collider()
		if body is CollisionObject2D and body.get_collision_layer_value(LAYER_PLATFORMS):
			return true
	return false

func _drop_through() -> void:
	set_collision_mask_value(LAYER_PLATFORMS, false)
	_drop_timer = 0.25
	_jump_buffer = 0.0
	position.y += 2
	Log.dbg("drop through platform at %s" % position)

## Start a swing. Light weapons swing often, heavy ones slowly but harder.
## The hit lands after the weapon's wind-up; the next swing waits for the cooldown.
func attack() -> void:
	var scale := float(cfg.get("attack_speed_scale", 1.0))
	_cast_cd = maxf(_cast_cd, float(cfg.get("attack_blocks_cast", 0.3)))
	_attack_cd = float(weapon.cooldown) * scale
	_swing_len = maxf(float(weapon.windup) * scale + 0.16, 0.2)
	_swing_time = _swing_len
	_pending_hit = float(weapon.windup) * scale
	swings += 1
	if _pending_hit <= 0.0:
		_land_attack()

func _land_attack() -> void:
	if weapon.get("thrown", false):
		_throw()
	else:
		_resolve_hit()

## Hit up to max_targets mobs in front, closest first. Returns how many were hit.
func _resolve_hit() -> int:
	_pending_hit = -1.0
	var box := attack_box()
	var targets := []
	for mob in get_tree().get_nodes_in_group("mobs"):
		if mob.is_alive() and box.intersects(mob.hurt_rect()):
			targets.append(mob)
	targets.sort_custom(func(a, b): return absf(a.global_position.x - global_position.x) < absf(b.global_position.x - global_position.x))
	var hits := 0
	for mob in targets.slice(0, int(weapon.max_targets)):
		Combat.hit(mob, self, roll_base_damage(weapon), "physical", _hit_opts(float(weapon.knockback)))
		hits += 1
	return hits

func _hit_opts(knockback: float) -> Dictionary:
	return {"crit_chance": float(cfg.crit_chance), "crit_mult": float(cfg.crit_mult), "knockback": knockback, "dir": facing}

## Throw the equipped thrown weapon in an arc, aimed at the nearest mob in front (or the auto target).
func _throw() -> void:
	_pending_hit = -1.0
	var from := global_position + Vector2(facing * 6, -14)
	var g := float(weapon.gravity)
	var spd := float(weapon.throw_speed)
	var target := _aim_target(float(weapon.range))
	var pr := Projectile.new()
	if target:
		pr.velocity = Projectile.lob_velocity(from, target.global_position + Vector2(0, -target.size.y / 2.0), spd, g)
		pr.ground_y = target.global_position.y + 2.0
	else:
		pr.velocity = Vector2(facing * spd, -150.0)
		pr.ground_y = global_position.y + 2.0
	pr.gravity = g
	pr.look = "kunai"
	pr.color = Color(weapon.color)
	pr.damage = roll_base_damage(weapon)
	pr.attacker = self
	pr.max_life = 2.5
	pr.element = "physical"
	pr.opts = _hit_opts(float(weapon.knockback))
	# Imbue: carries the element of the last spell cast, at reduced strength.
	if imbue_element != "":
		pr.element = imbue_element
		pr.color = Combat.element_color(imbue_element)
		pr.opts.proc = float(weapon.imbue_chance)
		pr.opts.strength = float(weapon.imbue_strength)
	get_parent().add_child(pr)
	pr.global_position = from
	last_projectile = pr

## Mob to aim at: the auto target if in range, else the nearest live mob in front.
func _aim_target(max_range: float) -> Mob:
	if auto_battle and _auto_target and is_instance_valid(_auto_target) and _auto_target.alive \
			and absf(_auto_target.global_position.x - global_position.x) <= max_range:
		return _auto_target
	var best: Mob = null
	var best_d := INF
	for m in get_tree().get_nodes_in_group("mobs"):
		if not m.alive:
			continue
		var dx: float = (m.global_position.x - global_position.x) * facing
		var dy: float = absf(m.global_position.y - global_position.y)
		if dx > -4.0 and dx <= max_range and dy < 90.0 and dx + dy < best_d:
			best_d = dx + dy
			best = m
	return best

## The area a swing covers right now, in front of the player.
func attack_box() -> Rect2:
	var reach := float(weapon.range)
	var tall := float(weapon.height)
	var center := global_position + Vector2(facing * (W / 2.0 + reach / 2.0), -H / 2.0)
	return Rect2(center - Vector2(reach / 2.0, tall / 2.0), Vector2(reach, tall))

func _mob_in_front() -> bool:
	var box := attack_box()
	for mob in get_tree().get_nodes_in_group("mobs"):
		if mob.alive and box.intersects(mob.hurt_rect()):
			return true
	return false

func equip(weapon_id: String) -> void:
	if not weapons.has(weapon_id):
		Log.warn("Unknown weapon '%s', keeping %s" % [weapon_id, weapon.get("name", "nothing")])
		return
	weapon_key = weapon_id
	weapon = weapons[weapon_id]
	_attack_cd = 0.0
	Log.info("Equipped %s (%s)" % [weapon.name, weapon.speed_label])
	stats_changed.emit()

## Base damage for one hit with weapon or spell `w` (no crit; Combat rolls crits).
## Level bonus scales with swing time so slow weapons keep up per hit.
func roll_base_damage(w: Dictionary) -> int:
	var bonus := (level - 1) * float(cfg.damage_per_level) * float(w.cooldown) / float(cfg.level_bonus_reference_cooldown)
	return randi_range(int(w.damage_min + bonus), int(w.damage_max + bonus))

func roll_damage() -> Dictionary:
	var bonus := (level - 1) * float(cfg.damage_per_level) * float(weapon.cooldown) / float(cfg.level_bonus_reference_cooldown)
	var lo := int(weapon.damage_min + bonus)
	var hi := int(weapon.damage_max + bonus)
	var amount := randi_range(lo, hi)
	var crit := randf() < float(cfg.crit_chance)
	if crit:
		amount = int(amount * float(cfg.crit_mult))
	return {"amount": amount, "crit": crit}

## Average damage per second at the current level, crits included.
func weapon_dps(w: Dictionary) -> float:
	var bonus := (level - 1) * float(cfg.damage_per_level) * float(w.cooldown) / float(cfg.level_bonus_reference_cooldown)
	var avg := (float(w.damage_min) + float(w.damage_max)) / 2.0 + bonus
	avg *= 1.0 + float(cfg.crit_chance) * (float(cfg.crit_mult) - 1.0)
	return avg / (float(w.cooldown) * float(cfg.get("attack_speed_scale", 1.0)))

func take_damage(amount: int, from_x: float) -> void:
	if _invuln > 0.0 or hp <= 0:
		return
	hp = max(hp - amount, 0)
	_invuln = float(cfg.invuln_time)
	velocity = Vector2(sign(global_position.x - from_x) * 140.0, -150.0)
	FloatText.spawn(get_parent(), global_position + Vector2(0, -H - 4), str(amount), Color("#ff6b6b"))
	stats_changed.emit()
	if hp <= 0:
		Log.warn("Player died at level %d, respawning in town" % level)
		died.emit()
		_respawn()

func _respawn() -> void:
	hp = max_hp
	mp = max_mp
	position = _spawn_point
	velocity = Vector2.ZERO
	_invuln = 2.0
	stats_changed.emit()

func gain_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		max_hp += int(cfg.hp_per_level)
		hp = max_hp
		max_mp += int(cfg.get("mp_per_level", 0))
		mp = max_mp
		Log.ok("Level up! Now level %d" % level)
		FloatText.spawn(get_parent(), global_position + Vector2(0, -H - 14), "LEVEL UP!", Color("#ffd84a"), 1.6)
	stats_changed.emit()

func _draw() -> void:
	# Blink while invulnerable.
	if _invuln > 0.0 and int(_invuln * 12) % 2 == 0:
		return
	var top := -H
	# Legs
	draw_rect(Rect2(-5, -6, 4, 6), Color("#3b4a6b"))
	draw_rect(Rect2(1, -6, 4, 6), Color("#3b4a6b"))
	# Body (shirt)
	draw_rect(Rect2(-6, -15, 12, 10), _shirt_color)
	# Head
	draw_circle(Vector2(0, top + 6), 6.5, _body_color)
	# Hair
	draw_rect(Rect2(-7, top - 1, 14, 4), Color("#4a3426"))
	draw_rect(Rect2(-7 if facing > 0 else 3, top - 1, 4, 7), Color("#4a3426"))
	# Eye
	draw_rect(Rect2(facing * 2 - 1, top + 5, 2, 3), Color("#1c1c1c"))
	# Weapon: idle on the shoulder, swings an arc when attacking.
	var hand := Vector2(facing * 6, -11)
	var length := float(weapon.length)
	var col := Color(weapon.color)
	var tip: Vector2
	if _swing_time > 0.0:
		var t := 1.0 - _swing_time / _swing_len
		# Heavy weapons pull back during the wind-up before the swing comes down.
		var wind := float(weapon.windup) * float(cfg.get("attack_speed_scale", 1.0)) / _swing_len
		var angle: float
		if t < wind:
			angle = lerpf(-1.2, -1.9, t / wind) * facing
		else:
			angle = lerpf(-1.9 if wind > 0.0 else -1.2, 1.0, (t - wind) / (1.0 - wind)) * facing
			draw_arc(hand, length, -PI / 2 + (0.0 if facing > 0 else PI), PI / 2 + (0.0 if facing > 0 else PI), 12, Color(1, 1, 1, 0.3), 2.0)
		tip = hand + Vector2(facing * length, 0).rotated(angle)
	else:
		tip = hand + Vector2(facing * length * 0.35, -length * 0.85)
	_draw_weapon(hand, tip, col)

func _draw_weapon(hand: Vector2, tip: Vector2, col: Color) -> void:
	match weapon_key:
		"throwing_kunai":
			draw_line(hand, hand + (tip - hand) * 0.45, col, 2.0)
		"dagger":
			draw_line(hand, tip, col, 2.0)
		"iron_hammer":
			draw_line(hand, tip, Color("#7a5232"), 2.0)
			var d := (tip - hand).normalized()
			var n := Vector2(-d.y, d.x)
			draw_colored_polygon(PackedVector2Array([tip + n * 5 - d * 3, tip + n * 5 + d * 3, tip - n * 5 + d * 3, tip - n * 5 - d * 3]), col)
		_:
			draw_line(hand, tip, col, 3.0)
			var d := (tip - hand).normalized()
			draw_line(hand + d * 3 + Vector2(-d.y, d.x) * 3, hand + d * 3 - Vector2(-d.y, d.x) * 3, Color("#b08a3c"), 2.0)
