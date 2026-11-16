extends SceneTree
## Character showcase: the player and every Simmo lined up, half facing each way, wind blowing.
## Run: godot --path . --rendering-driver opengl3 --script res://tools/screenshot_dolls.gd
## Saves screenshots/dolls.png (full) and dolls_zoom.png (cropped and enlarged around the line-up).

var _main
var _frame := 0

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
	if _frame == 3:
		root.get_node("Log").debug = false
		_main.hud.show_help = false
		for k in _main.balance.sims.size():
			if k >= 3:
				_main.invite(_main.balance.sims[k])
		for m in _main.world.mobs:
			m.alive = false
			m.visible = false
			m.set_physics_process(false)
		load("res://scripts/weather_state.gd").wind = 0.8
	var actors: Array = [p] + _main.sims
	if _frame >= 3:
		for k in actors.size():
			var a = actors[k]
			a.position = Vector2(560 + k * 34, 330)
			a.velocity.x = 0.0
			a.facing = 1 if k % 2 == 0 else -1
			a.brain.leader = null if a != p else a.brain.leader
	if _frame == 90:
		var img := root.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://screenshots/dolls.png"))
		var r := Rect2i(img.get_width() / 2 - 160, img.get_height() - 260, 320, 150)
		var crop := img.get_region(r)
		crop.resize(r.size.x * 3, r.size.y * 3, Image.INTERPOLATE_NEAREST)
		crop.save_png(ProjectSettings.globalize_path("res://screenshots/dolls_zoom.png"))
		root.get_node("Log").ok("saved screenshots/dolls.png and dolls_zoom.png")
		quit(0)
	return false
