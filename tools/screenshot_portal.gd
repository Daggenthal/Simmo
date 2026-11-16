extends SceneTree
## Screenshots of the portal danger label/hint and the under-level warning banner.
## Run: godot --path . --rendering-driver opengl3 --script res://tools/screenshot_portal.gd

var _main
var _frame := 0

func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)

func _process(_d: float) -> bool:
	_frame += 1
	var p = _main.player
	if _frame == 5:
		p.position = Vector2(1760, 330)
		for s in _main.sims:
			s.position = p.position + Vector2(-30 - 14 * _main.sims.find(s), 0)
	if _frame == 40:
		_save("portal_hint")
		var ev := InputEventAction.new()
		ev.action = "move_up"
		ev.pressed = true
		Input.parse_input_event(ev)
	if _frame == 41:
		var ev := InputEventAction.new()
		ev.action = "move_up"
		ev.pressed = false
		Input.parse_input_event(ev)
	if _frame == 70:
		_save("portal_warning")
		quit(0)
	return false

func _save(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://screenshots/%s.png" % name))
	root.get_node("Log").ok("saved screenshots/%s.png" % name)
