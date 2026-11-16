extends SceneTree
## Headless smoke test: boots the main scene, checks the world, moves the player,
## jumps, drops through a platform, kills mobs, checks XP and level-ups.
## Run: godot --headless --fixed-fps 60 --path . --script res://tests/smoke_test.gd
## Exit code 0 = pass, 1 = failures (all checks run so one pass shows every problem).

var _main: Node
var _frame := 0
var _failures := 0
var _log: Node
var _start_x := 0.0
var _phase := "boot"
var _phase_frame := 0
var _auto_kills := 0
var _weapon_ids: Array = []
var _weapon_idx := 0
var _swings_start := 0
var _nav_idx := 0
var _nav_max_y := 0.0
var _nav_kills := 0
## [start x, start platform y, mob x, mob platform y, label]
const NAV_CASES := [
	[550, 225, 380, 270, "higher platform -> lower platform on the left (the reported bug)"],
	[1000, 208, 820, 270, "higher platform -> lower platform across a gap"],
	[1450, 205, 1250, 268, "higher platform -> lower platform, wide gap"],
	[380, 270, 550, 225, "lower platform -> higher platform on the right"],
	[820, 270, 1000, 208, "lower platform -> higher platform across a gap"],
]
var _auto_min_y := 9999.0

func _initialize() -> void:
	_log = root.get_node("Log")
	# SIMMO_SEED=n runs with another seed, to shake out flaky checks.
	var env_seed := OS.get_environment("SIMMO_SEED")
	seed(int(env_seed) if env_seed != "" else 1337)
	_main = load("res://main.tscn").instantiate()
	_main.spawn_sims = false  # solo: these checks count the player's own kills
	root.add_child(_main)

func _check(cond: bool, msg: String) -> void:
	if cond:
		_log.ok("PASS " + msg)
	else:
		_failures += 1
		_log.error("FAIL " + msg)

func _goto(p: String) -> void:
	_phase = p
	_phase_frame = 0

func _physics_process(_delta: float) -> bool:
	_frame += 1
	_phase_frame += 1
	var player = _main.player
	var world = _main.world
	match _phase:
		"boot":
			if _phase_frame == 10:
				_check(player != null, "player exists")
				_check(world.mobs.size() == 12, "12 mobs spawned (got %d)" % world.mobs.size())
				_check(player.is_on_floor(), "player standing on ground")
				_check_reachability(world, player)
				# Park mobs so movement checks don't depend on random bumps.
				for m in world.mobs:
					m.alive = false
					m.visible = false
					m.set_physics_process(false)
				_start_x = player.position.x
				Input.action_press("move_right")
				_goto("walk")
		"walk":
			if _phase_frame == 60:
				Input.action_release("move_right")
				_check(player.position.x > _start_x + 50, "player walked right (%.0f -> %.0f)" % [_start_x, player.position.x])
				Input.action_press("jump")
				_goto("jump")
		"jump":
			if _phase_frame == 8:
				_check(player.velocity.y < 0 and not player.is_on_floor(), "player jumped")
				Input.action_release("jump")
			if _phase_frame == 90:
				_check(player.is_on_floor(), "player landed")
				# Stand under the first one-way platform and jump up through it for real.
				player.position = Vector2(370, 330)
				player.velocity = Vector2.ZERO
				_goto("platform")
		"platform":
			if _phase_frame == 10:
				Input.action_press("jump")
			if _phase_frame == 40:
				Input.action_release("jump")
			if _phase_frame == 90:
				_check(player.is_on_floor() and player.position.y < 275, "player stands on one-way platform (y=%.0f)" % player.position.y)
				Input.action_press("move_down")
				Input.action_press("jump")
			if _phase_frame == 94:
				Input.action_release("jump")
				Input.action_release("move_down")
			if _phase_frame == 140:
				_check(player.position.y > 320, "player dropped through platform (y=%.0f)" % player.position.y)
				for m in world.mobs:
					m.respawn()
				_auto_kills = player.kills
				player.set_auto_battle(true)
				_goto("auto")
		"auto":
			# Hands off: auto-battle should find, reach and kill mobs on its own.
			if _phase_frame == 2400:
				var got: int = player.kills - _auto_kills
				_check(got >= 6, "auto-battle killed mobs on its own (%d kills)" % got)
				_goto("climb")
		"climb":
			# Only one mob left alive, up on a platform: auto-battle must climb to it.
			var high = null
			if _phase_frame == 1:
				player.cfg.auto_use_spells = false  # movement tests: no ranged shortcuts
				for m in world.mobs:
					if m.home.y < 300.0 and high == null:
						high = m
						m.respawn()
					else:
						m.alive = false
						m.visible = false
						m.set_physics_process(false)
				_auto_kills = player.kills
				player.position = Vector2(world.spawn_point.x, 330)
				player.velocity = Vector2.ZERO
			if player.is_on_floor():
				_auto_min_y = min(_auto_min_y, player.position.y)
			if player.kills > _auto_kills or _phase_frame == 1200:
				_check(player.kills > _auto_kills, "auto-battle climbs to a mob on a platform and kills it (%d frames)" % _phase_frame)
				_check(_auto_min_y < 300.0, "auto-battle landed on a platform (highest floor y=%.0f)" % _auto_min_y)
				for m in world.mobs:
					m.respawn()
				player.set_auto_battle(false)
				_goto("override")
		"override":
			# Manual input must take over from auto-battle immediately.
			if _phase_frame == 1:
				player.set_auto_battle(true)
				Input.action_press("move_left")
			if _phase_frame == 30:
				_check(player.facing == -1 and player._auto_pause > 0.0, "manual input overrides auto-battle (facing %d, auto paused %.2fs)" % [player.facing, player._auto_pause])
				Input.action_release("move_left")
				_goto("resume")
		"resume":
			# After letting go, auto must pick a target from the new spot within half a second.
			if _phase_frame == 30:
				var t = player.brain.target
				_check(t != null and t.alive and (absf(player.velocity.x) > 1.0 or player._swing_time > 0.0),
					"auto-battle resumes within 0.5s of letting go (target %s, vx %.0f)" % [str(t.id) if t else "none", player.velocity.x])
				# Steering by hand with a mob right in front: auto keeps swinging.
				var m = null
				for mm in world.mobs:
					if mm.alive:
						m = mm
						break
				m.max_hp = 99999
				m.hp = 99999
				m.set_physics_process(false)
				# On the ground, so the check doesn't depend on where auto-battle was mid-jump.
				player.position = Vector2(700, 330)
				player.velocity = Vector2.ZERO
				player.facing = 1
				m.global_position = player.global_position + Vector2(14, 0)
				_swings_start = player.swings
				Input.action_press("move_down")
			if _phase_frame == 90:
				Input.action_release("move_down")
				_check(player.swings > _swings_start, "auto-battle keeps attacking while you steer (%d swings)" % (player.swings - _swings_start))
				for mm in world.mobs:
					mm.respawn()
				player.set_auto_battle(false)
				_goto("fight")
		"fight":
			# Teleport next to each live ground mob and swing until it dies.
			var target = null
			for m in world.mobs:
				if m.alive and m.position.y > 320:
					target = m
					break
			if target == null or _phase_frame > 1500:
				_check(player.kills >= 5, "killed at least 5 mobs (got %d)" % player.kills)
				_check(player.level >= 2, "leveled up from kills (level %d)" % player.level)
				_check(player.hp > 0, "player still alive or respawned (hp %d)" % player.hp)
				_goto("respawn")
			else:
				player.facing = 1
				player.position = Vector2(target.position.x - 18, player.position.y)
				target._dir = 0
				if _phase_frame % 25 == 0:
					player._attack_cd = 0.0
					player.attack()
		"respawn":
			if _phase_frame == 1:
				# Count right away: a swing still winding up from the fight phase can kill a fresh slime.
				player._pending_hit = -1.0
				world.respawn_all()
				var alive := 0
				for m in world.mobs:
					if m.alive:
						alive += 1
				_check(alive == world.mobs.size(), "all mobs respawn on F5 (%d alive)" % alive)
				_weapon_ids = player.weapons.keys()
				_goto("weapons")
		"weapons":
			_test_weapons(player, world)
		"nav":
			_test_nav(player, world)
		"focus":
			_test_focus(player, world)
		"done":
			if _failures == 0:
				_log.ok("ALL CHECKS PASSED (%d frames)" % _frame)
			else:
				_log.error("%d CHECK(S) FAILED" % _failures)
			quit(1 if _failures > 0 else 0)
	if _frame > 15000:
		_log.error("timeout in phase " + _phase)
		quit(1)
	return false

## Every platform must be reachable with one jump from the ground or another platform.
func _check_reachability(world, player) -> void:
	var cfg: Dictionary = player.cfg
	var max_up: float = pow(float(cfg.jump_velocity), 2) / (2.0 * float(cfg.gravity))
	var surfaces := [[-40.0, world.ground_y, world.map_w + 80.0]]
	for p in world.platforms:
		surfaces.append([float(p[0]), float(p[1]), float(p[2])])
	var bad := []
	for p in world.platforms:
		var ok := false
		for s in surfaces:
			if s[1] == float(p[1]) and s[0] == float(p[0]):
				continue
			var rise: float = s[1] - float(p[1])
			var gap: float = max(0.0, max(float(p[0]) - (s[0] + s[2]), s[0] - (float(p[0]) + float(p[2]))))
			if rise > 0.0 and rise <= max_up - 8.0 and gap <= 60.0:
				ok = true
				break
		if not ok:
			bad.append(p)
	_check(bad.is_empty(), "all platforms reachable by jumping (max jump %.0f px; unreachable: %s)" % [max_up, str(bad)])

## Hold attack for 3 s with each weapon and count real swings; then static balance checks.
func _test_weapons(player, world) -> void:
	if _weapon_idx >= _weapon_ids.size():
		_weapon_balance(player, world)
		_goto("nav")
		return
	var wid: String = _weapon_ids[_weapon_idx]
	if _phase_frame == 1:
		for m in world.mobs:
			m.alive = false
			m.visible = false
			m.set_physics_process(false)
		player.equip(wid)
		player.set_auto_battle(false)
		_swings_start = player.swings
		Input.action_press("attack")
	if _phase_frame == 181:
		Input.action_release("attack")
		var cd := float(player.weapon.cooldown) * float(player.cfg.get("attack_speed_scale", 1.0))
		var got: int = player.swings - _swings_start
		var expect := int(ceil(3.0 / cd))
		_check(absi(got - expect) <= 1, "%s swings every %.2fs while held (%d swings in 3s, expected ~%d)" % [player.weapon.name, cd, got, expect])
		_weapon_idx += 1
		_phase_frame = 0

func _weapon_balance(player, world) -> void:
	var w: Dictionary = player.weapons
	var light: Dictionary = w.dagger
	var heavy: Dictionary = w.iron_hammer
	_check(float(heavy.cooldown) > float(light.cooldown) * 2.0, "hammer swings much slower than dagger (%.2fs vs %.2fs)" % [heavy.cooldown, light.cooldown])
	_check((heavy.damage_min + heavy.damage_max) > 2.5 * (light.damage_min + light.damage_max), "hammer hits much harder per swing than dagger")
	for lvl in [1, 10, 30]:
		player.level = lvl
		var dps := []
		for k in w:
			dps.append(player.weapon_dps(w[k]))
		var spread: float = dps.max() / dps.min()
		_check(spread <= 1.3, "weapon DPS stays balanced at level %d (spread x%.2f: %s)" % [lvl, spread, ", ".join(dps.map(func(d): return "%.1f" % d))])
	player.level = 1
	# Wind-up: the hammer's hit lands later than the swing starts.
	player.equip("iron_hammer")
	player.attack()
	_check(player._pending_hit > 0.0, "hammer has a wind-up before the hit lands (%.2fs)" % player._pending_hit)
	player._pending_hit = -1.0
	# Cleave: line up 4 mobs in front and count targets per weapon.
	var lineup := []
	for m in world.mobs:
		if lineup.size() < 4:
			lineup.append(m)
	for k in ["dagger", "iron_hammer"]:
		player.equip(k)
		player.facing = 1
		for j in lineup.size():
			var m = lineup[j]
			m.respawn()
			m.max_hp = 99999
			m.hp = 99999
			m.set_physics_process(false)
			m.global_position = player.global_position + Vector2(12 + j * 3, 0)
		var hits: int = player._resolve_hit()
		_check(hits == int(w[k].max_targets), "%s hits %d target(s) per swing (got %d)" % [w[k].name, w[k].max_targets, hits])

## Auto-battle must go platform to platform without touching the ground when that's the short way.
func _test_nav(player, world) -> void:
	if _phase_frame == 1:
		world._respawn_queue.clear()
	if _phase_frame == 1 and _nav_idx == 0:
		var nav = world.nav
		var missing := []
		for a in nav.surfaces:
			for b in nav.surfaces:
				if a.id != b.id and nav.find_route(a.id, (a.x0 + a.x1) / 2.0, b.id, (b.x0 + b.x1) / 2.0).cost == INF:
					missing.append("%d->%d" % [a.id, b.id])
		_check(missing.is_empty(), "nav graph connects every surface (%d surfaces, %d links; missing %s)" % [nav.surfaces.size(), nav.links.size(), str(missing)])
	if _nav_idx >= NAV_CASES.size():
		_goto("focus")
		return
	var c: Array = NAV_CASES[_nav_idx]
	if _phase_frame == 1:
		player.set_auto_battle(false)
		var mob = world.mobs[0]
		for m in world.mobs:
			m.alive = false
			m.visible = false
			m.set_physics_process(false)
		mob.home = Vector2(c[2], c[3] - 1)
		mob.max_hp = int(mob.data.hp)
		mob.set_bounds(world.nav)
		mob.respawn()
		mob.data = mob.data.duplicate()
		mob.data.speed = 0.0
		mob.data.hop_velocity = 0.0
		player.position = Vector2(c[0], c[1])
		player.velocity = Vector2.ZERO
		_nav_kills = player.kills
		_nav_max_y = 0.0
	if _phase_frame == 6:
		player.set_auto_battle(true)
	if _phase_frame > 6:
		_nav_max_y = max(_nav_max_y, player.position.y)
	if OS.get_environment("NAV_TRACE") == "1" and _phase_frame % 20 == 0:
		var mm = world.mobs[0]
		print("trace f=%d player=(%.0f,%.0f) mob=(%.0f,%.0f) floor=%s mob_s=%d" % [_phase_frame, player.position.x, player.position.y, mm.position.x, mm.position.y, mm.is_on_floor(), world.nav.surface_at(mm.position.x, mm.position.y)])
	if player.kills > _nav_kills or _phase_frame == 900:
		_check(player.kills > _nav_kills and _nav_max_y < 300.0,
			"auto-battle %s without touching the ground (%s in %d frames, lowest feet y=%.0f)" % [c[4], "killed" if player.kills > _nav_kills else "NOT killed", _phase_frame, _nav_max_y])
		player.set_auto_battle(false)
		_nav_idx += 1
		_phase_frame = 0

## The reported case: hammer knocks a ground mob back, a fresh mob sits on the platform
## right above. Auto-battle must finish the wounded one first.
var _wounded = null
var _fresh = null
func _test_focus(player, world) -> void:
	if _phase_frame == 1:
		player.set_auto_battle(false)
		player.equip("iron_hammer")
		for m in world.mobs:
			m.alive = false
			m.visible = false
			m.set_physics_process(false)
		world._respawn_queue.clear()
		_wounded = world.mobs[0]
		_fresh = world.mobs[1]
		for pair in [[_wounded, Vector2(430, 329)], [_fresh, Vector2(380, 269)]]:
			var m = pair[0]
			m.home = pair[1]
			m.data = m.data.duplicate()
			m.data.hp = 60
			m.data.speed = 0.0
			m.data.hop_velocity = 0.0
			m.max_hp = 60
			m.set_bounds(world.nav)
			m.respawn()
		player.position = Vector2(420, 330)
		player.velocity = Vector2.ZERO
		player.facing = 1
	if _phase_frame == 3:
		# One hammer hit on the ground mob: wounds it and sends it flying 120 px away,
		# further than the fresh mob on the platform overhead.
		_wounded.take_hit(25, false, 1, player, 210.0)
		_wounded.global_position = Vector2(540, 329)
		_wounded.velocity = Vector2.ZERO
	if _phase_frame == 30:
		player.set_auto_battle(true)
	if OS.get_environment("NAV_TRACE") == "1" and (_phase_frame % 10 == 0 or _phase_frame < 6) and _phase_frame < 200:
		var t = player.brain.target
		print("focus f=%d player=(%.0f,%.0f) wounded=(%.0f,%.0f) fresh=(%.0f,%.0f) target=%s" % [_phase_frame, player.position.x, player.position.y, _wounded.position.x, _wounded.position.y, _fresh.position.x, _fresh.position.y, "wounded" if t == _wounded else ("fresh" if t == _fresh else "none")])
	if _phase_frame > 30 and (not _wounded.alive or not _fresh.alive or _phase_frame == 900):
		_check(not _wounded.alive and _fresh.alive, "auto-battle finishes the wounded mob before switching to a fresh one (wounded %s, fresh %s)" % ["dead" if not _wounded.alive else "alive", "dead" if not _fresh.alive else "alive"])
		player.set_auto_battle(false)
		player.equip("short_sword")
		_goto("done")
