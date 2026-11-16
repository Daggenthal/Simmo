extends SceneTree
## Headless social test: chat channels and colors, combat / XP / loot logs, chat tabs, Simmo speech
## bubbles and spam limits, trading through the window, invite and kick, Simmo potions.
## Run: godot --headless --fixed-fps 60 --path . --script res://tests/social_test.gd

var _main
var _log
var _frame := 0
var _pf := 0
var _phase := "boot"
var _failures := 0
var CL     # res://scripts/chat_log.gd (class names would compile before autoloads)
var _tank = null
var _n0 := 0
var _lines0 := 0

func _initialize() -> void:
	_log = root.get_node("Log")
	var env_seed := OS.get_environment("SIMMO_SEED")
	seed(int(env_seed) if env_seed != "" else 2468)
	CL = load("res://scripts/chat_log.gd")
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

func _click(ctrl, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	ctrl._gui_input(ev)

func _physics_process(_d: float) -> bool:
	_frame += 1
	_pf += 1
	var p = _main.player
	var world = _main.world
	match _phase:
		"boot":
			if _pf == 5:
				_park_all()
				for s in _main.sims:
					if s.role == "tank":
						_tank = s
				_check(CL.count("system") >= 1 and "Welcome" in CL.lines[0].text, "a system welcome line opens the chat")
				_check(CL.count("party") >= 3, "each Simmo says hi in party chat when joining (%d lines)" % CL.count("party"))
				var bubbles := 0
				for s in _main.sims:
					if s._bubble_t > 0.0 and s.bubble_text != "":
						bubbles += 1
				_check(bubbles == 3, "Simmos' lines also show as speech bubbles over their heads (%d)" % bubbles)
				_check(CL.color("local") == Color("#ffffff") and CL.color("party") == Color("#6fb7ff") and CL.color("system") == Color("#ffd84a"),
					"local is white, party is blue, system is yellow")
				_check_logs(p, world)
				_check_tabs()
				_check_chat_box()
				_check_spam()
				_main.chatter._local_t = 0.05
				_lines0 = CL.count("local")
			if _pf == 20:
				_check(CL.count("local") == _lines0 + 1, "passers-by chat in local now and then")
				_check_trade(p)
				_check_party()
				_goto("potions")
		"potions":
			if _pf == 1:
				# Out of the healer's reach, so it's the potion that saves it.
				for s in _main.sims:
					if s.role == "healer":
						s.mp = 0.0
				_tank.hp = int(_tank.max_hp * 0.2)
				_tank._item_cd = 0.0
				_n0 = _tank.inventory.count("red_potion")
			if _pf == 10:
				_check(_tank.inventory.count("red_potion") == _n0 - 1 and _tank.hp > int(_tank.max_hp * 0.2), "a hurt Simmo drinks one of its own potions")
				_tank.inventory.remove("red_potion", 99)
				_tank.inventory.remove("white_potion", 99)
				_lines0 = CL.count("party")
			if _pf == 60:
				var asked: bool = false
				for l in CL.lines:
					if l.channel == "party" and l.text.begins_with(_tank.display_name) and l.text.substr(_tank.display_name.length() + 2) in _main.chat_data.party.out_of_potions:
						asked = true
				_check(asked, "a Simmo out of potions asks the party for one")
				_goto("done")
		"done":
			if _failures == 0:
				_log.ok("ALL SOCIAL CHECKS PASSED (%d frames)" % _frame)
			else:
				_log.error("%d SOCIAL CHECK(S) FAILED" % _failures)
			quit(1 if _failures > 0 else 0)
	if _frame > 3000:
		_log.error("timeout in phase " + _phase)
		quit(1)
	return false

func _check_logs(p, world) -> void:
	var m = world.mobs[0]
	m.data = world.mob_data(m.id, 1)
	m.level = 1
	m.max_hp = 30
	m.respawn()
	var Comb = load("res://scripts/combat.gd")
	Comb.hit(m, p, 5, "physical", {"crit_chance": 0.0})
	_check(CL.last("combat").begins_with("You hit %s for 5" % m.data.name), "your hits go to the combat log (%s)" % CL.last("combat"))
	world.loot_table = [{"item": "red_potion", "chance": 1.0}]
	m.take_hit(999, false, 1, p, 0.0)
	_check(CL.last("combat").begins_with("You defeated"), "kills go to the combat log (%s)" % CL.last("combat"))
	_check(CL.last("xp").begins_with("+") and "XP" in CL.last("xp"), "XP gained goes to the log in green (%s)" % CL.last("xp"))
	_check(CL.last("loot") == "You got a Red Potion", "loot goes to the log (%s)" % CL.last("loot"))
	world.loot_table = _main.items.loot

func _check_tabs() -> void:
	var box = _main.chat_box
	box.tab = "All"
	var chans := {}
	for l in box.visible_lines():
		chans[l.channel] = true
	_check(not chans.has("combat"), "the All tab leaves out damage spam")
	box.tab = "Combat"
	var only_combat := true
	for l in box.visible_lines():
		only_combat = only_combat and l.channel in ["combat", "xp"]
	_check(only_combat and box.visible_lines().size() > 0, "the Combat tab shows damage, kills and XP")
	box.cycle_tab()
	_check(box.tab == "All", "Y cycles the tabs")

func _check_spam() -> void:
	var c0: int = CL.count("party")
	_main.chatter._said_t.clear()
	_main.chatter._party_gap = 0.0
	for k in 6:
		_main.chatter.party_say(_tank, "idle")
	for s in _main.sims:
		_main.chatter.party_say(s, "idle")
	_check(CL.count("party") == c0 + 1, "Simmos don't spam: 9 tries in a row give 1 line (%d)" % (CL.count("party") - c0))

func _check_trade(p) -> void:
	var ui = _main.trade_ui
	ui.partner_idx = _main.sims.find(_tank)
	ui.open()
	_check(ui.visible and ui.partner() == _tank, "T opens a trade with a party member")
	# Gift, done by clicking: your Red Potion slot, then Trade.
	var k := -1
	for i in p.inventory.slots.size():
		if p.inventory.slots[i] != null and p.inventory.slots[i].id == "red_potion":
			k = i
	var mine0: int = p.inventory.count("red_potion")
	var theirs0: int = _tank.inventory.count("red_potion")
	_click(ui, ui.slot_rect(ui.my_grid(), k).get_center())
	_check(int(ui.my_offer.get("red_potion", 0)) == 1, "clicking your item puts it on offer")
	_click(ui, ui.trade_button().get_center())
	_check(p.inventory.count("red_potion") == mine0 - 1 and _tank.inventory.count("red_potion") == theirs0 + 1, "a gift goes through")
	_check(CL.last("trade").begins_with("Traded with %s" % _tank.display_name), "trades go to the log in pink (%s)" % CL.last("trade"))
	# Unfair: one red for three blue.
	var b0: int = p.inventory.count("blue_potion")
	ui.my_offer = {"red_potion": 1}
	ui.their_offer = {"blue_potion": 3}
	_check(ui.propose() == "unfair" and p.inventory.count("blue_potion") == b0, "a Simmo turns down a bad deal and nothing moves")
	# Fair: two blue for one tonic? Tonic is worth more, so ask for a red instead.
	ui.my_offer = {"blue_potion": 2}
	ui.their_offer = {"red_potion": 1}
	_check(ui.propose() == "", "a fair swap goes through (2 blue for 1 red)")
	# Needs: ask for all their reds.
	ui.my_offer = {"xp_tonic": 1}
	ui.their_offer = {"red_potion": _tank.inventory.count("red_potion")}
	_check(ui.propose() == "needs", "a Simmo keeps its last HP potions even for a tonic")
	ui.visible = false

func _check_party() -> void:
	var main = _main
	var name: String = _tank.display_name
	main.kick(_tank)
	_check(main.sims.size() == 2 and not main.in_party(name) and main.world.party.size() == 3, "kick removes a Simmo from the party")
	_check(CL.last("system") == "%s left the party" % name, "and says so in system chat")
	_check(main.invite(main.roster_entry("Goldvein")) == "" and main.in_party("Goldvein"), "invite adds a Simmo from the roster")
	_check(main.invite(main.roster_entry("Fennick")) == "Your party is full", "a party holds 4 (you plus 3)")
	_check(main.invite(main.roster_entry("Goldvein")) != "", "can't invite someone already in the party")
	for s in main.sims:
		if s.display_name == "Goldvein":
			_tank = s

## Resize, minimize and scroll the chat box.
func _check_chat_box() -> void:
	var box = _main.chat_box
	box.tab = "All"
	box._reset_view()
	var w0: float = box.box_w
	var r0: int = box.rows
	box.start_resize()
	box.drag_resize(Vector2(60, -30))
	box.end_resize()
	_check(box.box_w == w0 + 60 and box.rows == r0 + 3, "dragging the grip resizes the chat (%dx%d rows -> %dx%d rows)" % [w0, r0, box.box_w, box.rows])
	box.start_resize()
	box.drag_resize(Vector2(-999, 999))
	box.end_resize()
	_check(box.box_w == box.MIN_W and box.rows == box.MIN_ROWS, "it can't shrink below a usable size (%d px, %d rows)" % [box.box_w, box.rows])
	_check(int(_main.pause_menu.settings.chat_rows) == box.rows, "the chat size goes into the settings (saved to disk in the real game)")
	box.toggle_minimized()
	_check(box.minimized and box.box_size().y < 20.0, "the - button minimizes it to its tabs")
	box.toggle_minimized()
	box.set_layout(250, 4, false)
	for k in 12:
		CL.add("system", "filler line %d" % k)
	box._process(0.0)
	var newest: String = box.visible_lines()[-1].text
	box.scroll_by(5)
	_check(box.visible_lines()[-1].text != newest and box.scroll == 5, "scrolling shows older lines")
	CL.add("system", "brand new line")
	box._process(0.0)
	_check(not box.visible_lines().any(func(l): return l.text == "brand new line") and box._unread == 1, "while scrolled up, a new line doesn't move the view (1 new)")
	box._reset_view()
	_check(box.visible_lines()[-1].text == "brand new line", "jumping back down shows the newest line")
	box.set_layout(250, 6, false)
