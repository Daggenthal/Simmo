extends SceneTree
## Headless environment test: day and night, weather, lights and rim light, hair and cloth physics,
## blinking, water ripples and wading, bridges, snow build-up and footprints, and two regressions
## (Simmos' own level in chat, the healer's ultimate).
## Run: godot --headless --fixed-fps 60 --path . --script res://tests/environment_test.gd

var _main
var _log
var _frame := 0
var _pf := 0
var _phase := "boot"
var _failures := 0
var WS     # res://scripts/weather_state.gd
var LG     # res://scripts/lighting.gd
var CL     # res://scripts/chat_log.gd
var _x0 := 0.0
var _v0 := 0.0
var _blinks: Array = []
var _was_blink := false
var _energy := 0.0
var _depth0 := 0.0

func _initialize() -> void:
	_log = root.get_node("Log")
	var env_seed := OS.get_environment("SIMMO_SEED")
	seed(int(env_seed) if env_seed != "" else 1357)
	WS = load("res://scripts/weather_state.gd")
	LG = load("res://scripts/lighting.gd")
	CL = load("res://scripts/chat_log.gd")
	_main = load("res://main.tscn").instantiate()
	_main.load_user_settings = false
	_main.show_start_screen = false
	_main.start_class = "mage"
	root.add_child(_main)

func _check(cond: bool, msg: String) -> void:
	if cond:
		_log.ok("PASS " + msg)
	else:
		_failures += 1
		_log.error("FAIL " + msg)

func _goto(p: String) -> void:
	_phase = p
	_pf = 0

func _park_all() -> void:
	var world = _main.world
	world._respawn_queue.clear()
	for m in world.mobs:
		m.alive = false
		m.visible = false
		m.set_physics_process(false)

func _place(a, pos: Vector2) -> void:
	a.position = pos
	a.velocity = Vector2.ZERO

func _wave_energy(wd: Dictionary) -> float:
	var e := 0.0
	for i in wd.h.size():
		e += absf(wd.h[i]) + absf(wd.v[i]) * 0.05
	return e

func _physics_process(_d: float) -> bool:
	_frame += 1
	_pf += 1
	var p = _main.player
	var w = _main.weather
	var world = _main.world
	match _phase:
		"boot":
			if _pf == 5:
				_park_all()
				for s in _main.sims:
					s.brain.leader = null  # stand still for these checks
				w.day_cycle = false
				w.time_of_day = 0.5
				_check(w.night_amount() < 0.05, "noon is bright (night %.2f)" % w.night_amount())
				w.time_of_day = 0.0
				_check(w.night_amount() > 0.95, "midnight is dark (night %.2f)" % w.night_amount())
				w.time_of_day = 0.5
				# Regressions found in screenshots.
				var healer = null
				var tank = null
				for s in _main.sims:
					if s.role == "healer": healer = s
					if s.role == "tank": tank = s
				_check(healer.ult_id == "sanctuary", "the healer Simmo's ultimate is Sanctuary, not the Mage's (%s)" % healer.ult_id)
				tank.set_level(7)
				_main.chatter._said_t.clear()
				_main.chatter._on_level(tank, 7)
				_check(CL.last("party").ends_with("7") or "level 7" in CL.last("party") or "lvl 7" in CL.last("party"), "a Simmo reports its real level in chat (%s)" % CL.last("party"))
				_goto("night")
		"night":
			if _pf == 1:
				w.time_of_day = 0.0
			if _pf == 10:
				_check(LG.darkness > 0.4, "night darkens the world (darkness %.2f)" % LG.darkness)
				var tint: Color = w.world_tint()
				_check(tint.v < 0.85, "the world tint goes dark blue at night (%s)" % str(tint))
				# Lamps light up at night.
				var lit := 0
				for l in world.env.lamps:
					if l.light and l.light.energy > 0.3:
						lit += 1
				_check(lit == world.env.lamps.size() and lit > 0, "lamps light up at night (%d of %d)" % [lit, world.env.lamps.size()])
				# A fireball carries its own light, which rim-lights a nearby character.
				_place(p, Vector2(400, 330))
				p.facing = 1
				p.mp = p.max_mp
				p.spell_cd.fireball = 0.0
				p._cast_cd = 0.0
				p.cast("fireball")
			if _pf == 12:
				var pr = p.last_projectile
				var has_light := false
				for c in pr.get_children():
					if c is PointLight2D:
						has_light = true
				_check(has_light, "a fireball carries a light")
				_check(p.doll.lights.size() >= 1, "the caster gets rim light from the fireball (%d lights)" % p.doll.lights.size())
				# Lightning lights its path.
				var n0: int = LG.count()
				load("res://scripts/fx.gd").lightning(world, Vector2(300, 250), Vector2(500, 320), Color("#ffe66b"))
				_check(LG.count() >= n0 + 3, "lightning lights up along its path (%d new lights)" % (LG.count() - n0))
				w.time_of_day = 0.5
				_goto("weather")
		"weather":
			if _pf == 1:
				w.set_state("rain")
			if _pf == 30:
				_check(w.rain > 0.3 and world.env.drops.size() > 20, "rain falls (%d drops)" % world.env.drops.size())
				w.set_state("storm")
			if _pf == 31:
				_check(absf(WS.wind) > 0.6, "storms blow harder (wind %.2f)" % WS.wind)
				w.set_state("clear")
				_goto("hair")
		"hair":
			# Hair trails behind when running, and leans with the wind.
			if _pf == 1:
				p.custom_look = true
				var lk: Dictionary = p.look.duplicate()
				lk.hair = "long"
				p.set_look(lk)
				_place(p, Vector2(300, 330))
				WS.wind = 0.0
				Input.action_press("move_right")
			if _pf == 40:
				var ch: Dictionary = p.doll.chains.hair_a
				var tip: Vector2 = ch.pts[ch.pts.size() - 1]
				_check(tip.x < ch.pts[0].x - 4.0, "running right, long hair trails behind (tip %.1f px behind the root)" % (ch.pts[0].x - tip.x))
				Input.action_release("move_right")
			if _pf == 120:
				WS.wind = -1.0
			if _pf == 240:
				var ch: Dictionary = p.doll.chains.hair_a
				_x0 = ch.pts[ch.pts.size() - 1].x - ch.pts[0].x
				WS.wind = 1.0
			if _pf == 360:
				var ch: Dictionary = p.doll.chains.hair_a
				var now: float = ch.pts[ch.pts.size() - 1].x - ch.pts[0].x
				_check(now > _x0 + 3.0, "wind blows the hair its way (tip moved %.1f px with the wind)" % (now - _x0))
				WS.wind = 0.25
				_blinks.clear()
				_goto("blink")
		"blink":
			var b: bool = p.doll.is_blinking()
			if b and not _was_blink:
				_blinks.append(_pf)
			_was_blink = b
			if _pf == 1200:
				var gaps := []
				for k in range(1, _blinks.size()):
					gaps.append(_blinks[k] - _blinks[k - 1])
				var quick := gaps.filter(func(g): return g < 60).size()
				_check(_blinks.size() >= 3 and _blinks.size() <= 14, "blinks now and then (%d in 20 s)" % _blinks.size())
				_check(quick <= maxi(1, gaps.size() / 3), "blinks are spaced out, quick doubles are rare (%d of %d gaps under 1 s)" % [quick, gaps.size()])
				_goto("water")
		"water":
			var wd: Dictionary = world.env.water_at(680)
			if _pf == 1:
				_check(wd.kind == "pond", "Mossy Meadow has a pond")
				_place(p, Vector2(600, 330))
				Input.action_press("move_right")
			if _pf == 20:
				_v0 = absf(p.velocity.x)
			if _pf == 45:
				_check(absf(p.velocity.x) < _v0 * 0.8 and world.water_kind_at(p.position.x) == "pond", "wading through the pond is slower (%.0f vs %.0f px/s)" % [absf(p.velocity.x), _v0])
				_check(_wave_energy(wd) > 5.0, "walking into the water makes ripples (energy %.1f)" % _wave_energy(wd))
				Input.action_release("move_right")
				_place(p, Vector2(300, 330))
			if _pf == 46:
				_energy = _wave_energy(wd)
			if _pf == 400:
				_check(_wave_energy(wd) < _energy * 0.3, "ripples settle down (%.1f -> %.1f)" % [_energy, _wave_energy(wd)])
				_goto("bridge")
		"bridge":
			if _pf == 1:
				_place(p, Vector2(1080, 330))
				Input.action_press("move_right")
			if _pf == 70:
				Input.action_release("move_right")
				_check(p.position.x > 1180.0 and absf(p.position.y - 330.0) < 1.0, "the bridge carries you over the river (x %.0f, y %.0f)" % [p.position.x, p.position.y])
				world.load_map("frostpeak_ruins")
				for a in world.party:
					a.arrive(world.spawn_point)
				_goto("snow")
		"snow":
			if _pf == 5:
				_park_all()
				_check(world.env.snowy and world.env.snow_depth(300, 330) > 1.0, "Frostpeak's ground is covered in snow (%.1f px)" % world.env.snow_depth(300, 330))
				_place(p, Vector2(300, 330))
				_depth0 = world.env.snow_depth(300, 330)
			if _pf == 20:
				_check(world.env.snow_depth(300, 330) < _depth0 * 0.5, "standing in snow presses it down (%.1f -> %.1f px)" % [_depth0, world.env.snow_depth(300, 330)])
				_check(world.env.snow_depth(360, 330) > _depth0 * 0.8, "next to the footprint the snow is untouched")
				_place(p, Vector2(150, 330))
				w.set_state("snow")
				_depth0 = world.env.snow_depth(300, 330)
			if _pf == 620:
				_check(world.env.snow_depth(300, 330) > _depth0 + 0.3, "falling snow fills the footprint back in (%.1f -> %.1f px)" % [_depth0, world.env.snow_depth(300, 330)])
				_check(world.env.drops.size() > 10 and world.env.drops[0].kind == "snow", "snowflakes fall in Frostpeak")
				_goto("done")
		"done":
			if _failures == 0:
				_log.ok("ALL ENVIRONMENT CHECKS PASSED (%d frames)" % _frame)
			else:
				_log.error("%d ENVIRONMENT CHECK(S) FAILED" % _failures)
			quit(1 if _failures > 0 else 0)
	if _frame > 5000:
		_log.error("timeout in phase " + _phase)
		quit(1)
	return false
