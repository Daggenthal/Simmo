extends SceneTree
## Soak run: the real game with the party and auto-battle on, 60 s per map at a fitting level.
## Watch the output for SCRIPT ERROR lines. Prints kills, levels and knockouts per map.
## Run: godot --headless --fixed-fps 60 --path . --script res://tools/soak.gd

const PLAN := [["mossy_meadow", 1], ["mushroom_grove", 7], ["ember_crags", 14], ["frostpeak_ruins", 22]]
var _main
var _log
var _frame := 0
var _idx := -1
var _kills0 := 0
var _kos := 0

func _initialize() -> void:
	_log = root.get_node("Log")
	_main = load("res://main.tscn").instantiate()
	_main.load_user_settings = false
	_main.show_start_screen = false
	var cls := OS.get_environment("SIMMO_CLASS")
	_main.start_class = cls
	root.add_child(_main)

func _physics_process(_d: float) -> bool:
	_frame += 1
	var p = _main.player
	if _frame % 3600 == 1:
		if _idx >= 0:
			var k: int = p.kills
			for s in _main.sims:
				k += s.kills
			_log.ok("%s: party kills %d, player Lv %d, sims Lv %s, knockouts %d" % [_main.world.map.name, k - _kills0, p.level, str(_main.sims.map(func(s): return s.level)), _kos])
		_idx += 1
		if _idx >= PLAN.size():
			quit(0)
			return false
		_main.world.load_map(PLAN[_idx][0])
		p.set_level(int(PLAN[_idx][1]))
		for s in _main.sims:
			s.set_level(p.level)
		var k := 0
		for a in _main.world.party:
			a.arrive(_main.world.spawn_point)
			if a != p:
				k += a.kills
		_kills0 = p.kills + k
		_kos = 0
		p.set_auto_battle(true)
	for s in _main.sims:
		if s.down_t > 0.0 and s.down_t > float(_main.balance.party.respawn_time) - 0.02:
			_kos += 1
	return false
