extends SceneTree
## Screenshots of the zone warp: rings building up, dissolving, and arriving on the next map.
## Run: godot --path . --rendering-driver opengl3 --script res://tools/screenshot_warp.gd

var _main
var _frame := 0
var _t0 := -1
var _saved := {}

func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	_main = load("res://main.tscn").instantiate()
	_main.load_user_settings = false
	_main.show_start_screen = false
	root.add_child(_main)

func _process(_d: float) -> bool:
	_frame += 1
	var p = _main.player
	if _frame == 5:
		root.get_node("Log").debug = false
		_main.hud.show_help = false
		p.position = Vector2(1760, 330)
		for s in _main.sims:
			s.position = p.position + Vector2(-30 - 14 * _main.sims.find(s), 0)
	if _frame == 30:
		_main.world.travel(_main.world.portals[0])
		_t0 = Time.get_ticks_msec()
	if _t0 < 0:
		return false
	# Real time, since the warp runs on a timer: 0.5 s and 1.0 s into the 1.2 s warp-out, 0.4 s into the warp-in.
	var ms := Time.get_ticks_msec() - _t0
	for pair in [[500, "warp_build"], [1000, "warp_dissolve"], [1650, "warp_arrive"]]:
		if ms >= pair[0] and not _saved.has(pair[1]):
			_saved[pair[1]] = true
			var img := root.get_texture().get_image()
			img.save_png(ProjectSettings.globalize_path("res://screenshots/%s.png" % pair[1]))
			root.get_node("Log").ok("saved screenshots/%s.png" % pair[1])
	if ms > 1800:
		quit(0)
	return false
