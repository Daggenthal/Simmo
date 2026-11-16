extends SceneTree
## Headless pause menu test: Esc pauses and resumes, every setting reaches the game,
## settings save and load, items work while paused, kick and invite from the Party tab.
## Run: godot --headless --fixed-fps 60 --path . --script res://tests/menu_test.gd

var _main
var _log
var _frame := 0
var _pf := 0
var _phase := "boot"
var _failures := 0
var _pos0 := Vector2.ZERO
var _mob_pos0 := Vector2.ZERO

func _initialize() -> void:
	_log = root.get_node("Log")
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

func _esc() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventKey.new()
	up.keycode = KEY_ESCAPE
	up.pressed = false
	Input.parse_input_event(up)

func _physics_process(_d: float) -> bool:
	_frame += 1
	_pf += 1
	var menu = _main.pause_menu
	var p = _main.player
	match _phase:
		"boot":
			if _pf == 5:
				menu.settings_path = "user://test_settings.cfg"
				menu.persist = true  # this test checks saving, to its own file only
				p.set_auto_battle(true)
			if _pf == 30:
				_esc()
			if _pf == 32:
				_check(menu.visible and paused, "Esc opens the menu and pauses the game")
				_pos0 = p.position
				_mob_pos0 = _main.world.mobs[0].position
			if _pf == 62:
				_check(p.position == _pos0 and _main.world.mobs[0].position == _mob_pos0, "nothing moves while paused")
				_settings(menu)
				_goto("inventory")
		"inventory":
			if _pf == 1:
				menu.tab = "Inventory"
				p.hp = 10
				p._item_cd = 0.0
				var k := -1
				for i in p.inventory.slots.size():
					if p.inventory.slots[i] != null and p.inventory.slots[i].id == "red_potion":
						k = i
				var n0: int = p.inventory.count("red_potion")
				menu.click(menu.inv_slot(k).get_center())
				_check(p.inventory.count("red_potion") == n0 - 1 and p.hp > 10, "clicking a potion in the paused inventory uses it")
				_party(menu)
			if _pf == 5:
				_esc()
			if _pf == 8:
				_check(not menu.visible and not paused, "Esc again closes the menu and resumes")
				_goto("done")
		"done":
			if _failures == 0:
				_log.ok("ALL MENU CHECKS PASSED (%d frames)" % _frame)
			else:
				_log.error("%d MENU CHECK(S) FAILED" % _failures)
			quit(1 if _failures > 0 else 0)
	if _frame > 2000:
		_log.error("timeout in phase " + _phase)
		quit(1)
	return false

func _row(menu, key: String) -> int:
	var rows: Array = menu.setting_rows()
	for n in rows.size():
		if rows[n][0] == key:
			return n
	return -1

func _settings(menu) -> void:
	var sfx = root.get_node("Sfx")
	menu.tab = "Settings"
	var s: Rect2 = menu.slider_rect(_row(menu, "effects"))
	menu.click(Vector2(s.position.x + s.size.x * 0.25, s.get_center().y))
	menu._drag = ""
	_check(absf(sfx.sfx_volume - 0.25) < 0.03, "the Effects slider sets the sound effect volume (%.2f)" % sfx.sfx_volume)
	s = menu.slider_rect(_row(menu, "ambient"))
	menu.click(Vector2(s.position.x + s.size.x * 0.1, s.get_center().y))
	menu._drag = ""
	_check(absf(sfx.ambient_volume - 0.1) < 0.03, "the Ambient slider sets rain and wind volume (%.2f)" % sfx.ambient_volume)
	s = menu.slider_rect(_row(menu, "master"))
	menu.click(Vector2(s.position.x + s.size.x * 0.5, s.get_center().y))
	menu._drag = ""
	_check(absf(db_to_linear(AudioServer.get_bus_volume_db(0)) - 0.5) < 0.03, "the Master slider sets the master volume")
	menu.click(menu.setting_rect(_row(menu, "mute")).get_center())
	_check(sfx.muted and AudioServer.is_bus_mute(0), "Mute silences everything")
	menu.click(menu.setting_rect(_row(menu, "mute")).get_center())
	menu.click(menu.setting_rect(_row(menu, "weather")).get_center())
	_check(not _main.weather.weather_on, "weather can be turned off")
	menu.click(menu.setting_rect(_row(menu, "day_cycle")).get_center())
	s = menu.slider_rect(_row(menu, "time"))
	menu.click(Vector2(s.position.x + s.size.x * 0.0 + 1, s.get_center().y))
	menu._drag = ""
	_check(not _main.weather.day_cycle and _main.weather.time_of_day < 0.05, "with the cycle off, the time slider sets the time (night)")
	menu.save_settings()
	var cf := ConfigFile.new()
	_check(cf.load(menu.settings_path) == OK and absf(float(cf.get_value("settings", "effects", 0.0)) - 0.25) < 0.03, "settings are saved")
	menu.settings.effects = 0.9
	menu.load_settings()
	_check(absf(sfx.sfx_volume - 0.25) < 0.03, "and loaded back")
	# Back to defaults for other tests in this run.
	menu.settings = menu.DEFAULTS.duplicate()
	menu.apply_settings()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(menu.settings_path))
	menu.persist = false  # closing the menu later must not write the file back

func _party(menu) -> void:
	menu.tab = "Party"
	var n0: int = _main.sims.size()
	var name0: String = _main.sims[0].display_name
	menu.click(menu.button_in(menu.member_rect(0)).get_center())
	_check(_main.sims.size() == n0 - 1 and not _main.in_party(name0), "Kick removes a Simmo (%s)" % name0)
	var free: Array = menu.roster_free()
	var pick: String = free[0].name
	menu.click(menu.button_in(menu.roster_rect(0)).get_center())
	_check(_main.in_party(pick), "Invite adds a Simmo from the roster (%s)" % pick)
	menu.click(menu.button_in(menu.roster_rect(0)).get_center())
	_check(menu.status == "Your party is full", "a full party can't take more (%s)" % menu.status)
