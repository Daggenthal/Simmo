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
var _auto_min_y := 9999.0

func _initialize() -> void:
	_log = root.get_node("Log")
	seed(1337)
	_main = load("res://main.tscn").instantiate()
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
				_check(player.facing == -1 and player._auto_pause > 1.0, "manual input overrides auto-battle (facing %d, auto paused %.2fs)" % [player.facing, player._auto_pause])
				Input.action_release("move_left")
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
				world.respawn_all()
			if _phase_frame == 5:
				var alive := 0
				for m in world.mobs:
					if m.alive:
						alive += 1
				_check(alive == world.mobs.size(), "all mobs respawn on F5 (%d alive)" % alive)
				_weapon_ids = player.weapons.keys()
				_goto("weapons")
		"weapons":
			_test_weapons(player, world)
		"done":
			if _failures == 0:
				_log.ok("ALL CHECKS PASSED (%d frames)" % _frame)
			else:
				_log.error("%d CHECK(S) FAILED" % _failures)
			quit(1 if _failures > 0 else 0)
	if _frame > 5000:
		_log.error("timeout in phase " + _phase)
		quit(1)
	return false

## Every platform must be reachable with one jump from the ground or another platform.
func _check_reachability(world, player) -> void:
	var cfg: Dictionary = player.cfg
	var max_up: float = pow(float(cfg.jump_velocity), 2) / (2.0 * float(cfg.gravity))
	var surfaces := [[-40.0, world.GROUND_Y, world.MAP_W + 80.0]]
	for p in world.PLATFORMS:
		surfaces.append([float(p[0]), float(p[1]), float(p[2])])
	var bad := []
	for p in world.PLATFORMS:
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
		_goto("done")
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
		var cd := float(player.weapon.cooldown)
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
