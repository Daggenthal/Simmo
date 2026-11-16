extends SceneTree
## Boss screenshots: the fight (HP bar, enrage timer, slam telegraph) and the loot chest after.
## Run: godot --path . --rendering-driver opengl3 --script res://tools/screenshot_boss.gd

var _main
var _frame := 0
var _boss
var _shot := false

func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	_main = load("res://main.tscn").instantiate()
	_main.load_user_settings = false
	_main.show_start_screen = false
	root.add_child(_main)

func _save(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://screenshots/%s.png" % name))
	root.get_node("Log").ok("saved screenshots/%s.png" % name)

func _process(_d: float) -> bool:
	_frame += 1
	var p = _main.player
	if _frame == 3:
		root.get_node("Log").debug = false
		_main.hud.show_help = false
		_main.weather.weather_on = false
		p.set_level(7)
		for s in _main.sims:
			s.set_level(7)
		for a in _main.world.party:
			a.position = Vector2(780, 330)
		_boss = _main.world.spawn_boss()
		_boss.boss_time = 70.0
		p.set_auto_battle(true)
	if not _shot and _boss and is_instance_valid(_boss) and _boss.slam_t > 0.0 and _boss.slam_t < 0.5:
		_shot = true
		_save("boss_fight")
		_boss.take_hit(_boss.hp + 1, false, 1, p, 0.0)
		p.set_auto_battle(false)
		_frame = 1000
	if _frame == 1040:
		p.position = _main.world.chest.global_position + Vector2(-40, 0)
	if _frame == 1050:
		_save("boss_chest")
		_main.world.chest.open(p)
	if _frame == 1070:
		_main.pause_menu.open()
		_main.pause_menu.tab = "Inventory"
	if _frame == 1074:
		_save("boss_loot")
		quit(0)
	if _frame == 900:
		root.get_node("Log").warn("no slam seen")
		quit(1)
	return false
