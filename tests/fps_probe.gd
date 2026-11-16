extends SceneTree
## Frame rate independence probe. Plays the same 15 s scenario (auto-battle with the party, a storm,
## a boss) and prints a FINGERPRINT of the outcome. run.sh runs it at several --fixed-fps values;
## the fingerprints must match, because gameplay runs on the fixed 60 Hz physics tick.
## Run: godot --headless --fixed-fps 144 --path . --script res://tests/fps_probe.gd

var _main
var _f := 0

func _initialize() -> void:
	seed(424242)
	_main = load("res://main.tscn").instantiate()
	_main.load_user_settings = false
	_main.show_start_screen = false
	_main.start_class = "mage"
	root.add_child(_main)

func _physics_process(_d: float) -> bool:
	_f += 1
	var p = _main.player
	var w = _main.world
	if _f == 2:
		_main.weather.set_state("storm")
		p.set_level(6)
		for s in _main.sims:
			s.set_level(6)
		p.set_auto_battle(true)
	if _f == 420:
		w.spawn_boss()
	if _f == 900:
		var sims := ""
		for s in _main.sims:
			sims += "(%.1f,%.1f,%d,%d)" % [s.position.x, s.position.y, s.hp, s.damage_dealt]
		var boss_hp: int = w.boss.hp if w.boss and is_instance_valid(w.boss) else -1
		var water := 0.0
		for wd in w.env.waters:
			for i in wd.h.size():
				water += absf(wd.h[i])
		print("FINGERPRINT player=(%.1f,%.1f) hp=%d mp=%.1f xp=%d lvl=%d kills=%d dmg=%d sims=%s boss=%d water=%.2f tod=%.4f chat=%d" % [
			p.position.x, p.position.y, p.hp, p.mp, p.xp, p.level, p.kills, p.damage_dealt, sims, boss_hp, water,
			_main.weather.time_of_day, load("res://scripts/chat_log.gd").lines.size()])
		if OS.get_environment("FPS_DUMP") == "1":
			for l in load("res://scripts/chat_log.gd").lines:
				print("CHAT %d [%s] %s" % [l.frame, l.channel, l.text])
		quit(0)
	return false
