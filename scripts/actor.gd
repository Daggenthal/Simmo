class_name Actor
extends CharacterBody2D
## A player-shaped body: MapleStory-style movement, weapons, spells, HP/MP, XP.
## Player (keyboard + optional auto-battle) and SimPlayer (always a Brain) both extend it.
## Each frame an intent ({dir, jump, jump_release, down, attack, spell}) drives the body;
## where it comes from is the subclass's business (_get_intent).
## One-way platforms can be jumped through from below; Down + Jump drops through.
## Drawing is paper-doll style: layers (legs, shirt, head, hair, hat, weapon) colored from `look`.
## Classes (balance.json "classes") set the allowed weapons, skills, starting stats and look.
## Stats: STR, DEX, INT, LUK. Each attack scales with its own stat ("stat" on the weapon or skill);
## level-ups give AP, which auto-assign spends by the class's auto_ap split.

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
# Class and stats
const STATS := ["str", "dex", "int", "luk"]
var class_id := ""
var class_cfg: Dictionary = {}
var allowed_weapons: Array = []
var stats := {"str": 4, "dex": 4, "int": 4, "luk": 4}
var base_stats := {"str": 4, "dex": 4, "int": 4, "luk": 4}
var ap := 0
var auto_assign := true
var stat_effects: Dictionary = {}
var _spell_table: Dictionary = {}
# Charge (dash skill) in progress
var _dash_t := 0.0
var _dash_sp: Dictionary = {}
var _dash_hit: Array = []
var _classes: Dictionary = {}
var _balance: Dictionary = {}

func setup(config: Dictionary, spawn: Vector2, weapon_table: Dictionary = {}, spell_table: Dictionary = {}) -> void:
	cfg = config
	_spell_table = spell_table
	weapons = weapon_table
	allowed_weapons = weapons.keys()
	look = cfg.get("look", {})
	_spawn_point = spawn
	position = spawn
	brain = Brain.new(self)
	_set_spells(spell_table.keys())
	_set_weapon(weapons.keys()[0] if not weapons.is_empty() else "")
	recalc()
	hp = max_hp
	mp = max_mp

## Become class `id` from balance.json: its weapons, skills, starting stats and look.
## Keeps the current level; AP earned so far is re-spent by auto-assign.
## weapon / skill_ids override the class defaults (SimPlayer roles use this).
func set_class(balance: Dictionary, id: String, weapon_id := "", skill_ids: Array = []) -> void:
	_balance = balance
	_classes = balance.get("classes", {})
	stat_effects = balance.get("stat_effects", {})
	if not Log.check(_classes.has(id), "unknown class '%s'" % id):
		return
	class_id = id
	class_cfg = _classes[id]
	allowed_weapons = class_cfg.get("weapons", [])
	if look.is_empty() or display_name == "":
		look = class_cfg.get("look", look)
	_set_spells(skill_ids if not skill_ids.is_empty() else class_cfg.get("spells", []))
	_set_weapon(weapon_id if weapon_id != "" else String(allowed_weapons[0]))
	for k in STATS:
		base_stats[k] = int(class_cfg.get("stats", {}).get(k, 4))
	stats = base_stats.duplicate()
	ap = (level - 1) * int(cfg.get("ap_per_level", 5))
	if auto_assign:
		auto_spend()
	recalc()
	hp = max_hp
	mp = max_mp
	stats_changed.emit()

func class_name_label() -> String:
	return String(class_cfg.get("name", class_id.capitalize()))

## Tests and tools: become the class that owns weapon `id` (keeping the level) and equip it.
func switch_to_weapon_class(id: String) -> void:
	var c := class_for_weapon(id)
	if c != "" and c != class_id:
		set_class(_balance, c)
	equip(id)

## The class that may use weapon `id`, or "".
func class_for_weapon(id: String) -> String:
	for c in _classes:
		if id in _classes[c].get("weapons", []):
			return c
	return ""

func _set_spells(ids: Array) -> void:
	spells = {}
	spell_cd = {}
	for k in ids:
		if _spell_table.has(k):
			spells[k] = _spell_table[k]
			spell_cd[k] = 0.0

func _set_weapon(id: String) -> void:
	weapon_key = id
	weapon = weapons.get(id, {})
	_attack_cd = 0.0

## Spend free AP by the class's auto_ap split (e.g. 4 STR + 1 DEX per level).
func auto_spend() -> void:
	var split: Dictionary = class_cfg.get("auto_ap", {})
	var per := 0
	for k in split:
		per += int(split[k])
	if per <= 0:
		return
	while ap >= per:
		for k in split:
			stats[k] += int(split[k])
		ap -= per
	# Leftovers go to the main stat.
	var main := String(class_cfg.get("primary", "str"))
	stats[main] += ap
	ap = 0

## Spend one AP on stat k by hand. Returns true if it went in.
func add_stat(k: String) -> bool:
	if ap <= 0 or not k in STATS:
		return false
	stats[k] += 1
	ap -= 1
	recalc()
	stats_changed.emit()
	return true

func _effect(kind: String) -> float:
	var total := 0.0
	for k in STATS:
		total += float(stat_effects.get(k, {}).get(kind, 0.0)) * stats[k]
	return total

## Max HP / MP from level, class multipliers and STR / INT. Keeps current HP and MP where they fit.
func recalc() -> void:
	var hp_mult := float(class_cfg.get("hp_mult", 1.0))
	var mp_mult := float(class_cfg.get("mp_mult", 1.0))
	max_hp = int(round((float(cfg.max_hp) + float(cfg.hp_per_level) * (level - 1)) * hp_mult + _effect("hp")))
	max_mp = int(round((float(cfg.get("max_mp", 40)) + float(cfg.get("mp_per_level", 0)) * (level - 1)) * mp_mult + _effect("mp")))
	hp = mini(hp, max_hp)
	mp = minf(mp, max_mp)

func crit_chance() -> float:
	return float(cfg.crit_chance) + _effect("crit")

## Loot chance multiplier from LUK.
func drop_mult() -> float:
	return 1.0 + _effect("drop")

## Jump straight to level n (tests and tools): AP re-spent by auto-assign, HP and MP full.
func set_level(n: int) -> void:
	level = maxi(n, 1)
	xp = 0
	stats = base_stats.duplicate()
	ap = (level - 1) * int(cfg.get("ap_per_level", 5))
	if auto_assign:
		auto_spend()
	recalc()
	hp = max_hp
	mp = max_mp
	stats_changed.emit()

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
	if _dash_t > 0.0:
		_dash_step(delta)
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
	if String(sp.element) != "physical":
		imbue_element = String(sp.element)
	var target := _aim_target(float(sp.get("range", sp.get("radius", 60.0))))
	if target:
		facing = 1 if target.global_position.x >= global_position.x else -1
	var from := global_position + Vector2(facing * 8, -14)
	match String(sp.kind):
		"chain":
			_cast_chain(sp, target, from)
		"strike":
			_cast_strike(sp)
		"slam":
			_cast_slam(sp)
		"volley":
			_cast_volley(sp, target, from)
		"dash":
			_dash_t = float(sp.distance) / float(sp.speed)
			_dash_sp = sp
			_dash_hit = []
			_invuln = maxf(_invuln, _dash_t)
		"buff":
			var label := ""
			if sp.has("dmg_mult"):
				label = "+%d%% damage" % int(round((float(sp.dmg_mult) - 1.0) * 100.0))
			elif sp.has("speed_mult"):
				label = "+%d%% attack speed" % int(round((float(sp.speed_mult) - 1.0) * 100.0))
			buffs[id] = {"name": String(sp.name), "t": float(sp.duration), "max_t": float(sp.duration), "color": String(sp.color),
				"dmg_mult": float(sp.get("dmg_mult", 1.0)), "speed_mult": float(sp.get("speed_mult", 1.0)), "label": label}
			Fx.burst(get_parent(), global_position + Vector2(0, -12), 22.0, Color(sp.color))
			FloatText.spawn(get_parent(), global_position + Vector2(0, -H - 14), String(sp.name).to_upper() + "!", Color(sp.color), 1.2)
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

## Charge: run forward fast, hitting each mob in the way once.
func _dash_step(delta: float) -> void:
	_dash_t -= delta
	velocity.x = facing * float(_dash_sp.speed)
	var me := Rect2(global_position + Vector2(-W / 2.0 - 4, -H), Vector2(W + 8, H))
	for m in get_tree().get_nodes_in_group("mobs"):
		if m.alive and not _dash_hit.has(m) and me.intersects(m.hurt_rect()):
			_dash_hit.append(m)
			Combat.hit(m, self, roll_base_damage(_dash_sp), String(_dash_sp.element), _hit_opts(float(_dash_sp.get("knockback", 0.0))))
	if _dash_t <= 0.0:
		velocity.x *= 0.3

## Damage multiplier from active buffs (War Cry).
func buff_dmg_mult() -> float:
	var m := 1.0
	for b in buffs.values():
		m *= float(b.get("dmg_mult", 1.0))
	return m

## Attack speed multiplier from active buffs (Haste).
func buff_speed_mult() -> float:
	var m := 1.0
	for b in buffs.values():
		m *= float(b.get("speed_mult", 1.0))
	return m

## Power Strike: one heavy hit on the closest mobs in a box in front.
func _cast_strike(sp: Dictionary) -> void:
	var reach := float(sp.range)
	var tall := float(sp.get("height", 30.0))
	var center := global_position + Vector2(facing * (W / 2.0 + reach / 2.0), -H / 2.0)
	var box := Rect2(center - Vector2(reach, tall) / 2.0, Vector2(reach, tall))
	var targets: Array = []
	for m in get_tree().get_nodes_in_group("mobs"):
		if m.alive and box.intersects(m.hurt_rect()):
			targets.append(m)
	targets.sort_custom(func(a, b): return absf(a.global_position.x - global_position.x) < absf(b.global_position.x - global_position.x))
	Fx.burst(get_parent(), center, 12.0, Color(sp.color))
	var hits := int(sp.get("hits", 1))
	for m in targets.slice(0, int(sp.get("max_targets", 1))):
		Combat.hit(m, self, roll_base_damage(sp), String(sp.element), _hit_opts(float(sp.get("knockback", 0.0))))
		# Flurry: the follow-up stabs land a beat apart.
		for k in range(1, hits):
			get_tree().create_timer(0.1 * k, false, true).timeout.connect(func() -> void:
				if is_instance_valid(m) and m.alive and is_instance_valid(self):
					_swing_time = 0.12
					_swing_len = 0.12
					Combat.hit(m, self, roll_base_damage(sp), String(sp.element), _hit_opts(float(sp.get("knockback", 0.0)))))

## Ground Slam: hits every mob around you on your level, pushing them away.
func _cast_slam(sp: Dictionary) -> void:
	var r := float(sp.radius)
	Fx.burst(get_parent(), global_position + Vector2(0, -4), r, Color(sp.color))
	var hit := 0
	for m in get_tree().get_nodes_in_group("mobs"):
		if hit >= int(sp.get("max_targets", 6)):
			break
		if m.alive and absf(m.global_position.x - global_position.x) <= r and absf(m.global_position.y - global_position.y) < 30.0:
			var o := _hit_opts(float(sp.get("knockback", 0.0)))
			o.dir = 1 if m.global_position.x >= global_position.x else -1
			Combat.hit(m, self, roll_base_damage(sp), String(sp.element), o)
			hit += 1

## Lucky Seven: a quick spread of thrown stars (kunai) at the target.
func _cast_volley(sp: Dictionary, target: Mob, from: Vector2) -> void:
	var g := float(sp.gravity)
	for k in int(sp.count):
		var pr := Projectile.new()
		var aim := target.global_position + Vector2(0, -target.size.y / 2.0) if target else from + Vector2(facing * float(sp.range) * 0.6, 10)
		pr.velocity = Projectile.lob_velocity(from, aim, float(sp.throw_speed) * (1.0 + 0.12 * k), g)
		pr.ground_y = (target.global_position.y if target else global_position.y) + 2.0
		pr.gravity = g
		pr.look = "kunai"
		pr.color = Color(sp.color)
		pr.damage = roll_base_damage(sp)
		pr.attacker = self
		pr.max_life = 2.5
		pr.element = String(sp.element)
		pr.opts = _hit_opts(40.0)
		get_parent().add_child(pr)
		pr.global_position = from + Vector2(0, -3 * k)
		last_projectile = pr

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
	var scale := float(cfg.get("attack_speed_scale", 1.0)) / buff_speed_mult()
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
	return {"crit_chance": crit_chance(), "crit_mult": float(cfg.crit_mult), "knockback": knockback, "dir": facing}

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

## Equip a weapon your class can use. Returns "" or why not.
func equip(weapon_id: String) -> String:
	if not weapons.has(weapon_id):
		Log.warn("Unknown weapon '%s', keeping %s" % [weapon_id, weapon.get("name", "nothing")])
		return "Unknown weapon"
	if not weapon_id in allowed_weapons:
		var owner := class_for_weapon(weapon_id)
		var msg := "Only %ss can use the %s" % [String(_classes.get(owner, {}).get("name", "other class")), weapons[weapon_id].name]
		Log.info(msg)
		return msg
	_set_weapon(weapon_id)
	Log.info("Equipped %s (%s)" % [weapon.name, weapon.speed_label])
	stats_changed.emit()
	return ""

## Damage bonus for weapon or skill `w`: points of its stat above the class's start,
## times damage_per_point, scaled by cooldown so slow hits keep up per hit.
func damage_bonus(w: Dictionary) -> float:
	var k := String(w.get("stat", "str"))
	var pts := float(int(stats.get(k, 0)) - int(base_stats.get(k, 0)))
	return pts * float(cfg.damage_per_point) * float(w.cooldown) / float(cfg.level_bonus_reference_cooldown)

## Base damage for one hit with weapon or spell `w` (no crit; Combat rolls crits).
## INT spells cast while holding a staff get its spell_power.
func roll_base_damage(w: Dictionary) -> int:
	var bonus := damage_bonus(w)
	var mult := buff_dmg_mult()
	if w.has("kind") and String(w.get("stat", "")) == "int":
		mult *= float(weapon.get("spell_power", 1.0))
	return int(round(randi_range(int(w.damage_min + bonus), int(w.damage_max + bonus)) * mult))

## Damage range of weapon or skill `w` right now, before crits (stats window).
func damage_range(w: Dictionary) -> Vector2i:
	var bonus := damage_bonus(w)
	var mult := float(weapon.get("spell_power", 1.0)) if w.has("kind") and String(w.get("stat", "")) == "int" else 1.0
	return Vector2i(int(round((float(w.damage_min) + bonus) * mult)), int(round((float(w.damage_max) + bonus) * mult)))

## Average damage per second at the current level and stats, crits included.
func weapon_dps(w: Dictionary) -> float:
	var avg := (float(w.damage_min) + float(w.damage_max)) / 2.0 + damage_bonus(w)
	avg *= 1.0 + crit_chance() * (float(cfg.crit_mult) - 1.0)
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
		ap += int(cfg.get("ap_per_level", 5))
		if auto_assign:
			auto_spend()
		recalc()
		hp = max_hp
		mp = max_mp
		Log.ok("%s Now level %d" % ["Level up!" if display_name == "" else display_name + " leveled up!", level])
		FloatText.spawn(get_parent(), global_position + Vector2(0, -H - 14), "LEVEL UP!", Color("#ffd84a"), 1.6)
	stats_changed.emit()

## Paper-doll layers, back to front. Palette swaps come from `look`; new hair styles,
## hats or outfits are another match arm in draw_doll (or sprites later, same order).
func _draw() -> void:
	# Blink while invulnerable.
	if _invuln > 0.0 and int(_invuln * 12) % 2 == 0:
		return
	draw_doll(self, look, facing)
	# Weapon: idle on the shoulder, swings an arc when attacking.
	var hand := Vector2(facing * 6, -11)
	var length := float(weapon.length)
	var col := Color(weapon.color)
	var tip: Vector2
	if _swing_time > 0.0 and String(weapon.get("motion", "")) == "thrust":
		# Stabs: straight ahead, then angled up, then angled down, punching out and back.
		var t := 1.0 - _swing_time / _swing_len
		var ext := sin(t * PI)
		var ang: float = [0.0, -0.45, 0.4][swings % 3] * facing
		hand += Vector2(facing * ext * 5.0, 0)
		tip = hand + Vector2(facing * length * (0.5 + 0.7 * ext), 0).rotated(ang)
		var streak := hand + Vector2(facing * (length * 1.2 + 6.0), 0).rotated(ang)
		draw_line(tip, tip.lerp(streak, ext), Color(1, 1, 1, 0.35 * ext), 2.0)
	elif _swing_time > 0.0:
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
	draw_weapon_shape(self, weapon_key, weapon, hand, tip)
	_draw_tag()

## Name tag under the feet (MapleStory style). The player has none.
func _draw_tag() -> void:
	if display_name == "" or _font == null:
		return
	var w := _font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
	draw_rect(Rect2(-w / 2.0 - 2, 2, w + 4, 9), Color(0, 0, 0, 0.55))
	draw_string(_font, Vector2(-w / 2.0, 9), display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, tag_color)

## One weapon drawn from hand to tip on any canvas item.
static func draw_weapon_shape(ci: CanvasItem, key: String, w: Dictionary, hand: Vector2, tip: Vector2) -> void:
	var col := Color(w.get("color", "#ffffff"))
	match key:
		"oak_staff":
			var d := (tip - hand).normalized()
			ci.draw_line(hand - d * 4, tip, col, 2.0)
			ci.draw_circle(tip, 2.5, Color(w.get("orb", "#8fd8ff")))
			ci.draw_circle(tip, 1.2, Color(1, 1, 1, 0.8))
		"throwing_kunai":
			ci.draw_line(hand, hand + (tip - hand) * 0.45, col, 2.0)
		"dagger":
			ci.draw_line(hand, tip, col, 2.0)
		"iron_hammer":
			ci.draw_line(hand, tip, Color("#7a5232"), 2.0)
			var d := (tip - hand).normalized()
			var n := Vector2(-d.y, d.x)
			ci.draw_colored_polygon(PackedVector2Array([tip + n * 5 - d * 3, tip + n * 5 + d * 3, tip - n * 5 + d * 3, tip - n * 5 - d * 3]), col)
		_:
			ci.draw_line(hand, tip, col, 3.0)
			var d := (tip - hand).normalized()
			ci.draw_line(hand + d * 3 + Vector2(-d.y, d.x) * 3, hand + d * 3 - Vector2(-d.y, d.x) * 3, Color("#b08a3c"), 2.0)

## Body layers (everything but the weapon) on any canvas item: actors, the class select screen.
static func draw_doll(ci: CanvasItem, lk: Dictionary, face: int) -> void:
	var top := -H
	var hair := Color(lk.get("hair", "#4a3426"))
	var style := String(lk.get("hair_style", "short"))
	# Back hair
	if style == "long":
		ci.draw_rect(Rect2(-7 if face > 0 else 1, top + 1, 6, 13), hair)
	# Legs
	ci.draw_rect(Rect2(-5, -6, 4, 6), Color(lk.get("pants", "#3b4a6b")))
	ci.draw_rect(Rect2(1, -6, 4, 6), Color(lk.get("pants", "#3b4a6b")))
	# Body (shirt)
	ci.draw_rect(Rect2(-6, -15, 12, 10), Color(lk.get("shirt", "#d9534f")))
	# Head
	ci.draw_circle(Vector2(0, top + 6), 6.5, Color(lk.get("skin", "#f2c27b")))
	# Hair
	match style:
		"spiky":
			for k in 4:
				var hx := -7.0 + k * 4.0
				ci.draw_colored_polygon(PackedVector2Array([Vector2(hx, top + 3), Vector2(hx + 2 - face, top - 4), Vector2(hx + 4, top + 3)]), hair)
			ci.draw_rect(Rect2(-7, top, 14, 3), hair)
		_:
			ci.draw_rect(Rect2(-7, top - 1, 14, 4), hair)
			ci.draw_rect(Rect2(-7 if face > 0 else 3, top - 1, 4, 7), hair)
	# Hat
	match String(lk.get("hat", "")):
		"helm":
			ci.draw_rect(Rect2(-7, top - 2, 14, 5), Color("#9aa3ad"))
			ci.draw_rect(Rect2(-1, top - 5, 2, 3), Color("#c43b3b"))
		"band":
			ci.draw_rect(Rect2(-7, top + 1, 14, 2), Color("#e0e0e0"))
			ci.draw_rect(Rect2(-face * 7 - 1, top + 1, 2, 6), Color("#e0e0e0"))
	# Eye
	ci.draw_rect(Rect2(face * 2 - 1, top + 5, 2, 3), Color("#1c1c1c"))

## The weapon at rest on the shoulder (class select screen).
static func draw_idle_weapon(ci: CanvasItem, key: String, w: Dictionary, face: int) -> void:
	var hand := Vector2(face * 6, -11)
	var length := float(w.get("length", 16))
	draw_weapon_shape(ci, key, w, hand, hand + Vector2(face * length * 0.35, -length * 0.85))


