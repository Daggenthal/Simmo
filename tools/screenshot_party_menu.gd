extends SceneTree
## The right-click party menu open on a frame, and the Inspect window: screenshots/party_menu.png.
## Run: godot --path . --rendering-driver opengl3 --script res://tools/screenshot_party_menu.gd

var _main
var _frame := 0

func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	_main = load("res://main.tscn").instantiate()
	_main.load_user_settings = false
	_main.show_start_screen = false
	_main.start_class = "mage"
	root.add_child(_main)

func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 3:
		root.get_node("Log").debug = false
		_main.hud.show_help = false
		_main.weather.weather_on = false
	if _frame == 40:
		var pm = _main.party_menu
		pm.inspecting = _main.sims[1]
		var fr: Array = _main.hud.party_frames()[0]
		pm.open_menu(fr[1], fr[0].position + Vector2(10, 10))
	if _frame == 60:
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://screenshots/party_menu.png"))
		root.get_node("Log").ok("saved screenshots/party_menu.png")
		quit(0)
	return false
