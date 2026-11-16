extends SceneTree
## Mage on auto-battle on a real map: which spells get cast, and why the others don't.
## Run: SIMMO_CLASS=mage godot --headless --fixed-fps 60 --path . --script res://tools/spell_probe.gd

var _main
var _frame := 0
var _why := {}

func _initialize() -> void:
	seed(int(OS.get_environment("SIMMO_SEED")) if OS.get_environment("SIMMO_SEED") != "" else 1)
	_main = load("res://main.tscn").instantiate()
	_main.load_user_settings = false
	_main.show_start_screen = false
	_main.start_class = OS.get_environment("SIMMO_CLASS") if OS.get_environment("SIMMO_CLASS") != "" else "mage"
	_main.spawn_sims = OS.get_environment("SIMMO_SIMS") == "1"
	_main.start_map = OS.get_environment("SIMMO_MAP")
	root.add_child(_main)

func _physics_process(_d: float) -> bool:
	_frame += 1
	var p = _main.player
	if _frame == 5:
		root.get_node("Log").debug = false
		p.set_level(int(OS.get_environment("SIMMO_LEVEL")) if OS.get_environment("SIMMO_LEVEL") != "" else 3)
		if OS.get_environment("SIMMO_SPRITE") != "":
			var lk: Dictionary = p.look.duplicate()
			lk.sprite = OS.get_environment("SIMMO_SPRITE")
			p.custom_look = true
			p.set_look(lk)
		p.set_auto_battle(true)
	# Every 10 frames, record why each spell can't go: cooldown, MP, global cooldown.
	if _frame > 5 and _frame % 10 == 0 and p.brain.target != null:
		for id in p.spells:
			var r := "ready"
			if p.spell_cd[id] > 0.0: r = "cd"
			elif p.mp < float(p.spells[id].mp): r = "mp"
			elif p._cast_cd > 0.0: r = "gcd"
			if r == "ready":
				var t = p.brain.target
				var sp: Dictionary = p.spells[id]
				var dist := absf(t.global_position.x - p.global_position.x)
				var dy := absf(p.brain.mob_surface_y(t) - p.global_position.y)
				var max_dy := 90.0 if sp.kind == "lob" else 22.0
				if t.resist(String(sp.element)) >= 0.5: r = "ready-resisted"
				elif dist > float(sp.range): r = "ready-too-far(%d)" % (int(dist) / 50 * 50)
				elif dy > max_dy: r = "ready-height"
				elif id == "chain_lightning" and not t.is_frozen(): r = "ready-not-frozen"
				elif id == "fireball" and t.is_burning() and t.poison_stacks < 3: r = "ready-already-burning"
				elif id == "frost_bolt" and (t.is_frozen() or t.is_chilled()): r = "ready-already-chilled"
				elif id == "venom_glob" and t.poison_stacks >= 3: r = "ready-3-stacks"
				else: r = "ready-eligible"
			var k: String = "%s:%s" % [id, r]
			_why[k] = int(_why.get(k, 0)) + 1
	if _frame == 60 * 60:
		var counts := {}
		for e in p.cast_log:
			counts[e[1]] = int(counts.get(e[1], 0)) + 1
		print("casts: ", counts, "  swings: ", p.swings, "  level: ", p.level, "  mp ", p.mp, "/", p.max_mp)
		var keys := _why.keys()
		keys.sort()
		for k in keys:
			print("  ", k, " ", _why[k])
		quit(0)
	return false
