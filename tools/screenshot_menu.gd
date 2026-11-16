extends SceneTree
## Screenshots of the Esc pause menu tabs: screenshots/menu_settings.png, menu_inventory.png, menu_party.png.
## Run: godot --path . --rendering-driver opengl3 --script res://tools/screenshot_menu.gd

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
	if _frame == 20:
		_main.pause_menu.open()
	for pair in [[25, "Settings"], [30, "Inventory"], [35, "Party"]]:
		if _frame == pair[0]:
			_main.pause_menu.tab = pair[1]
		if _frame == pair[0] + 3:
			var img := root.get_texture().get_image()
			img.save_png(ProjectSettings.globalize_path("res://screenshots/menu_%s.png" % String(pair[1]).to_lower()))
	if _frame == 40:
		root.get_node("Log").ok("saved menu screenshots")
		quit(0)
	return false
