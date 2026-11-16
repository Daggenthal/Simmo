extends SceneTree
## Headless boss and loot test: spawning after kills, focus, slam telegraph and jump dodge, enrage
## (the DPS check), the chest, Diablo-style rarities, and equipping gear.
## Run: godot --headless --fixed-fps 60 --path . --script res://tests/boss_test.gd

var _main
var _log
var _frame := 0
var _pf := 0
var _phase := "boot"
var _failures := 0
var GearS
var CL
var _boss = null
var _hp0 := 0
var _inv0 := 0

func _initialize() -> void:
	_log = root.get_node("Log")
	var env_seed := OS.get_environment("SIMMO_SEED")
	seed(int(env_seed) if env_seed != "" else 7777)
	GearS = load("res://scripts/gear.gd")
	CL = load("res://scripts/chat_log.gd")
	_main = load("res://main.tscn").instantiate()
	_main.load_user_settings = false
	_main.show_start_screen = false
	_main.start_class = "warrior"
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
		if m.is_boss:
			continue
		m.alive = false
		m.visible = false
		m.set_physics_process(false)

func _place(a, pos: Vector2) -> void:
	a.position = pos
	a.velocity = Vector2.ZERO

func _physics_process(_d: float) -> bool:
	_frame += 1
	_pf += 1
	var p = _main.player
	var world = _main.world
	match _phase:
		"boot":
			if _pf == 5:
				_main.weather.weather_on = false
				p.set_level(8)
				_check_loot_rolls(p)
				_check_equip(p)
				# 29 kills, then one more brings the boss.
				world.kills_here = int(_main.balance.bosses.kills_to_spawn) - 1
				_check(world.boss == null, "no boss before enough kills")
				var m = world.mobs[0]
				m.take_hit(9999, false, 1, p, 0.0)
				_boss = world.boss
				_check(_boss != null and _boss.is_boss and _boss.id == "slime_monarch", "the boss appears after %d kills (%s)" % [int(_main.balance.bosses.kills_to_spawn), _boss.id if _boss else "none"])
				_check(CL.last("warning").begins_with("BOSS:"), "and it's announced in chat (%s)" % CL.last("warning"))
				_check(_boss.size.x >= 40.0 and _boss.max_hp > 1000, "bosses are big, with lots of HP (%d)" % _boss.max_hp)
				_check(absf(_boss.enrage_left() - float(_main.balance.bosses.enrage_time)) < 0.5, "the enrage timer starts at %.0f s" % float(_main.balance.bosses.enrage_time))
				_boss.apply_freeze(5.0)
				_boss.apply_stun(5.0)
				_check(not _boss.is_frozen() and not _boss.is_stunned(), "bosses can't be frozen or stunned")
				_goto("focus")
		"focus":
			if _pf == 1:
				_park_all()
				_boss.data = _boss.data.duplicate()
				_boss.data.touch_damage = 0
				_boss.data.speed = 0.0
				_boss.data.hop_velocity = 0.0
				_place(_boss, Vector2(900, 329))
				_boss._slam_cd = 999.0
				var near = world.mobs[0]
				near.respawn()
				near.data = near.data.duplicate()
				near.data.speed = 0.0
				near.data.hop_velocity = 0.0
				near.data.touch_damage = 0
				near.position = Vector2(560, 329)
				_place(p, Vector2(520, 330))
				p.set_auto_battle(true)
			if _pf == 30:
				_check(p.brain.target == _boss, "auto-battle goes for the boss over a closer mob")
				p.set_auto_battle(false)
				_goto("slam")
		"slam":
			# On the ground in range: the slam hurts.
			if _pf == 1:
				_park_all()
				_place(p, Vector2(860, 330))
				p._invuln = 0.0
				p.hp = p.max_hp
				_hp0 = p.hp
				_boss.data.touch_damage = int(_main.balance.mobs.slime_monarch.touch_damage)
				_boss._slam_cd = 0.0
			if _pf == 5:
				_check(_boss.slam_t > 0.0, "the boss telegraphs its slam first")
			if _pf == 90:
				_check(p.hp < _hp0 and _boss.slams >= 1, "standing in the slam hurts (%d -> %d)" % [_hp0, p.hp])
				p.hp = p.max_hp
				_hp0 = p.hp
				p._invuln = 0.0
				_boss._slam_cd = 0.0
			# Jump right before it lands: no damage.
			if _pf > 92 and _boss.slam_t > 0.0 and _boss.slam_t < 0.25 and p.is_on_floor():
				p.velocity.y = -360.0
			if _pf == 200:
				_check(p.hp == _hp0 and _boss.slams >= 2, "jumping over the slam dodges it (%d hp)" % p.hp)
				_goto("enrage")
		"enrage":
			if _pf == 1:
				_place(p, Vector2(300, 330))
				_boss.boss_time = float(_main.balance.bosses.enrage_time) - 0.05
			if _pf == 10:
				_check(_boss.enraged, "missing the DPS check: the boss enrages")
				_check(_boss.touch_damage() > int(_main.balance.mobs.slime_monarch.touch_damage) * 2, "an enraged boss hits much harder (%d)" % _boss.touch_damage())
				_check(CL.last("warning").contains("ENRAGED"), "and chat says so")
				_inv0 = 0
				for s in p.inventory.slots:
					if s == null:
						_inv0 += 1
				_boss.take_hit(_boss.hp + 10, false, 1, p, 0.0)
			if _pf == 12:
				_check(world.boss == null and world.chest != null, "killing the boss drops a chest")
				_check(not world.mobs.has(_boss), "and the boss doesn't respawn")
				_place(p, Vector2(300, 330))
				p.set_auto_battle(true)
			if _pf > 12 and world.chest != null and world.chest.opened and _pf < 900:
				_pf = 900
			if _pf == 901:
				_check(world.chest.opened, "auto-battle walks to the chest and opens it")
				var free := 0
				for s in p.inventory.slots:
					if s == null:
						free += 1
				_check(free < _inv0, "the loot goes into your bag (%d items)" % (_inv0 - free))
				var colored := 0
				for l in CL.lines:
					if l.channel == "loot" and l.text.begins_with("[") and l.color.a > 0.0:
						colored += 1
				_check(colored >= 3, "each item is announced in its rarity color (%d lines)" % colored)
				p.set_auto_battle(false)
				_goto("done")
		"done":
			if _failures == 0:
				_log.ok("ALL BOSS CHECKS PASSED (%d frames)" % _frame)
			else:
				_log.error("%d BOSS CHECK(S) FAILED" % _failures)
			quit(1 if _failures > 0 else 0)
	if _frame > 4000:
		_log.error("timeout in phase " + _phase)
		quit(1)
	return false

func _check_loot_rolls(p) -> void:
	var counts := {}
	for k in 6000:
		var r: String = GearS.roll_rarity()
		counts[r] = int(counts.get(r, 0)) + 1
	var d: Dictionary = GearS.load_data()
	var total := 0.0
	for k in d.rarities:
		total += float(d.rarities[k].weight)
	var ok := true
	var report := []
	for k in d.rarities:
		var want: float = float(d.rarities[k].weight) / total
		var got: float = float(counts.get(k, 0)) / 6000.0
		report.append("%s %.1f%%" % [k, got * 100.0])
		ok = ok and absf(got - want) < 0.02
	_check(ok, "rarities drop at their weights (%s)" % ", ".join(report))
	_check(GearS.color("legendary") == Color("#ff8000") and GearS.color("epic") == Color("#a335ee") and GearS.color("magic") == Color("#6969ff") and GearS.color("junk") == Color("#9d9d9d"),
		"rarity colors: junk gray, magic blue, epic purple, legendary orange")
	var junk: Dictionary = GearS.make("junk", 10)
	_check(junk.kind == "junk" and not junk.has("slot"), "junk is just junk")
	var magic: Dictionary = GearS.make("magic", 10, ["short_sword"])
	var leg: Dictionary = GearS.make("legendary", 10, ["short_sword"])
	_check(magic.mods.size() >= 2 and magic.mods.size() <= 2, "magic gear: a base bonus plus 1 affix (%s)" % str(magic.mods))
	_check(leg.mods.size() >= 4 and leg.name.contains("("), "legendary gear: several affixes and a unique name (%s: %s)" % [leg.name, str(leg.mods)])
	# Compare like with like: a common weapon's base damage bonus (affixes are random and differ in scale).
	var lo: Dictionary = GearS.make("common", 5, ["short_sword"])
	var hi: Dictionary = GearS.make("common", 30, ["short_sword"])
	while lo.slot != "weapon":
		lo = GearS.make("common", 5, ["short_sword"])
	while hi.slot != "weapon":
		hi = GearS.make("common", 30, ["short_sword"])
	_check(int(hi.mods.damage) > int(lo.mods.damage) * 3, "higher-level bosses drop stronger gear (weapon damage +%d%% vs +%d%%)" % [lo.mods.damage, hi.mods.damage])

func _check_equip(p) -> void:
	var it: Dictionary = GearS.make("rare", 10, ["short_sword"])
	it.weapon = "short_sword"
	it.slot = "weapon"
	it.mods = {"damage": 20, "str": 5}
	var before: Vector2i = p.damage_range(p.weapon)
	var str0: int = p.stat("str")
	var k: int = p.inventory.add_item(it)
	_check(p.equip_slot(k) == "" and p.equipment.weapon == it, "gear equips from the bag")
	_check(p.stat("str") == str0 + 5, "its stat bonus applies (STR %d -> %d)" % [str0, p.stat("str")])
	var after: Vector2i = p.damage_range(p.weapon)
	_check(after.y > before.y, "and its damage bonus (%d -> %d max)" % [before.y, after.y])
	var staff: Dictionary = GearS.make("magic", 10, ["oak_staff"])
	staff.slot = "weapon"
	staff.weapon = "oak_staff"
	var ks: int = p.inventory.add_item(staff)
	_check(p.equip_slot(ks) != "" and p.equipment.weapon == it, "a Warrior can't wear a staff")
	p.inventory.take_slot(ks)
	var it2: Dictionary = GearS.make("magic", 10, ["iron_hammer"])
	it2.slot = "weapon"
	it2.weapon = "iron_hammer"
	var k2: int = p.inventory.add_item(it2)
	p.equip_slot(k2)
	_check(p.equipment.weapon == it2 and p.weapon_key == "iron_hammer" and p.inventory.slots[k2] != null and p.inventory.slots[k2].item == it, "swapping gear puts the old piece back in the bag")
	var ring: Dictionary = GearS.make("rare", 10)
	ring.slot = "ring"
	ring.weapon = ""
	ring.mods = {"crit": 5}
	var c0: float = p.crit_chance()
	p.equip_slot(p.inventory.add_item(ring))
	_check(absf(p.crit_chance() - c0 - 0.05) < 0.001, "a ring's crit bonus applies (%.1f%% -> %.1f%%)" % [c0 * 100, p.crit_chance() * 100])
