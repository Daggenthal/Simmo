extends SceneTree
## The PixelLab test sprite in game, next to the code-drawn party: screenshots/sprite_game.png
## (full) and sprite_zoom.png (cropped around the player), then the creator with her selected
## (sprite_creator.png).
## Run: godot --path . --rendering-driver opengl3 --script res://tools/screenshot_sprite.gd

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

func _save(name: String) -> Image:
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://screenshots/%s.png" % name))
	root.get_node("Log").ok("saved screenshots/%s.png" % name)
	return img

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
		var lk: Dictionary = p.look.duplicate()
		lk.sprite = "test_heroine"
		p.custom_look = true
		p.set_look(lk)
		p.position = Vector2(780, 330)
		p.facing = 1
		for s in _main.sims:
			s.position = p.position + Vector2(36 + 30 * _main.sims.find(s), 0)
			s.brain.leader = null
	if _frame > 3 and _frame < 60:
		p.position.x = 780.0
		for s in _main.sims:
			s.position.x = 816.0 + 30 * _main.sims.find(s)
	if _frame == 60:
		var img := _save("sprite_game")
		var scale := float(img.get_width()) / root.get_visible_rect().size.x
		var c: Vector2 = p.get_global_transform_with_canvas().origin * scale
		var w := int(150 * scale / 2.0)
		var h := int(60 * scale / 2.0)
		var r := Rect2i(int(c.x) - int(20 * scale / 2.0), int(c.y) - h + int(6 * scale / 2.0), w, h)
		var crop := img.get_region(r)
		crop.resize(r.size.x * 2, r.size.y * 2, Image.INTERPOLATE_NEAREST)
		crop.save_png(ProjectSettings.globalize_path("res://screenshots/sprite_zoom.png"))
		quit(0)
	return false
