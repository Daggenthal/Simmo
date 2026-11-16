class_name Actor
extends CharacterBody2D
## A player-shaped body: MapleStory-style movement, weapons, spells, HP/MP, XP.
## Player (keyboard + optional auto-battle) and SimPlayer (always a Brain) both extend it.
## Each frame an intent ({dir, jump, jump_release, down, attack, spell}) drives the body;
## where it comes from is the subclass's business (_get_intent).
## One-way platforms can be jumped through from below; Down + Jump drops through.
## Drawing is paper-doll style: layers (legs, shirt, head, hair, hat, weapon) colored from `look`.

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
var world: World
var _spawn_point := Vector2.ZERO
var brain: Brain
var display_name := ""
var tag_color := Color.WHITE
var look: Dictionary = {}
## Who a support spell (heal) lands on; set by the brain before casting.
var spell_target: Node2D = null
var heals_done := 0
## Timed effects, e.g. "xp": {mult, t, max_t, name, color}. XP buffs of one kind don't stack.
var buffs: Dictionary = {}
## The intent used this frame (debug overlay and tests).
var last_intent: Dictionary = {}
var _font: Font

func setup(config: Dictionary, spawn: Vector2, weapon_table: Dictionary = {}, spell_table: Dictionary = {}) -> void:
	cfg = config
	spells = {}
	# Only the spells this actor knows, in slot order.
	var known: Array = cfg.get("spells", spell_table.keys())
	for k in known:
		if spell_table.has(k):
			spells[k] = spell_table[k]
	look = cfg.get("look", {})
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
	brain = Brain.new(self)

func _ready() -> void:
	add_to_group("actors")
	add_to_group("persist")
	z_index = 5
	_font = ThemeDB.fallback_font
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
	_cast_cd = max(_cast_cd - delta, 0.0)
	for k in spell_cd:
		spell_cd[k] = maxf(spell_cd[k] - delta, 0.0)
	mp = minf(mp + float(cfg.get("mp_regen", 0.0)) * delta, max_mp)
	if _drop_timer > 0.0:
		_drop_timer -= delta
		if _drop_timer <= 0.0:
			set_collision_mask_value(LAYER_PLATFORMS, true)

	_tick_buffs(delta)
	var intent := _get_intent(delta)
	last_intent = intent
	_apply(intent, delta)
	move_and_slide()
	queue_redraw()

## This frame's intent. Base actors are always brain-driven.
func _get_intent(delta: float) -> Dictionary:
	return brain.think(delta)

## Whether aiming should prefer the brain's target.
func _uses_brain() -> bool:
	return true

static func blank_intent() -> Dictionary:
	return {"dir": 0.0, "jump": false, "jump_release": false, "down": false, "attack": false, "spell": ""}

func is_alive() -> bool:
	return hp > 0 and visible

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
	casts += 1
	cast_log.append([Engine.get_physics_frames(), id])
	if cast_log.size() > 200:
		cast_log.pop_front()
	_swing_time = 0.18
	_swing_len = 0.18
	if String(sp.kind) == "heal":
		_cast_heal(sp)
		stats_changed.emit()
		return true
	imbue_element = String(sp.element)
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

## Heal the spell target (or yourself): heal_min..heal_max plus heal_per_level per level.
func _cast_heal(sp: Dictionary) -> void:
	var who: Node2D = spell_target if is_instance_valid(spell_target) and spell_target.is_alive() else self
	spell_target = null
	var amount := randi_range(int(sp.heal_min), int(sp.heal_max)) + (level - 1) * int(sp.get("heal_per_level", 0))
	who.heal(amount)
	heals_done += 1
	if who != self:
		facing = 1 if who.global_position.x >= global_position.x else -1
		Fx.lightning(get_parent(), global_position + Vector2(facing * 6, -14), who.global_position + Vector2(0, -12), Color(sp.color))
	Fx.burst(get_parent(), who.global_position + Vector2(0, -12), 14.0, Color(sp.color))

func heal(amount: int) -> void:
	if hp <= 0:
		return
	var before := hp
	hp = mini(hp + amount, max_hp)
	if hp > before:
		FloatText.spawn(get_parent(), global_position + Vector2(0, -H - 4), "+%d" % (hp - before), Color("#9dffb0"))
	stats_changed.emit()

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
	var bt: Mob = brain.target if brain else null
	if _uses_brain() and bt and is_instance_valid(bt) and bt.alive \
			and absf(bt.global_position.x - global_position.x) <= max_range:
		return bt
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
		_on_death()

## Out of HP. The player respawns at the map's spawn point; SimPlayer overrides this.
func _on_death() -> void:
	Log.warn("%s died at level %d, respawning" % [display_name if display_name != "" else "Player", level])
	died.emit()
	_respawn()

func _respawn() -> void:
	hp = max_hp
	mp = max_mp
	position = world.spawn_point if world else _spawn_point
	velocity = Vector2.ZERO
	_invuln = 2.0
	brain.reset()
	stats_changed.emit()

## Placed on a new map (portal travel).
func arrive(pos: Vector2) -> void:
	position = pos
	velocity = Vector2.ZERO
	_spawn_point = pos
	_nav_reset()
	brain.reset()

func _nav_reset() -> void:
	_drop_timer = 0.0
	set_collision_mask_value(LAYER_PLATFORMS, true)

func _tick_buffs(delta: float) -> void:
	for k in buffs.keys():
		buffs[k].t -= delta
		if buffs[k].t <= 0.0:
			Log.info("%s wore off" % buffs[k].name)
			buffs.erase(k)
			stats_changed.emit()

## Multiplier on kill XP from active buffs.
func xp_mult() -> float:
	var m := 1.0
	for b in buffs.values():
		m *= float(b.get("mult", 1.0))
	return m

func gain_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		max_hp += int(cfg.hp_per_level)
		hp = max_hp
		max_mp += int(cfg.get("mp_per_level", 0))
		mp = max_mp
		Log.ok("%s Now level %d" % ["Level up!" if display_name == "" else display_name + " leveled up!", level])
		FloatText.spawn(get_parent(), global_position + Vector2(0, -H - 14), "LEVEL UP!", Color("#ffd84a"), 1.6)
	stats_changed.emit()

func _col(key: String, fallback: String) -> Color:
	return Color(look.get(key, fallback))

## Paper-doll layers, back to front. Palette swaps come from `look`; new hair styles,
## hats or outfits are another match arm here (or sprites later, same order).
func _draw() -> void:
	# Blink while invulnerable.
	if _invuln > 0.0 and int(_invuln * 12) % 2 == 0:
		return
	var top := -H
	var hair := _col("hair", "#4a3426")
	var style := String(look.get("hair_style", "short"))
	# Back hair
	if style == "long":
		draw_rect(Rect2(-7 if facing > 0 else 1, top + 1, 6, 13), hair)
	# Legs
	draw_rect(Rect2(-5, -6, 4, 6), _col("pants", "#3b4a6b"))
	draw_rect(Rect2(1, -6, 4, 6), _col("pants", "#3b4a6b"))
	# Body (shirt)
	draw_rect(Rect2(-6, -15, 12, 10), _col("shirt", "#d9534f"))
	# Head
	draw_circle(Vector2(0, top + 6), 6.5, _col("skin", "#f2c27b"))
	# Hair
	match style:
		"spiky":
			for k in 4:
				var hx := -7.0 + k * 4.0
				draw_colored_polygon(PackedVector2Array([Vector2(hx, top + 3), Vector2(hx + 2 - facing, top - 4), Vector2(hx + 4, top + 3)]), hair)
			draw_rect(Rect2(-7, top, 14, 3), hair)
		_:
			draw_rect(Rect2(-7, top - 1, 14, 4), hair)
			draw_rect(Rect2(-7 if facing > 0 else 3, top - 1, 4, 7), hair)
	# Hat
	match String(look.get("hat", "")):
		"helm":
			draw_rect(Rect2(-7, top - 2, 14, 5), Color("#9aa3ad"))
			draw_rect(Rect2(-1, top - 5, 2, 3), Color("#c43b3b"))
		"band":
			draw_rect(Rect2(-7, top + 1, 14, 2), Color("#e0e0e0"))
			draw_rect(Rect2(-facing * 7 - 1, top + 1, 2, 6), Color("#e0e0e0"))
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
	_draw_tag()

## Name tag under the feet (MapleStory style). The player has none.
func _draw_tag() -> void:
	if display_name == "" or _font == null:
		return
	var w := _font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
	draw_rect(Rect2(-w / 2.0 - 2, 2, w + 4, 9), Color(0, 0, 0, 0.55))
	draw_string(_font, Vector2(-w / 2.0, 9), display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, tag_color)

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
