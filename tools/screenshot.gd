extends SceneTree
## Renders the game for a few seconds and saves screenshots to res://screenshots/.
## Needs a display (not --headless). On Linux CI: xvfb-run godot --path . --script res://tools/screenshot.gd
## Pass a width after -- to test aspect ratios: ... -- 1280x720 / 2560x1080 (ultrawide) / 1812x2176 (unfolded Fold)
## Other args: weapon=iron_hammer (switches to its class), class=mage, map=ember_crags, level=15, start (shoot the class select screen)

var _main: Node
var _frame := 0
var _size := Vector2i(1280, 720)
var _tag := "16x9"
var _weapon := ""
var _map := ""
var _level := 0
var _class := ""
var _start := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("weapon="):
			_weapon = a.substr(7)
			_tag += "_" + _weapon
		elif a.begins_with("map="):
			_map = a.substr(4)
			_tag += "_" + _map
		elif a.begins_with("level="):
			_level = int(a.substr(6))
		elif a.begins_with("class="):
			_class = a.substr(6)
			_tag += "_" + _class
		elif a == "start":
			_start = true
			_tag += "_start"
		elif "x" in a:
			var parts := a.split("x")
			_size = Vector2i(int(parts[0]), int(parts[1]))
			_tag = a
	DisplayServer.window_set_size(_size)
	root.size = _size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	_main = load("res://main.tscn").instantiate()
	_main.start_map = _map
	_main.show_start_screen = _start
	_main.start_class = _class
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frame += 1
	if _start:
		if _frame == 30:
			_save("select")
			_main.start_screen.select(1)
		if _frame == 40:
			_save("select_mage")
			_main.start_screen.select(2)
		if _frame == 50:
			_save("select_rogue")
			quit(0)
		return false
	var p = _main.player
	if _frame == 5:
		root.get_node("Log").debug = false
		p.position = Vector2(560, 330)
		if _level > 0:
			p.set_level(_level)
		for s in _main.sims:
			s.position = p.position + Vector2(-20 - 14 * _main.sims.find(s), 0)
		p.set_auto_battle(true)
		if _weapon != "":
			p.switch_to_weapon_class(_weapon)
	if _frame in [40, 60, 80]:
		p._attack_cd = 0.0
		p.attack()
	if _frame == 54:
		_save("swing")
	if _frame == 84:
		_save("combat")
	if _frame == 90:
		root.get_node("Log").debug = true
	if _frame == 100:
		_save("debug")
		quit(0)
	return false

func _save(name: String) -> void:
	var img := root.get_texture().get_image()
	var path := "res://screenshots/%s_%s.png" % [name, _tag]
	img.save_png(ProjectSettings.globalize_path(path))
	root.get_node("Log").ok("saved %s (%dx%d)" % [path, img.get_width(), img.get_height()])
