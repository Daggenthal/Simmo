extends SceneTree
## Headless items test: inventory stacking, potions, XP tonics, loot, auto-potions, hotkeys and the window.
## Run: godot --headless --fixed-fps 60 --path . --script res://tests/items_test.gd

var _main
var _log
var _frame := 0
var _pf := 0
var _phase := "boot"
var _failures := 0
var InvS   # res://scripts/inventory.gd, loaded at runtime (class names would compile before autoloads)
var _n0 := 0
var _hp0 := 0

func _initialize() -> void:
	_log = root.get_node("Log")
	var env_seed := OS.get_environment("SIMMO_SEED")
	seed(int(env_seed) if env_seed != "" else 31337)
	InvS = load("res://scripts/inventory.gd")
	_main = load("res://main.tscn").instantiate()
	_main.spawn_sims = false
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

func _action(name: String) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = name
		ev.pressed = pressed
		Input.parse_input_event(ev)

func _physics_process(_d: float) -> bool:
	_frame += 1
	_pf += 1
	var p = _main.player
	var world = _main.world
	match _phase:
		"boot":
			if _pf == 5:
				_park_all()
				_check_inventory()
				_check_potions(p)
				_goto("tonic")
		"tonic":
			if _pf == 1:
				_check_tonics(p, world)
			if _pf == 2:
				p.buffs.xp.t = 0.05
			if _pf == 12:
				_check(not p.buffs.has("xp") and is_equal_approx(p.xp_mult(), 1.0), "XP buff wears off when its time runs out")
				_check_loot(p, world)
				_goto("auto_pot")
		"auto_pot":
			if _pf == 1:
				p.position = Vector2(700, 330)
				p.velocity = Vector2.ZERO
				p._item_cd = 0.0
				p.hp = 5
				_n0 = p.inventory.count("red_potion")
				p.set_auto_battle(true)
			if _pf == 30:
				_check(p.hp > 5 and p.inventory.count("red_potion") == _n0 - 1, "auto-battle drinks a potion at low HP (hp %d, potions %d -> %d)" % [p.hp, _n0, p.inventory.count("red_potion")])
				p.set_auto_battle(false)
				_goto("hotkey")
		"hotkey":
			if _pf == 1:
				p._item_cd = 0.0
				p.hp = 10
				_n0 = p.inventory.count("red_potion")
				_action("potion_hp")
			if _pf == 5:
				_check(p.hp > 10 and p.inventory.count("red_potion") == _n0 - 1, "R drinks an HP potion (hp %d)" % p.hp)
				_action("inventory_toggle")
			if _pf == 8:
				var ui = _main.inventory_ui
				_check(ui.visible, "I opens the inventory window")
				p._item_cd = 0.0
				p.hp = 10
				var k := -1
				for i in p.inventory.slots.size():
					var s = p.inventory.slots[i]
					if s != null and s.id == "red_potion":
						k = i
				_n0 = p.inventory.count("red_potion")
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = true
				ev.position = ui.slot_center(k)
				ui._gui_input(ev)
				_check(p.hp > 10 and p.inventory.count("red_potion") == _n0 - 1, "clicking a potion in the window uses it (hp %d)" % p.hp)
				_action("inventory_toggle")
			if _pf == 11:
				_check(not _main.inventory_ui.visible, "I closes it again")
				_goto("done")
		"done":
			if _failures == 0:
				_log.ok("ALL ITEM CHECKS PASSED (%d frames)" % _frame)
			else:
				_log.error("%d ITEM CHECK(S) FAILED" % _failures)
			quit(1 if _failures > 0 else 0)
	if _frame > 2000:
		_log.error("timeout in phase " + _phase)
		quit(1)
	return false

func _check_inventory() -> void:
	var p = _main.player
	_check(p.inventory.count("red_potion") == 10 and p.inventory.count("blue_potion") == 5 and p.inventory.count("xp_tonic") == 2,
		"starter kit: 10 Red, 5 Blue, 2 Scholar's Tonic")
	var inv = InvS.new(_main.items.items, 4)
	_check(inv.add("red_potion", 150) == 150, "150 Red Potions fit in 4 slots")
	var used := 0
	for s in inv.slots:
		if s != null:
			used += 1
	_check(used == 2 and inv.count("red_potion") == 150, "they stack 100 per slot (2 slots used)")
	inv.add("blue_potion", 1)
	inv.add("xp_tonic", 1)
	_check(inv.add("xp_elixir", 1) == 0 and inv.is_full_for("xp_elixir"), "a full inventory refuses new items")
	_check(inv.add("red_potion", 60) == 50, "but tops up an existing stack (50 of 60 fit)")
	_check(inv.remove("red_potion", 120) == 120 and inv.count("red_potion") == 80, "removing takes from stacks (200 -> 80)")

func _check_potions(p) -> void:
	p._item_cd = 0.0
	p.hp = 10
	var n0: int = p.inventory.count("red_potion")
	_check(p.use_item("red_potion") == "" and p.hp == mini(60, p.max_hp) and p.inventory.count("red_potion") == n0 - 1, "Red Potion heals 50 and is used up (hp %d)" % p.hp)
	_check(p.use_item("red_potion") == "Not yet", "potions have a short cooldown")
	p._item_cd = 0.0
	p.hp = p.max_hp
	_check(p.use_item("red_potion") == "HP is full" and p.inventory.count("red_potion") == n0 - 1, "can't waste a potion at full HP")
	p.mp = 0.0
	_check(p.use_item("blue_potion") == "" and is_equal_approx(p.mp, minf(40.0, p.max_mp)), "Blue Potion restores 40 MP, up to max (%.0f of %d)" % [p.mp, p.max_mp])
	# Best potion: the smallest that covers what's missing, else the biggest.
	p.inventory.add("white_potion", 2)
	p.max_hp = 400
	p.hp = 370
	_check(p.best_item("heal_hp") == "red_potion", "30 HP missing: picks the Red Potion")
	p.hp = 220
	_check(p.best_item("heal_hp") == "white_potion", "180 HP missing: picks the White Potion")
	p.hp = 10
	_check(p.best_item("heal_hp") == "white_potion", "390 HP missing: picks the biggest")
	p.max_hp = int(p.cfg.max_hp)
	p.hp = p.max_hp
	p.inventory.remove("white_potion", 2)

func _check_tonics(p, world) -> void:
	p._item_cd = 0.0
	_check(p.use_item("xp_tonic") == "" and is_equal_approx(p.xp_mult(), 1.2), "Scholar's Tonic: +20% XP")
	var m = world.mobs[0]
	m.data = world.mob_data(m.id, p.level)
	m.level = p.level
	m.data.xp = 100
	var got: Dictionary = world.award_xp(m, p)
	_check(int(got[p]) == 120, "a 100 XP kill gives 120 with the tonic (got %d)" % int(got[p]))
	p.inventory.add("xp_elixir", 1)
	p._item_cd = 0.0
	_check(p.use_item("xp_elixir") == "" and is_equal_approx(p.xp_mult(), 1.5), "Sage's Elixir replaces it: +50% (buffs don't stack)")
	p._item_cd = 0.0
	var n: int = p.inventory.count("xp_tonic")
	_check(p.use_item("xp_tonic") != "" and p.inventory.count("xp_tonic") == n, "a weaker tonic won't replace a stronger buff")

func _check_loot(p, world) -> void:
	var m = world.mobs[1]
	m.data = world.mob_data(m.id, 3)
	m.level = 3
	m.max_hp = 10
	m.respawn()
	world.loot_table = [{"item": "red_potion", "chance": 1.0}, {"item": "xp_elixir", "chance": 1.0, "min_level": 13}]
	var n0: int = p.inventory.count("red_potion")
	var e0: int = p.inventory.count("xp_elixir")
	m.take_hit(999, false, 1, p, 0.0)
	_check(p.inventory.count("red_potion") == n0 + 1, "a kill drops loot into the inventory")
	_check(p.inventory.count("xp_elixir") == e0, "loot with min_level 13 doesn't drop from a level 3 mob")
	world.loot_table = _main.items.loot
	var drops := 0
	for k in 2000:
		drops += world.roll_loot(m).count("red_potion")
	var chance := 0.0
	for e in _main.items.loot:
		if e.item == "red_potion":
			chance = float(e.chance)
	_check(absf(drops / 2000.0 - chance) < 0.025, "Red Potion drops about %.0f%% of the time (%.1f%%)" % [chance * 100, drops / 20.0])
