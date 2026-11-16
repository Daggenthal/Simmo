extends SceneTree
## World look: one shot per scene (map, time of day, weather), with the party walking around.
## Run: godot --path . --rendering-driver opengl3 --script res://tools/screenshot_world.gd [-- scene_name]
## Scenes: day_pond, night_lights, storm, snow. Saves screenshots/world_<scene>.png.

const SCENES := {
	"day_pond": {"map": "mossy_meadow", "time": 0.45, "weather": "clear", "x": 690, "fire": false},
	"night_lights": {"map": "mossy_meadow", "time": 0.02, "weather": "clear", "x": 900, "fire": true},
	"storm": {"map": "mushroom_grove", "time": 0.55, "weather": "storm", "x": 520, "fire": false},
	"snow": {"map": "frostpeak_ruins", "time": 0.4, "weather": "snow", "x": 600, "fire": false},
}

var _main
var _frame := 0
var _scene := "day_pond"
var _cfg: Dictionary

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if SCENES.has(a):
			_scene = a
	_cfg = SCENES[_scene]
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	_main = load("res://main.tscn").instantiate()
	_main.load_user_settings = false
	_main.show_start_screen = false
	_main.start_map = _cfg.map
	root.add_child(_main)

func _process(_d: float) -> bool:
	_frame += 1
	var p = _main.player
	if _frame == 3:
		root.get_node("Log").debug = false
		_main.hud.show_help = false
		_main.weather.day_cycle = false
		_main.weather.time_of_day = _cfg.time
		_main.weather.set_state(_cfg.weather)
		p.position = Vector2(_cfg.x, 330)
		for s in _main.sims:
			s.position = p.position + Vector2(-30 - 16 * _main.sims.find(s), 0)
		if _cfg.weather != "snow":
			p.set_auto_battle(false)
	if _frame > 3 and _frame < 70:
		# Walk right through the scene so feet hit the water / snow.
		Input.action_press("move_right")
	if _frame == 70:
		Input.action_release("move_right")
		if _cfg.fire:
			p.set_class(_main.balance, "mage")
			p.facing = 1
			p.mp = p.max_mp
			p.spell_cd.fireball = 0.0
			p._cast_cd = 0.0
			p.cast("fireball")
	if _frame == 86:
		var img := root.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://screenshots/world_%s.png" % _scene))
		root.get_node("Log").ok("saved screenshots/world_%s.png" % _scene)
		quit(0)
	return false
