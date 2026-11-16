extends SceneTree
## Priest and chat box: the Priest healing (Renew sparkles, party frame marker) and a taller chat
## scrolled up through history. Saves screenshots/priest_chat.png.
## Run: godot --path . --rendering-driver opengl3 --script res://tools/screenshot_priest.gd

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
		_main.weather.weather_on = false
		for m in _main.world.mobs:
			m.alive = false
			m.visible = false
		p.position = Vector2(700, 330)
		p.hp = int(p.max_hp * 0.6)
		for s in _main.sims:
			s.position = p.position + Vector2(-50 + 30 * _main.sims.find(s), 0)
			s.hp = int(s.max_hp * 0.7)
		var cl = load("res://scripts/chat_log.gd")
		for k in 30:
			cl.add("local" if k % 3 else "party", "history line %d" % k)
		_main.chat_box.set_layout(320, 10, false)
	if _frame == 80:
		_main.chat_box.scroll_by(8)
		load("res://scripts/chat_log.gd").add("system", "a new line while you read")
	if _frame == 90:
		var img := root.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://screenshots/priest_chat.png"))
		root.get_node("Log").ok("saved screenshots/priest_chat.png")
		quit(0)
	return false
