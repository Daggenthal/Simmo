extends SceneTree
## Headless class test: the class select screen, class weapon locks, stats and AP,
## every class skill, and auto-battle walking to the next map once you reach its level.
## Run: godot --headless --fixed-fps 60 --path . --script res://tests/class_test.gd

var _main
var _log
var _frame := 0
var _pf := 0
var _phase := "boot"
var _failures := 0
var _bal: Dictionary
var _m = null
var _n = null
var _hp0 := 0
var _x0 := 0.0
var _hits := 0
var _last_hp := 0

func _initialize() -> void:
	_log = root.get_node("Log")
	var env_seed := OS.get_environment("SIMMO_SEED")
	seed(int(env_seed) if env_seed != "" else 5150)
	_main = load("res://main.tscn").instantiate()
	_main.spawn_sims = false
	root.add_child(_main)  # start screen on (the default)

func _check(cond: bool, msg: String) -> void:
	if cond:
		_log.ok("PASS " + msg)
	else:
		_failures += 1
		_log.error("FAIL " + msg)

func _goto(p: String) -> void:
	_phase = p
	_pf = 0

func _key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)

func _click(ctrl, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	ctrl._gui_input(ev)

func _park_all() -> void:
	var world = _main.world
	world._respawn_queue.clear()
	for m in world.mobs:
		m.alive = false
		m.visible = false
		m.set_physics_process(false)
		m.clear_statuses()

func _dummy(idx: int, pos: Vector2, hp := 100000):
	var world = _main.world
	var m = world.mobs[idx]
	m.data = m.data.duplicate()
	m.data.speed = 0.0
	m.data.hop_velocity = 0.0
	m.data.touch_damage = 0
	m.data.knockback_mult = 0.0
	m.home = pos
	m.max_hp = hp
	m.set_bounds(world.nav)
	m.respawn()
	return m

func _place(p, pos: Vector2, face := 1) -> void:
	p.position = pos
	p.velocity = Vector2.ZERO
	p.facing = face

func _ready_to_cast(p) -> void:
	p._cast_cd = 0.0
	p._attack_cd = 0.0
	p.mp = p.max_mp
	for k in p.spell_cd:
		p.spell_cd[k] = 0.0

func _physics_process(_d: float) -> bool:
	_frame += 1
	_pf += 1
	var p = _main.player
	match _phase:
		"boot":
			if _pf == 3:
				_check(_main.start_screen != null and _main.player == null, "game opens on the class select screen")
				_bal = _main.balance
				var ss = _main.start_screen
				_check(ss.ids.size() == 3, "three classes to pick from (%s)" % str(ss.ids))
				_key(KEY_3)
			if _pf == 6:
				var ss = _main.start_screen
				_check(ss.class_id() == "rogue", "3 selects the Rogue (%s)" % ss.class_id())
				# Click the Mage card once (select), then again (start).
				var mage: int = ss.ids.find("mage")
				_click(ss, ss.card_rect(mage).get_center())
				_check(ss.class_id() == "mage", "clicking a card selects it")
				_check(_main.player == null, "one click only selects, it doesn't start yet")
				_click(ss, ss.card_rect(mage).get_center())
			if _pf == 10:
				_check(p != null and p.class_id == "mage", "clicking the selected card starts as that class (%s)" % (p.class_id if p else "none"))
				_check(p.weapon_key == "oak_staff", "a Mage starts with the Oak Staff (%s)" % p.weapon_key)
				_check(p.spells.keys() == _bal.classes.mage.spells, "a Mage gets the Mage skills (%s)" % str(p.spells.keys()))
				_check(_main.start_screen == null, "the select screen is gone")
				_park_all()
				_check_weapons(p)
				_check_stats(p)
				_goto("skills_warrior")
		"skills_warrior":
			_skills_warrior(p)
		"skills_rogue":
			_skills_rogue(p)
		"advance":
			_advance(p)
		"done":
			if _failures == 0:
				_log.ok("ALL CLASS CHECKS PASSED (%d frames)" % _frame)
			else:
				_log.error("%d CLASS CHECK(S) FAILED" % _failures)
			quit(1 if _failures > 0 else 0)
	if _frame > 6000:
		_log.error("timeout in phase " + _phase)
		quit(1)
	return false

func _check_weapons(p) -> void:
	var r: String = p.equip("short_sword")
	_check(r != "" and p.weapon_key == "oak_staff", "a Mage can't equip a Short Sword (%s)" % r)
	p.set_class(_bal, "warrior")
	_check(p.weapon_key == "short_sword", "a Warrior starts with the Short Sword")
	_check(p.equip("oak_staff") != "" and p.weapon_key == "short_sword", "only Mages can use staffs")
	_check(p.equip("iron_hammer") == "" and p.weapon_key == "iron_hammer", "a Warrior can switch to the Iron Hammer")
	p.set_class(_bal, "rogue")
	_check(p.weapon_key == "dagger" and p.allowed_weapons.has("throwing_kunai") and not p.allowed_weapons.has("iron_hammer"), "a Rogue gets the dagger and kunai, not the hammer")
	_check(String(_bal.weapons.dagger.get("motion", "")) == "thrust", "daggers stab instead of swinging an arc")
	# Every class fills all four skill slots.
	for c in _bal.classes:
		_check(_bal.classes[c].spells.size() == 4, "%s has 4 skills (%s)" % [_bal.classes[c].name, str(_bal.classes[c].spells)])

func _check_stats(p) -> void:
	p.set_class(_bal, "warrior")
	p.set_level(1)
	var st: Dictionary = _bal.classes.warrior.stats
	_check(p.stats.str == int(st.str) and p.ap == 0, "Warrior starts with %d STR and no free AP" % int(st.str))
	var dmg1: Vector2i = p.damage_range(p.weapon)
	var hp1: int = p.max_hp
	p.gain_xp(p.xp_to_next())
	_check(p.level == 2 and p.stats.str == int(st.str) + 4 and p.stats.dex == int(st.dex) + 1 and p.ap == 0, "level up: auto-assign spends 5 AP as 4 STR + 1 DEX (STR %d)" % p.stats.str)
	var dmg2: Vector2i = p.damage_range(p.weapon)
	_check(dmg2.x == dmg1.x + 5 and dmg2.y == dmg1.y + 5, "4 STR adds 5 damage to the Short Sword (%d-%d -> %d-%d)" % [dmg1.x, dmg1.y, dmg2.x, dmg2.y])
	_check(p.max_hp > hp1, "STR and the level raise max HP (%d -> %d)" % [hp1, p.max_hp])
	p.auto_assign = false
	p.gain_xp(p.xp_to_next())
	_check(p.ap == 5, "with auto-assign off, AP waits to be spent (%d)" % p.ap)
	var luk0: int = p.stats.luk
	var c0: float = p.crit_chance()
	var ui = _main.stats_ui
	ui.visible = true
	ui.size = Vector2(ui.W, 200)
	_click(ui, ui.plus_rect(3).get_center())
	_check(p.stats.luk == luk0 + 1 and p.ap == 4 and p.crit_chance() > c0, "clicking + on LUK spends 1 AP and raises crit (%.2f%% -> %.2f%%)" % [c0 * 100, p.crit_chance() * 100])
	_click(ui, ui.auto_rect().get_center())
	_check(p.auto_assign and p.ap == 0, "turning auto-assign back on spends what's left")
	ui.visible = false
	# Staffs boost INT spells.
	p.set_class(_bal, "mage")
	p.set_level(1)
	var fb: Dictionary = _bal.spells.fireball
	_check(p.damage_range(fb).x == int(round(float(fb.damage_min) * 1.2)), "the Oak Staff adds 20%% spell damage (Fireball min %d -> %d)" % [fb.damage_min, p.damage_range(fb).x])
	# Number keys pick from your class's weapons.
	p.set_class(_bal, "warrior")
	var ev := InputEventAction.new()
	ev.action = "weapon_2"
	ev.pressed = true
	_main._unhandled_input(ev)
	_check(p.weapon_key == "iron_hammer", "2 picks the class's second weapon (Iron Hammer)")

func _skills_warrior(p) -> void:
	if _pf == 1:
		p.set_class(_bal, "warrior")
		p.set_level(5)
		_place(p, Vector2(600, 330))
		_m = _dummy(0, Vector2(625, 329))
		_n = _dummy(1, Vector2(570, 329))
		_ready_to_cast(p)
		_hp0 = _m.hp
		_check(p.cast("power_strike") and _m.hp < _hp0, "Power Strike hits the mob in front (%d dmg)" % (_hp0 - _m.hp))
		_check(_n.hp == _n.max_hp, "Power Strike doesn't hit behind you")
	if _pf == 5:
		_ready_to_cast(p)
		var a0: int = _m.hp
		var b0: int = _n.hp
		_check(p.cast("ground_slam") and _m.hp < a0 and _n.hp < b0, "Ground Slam hits mobs on both sides")
	if _pf == 8:
		_ready_to_cast(p)
		var r0: Vector2i = p.damage_range(p.weapon)
		_check(p.cast("war_cry") and is_equal_approx(p.buff_dmg_mult(), 1.25), "War Cry: +25%% damage buff (x%.2f)" % p.buff_dmg_mult())
	if _pf == 10:
		# Charge: dash 90 px forward through a mob.
		_park_all()
		_place(p, Vector2(500, 330))
		_m = _dummy(0, Vector2(550, 329))
		_ready_to_cast(p)
		_hp0 = _m.hp
		_x0 = p.position.x
		p.cast("charge")
	if _pf == 40:
		_check(p.position.x - _x0 > 60.0, "Charge dashes forward (%.0f px)" % (p.position.x - _x0))
		_check(_m.hp < _hp0, "Charge hits the mob in its path (%d dmg)" % (_hp0 - _m.hp))
		_goto("skills_rogue")

func _skills_rogue(p) -> void:
	if _pf == 1:
		_park_all()
		p.set_class(_bal, "rogue")
		p.set_level(5)
		_place(p, Vector2(600, 330))
		_m = _dummy(0, Vector2(622, 329))
		_ready_to_cast(p)
		_hits = 0
		_last_hp = _m.hp
		p.cast("flurry")
	if _pf >= 1 and _pf <= 40 and _m.hp < _last_hp:
		_hits += 1
		_last_hp = _m.hp
	if _pf == 40:
		_check(_hits == 3, "Flurry stabs 3 times (%d hits)" % _hits)
		# Haste: faster attacks.
		_ready_to_cast(p)
		p.attack()
		var cd0: float = p._attack_cd
		_ready_to_cast(p)
		p.cast("haste")
		p._attack_cd = 0.0
		p.attack()
		_check(p._attack_cd < cd0 * 0.8, "Haste speeds up attacks (%.2fs -> %.2fs)" % [cd0, p._attack_cd])
		# Lucky Seven at a mob 110 px away.
		_park_all()
		_place(p, Vector2(500, 330))
		_m = _dummy(0, Vector2(610, 329))
		_hp0 = _m.hp
		_hits = 0
		_last_hp = _m.hp
		_ready_to_cast(p)
		p.cast("lucky_seven")
	if _pf > 40 and _m.hp < _last_hp:
		_hits += 1
		_last_hp = _m.hp
	if _pf == 140:
		_check(_hits == 2, "Lucky Seven lands 2 kunai on a mob 110 px away (%d hits)" % _hits)
		_goto("advance")

func _advance(p) -> void:
	var world = _main.world
	if _pf == 1:
		# Level 5, mobs out of the way: auto-battle must stay put.
		p.set_class(_bal, "warrior")
		p.set_level(5)
		_park_all()
		_place(p, Vector2(400, 330))
		p.set_auto_battle(true)
	if _pf == 300:
		_check(world.map_id == "mossy_meadow" and p.advancing_to == "", "below the next map's level, auto-battle stays (%s)" % world.map_id)
		p.set_level(6)
	if _pf > 300 and world.map_id == "mushroom_grove" and _x0 >= 0.0:
		_check(true, "at level 6 auto-battle walks to the portal and enters Mushroom Grove (%.1fs)" % ((_pf - 300) / 60.0))
		_check(_main.hud.warning_text == "", "no under-level warning on arrival")
		_x0 = -1.0
	if _pf == 1500:
		if _x0 >= 0.0:
			_check(false, "at level 6 auto-battle walks to the portal and enters Mushroom Grove (still in %s at x=%.0f)" % [world.map_id, p.position.x])
		p.set_auto_battle(false)
	if _pf == 1560:
		_check(world.map_id == "mushroom_grove", "it doesn't walk back to the lower map")
		# Auto-battle off: no auto travel.
		world.load_map("mossy_meadow")
		p.arrive(world.spawn_point)
	if _pf == 1800:
		_check(world.map_id == "mossy_meadow", "without auto-battle you stay where you are")
		_goto("done")
