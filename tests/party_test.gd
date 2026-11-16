extends SceneTree
## Headless party test: SimPlayers spawn, follow the player across platforms, stand by role,
## heal, perch, share XP, fight on their own, come back after a knockout and follow through portals.
## Run: godot --headless --fixed-fps 60 --path . --script res://tests/party_test.gd

var _main
var _log
var _frame := 0
var _pf := 0
var _phase := "boot"
var _failures := 0
var _tank = null
var _healer = null
var _ranged = null
var _m = null
var _hp0 := 0
var _kills0 := 0
var _swings0 := 0
var _on_perch := false
var _ever_far := 0.0
var _hp_track: Array = []
var _closest := 9999.0
var _swings_p := 0

func _initialize() -> void:
	_log = root.get_node("Log")
	# SIMMO_SEED=n runs with another seed, to shake out flaky checks.
	var env_seed := OS.get_environment("SIMMO_SEED")
	seed(int(env_seed) if env_seed != "" else 9001)
	_main = load("res://main.tscn").instantiate()
	_main.load_user_settings = false
	_main.show_start_screen = false
	_main.start_class = "warrior"
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

func _respawn_all() -> void:
	var world = _main.world
	world._respawn_queue.clear()
	for k in world.mobs.size():
		var m = world.mobs[k]
		var sp: Array = world.spawns[k]
		m.data = world.mob_data(m.id, m.level)
		m.max_hp = int(m.data.hp)
		m.home = Vector2(sp[1], sp[2] - 1)
		m.set_bounds(world.nav)
		m.respawn()

func _dummy(idx: int, pos: Vector2, hp := 100000):
	var world = _main.world
	var m = world.mobs[idx]
	m.data = m.data.duplicate()
	m.data.speed = 0.0
	m.data.hop_velocity = 0.0
	m.data.touch_damage = 0
	m.home = pos
	m.max_hp = hp
	m.set_bounds(world.nav)
	m.respawn()
	return m

func _place(p, pos: Vector2) -> void:
	p.position = pos
	p.velocity = Vector2.ZERO

func _physics_process(_d: float) -> bool:
	_frame += 1
	_pf += 1
	var p = _main.player
	var world = _main.world
	match _phase:
		"boot":
			if _pf == 5:
				var sims: Array = _main.sims
				_check(sims.size() == 3, "3 SimPlayers join the party (%d)" % sims.size())
				for s in sims:
					match s.role:
						"tank": _tank = s
						"healer": _healer = s
						"ranged": _ranged = s
				_check(_tank != null and _healer != null and _ranged != null, "party has a tank, a healer and a ranged sim")
				_check(world.party.size() == 4 and world.party[0] == p, "world party is the player plus 3 sims")
				_check(_tank.max_hp > p.max_hp and _tank.weapon_key == "iron_hammer", "tank has more HP (%d vs %d) and a hammer" % [_tank.max_hp, p.max_hp])
				_check(_healer.spells.has("heal") and not p.spells.has("heal"), "healer knows Heal; the player's skill bar doesn't get it")
				_check(_ranged.weapon.get("thrown", false), "ranged sim throws kunai")
				_check(_tank.class_id == "warrior" and _healer.class_id == "priest" and _healer.weapon_key == "holy_scepter" and _ranged.class_id == "rogue",
					"Simmos have classes: Warrior tank, Priest healer with a scepter, Rogue ranged")
				var looks := {}
				for s in sims:
					looks[str(s.look)] = true
				_check(looks.size() == 3 and _tank.display_name != "", "each sim has its own name and look (paper-doll palette)")
				_check(p.spells.size() == 4, "player keeps 4 spell slots (%d)" % p.spells.size())
				_park_all()
				_goto("follow")
		"follow":
			# Player hops up to a high platform; everyone should come along via the nav graph.
			if _pf == 1:
				_place(p, Vector2(1000, 208))
				p.facing = 1
			if _pf == 900:
				var near := 0
				var on_plat := 0
				for s in _main.sims:
					if s.global_position.distance_to(p.global_position) < 90.0:
						near += 1
					if s.is_on_floor() and absf(s.global_position.y - 208.0) < 4.0:
						on_plat += 1
				_check(near == 3 and on_plat == 3, "all sims follow the player up onto a platform (%d near, %d on it)" % [near, on_plat])
				_goto("roles")
		"roles":
			if _pf == 1:
				_place(p, Vector2(700, 330))
				p.facing = 1
				for s in _main.sims:
					_place(s, Vector2(700 + randf_range(-30, 30), 330))
			if _pf == 240:
				_check(_tank.global_position.x > p.global_position.x + 10.0, "tank stands in front of the player (%.0f vs %.0f)" % [_tank.global_position.x, p.global_position.x])
				_check(_healer.global_position.x < p.global_position.x - 10.0, "healer stands behind the player (%.0f vs %.0f)" % [_healer.global_position.x, p.global_position.x])
				_goto("heal")
		"heal":
			if _pf == 1:
				p.hp = int(p.max_hp * 0.3)
				_hp0 = p.hp
				_healer.mp = _healer.max_mp
				_healer.spell_cd.heal = 0.0
				_healer._cast_cd = 0.0
			if _pf == 180:
				_check(p.hp > _hp0 and _healer.heals_done > 0, "healer heals a hurt player (%d -> %d hp, %d heals)" % [_hp0, p.hp, _healer.heals_done])
				p.hp = p.max_hp
				_goto("perch")
		"perch":
			# One sturdy mob on the ground beside a low platform: the ranged sim should throw from up there.
			if _pf == 1:
				_park_all()
				_m = _dummy(0, Vector2(830, 329))
				_m.data.knockback_mult = 0.0  # the tank's hammer would push it out of the test
				_place(p, Vector2(700, 330))
				_place(_ranged, Vector2(660, 330))
				_swings0 = _ranged.swings
				_on_perch = false
			if _ranged.is_on_floor() and absf(_ranged.global_position.y - 270.0) < 4.0:
				_on_perch = true
			if _pf == 600:
				_check(_on_perch, "ranged sim climbs onto a platform above the target to throw")
				_check(_ranged.swings - _swings0 >= 7, "ranged sim keeps throwing (%d throws)" % (_ranged.swings - _swings0))
				_goto("xp_share")
		"xp_share":
			if _pf == 1:
				_park_all()
				var m = _dummy(1, Vector2(900, 329), 10)
				m.data.xp = 100
				m.data.level = p.level
				var xp0: int = p.xp
				var lvl0: int = p.level
				var got: Dictionary = world.award_xp(m, p)
				var share: float = (1.0 + float(_main.balance.party.xp_bonus_per_member) * 3) / 4.0
				_check(got.size() == 4, "a kill's XP goes to all 4 party members (%d)" % got.size())
				_check(int(got.get(p, 0)) == int(round(100 * share)), "each member gets the party share (%d of 100, expected %d)" % [got.get(p, 0), int(round(100 * share))])
				_check(p.xp > xp0 or p.level > lvl0, "player's XP went up")
				# Loot from a sim's kill goes to the player.
				world.loot_table = [{"item": "red_potion", "chance": 1.0}]
				var n0: int = p.inventory.count("red_potion")
				var m2 = _dummy(2, Vector2(950, 329), 10)
				m2.take_hit(999, false, 1, _tank, 0.0)
				_check(p.inventory.count("red_potion") == n0 + 1, "loot from the tank's kill lands in the player's inventory")
				world.loot_table = _main.items.loot
				_goto("fight")
		"fight":
			# Hands off with the whole map alive: sims should kill things too.
			if _pf == 1:
				_respawn_all()
				_place(p, Vector2(400, 330))
				p.set_auto_battle(true)
				_kills0 = 0
				for s in _main.sims:
					_kills0 += s.kills
					s.set_meta("dmg0", s.damage_dealt)
					s.set_meta("heals0", s.heals_done)
				p.set_meta("dmg0", p.damage_dealt)
			if _pf > 120:
				for s in _main.sims:
					if s.is_alive():
						_ever_far = maxf(_ever_far, s.global_position.distance_to(p.global_position))
			if _pf == 2400:
				var k := 0
				for s in _main.sims:
					k += s.kills
				# Kills go to the last hit, and the player often lands it; damage shows who really fought.
				var dmg := []
				for s in _main.sims:
					dmg.append(s.damage_dealt - int(s.get_meta("dmg0")))
				var pd: int = p.damage_dealt - int(p.get_meta("dmg0"))
				# The healer stays back and spends its casts on heals, so it counts heals or damage.
				var healer_did := false
				var fighters := 0
				var others_ok := true
				for n in _main.sims.size():
					var s = _main.sims[n]
					if s.role == "healer":
						healer_did = dmg[n] > 0 or s.heals_done > int(s.get_meta("heals0", 0))
					else:
						fighters += dmg[n]
						others_ok = others_ok and dmg[n] > 0
				_check(others_ok and healer_did and fighters >= pd * 0.2,
					"every Simmo fights on its own (damage %s vs player %d, %d Simmo kills)" % [str(dmg), pd, k - _kills0])
				_check(_ever_far < 600.0, "sims never got lost while following (furthest %.0f px)" % _ever_far)
				p.set_auto_battle(false)
				_goto("knockout")
		"knockout":
			if _pf == 1:
				_park_all()
				_place(p, Vector2(700, 330))
				_tank._invuln = 0.0
				_tank.take_damage(99999, 0.0)
				_check(not _tank.is_alive() and not _tank.visible, "a sim at 0 HP is knocked out")
			if _pf == int(float(_main.balance.party.respawn_time) * 60.0) + 30:
				_check(_tank.is_alive() and _tank.hp == _tank.max_hp, "knocked-out sim comes back with full HP")
				_check(_tank.global_position.distance_to(p.global_position) < 120.0, "and comes back next to the player (%.0f px)" % _tank.global_position.distance_to(p.global_position))
				_goto("portal")
		"portal":
			if _pf == 1:
				_place(p, Vector2(1760, 330))
			if _pf == 5:
				var ev := InputEventAction.new()
				ev.action = "move_up"
				ev.pressed = true
				Input.parse_input_event(ev)
			if _pf == 6:
				var ev := InputEventAction.new()
				ev.action = "move_up"
				ev.pressed = false
				Input.parse_input_event(ev)
			if _pf == 5 + 72 + 8:
				# Right after arriving (after the 1.2 s warp) (they go fight nearby mobs soon after, which is fine).
				_check(world.map_id == "mushroom_grove", "player went through the portal (%s)" % world.map_id)
				var near := 0
				for s in _main.sims:
					if s.is_inside_tree() and s.global_position.distance_to(p.global_position) < 60.0:
						near += 1
				_check(near == 3, "the party comes along through the portal (%d of 3 next to the player)" % near)
			if _pf == 600:
				var near := 0
				for s in _main.sims:
					if s.global_position.distance_to(p.global_position) < 300.0:
						near += 1
				_check(near == 3, "and sticks around on the new map (%d of 3 within 300 px)" % near)
				_goto("priest")
		"priest":
			_priest(p, world)
		"done":
			if _failures == 0:
				_log.ok("ALL PARTY CHECKS PASSED (%d frames)" % _frame)
			else:
				_log.error("%d PARTY CHECK(S) FAILED" % _failures)
			quit(1 if _failures > 0 else 0)
	if _frame > 12000:
		_log.error("timeout in phase " + _phase)
		quit(1)
	return false

## The Priest: heal over time, party heal, stays back, never melees, smites the undead.
func _priest(p, world) -> void:
	if _pf == 1:
		_park_all()
		_place(p, Vector2(700, 330))
		_place(_healer, Vector2(640, 330))
		_place(_tank, Vector2(760, 330))
		_healer.mp = _healer.max_mp
		for k in _healer.spell_cd:
			_healer.spell_cd[k] = 0.0
		p.hp = int(p.max_hp * 0.8)
		_hp_track = []
	if _pf == 40:
		_check(p.buffs.has("renew"), "the Priest puts Renew (a heal over time) on a lightly hurt ally")
		_hp_track.append(p.hp)
	if _pf == 100 or _pf == 160:
		_hp_track.append(p.hp)
	if _pf == 161:
		_check(_hp_track[1] > _hp_track[0] and _hp_track[2] > _hp_track[1], "Renew keeps healing over time (%s)" % str(_hp_track))
		# Two allies hurt: Prayer heals both at once.
		p.buffs.clear()
		_tank.buffs.clear()
		p.hp = int(p.max_hp * 0.5)
		_tank.hp = int(_tank.max_hp * 0.5)
		_healer.mp = _healer.max_mp
		_healer._cast_cd = 0.0
		for k in _healer.spell_cd:
			_healer.spell_cd[k] = 0.0
		_hp_track = [p.hp, _tank.hp]
	if _pf == 175:
		_check(p.hp > _hp_track[0] and _tank.hp > _hp_track[1] and _healer.spell_cd.prayer > 0.0, "with two allies hurt, Prayer heals the whole party")
		# A fight: the Priest stays back, never swings, and smites.
		p.hp = p.max_hp
		_tank.hp = _tank.max_hp
		_m = _dummy(0, Vector2(860, 329))
		p.set_auto_battle(true)
		_swings_p = _healer.swings
		_closest = 9999.0
		_healer.set_meta("pd0", _healer.damage_dealt)
	if _pf > 180 and _pf < 600:
		_closest = minf(_closest, absf(_healer.position.x - _m.position.x))
	if _pf == 600:
		p.set_auto_battle(false)
		_check(_healer.swings == _swings_p, "the Priest never melees (%d swings)" % (_healer.swings - _swings_p))
		_check(_closest > 50.0, "and keeps its distance from the fight (closest %.0f px)" % _closest)
		_check(_healer.damage_dealt > int(_healer.get_meta("pd0")), "while smiting from range (%d damage)" % (_healer.damage_dealt - int(_healer.get_meta("pd0"))))
		# Holy light burns the undead.
		var Comb = load("res://scripts/combat.gd")
		_m.data = world.mob_data("skeleton", 24)
		_m.max_hp = 100000
		_m.hp = 100000
		var r1: Dictionary = Comb.hit(_m, p, 100, "holy", {"crit_chance": 0.0})
		_m.data = world.mob_data("green_slime", 3)
		var r2: Dictionary = Comb.hit(_m, p, 100, "holy", {"crit_chance": 0.0})
		_check(int(r1.amount) == int(r2.amount * 1.5), "Smite does +50%% to undead (%d vs %d)" % [r1.amount, r2.amount])
		_goto("done")
