extends SceneTree
## Renders the game for a few seconds and saves screenshots to res://screenshots/.
## Needs a display (not --headless). On Linux CI: xvfb-run godot --path . --script res://tools/screenshot.gd
## Pass a width after -- to test aspect ratios: ... -- 1280x720 / 2560x1080 (ultrawide) / 1812x2176 (unfolded Fold)
## Other args: weapon=iron_hammer, map=ember_crags (start on another map), level=15

var _main: Node
var _frame := 0
var _size := Vector2i(1280, 720)
var _tag := "16x9"
var _weapon := ""
var _map := ""
var _level := 0

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
		elif "x" in a:
			var parts := a.split("x")
			_size = Vector2i(int(parts[0]), int(parts[1]))
			_tag = a
	DisplayServer.window_set_size(_size)
	root.size = _size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	_main = load("res://main.tscn").instantiate()
	_main.start_map = _map
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frame += 1
	var p = _main.player
	if _frame == 5:
		root.get_node("Log").debug = false
		p.position = Vector2(560, 330)
		if _level > 0:
			p.gain_xp(0)
			while p.level < _level:
				p.gain_xp(p.xp_to_next())
		for s in _main.sims:
			s.position = p.position + Vector2(-20 - 14 * _main.sims.find(s), 0)
		p.set_auto_battle(true)
		if _weapon != "":
			p.equip(_weapon)
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
