extends SceneTree
## Headless test for ultimates and the mage's ranged play.
## Run: godot --headless --fixed-fps 60 --path . --script res://tests/combat_ai_test.gd

var _main
var _log
var _frame := 0
var _pf := 0
var _phase := "boot"
var _failures := 0
var _bal: Dictionary
var _m = null
var _mobs: Array = []
var _hp0: Array = []
var _x0 := 0.0
var _min_d := 9999.0
var _swings0 := 0
var _casts0 := 0
var Comb

func _initialize() -> void:
	_log = root.get_node("Log")
	var env_seed := OS.get_environment("SIMMO_SEED")
	seed(int(env_seed) if env_seed != "" else 8080)
	Comb = load("res://scripts/combat.gd")
	_main = load("res://main.tscn").instantiate()
	_main.load_user_settings = false
	_main.show_start_screen = false
	_main.start_class = "mage"
	_main.spawn_sims = false
	root.add_child(_main)

func _check(cond: bool, msg: String) -> void:
	if cond:
		_log.ok("PASS " + msg)
	else:
		_failures += 1
		_log.error("FAIL " + msg)

func _goto(p: String) -> void:
	_phase = p
	_pf = 0

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

func _physics_process(_d: float) -> bool:
	_frame += 1
	_pf += 1
	var p = _main.player
	match _phase:
		"boot":
			if _pf == 5:
				_bal = _main.balance
				for c in _bal.classes:
					var u: Dictionary = _bal.spells.get(String(_bal.classes[c].get("ultimate", "")), {})
					_check(not u.is_empty() and is_equal_approx(float(u.cooldown), 60.0), "%s has an ultimate with a 60 s cooldown (%s)" % [_bal.classes[c].name, u.get("name", "none")])
				_check(load("res://scripts/hud.gd").cd_label(12.3) == "13" and load("res://scripts/hud.gd").cd_label(0.42) == "0.4" and load("res://scripts/hud.gd").cd_label(0.0) == "",
					"cooldown timers read 13, then 0.4 under a second, blank when ready")
				_goto("mage_range")
		"mage_range":
			# One sturdy mob 260 px away: the mage should close to casting range, not melee range.
			if _pf == 1:
				_park_all()
				p.set_level(5)
				_place(p, Vector2(400, 330))
				_m = _dummy(0, Vector2(660, 329))
				_swings0 = p.swings
				_casts0 = p.casts
				_min_d = 9999.0
				p.set_auto_battle(true)
			if _pf > 90:
				_min_d = minf(_min_d, absf(_m.position.x - p.position.x))
			if _pf == 480:
				var d := absf(_m.position.x - p.position.x)
				_check(p.casts - _casts0 >= 3, "the mage casts spells at the target (%d casts in 8 s)" % (p.casts - _casts0))
				_check(_min_d >= 60.0 and d <= 160.0, "the mage fights from range (closest %.0f px, now %.0f px)" % [_min_d, d])
				# All spells on cooldown: only then walk in and use the staff.
				for k in p.spell_cd:
					p.spell_cd[k] = 30.0
				_swings0 = p.swings
			if _pf == 780:
				_check(p.swings > _swings0 and absf(_m.position.x - p.position.x) < 50.0, "with every spell on cooldown the mage walks in and melees (%d swings)" % (p.swings - _swings0))
				for k in p.spell_cd:
					p.spell_cd[k] = 0.0
				p.mp = p.max_mp
			if _pf == 1080:
				_check(absf(_m.position.x - p.position.x) > 60.0, "once spells are back it steps away again (%.0f px)" % absf(_m.position.x - p.position.x))
				p.set_auto_battle(false)
				_goto("cataclysm")
		"cataclysm":
			if _pf == 1:
				_park_all()
				_place(p, Vector2(400, 330), 1)
				_mobs = [_dummy(0, Vector2(470, 329)), _dummy(1, Vector2(1500, 329)), _dummy(2, Vector2(1010, 207))]
				_hp0 = _mobs.map(func(m): return m.hp)
				p.mp = p.max_mp
				p.ult_cd = 0.0
				_check(p.cast_ultimate(), "G starts Arcane Cataclysm")
				_check(p._channel_t > 0.5, "with a channel (%.1fs)" % p._channel_t)
			if _pf == 10:
				_check(_mobs[0].hp == _hp0[0], "nothing is hit during the channel")
			if _pf == 150:
				var hit := 0
				for k in _mobs.size():
					if _mobs[k].hp < _hp0[k]:
						hit += 1
				_check(hit == 3, "Arcane Cataclysm hits every mob on the map, even 1100 px away and up on a platform (%d of 3)" % hit)
				_check(_mobs[0].hp < _mobs[1].hp, "the mob in the fire cone takes extra damage")
				_check(not p.can_ultimate() and p.ult_cd > 50.0, "then it's on a 60 s cooldown (%.0fs left)" % p.ult_cd)
				_goto("quake")
		"quake":
			if _pf == 1:
				_park_all()
				p.set_class(_bal, "warrior")
				p.set_level(5)
				_place(p, Vector2(600, 330))
				_mobs = [_dummy(0, Vector2(500, 329)), _dummy(1, Vector2(720, 329))]
				_hp0 = _mobs.map(func(m): return m.hp)
				p.cast_ultimate()
			if _pf == 40:
				_check(_mobs[0].hp < _hp0[0] and _mobs[1].hp < _hp0[1], "Titan's Wrath hits mobs on both sides")
				_check(_mobs[0].is_stunned() and _mobs[1].is_stunned(), "and stuns them")
				_check(p.buffs.has("berserk") and p.buff_dmg_mult() > 1.4, "then Berserk: +50% damage")
				_goto("shadow")
		"shadow":
			if _pf == 1:
				_park_all()
				p.set_class(_bal, "rogue")
				p.set_level(5)
				_place(p, Vector2(600, 330))
				_x0 = p.position.x
				_mobs = [_dummy(0, Vector2(480, 329)), _dummy(1, Vector2(700, 329)), _dummy(2, Vector2(780, 329))]
				_hp0 = _mobs.map(func(m): return m.hp)
				p.cast_ultimate()
			if _pf == 20:
				_check(p.modulate.a < 0.9, "Shadow Dance: the rogue turns to shadow")
			if _pf == 120:
				var hit := 0
				for k in _mobs.size():
					if _mobs[k].hp < _hp0[k]:
						hit += 1
				_check(hit == 3, "Shadow Dance strikes every nearby mob (%d of 3)" % hit)
				_check(absf(p.position.x - _x0) < 4.0 and is_equal_approx(p.modulate.a, 1.0), "and the rogue returns to where it started (%.0f px off)" % absf(p.position.x - _x0))
				_goto("auto_ult")
		"auto_ult":
			# Auto-battle fires the ultimate into a crowd on its own.
			if _pf == 1:
				_park_all()
				p.set_class(_bal, "warrior")
				p.set_level(5)
				_place(p, Vector2(600, 330))
				for k in 4:
					_dummy(k, Vector2(560 + k * 30, 329))
				var u0: int = p.ults_used
				_x0 = u0
				p.set_auto_battle(true)
			if _pf == 120:
				_check(p.ults_used > int(_x0), "auto-battle uses the ultimate on a crowd of 4")
				p.set_auto_battle(false)
				_goto("done")
		"done":
			if _failures == 0:
				_log.ok("ALL COMBAT AI CHECKS PASSED (%d frames)" % _frame)
			else:
				_log.error("%d COMBAT AI CHECK(S) FAILED" % _failures)
			quit(1 if _failures > 0 else 0)
	if _frame > 5000:
		_log.error("timeout in phase " + _phase)
		quit(1)
	return false
