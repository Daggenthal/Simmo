extends SceneTree
## Screenshot of the character creator (Mage, a few options changed, walking with wind).
## Run: godot --path . --rendering-driver opengl3 --script res://tools/screenshot_creator.gd

var _main
var _frame := 0

func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	_main = load("res://main.tscn").instantiate()
	_main.load_user_settings = false
	root.add_child(_main)

func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main.start_screen.select(0)
		_main.start_screen.choose()
	if _frame == 6:
		var cr = _main.creator
		cr.look.gender = "female"
		cr.look.hair = "twintails"
		cr.look.hair_color = "#e86aa0"
		cr.look.cape = "cape"
		cr.look.cape_color = "#2980b9"
		cr.look.face = "bright"
		cr.look.eye_color = "#3a6ad0"
		cr._doll.set_look(cr.look)
		cr.walking = true
		load("res://scripts/weather_state.gd").wind = -0.6
	if _frame == 60:
		var img := root.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://screenshots/creator.png"))
		root.get_node("Log").ok("saved screenshots/creator.png")
		quit(0)
	return false
