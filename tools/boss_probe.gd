extends SceneTree
## Balance probe: a full auto-battling party against each map's boss at the boss's level.
## Prints how long the kill took (enrage is at 90 s), knockouts, and player deaths.
## Run: SIMMO_CLASS=mage godot --headless --fixed-fps 60 --path . --script res://tools/boss_probe.gd

const PLAN := ["mossy_meadow", "mushroom_grove", "ember_crags", "frostpeak_ruins"]
var _main
var _f := 0
var _idx := -1
var _start := 0
var _kos := 0
var _deaths := 0

func _initialize() -> void:
	_main = load("res://main.tscn").instantiate()
	_main.load_user_settings = false
	_main.show_start_screen = false
	_main.start_class = OS.get_environment("SIMMO_CLASS")
	root.add_child(_main)

func _next() -> void:
	_idx += 1
	if _idx >= PLAN.size():
		quit(0)
		return
	var w = _main.world
	w.load_map(PLAN[_idx])
	var spec: Dictionary = _main.balance.bosses.maps[PLAN[_idx]]
	var lvl := int(_main.balance.mobs[spec.id].level)
	_main.player.set_level(lvl)
	for s in _main.sims:
		s.set_level(lvl)
	for a in w.party:
		a.arrive(Vector2(float(spec.spawn_x) - 120.0, w.ground_y))
		a.ult_cd = 0.0
	w.spawn_boss()
	_main.player.set_auto_battle(true)
	_start = _f
	_kos = 0
	_deaths = 0

func _physics_process(_d: float) -> bool:
	_f += 1
	if _f == 5:
		_main.weather.weather_on = false
		_main.player.died.connect(func() -> void: _deaths += 1)
		for s in _main.sims:
			s.died.connect(func() -> void: _kos += 1)
		_next()
		return false
	var w = _main.world
	if _idx >= 0 and _idx < PLAN.size():
		var secs := (_f - _start) / 60.0
		if w.boss == null or secs > 150.0:
			var b_name: String = _main.balance.mobs[_main.balance.bosses.maps[PLAN[_idx]].id].name
			print("BOSS %s: %s in %.0f s, Simmo knockouts %d, player deaths %d" % [b_name, "killed" if w.boss == null else "NOT killed", secs, _kos, _deaths])
			_next()
	return false
