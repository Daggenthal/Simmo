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
signal ultimate_used(actor: Actor, ult_name: String)
signal leveled_up(actor: Actor, new_level: int)

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
## Total damage this actor has dealt (party stats, boss DPS checks, tests).
var damage_dealt := 0

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
var doll: Doll
## True once a look was chosen on purpose (character creator, Simmo roster), so classes don't overwrite it.
var custom_look := false
## Who a support spell (heal) lands on; set by the brain before casting.
var spell_target: Node2D = null
var heals_done := 0
## Timed effects, e.g. "xp": {mult, t, max_t, name, color}. XP buffs of one kind don't stack.
var buffs: Dictionary = {}
# Items: every actor has a bag (the player's starter kit, sims' sim_kit).
var inventory: Inventory
var item_cfg: Dictionary = {}
var items_used := 0
var _item_cd := 0.0
## Name of the map auto-battle is heading to, or "" (shown on the HUD).
var advancing_to := ""

## items: data/items.json. Fills the bag with `kit` ([[item, count], ...]; the starter kit by default).
func setup_items(items: Dictionary, kit = null) -> void:
	item_cfg = items
	inventory = Inventory.new(items.get("items", {}), int(items.get("inventory_slots", 24)))
	for e in (kit if kit != null else items.get("starter_kit", [])):
		inventory.add(String(e[0]), int(e[1]))

## Use one of item `id`. Returns "" on success, or why it couldn't be used.
func use_item(id: String) -> String:
	if inventory == null or inventory.count(id) <= 0:
		return "None left"
	if _item_cd > 0.0:
		return "Not yet"
	if hp <= 0:
		return "Can't use that now"
	var d: Dictionary = inventory.def(id)
	match String(d.get("effect", "")):
		"heal_hp":
			if hp >= max_hp:
				return "HP is full"
			heal(int(d.amount))
		"heal_mp":
			if mp >= max_mp:
				return "MP is full"
			var before := mp
			mp = minf(mp + float(d.amount), max_mp)
			FloatText.spawn(get_parent(), global_position + Vector2(0, -H - 4), "+%d MP" % int(mp - before), Color("#7fb3ff"))
		"xp_buff":
			var cur: Dictionary = buffs.get("xp", {})
			if not cur.is_empty() and float(cur.mult) > float(d.mult):
				return "A stronger XP buff is active"
			buffs["xp"] = {"mult": float(d.mult), "t": float(d.duration), "max_t": float(d.duration), "name": String(d.name), "color": String(d.color)}
			FloatText.spawn(get_parent(), global_position + Vector2(0, -H - 14), "XP +%d%%" % int(round((float(d.mult) - 1.0) * 100.0)), Color(d.color), 1.4)
			Log.ok("%s: %s" % [d.name, d.desc])
		_:
			return "Can't use that"
	inventory.remove(id)
	items_used += 1
	sfx("potion", 0.8)
	_item_cd = float(item_cfg.get("use_cooldown", 0.5))
	stats_changed.emit()
	return ""

## Use the best owned item with `effect` (heal_hp / heal_mp): the smallest one that covers
## what's missing, or the biggest when none does. Returns "" on success or the reason.
func use_best(effect: String) -> String:
	var id := best_item(effect)
	if id == "":
		return "No potions"
	return use_item(id)

func best_item(effect: String) -> String:
	if inventory == null:
		return ""
	var missing := float(max_hp - hp) if effect == "heal_hp" else max_mp - mp
	var best := ""
	var best_amt := 0.0
	for id in inventory.defs:
		var d: Dictionary = inventory.defs[id]
		if String(d.get("effect", "")) != effect or inventory.count(id) <= 0:
			continue
		var amt := float(d.get("amount", 0))
		var better: bool = best == "" \
			or (amt >= missing and (best_amt < missing or amt < best_amt)) \
			or (amt < missing and best_amt < missing and amt > best_amt)
		if better:
			best = id
			best_amt = amt
	return best

## Manual use: show why it didn't work over the player's head.
func use_and_report(result: String) -> void:
	if result != "":
		FloatText.spawn(get_parent(), global_position + Vector2(0, -H - 10), result, Color("#c8c8c8"), 0.9)

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
# Ultimate (60 s cooldown): channel first, then release. Shadow Dance blinks through a queue of mobs.
var ult: Dictionary = {}
var ult_id := ""
var ult_cd := 0.0
var ults_used := 0
var _channel_t := 0.0
var _channel_len := 0.0
var _shadow_queue: Array = []
var _shadow_t := 0.0
var _shadow_home := Vector2.ZERO
var _regen_acc := 0.0
# Speech bubble over the head when a Simmo talks in party chat.
var bubble_text := ""
var _step_t := 0.0
## Which sprite attack animation the current swing or cast plays (PixelLab sprites).
var _action_kind := "attack_slash"
var _was_on_floor := true
var _bubble_t := 0.0
# Zone warp: frozen in place while the rings play; the body fades out (leaving) or in (arriving).
var _warp_t := 0.0
var _warp_len := 1.0
var _warp_in := false
var _dash_sp: Dictionary = {}
var _dash_hit: Array = []
var _classes: Dictionary = {}
var _balance: Dictionary = {}
## Worn gear by slot ("weapon", "ring", "amulet"); {} when empty. See Gear for the item format.
var equipment := {"weapon": {}, "ring": {}, "amulet": {}}

func setup(config: Dictionary, spawn: Vector2, weapon_table: Dictionary = {}, spell_table: Dictionary = {}) -> void:
	cfg = config
	_spell_table = spell_table
	weapons = weapon_table
	allowed_weapons = weapons.keys()
	look = cfg.get("look", {})
	doll = Doll.new(look)
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
	# Class looks are defaults; a look from the character creator (or a Simmo's own) wins.
	if not custom_look:
		look = class_cfg.get("look", look)
	set_look(look)
	_set_spells(skill_ids if not skill_ids.is_empty() else class_cfg.get("spells", []))
	set_ultimate(String(class_cfg.get("ultimate", "")))
	# Healer classes (Priest) heal the party in auto-battle; SimPlayer roles overwrite this.
	if brain:
		brain.role = String(class_cfg.get("role", ""))
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

## Change how this actor looks (character creator, class defaults).
func set_look(lk: Dictionary) -> void:
	look = Doll.normalize(lk)
	if doll == null:
		doll = Doll.new(look)
	else:
		doll.set_look(look)

func set_ultimate(id: String) -> void:
	ult_id = id
	ult = _spell_table.get(id, {})
	ult_cd = 0.0

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

## A stat including worn gear.
func stat(k: String) -> int:
	return int(stats.get(k, 0)) + int(gear_mod(k))

## Sum of one mod over all worn gear.
func gear_mod(key: String) -> float:
	var v := 0.0
	for slot in equipment:
		var it: Dictionary = equipment[slot]
		if not it.is_empty():
			v += float(it.get("mods", {}).get(key, 0))
	return v

func _effect(kind: String) -> float:
	var total := 0.0
	for k in STATS:
		total += float(stat_effects.get(k, {}).get(kind, 0.0)) * stat(k)
	return total

## Wear the gear in inventory slot k. Returns "" or why not. What was worn goes back to the bag.
func equip_slot(k: int) -> String:
	if inventory == null or inventory.slots[k] == null or not inventory.slots[k].has("item"):
		return "Nothing to equip"
	var it: Dictionary = inventory.slots[k].item
	if String(it.get("kind", "")) != "gear":
		return "Can't equip junk"
	if String(it.slot) == "weapon" and not String(it.weapon) in allowed_weapons:
		var owner := class_for_weapon(String(it.weapon))
		return "Only %ss can use that" % String(_classes.get(owner, {}).get("name", "other class"))
	inventory.take_slot(k)
	var old: Dictionary = equipment[String(it.slot)]
	equipment[String(it.slot)] = it
	if not old.is_empty():
		inventory.slots[k] = {"id": "item", "count": 1, "item": old}
	if String(it.slot) == "weapon":
		_set_weapon(String(it.weapon))
	var hp_frac := float(hp) / maxf(max_hp, 1)
	recalc()
	hp = maxi(1, int(round(max_hp * hp_frac)))
	sfx("ui_click")
	stats_changed.emit()
	return ""

## Max HP / MP from level, class multipliers and STR / INT. Keeps current HP and MP where they fit.
func recalc() -> void:
	var hp_mult := float(class_cfg.get("hp_mult", 1.0))
	var mp_mult := float(class_cfg.get("mp_mult", 1.0))
	max_hp = int(round((float(cfg.max_hp) + float(cfg.hp_per_level) * (level - 1)) * hp_mult + _effect("hp") + gear_mod("hp")))
	max_mp = int(round((float(cfg.get("max_mp", 40)) + float(cfg.get("mp_per_level", 0)) * (level - 1)) * mp_mult + _effect("mp") + gear_mod("mp")))
	hp = mini(hp, max_hp)
	mp = minf(mp, max_mp)

func crit_chance() -> float:
	return float(cfg.crit_chance) + _effect("crit") + gear_mod("crit") / 100.0

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
	_item_cd = maxf(_item_cd - delta, 0.0)
	ult_cd = maxf(ult_cd - delta, 0.0)
	_bubble_t = maxf(_bubble_t - delta, 0.0)
	var intent := _get_intent(delta)
	if _warp_t > 0.0 or (not _warp_in and _warp_len > 0.0 and self_modulate.a <= 0.01):
		intent = blank_intent()
		_tick_warp(delta)
	elif _channel_t > 0.0 or not _shadow_queue.is_empty():
		# Channeling or mid Shadow Dance: no moving, attacking or casting.
		intent = blank_intent()
		_tick_ultimate(delta)
	last_intent = intent
	_apply(intent, delta)
	if _dash_t > 0.0:
		_dash_step(delta)
	move_and_slide()
	_footsteps(delta)
	doll.update(delta, global_position, velocity, is_on_floor(), facing)
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
	var top_speed := float(cfg.speed)
	# Wading through a pond is slower.
	if world and is_on_floor() and absf(global_position.y - world.ground_y) < 4.0 and world.water_kind_at(global_position.x) == "pond":
		top_speed *= float(world._balance.get("environment", {}).get("pond_speed", 0.65))
	if dir != 0.0:
		velocity.x = move_toward(velocity.x, dir * top_speed, float(cfg.accel) * control * delta)
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

	if i.get("ult", false):
		cast_ultimate()
	# Spells first: a cast locks out the weapon for the global cooldown, so they can't fire together.
	if i.get("spell", "") != "":
		cast(i.spell)
	if i.attack and _attack_cd <= 0.0:
		attack()

## Start a zone warp: rings play for `duration`; leaving fades the body out, arriving fades it in.
func start_warp(duration: float, arriving: bool, col: Color) -> void:
	_warp_t = duration
	_warp_len = duration
	_warp_in = arriving
	_invuln = maxf(_invuln, duration)
	velocity = Vector2.ZERO
	self_modulate.a = 0.0 if arriving else 1.0
	Fx.warp(self, duration, arriving, col)

func is_warping() -> bool:
	return _warp_t > 0.0

func _tick_warp(delta: float) -> void:
	velocity.x = 0.0
	if _warp_t <= 0.0:
		return
	_warp_t = maxf(_warp_t - delta, 0.0)
	var t := 1.0 - _warp_t / _warp_len
	# Leaving: visible for the first half, then dissolve. Arriving: materialize over the first 60%.
	self_modulate.a = clampf(t / 0.6, 0.0, 1.0) if _warp_in else clampf(1.0 - (t - 0.5) / 0.45, 0.0, 1.0)
	if _warp_t <= 0.0 and _warp_in:
		self_modulate.a = 1.0
		_warp_len = 0.0

## Show `text` in a bubble over the head for a few seconds (party chat lines).
func say(text: String, seconds := 4.0) -> void:
	bubble_text = text
	_bubble_t = seconds

## Sound from this actor: full volume for the player, quieter for everyone else.
func sfx(sound: String, volume := 1.0, pitch := 1.0) -> void:
	Sfx.play(sound, volume * (1.0 if is_in_group("player") else 0.25), pitch)

## Steps while walking on the ground, a hop when leaving it, a thud when landing.
func _footsteps(delta: float) -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor and velocity.y >= 0.0:
		sfx("land", 0.6)
	elif not on_floor and _was_on_floor and velocity.y < -100.0:
		sfx("jump", 0.5)
	_was_on_floor = on_floor
	if on_floor and absf(velocity.x) > 30.0:
		_step_t -= delta
		if _step_t <= 0.0:
			_step_t = 0.28
			sfx("step", 0.45, randf_range(0.85, 1.15))
	else:
		_step_t = 0.0

## The sprite attack animation for the weapon in hand: swords and hammers slash, daggers stab,
## kunai are thrown, staffs and scepters cast.
func sprite_attack() -> String:
	if weapon.get("thrown", false):
		return "attack_throw"
	if String(weapon.get("motion", "")) == "thrust":
		return "attack_stab"
	if weapon.has("spell_power"):
		return "attack_cast"
	return "attack_slash"

## Code-drawn characters hold a drawn weapon; sprites carry their own in the art (in every clip).
func draws_weapon() -> bool:
	return not doll.has_sprite()

func can_ultimate() -> bool:
	return not ult.is_empty() and ult_cd <= 0.0 and mp >= float(ult.get("mp", 0)) and _channel_t <= 0.0 and _shadow_queue.is_empty()

## Start the ultimate: a short channel, then _release_ultimate. Returns true if it started.
func cast_ultimate() -> bool:
	if not can_ultimate():
		return false
	mp -= float(ult.get("mp", 0))
	ult_cd = float(ult.cooldown)
	ults_used += 1
	_channel_len = maxf(float(ult.get("cast_time", 0.3)), 0.05)
	_channel_t = _channel_len
	velocity.x = 0.0
	if String(ult.ult) == "quake":
		velocity.y = -220.0  # the leap
	ultimate_used.emit(self, String(ult.name))
	sfx("ultimate")
	Log.ok("%s: %s!" % ["You" if is_in_group("player") else display_name, ult.name])
	stats_changed.emit()
	return true

func _tick_ultimate(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
	if _channel_t > 0.0:
		_channel_t -= delta
		if _channel_t <= 0.0:
			_release_ultimate()
		return
	_shadow_t -= delta
	if _shadow_t <= 0.0:
		_shadow_step()

func _release_ultimate() -> void:
	var col := Color(ult.color)
	if is_in_group("player"):
		var hud := get_tree().get_first_node_in_group("hud")
		if hud:
			hud.flash(col.lightened(0.4), 0.5)
	match String(ult.ult):
		"cataclysm":
			_ult_cataclysm()
		"quake":
			_ult_quake()
		"shadow":
			_ult_shadow_start()
		"sanctuary":
			_ult_sanctuary()

## Mage: a fire blast in a wide cone in front, then lightning from the sky on every mob on the map.
func _ult_cataclysm() -> void:
	var from := global_position + Vector2(facing * 8, -12)
	var dir := Vector2(facing, 0)
	var length := float(ult.cone_range)
	var half := float(ult.cone_angle)
	Fx.cone(get_parent(), from, dir, length, half, Combat.element_color("fire"))
	var cone_w := {"damage_min": ult.cone_damage_min, "damage_max": ult.cone_damage_max, "cooldown": ult.cooldown, "scale_cooldown": ult.scale_cooldown, "stat": "int", "kind": "ultimate"}
	var k := 0
	for m in get_tree().get_nodes_in_group("mobs"):
		if not m.alive:
			continue
		var to: Vector2 = m.global_position + Vector2(0, -m.size.y / 2.0) - from
		if to.length() <= length and absf(dir.angle_to(to)) <= half:
			Combat.hit(m, self, roll_base_damage(cone_w), "fire", _hit_opts(160.0))
	# Sky strikes land one after another for a rolling wipe across the map.
	for m in get_tree().get_nodes_in_group("mobs"):
		if not m.alive:
			continue
		var delay := 0.05 + 0.035 * k
		k += 1
		get_tree().create_timer(delay, false, true).timeout.connect(func() -> void:
			if is_instance_valid(m) and m.alive and is_instance_valid(self):
				var top: Vector2 = m.global_position + Vector2(randf_range(-20, 20), -260)
				Fx.lightning(m.get_parent(), top, m.global_position + Vector2(0, -m.size.y / 2.0), Color(ult.color))
				Fx.burst(m.get_parent(), m.global_position + Vector2(0, -m.size.y / 2.0), 14.0, Color(ult.color))
				Combat.hit(m, self, roll_base_damage(ult), "lightning", _hit_opts(60.0)))

## Warrior: quake that hits and stuns every mob nearby on your level, then Berserk.
func _ult_quake() -> void:
	var r := float(ult.radius)
	Fx.burst(get_parent(), global_position, r * 0.5, Color(ult.color))
	Fx.burst(get_parent(), global_position, r, Color(ult.color).darkened(0.2))
	for m in get_tree().get_nodes_in_group("mobs"):
		if m.alive and absf(m.global_position.x - global_position.x) <= r and absf(m.global_position.y - global_position.y) < 40.0:
			var o := _hit_opts(0.0)
			Combat.hit(m, self, roll_base_damage(ult), "physical", o)
			if m.alive:
				m.apply_stun(float(ult.stun))
	buffs["berserk"] = {"name": "Berserk", "t": float(ult.berserk_time), "max_t": float(ult.berserk_time), "color": String(ult.color),
		"dmg_mult": float(ult.berserk_mult), "label": "+%d%% damage" % int(round((float(ult.berserk_mult) - 1.0) * 100.0))}

## Rogue: vanish, then blink to up to N nearby mobs (closest first), striking each a few times.
func _ult_shadow_start() -> void:
	_shadow_home = global_position
	var near: Array = []
	for m in get_tree().get_nodes_in_group("mobs"):
		if m.alive and m.global_position.distance_to(global_position) <= float(ult.range):
			near.append(m)
	near.sort_custom(func(a, b): return a.global_position.distance_to(global_position) < b.global_position.distance_to(global_position))
	_shadow_queue = near.slice(0, int(ult.targets))
	_shadow_queue.append(null)  # last step: back home
	_shadow_t = 0.0
	modulate = Color(0.55, 0.45, 1.0, 0.55)
	_invuln = maxf(_invuln, float(ult.step_time) * _shadow_queue.size() + 0.3)

func _shadow_step() -> void:
	_shadow_t = float(ult.step_time)
	var m = _shadow_queue.pop_front()
	Fx.afterimage(get_parent(), global_position, Color(ult.color))
	if m == null or not is_instance_valid(m):
		global_position = _shadow_home
		velocity = Vector2.ZERO
		reset_physics_interpolation()
		modulate = Color.WHITE
		_shadow_queue.clear()
		return
	if not m.alive:
		return
	var side := -1.0 if randf() < 0.5 else 1.0
	global_position = Vector2(m.global_position.x + side * (m.size.x / 2.0 + 8.0), m.global_position.y)
	velocity = Vector2.ZERO
	reset_physics_interpolation()
	facing = 1 if m.global_position.x >= global_position.x else -1
	_swing_time = 0.12
	_swing_len = 0.12
	for h in int(ult.hits):
		if m.alive:
			Combat.hit(m, self, roll_base_damage(ult), "physical", _hit_opts(0.0))

## Healer: full heal for the party plus a few seconds of regeneration.
func _ult_sanctuary() -> void:
	Fx.burst(get_parent(), global_position + Vector2(0, -12), 70.0, Color(ult.color))
	var party: Array = world.party if world else [self]
	for m in party:
		if is_instance_valid(m) and m.is_inside_tree() and m.is_alive():
			m.heal(m.max_hp)
			m.buffs["sanctuary"] = {"name": "Sanctuary", "t": float(ult.regen_time), "max_t": float(ult.regen_time), "color": String(ult.color),
				"regen": float(ult.regen), "label": "+%d HP/s" % int(ult.regen)}
			Fx.burst(m.get_parent(), m.global_position + Vector2(0, -12), 18.0, Color(ult.color))

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
	_action_kind = "attack_cast"
	var cast_sound := "cast_%s" % String(sp.element)
	if Sfx.has_method("_gen_" + cast_sound):
		sfx(cast_sound, 0.7)
	else:
		sfx("swing", 0.8, 0.8)
	if String(sp.kind) in ["heal", "hot", "party_heal"]:
		match String(sp.kind):
			"heal":
				_cast_heal(sp)
			"hot":
				_cast_renew(sp)
			"party_heal":
				_cast_prayer(sp)
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
				var aim_at := lead(from, target, float(sp.speed)) if target else from + Vector2(facing * float(sp.range) * 0.7, 16)
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
		var aim := lead(from, target, float(sp.throw_speed)) if target else from + Vector2(facing * float(sp.range) * 0.6, 10)
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

## Who a heal lands on: the brain's pick, or (cast by hand) the most hurt party member in range.
func _heal_target(sp: Dictionary) -> Node2D:
	if is_instance_valid(spell_target) and spell_target.is_alive():
		var t := spell_target
		spell_target = null
		return t
	var best: Node2D = self
	var best_frac := float(hp) / maxf(max_hp, 1)
	if world:
		for m in world.party:
			if is_instance_valid(m) and m.is_inside_tree() and m.is_alive() and m.global_position.distance_to(global_position) <= float(sp.get("range", 170.0)):
				var fr := float(m.hp) / maxf(m.max_hp, 1)
				if fr < best_frac:
					best_frac = fr
					best = m
	return best

## Heal per level and staff: heal_min..heal_max + heal_per_level per level, times the weapon's spell_power.
func heal_amount(sp: Dictionary) -> int:
	var base := randi_range(int(sp.get("heal_min", 0)), int(sp.get("heal_max", 0))) + (level - 1) * int(sp.get("heal_per_level", 0))
	return int(round(base * float(weapon.get("spell_power", 1.0))))

## Renew: heal over time on one ally (a regen buff that ticks once a second).
func _cast_renew(sp: Dictionary) -> void:
	var who: Node2D = _heal_target(sp)
	var total := (float(sp.heal_total) + (level - 1) * float(sp.get("heal_total_per_level", 0))) * float(weapon.get("spell_power", 1.0))
	var dur := float(sp.duration)
	who.buffs["renew"] = {"name": "Renew", "t": dur, "max_t": dur, "color": String(sp.color), "regen": total / dur, "label": "+%d HP/s" % int(round(total / dur))}
	heals_done += 1
	if who != self:
		facing = 1 if who.global_position.x >= global_position.x else -1
	Fx.burst(get_parent(), who.global_position + Vector2(0, -12), 12.0, Color(sp.color))

## Prayer: heal everyone in the party within reach.
func _cast_prayer(sp: Dictionary) -> void:
	Fx.burst(get_parent(), global_position + Vector2(0, -12), float(sp.radius) * 0.5, Color(sp.color))
	var party: Array = world.party if world else [self]
	for m in party:
		if is_instance_valid(m) and m.is_inside_tree() and m.is_alive() and m.global_position.distance_to(global_position) <= float(sp.radius):
			m.heal(heal_amount(sp))
			Fx.burst(m.get_parent(), m.global_position + Vector2(0, -12), 10.0, Color(sp.color))
	heals_done += 1

## Heal the spell target (or the most hurt ally in range).
func _cast_heal(sp: Dictionary) -> void:
	var who: Node2D = _heal_target(sp)
	who.heal(heal_amount(sp))
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
	_action_kind = sprite_attack()
	sfx("swing", 0.5, randf_range(0.9, 1.15) * (0.8 if float(weapon.cooldown) > 1.0 else 1.0))
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
		pr.velocity = Projectile.lob_velocity(from, lead(from, target, spd), spd, g)
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

## Where to aim a slow arcing shot at `t` so it lands where the target will be (its middle, led by
## its walking speed over the flight time). Kept on its platform, so a lead never aims off a ledge.
func lead(from: Vector2, t: Mob, speed: float) -> Vector2:
	var aim := t.global_position + Vector2(0, -t.size.y / 2.0)
	var flight := absf(aim.x - from.x) / maxf(speed, 1.0)
	var ahead := clampf(t.velocity.x * flight, -60.0, 60.0)
	aim.x = clampf(aim.x + ahead, t.bound_x0, t.bound_x1) if t.bound_x0 > -INF else aim.x + ahead
	return aim

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
	var pts := float(stat(k) - int(base_stats.get(k, 0)))
	return pts * float(cfg.damage_per_point) * float(w.get("scale_cooldown", w.cooldown)) / float(cfg.level_bonus_reference_cooldown)

## Base damage for one hit with weapon or spell `w` (no crit; Combat rolls crits).
## INT spells cast while holding a staff get its spell_power.
func roll_base_damage(w: Dictionary) -> int:
	var bonus := damage_bonus(w)
	var mult := buff_dmg_mult() * (1.0 + gear_mod("damage") / 100.0)
	if w.has("kind") and String(w.get("stat", "")) == "int":
		mult *= float(weapon.get("spell_power", 1.0))
	return int(round(randi_range(int(w.damage_min + bonus), int(w.damage_max + bonus)) * mult))

## Damage range of weapon or skill `w` right now, before crits (stats window).
func damage_range(w: Dictionary) -> Vector2i:
	var bonus := damage_bonus(w)
	var mult := float(weapon.get("spell_power", 1.0)) if w.has("kind") and String(w.get("stat", "")) == "int" else 1.0
	mult *= buff_dmg_mult() * (1.0 + gear_mod("damage") / 100.0)
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
	sfx("player_hurt", 0.8)
	doll.jolt(5.0)
	velocity = Vector2(sign(global_position.x - from_x) * 140.0, -150.0)
	FloatText.spawn(get_parent(), global_position + Vector2(0, -H - 4), str(amount), Color("#ff6b6b"))
	stats_changed.emit()
	if hp <= 0:
		_on_death()

## Out of HP. The player respawns at the map's spawn point; SimPlayer overrides this.
func _on_death() -> void:
	Log.warn("%s died at level %d, respawning" % [display_name if display_name != "" else "You", level])
	died.emit()
	_respawn()

func _respawn() -> void:
	hp = max_hp
	mp = max_mp
	position = world.spawn_point if world else _spawn_point
	velocity = Vector2.ZERO
	reset_physics_interpolation()
	_invuln = 2.0
	brain.reset()
	stats_changed.emit()

## Placed on a new map (portal travel).
func arrive(pos: Vector2) -> void:
	position = pos
	velocity = Vector2.ZERO
	reset_physics_interpolation()
	_warp_t = 0.0
	self_modulate.a = 1.0
	_spawn_point = pos
	_nav_reset()
	brain.reset()

func _nav_reset() -> void:
	_drop_timer = 0.0
	set_collision_mask_value(LAYER_PLATFORMS, true)

func _tick_buffs(delta: float) -> void:
	# Heals over time (Renew, Sanctuary) tick once a second, each showing a small green number.
	var regen := 0.0
	for k in buffs:
		regen += float(buffs[k].get("regen", 0.0))
	if regen > 0.0:
		_regen_acc += delta
		if _regen_acc >= 1.0:
			_regen_acc -= 1.0
			if hp > 0 and hp < max_hp:
				var before := hp
				hp = mini(hp + int(round(regen)), max_hp)
				FloatText.spawn(get_parent(), global_position + Vector2(randf_range(-4, 4), -H - 2), "+%d" % (hp - before), Color("#b6ff9d"), 0.7)
				stats_changed.emit()
	else:
		_regen_acc = 0.0
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
		leveled_up.emit(self, level)
		sfx("level_up")
		Log.ok("%s Now level %d" % ["Level up!" if is_in_group("player") else display_name + " leveled up!", level])
		FloatText.spawn(get_parent(), global_position + Vector2(0, -H - 14), "LEVEL UP!", Color("#ffd84a"), 1.6)
	stats_changed.emit()

## Paper-doll layers, back to front. Palette swaps come from `look`; new hair styles,
## hats or outfits are another match arm in draw_doll (or sprites later, same order).
func _draw() -> void:
	# Blink while invulnerable.
	if _invuln > 0.0 and int(_invuln * 12) % 2 == 0:
		return
	if _channel_t > 0.0:
		_draw_channel()
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
	if _regen_t_visual():
		_draw_regen()
	doll.action = {"kind": _action_kind, "t": 1.0 - _swing_time / maxf(_swing_len, 0.01)} if _swing_time > 0.0 else {}
	doll.draw(self, hand)
	if not draws_weapon():
		# The sprite holds its own weapon, so no drawn weapon on top. Melee swings get a trail that
		# fades out (the clips can hide the blade mid-swing); casts and throws show their projectile.
		if _swing_time > 0.0 and _action_kind in ["attack_slash", "attack_stab"]:
			var sw := 1.0 - _swing_time / _swing_len
			var trail := Color(1, 1, 1, 0.6 * (1.0 - sw))
			if _action_kind == "attack_stab":
				var x0 := 6.0 + 10.0 * sw
				draw_line(Vector2(facing * x0, -11), Vector2(facing * (x0 + 12.0), -11), trail, 2.0, true)
			else:
				var a0 := -PI / 2 * facing + (0.0 if facing > 0 else PI)
				draw_arc(Vector2(facing * 4, -12), 14.0, a0, a0 + PI * sw * facing, 10, trail, 2.0, true)
	else:
		draw_weapon_shape(self, weapon_key, weapon, hand, tip)
	doll.draw_hand(self, hand)
	_draw_tag()
	_draw_bubble()

## Ultimate channel: a magic circle that grows under the feet, runes turning, sparks rising.
func _draw_channel() -> void:
	var col := Color(ult.get("color", "#ffffff"))
	var t := 1.0 - _channel_t / _channel_len
	var r := 8.0 + 22.0 * t
	var spin := Time.get_ticks_msec() / 300.0
	draw_set_transform(Vector2(0, 0), 0.0, Vector2(1.0, 0.35))
	draw_arc(Vector2.ZERO, r, 0, TAU, 32, Color(col, 0.9), 2.0)
	draw_arc(Vector2.ZERO, r * 0.7, spin, spin + PI * 1.5, 24, Color(col.lightened(0.3), 0.8), 1.5)
	for k in 6:
		var a := spin * 0.6 + k * TAU / 6.0
		draw_rect(Rect2(Vector2(cos(a), sin(a)) * r - Vector2(1.5, 1.5), Vector2(3, 3)), col.lightened(0.5))
	draw_set_transform(Vector2.ZERO)
	for k in 5:
		var ph := fmod(t * 3.0 + k * 0.2, 1.0)
		draw_rect(Rect2(Vector2(-10 + k * 5, -ph * 34.0), Vector2(2, 2)), Color(col.lightened(0.4), 1.0 - ph))
	draw_circle(Vector2(facing * 8, -14), 3.0 + 3.0 * t, Color(col, 0.6))

func _regen_t_visual() -> bool:
	for b in buffs.values():
		if float(b.get("regen", 0.0)) > 0.0:
			return true
	return false

## Heal over time: soft green motes rising around the body.
func _draw_regen() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for k in 6:
		var ph := fmod(t * 0.8 + k * 0.17, 1.0)
		var x := sin(k * 2.4 + t) * 7.0
		draw_circle(Vector2(x, -2.0 - ph * 26.0), 1.1 * (1.0 - ph * 0.5), Color(0.7, 1.0, 0.6, 0.85 * (1.0 - ph)))

## Speech bubble: white box over the head, wrapped to two lines, fading out at the end.
func _draw_bubble() -> void:
	if _bubble_t <= 0.0 or bubble_text == "" or _font == null:
		return
	# Stack over neighbors who are talking too, so bubbles don't cover each other.
	var stack := 0
	for o in get_tree().get_nodes_in_group("actors"):
		if o != self and o._bubble_t > 0.0 and absf(o.global_position.x - global_position.x) < 70.0 and o.get_instance_id() < get_instance_id():
			stack += 1
	var a := clampf(_bubble_t / 0.4, 0.0, 1.0)
	var max_w := 96.0
	var words := bubble_text.split(" ")
	var lines: Array = [""]
	for w in words:
		var test: String = w if lines[-1] == "" else lines[-1] + " " + w
		if _font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x > max_w and lines[-1] != "":
			if lines.size() == 2:
				lines[-1] += "..."
				break
			lines.append(w)
		else:
			lines[-1] = test
	var w := 0.0
	for l in lines:
		w = maxf(w, _font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x)
	var h := lines.size() * 9.0 + 4.0
	var r := Rect2(-w / 2.0 - 4, -H - 14 - h - stack * (h + 3.0), w + 8, h)
	draw_rect(r, Color(1, 1, 1, 0.92 * a))
	draw_rect(r, Color(0.2, 0.25, 0.35, a), false, 1.0)
	draw_colored_polygon(PackedVector2Array([Vector2(-3, r.end.y), Vector2(3, r.end.y), Vector2(0, r.end.y + 4)]), Color(1, 1, 1, 0.92 * a))
	for k in lines.size():
		draw_string(_font, Vector2(r.position.x + 4, r.position.y + 10 + k * 9), lines[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.1, 0.12, 0.2, a))

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

## A preview of a doll holding weapon `key`, drawn at `at`, `zoom` times bigger (menus).
static func draw_preview(ci: CanvasItem, d: Doll, key: String, w: Dictionary, at: Vector2, zoom: float) -> void:
	var face := d.facing
	var hand := Vector2(face * 6, -12)
	d.draw(ci, hand, at, zoom)
	if not w.is_empty() and not d.has_sprite():
		ci.draw_set_transform(at, 0.0, Vector2(zoom, zoom))
		var length := float(w.get("length", 16))
		draw_weapon_shape(ci, key, w, hand, hand + Vector2(face * length * 0.35, -length * 0.85))
		ci.draw_set_transform(Vector2.ZERO)
	d.draw_hand(ci, hand, at, zoom)

## The weapon at rest on the shoulder (class select screen).
static func draw_idle_weapon(ci: CanvasItem, key: String, w: Dictionary, face: int) -> void:
	var hand := Vector2(face * 6, -11)
	var length := float(w.get("length", 16))
	draw_weapon_shape(ci, key, w, hand, hand + Vector2(face * length * 0.35, -length * 0.85))


