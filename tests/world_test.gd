extends SceneTree
## Headless world test: every map's data, portal travel, mob level scaling, XP by level difference, resists.
## Run: godot --headless --fixed-fps 60 --path . --script res://tests/world_test.gd

var _main
var _log
var _frame := 0
var _pf := 0
var _phase := "boot"
var _failures := 0
var Scal   # res://scripts/scaling.gd, loaded at runtime (class names would compile before autoloads)
var _old_mob = null

func _initialize() -> void:
	_log = root.get_node("Log")
	# SIMMO_SEED=n runs with another seed, to shake out flaky checks.
	var env_seed := OS.get_environment("SIMMO_SEED")
	seed(int(env_seed) if env_seed != "" else 777)
	Scal = load("res://scripts/scaling.gd")
	_main = load("res://main.tscn").instantiate()
	_main.spawn_sims = false
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

func _press_up() -> void:
	var ev := InputEventAction.new()
	ev.action = "move_up"
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = "move_up"
	up.pressed = false
	Input.parse_input_event(up)

func _physics_process(_d: float) -> bool:
	_frame += 1
	_pf += 1
	var p = _main.player
	var world = _main.world
	match _phase:
		"boot":
			if _pf == 5:
				_check_map_data(world, p)
				_check_scaling()
				_check_xp_rules(world, p)
				_check_resist(world, p)
				_goto("portal")
		"portal":
			# Walk onto the east portal of the first map and press Up.
			if _pf == 1:
				_check(world.map_id == "mossy_meadow", "game starts in Mossy Meadow (%s)" % world.map_id)
				var east: Dictionary = world.portals[0]
				p.position = Vector2(float(east.x), world.ground_y)
				p.velocity = Vector2.ZERO
				_old_mob = world.mobs[0]
			if _pf == 10:
				_check(not world.portal_at(p.global_position).is_empty(), "player stands on the portal")
				_press_up()
			if _pf == 20:
				_check(world.map_id == "mushroom_grove", "Up on a portal travels to the next map (%s)" % world.map_id)
				_check(world.mobs.size() == world.spawns.size(), "new map spawns its own mobs (%d of %d)" % [world.mobs.size(), world.spawns.size()])
				_check(not is_instance_valid(_old_mob) or not _old_mob.is_inside_tree(), "old map's mobs are gone")
				var west: Dictionary = world.portals[0]
				_check(absf(p.global_position.x - float(west.x)) < 50.0, "player arrives at the matching portal (x=%.0f, portal %.0f)" % [p.global_position.x, west.x])
				_check(_main._cam.limit_right == int(world.map_w), "camera limits follow the new map width (%d)" % _main._cam.limit_right)
				var lowest := 999
				for m in world.mobs:
					lowest = mini(lowest, m.level)
				_check(lowest >= 6, "Mushroom Grove mobs are stronger (lowest level %d)" % lowest)
				var types := {}
				for m in world.mobs:
					types[m.id] = true
				_check(not types.has("green_slime") and types.size() >= 3, "new map has its own mob types (%s)" % str(types.keys()))
			if _pf == 40:
				# And back again.
				var west: Dictionary = world.portals[0]
				p.position = Vector2(float(west.x), world.ground_y)
				p.velocity = Vector2.ZERO
			if _pf == 50:
				_press_up()
			if _pf == 60:
				_check(world.map_id == "mossy_meadow", "west portal leads back (%s)" % world.map_id)
				_check(absf(p.global_position.x - 1760.0) < 50.0, "and lands at the east portal (x=%.0f)" % p.global_position.x)
				_goto("walk_portals")
		"walk_portals":
			# Ride every portal in a chain to the last map and check the player can stand there.
			if _pf % 20 == 1:
				var east = null
				for q in world.portals:
					if q.name == "east":
						east = q
				if east == null:
					_check(world.map_id == "frostpeak_ruins", "portal chain reaches the last map (%s)" % world.map_id)
					_goto("done")
				else:
					p.position = Vector2(float(east.x), world.ground_y)
					p.velocity = Vector2.ZERO
			if _pf % 20 == 8:
				_press_up()
			if _pf % 20 == 18:
				_check(p.is_on_floor() or p.velocity.y >= 0.0, "player is fine after entering %s (y=%.0f)" % [world.map.name, p.position.y])
		"done":
			if _failures == 0:
				_log.ok("ALL WORLD CHECKS PASSED (%d frames)" % _frame)
			else:
				_log.error("%d WORLD CHECK(S) FAILED" % _failures)
			quit(1 if _failures > 0 else 0)
	if _frame > 3000:
		_log.error("timeout in phase " + _phase)
		quit(1)
	return false

## Data rules for every map: reachable platforms, connected nav, valid spawns, two-way portals.
func _check_map_data(world, p) -> void:
	var cfg: Dictionary = p.cfg
	var max_up: float = pow(float(cfg.jump_velocity), 2) / (2.0 * float(cfg.gravity))
	var maps: Dictionary = world.maps
	var prev_low := 0
	for id in maps:
		var m: Dictionary = maps[id]
		var gy := float(m.ground_y)
		var surfaces := [[-40.0, gy, float(m.width) + 80.0]]
		for pl in m.platforms:
			surfaces.append([float(pl[0]), float(pl[1]), float(pl[2])])
		var bad := []
		for pl in m.platforms:
			var ok := false
			for s in surfaces:
				if s[1] == float(pl[1]) and s[0] == float(pl[0]):
					continue
				var rise: float = s[1] - float(pl[1])
				var gap: float = max(0.0, max(float(pl[0]) - (s[0] + s[2]), s[0] - (float(pl[0]) + float(pl[2]))))
				if rise > 0.0 and rise <= max_up - 8.0 and gap <= 56.0:
					ok = true
					break
			if not ok:
				bad.append(pl)
		_check(bad.is_empty(), "%s: every platform reachable by a jump (unreachable: %s)" % [m.name, str(bad)])
		var nav = load("res://scripts/nav.gd").new()
		nav.build(gy, float(m.width), m.platforms, max_up)
		var missing := []
		for a in nav.surfaces:
			for b in nav.surfaces:
				if a.id != b.id and nav.find_route(a.id, (a.x0 + a.x1) / 2.0, b.id, (b.x0 + b.x1) / 2.0).cost == INF:
					missing.append("%d->%d" % [a.id, b.id])
		_check(missing.is_empty(), "%s: nav graph connects every surface (missing %s)" % [m.name, str(missing)])
		var bad_spawns := []
		for s in m.spawns:
			var base: Dictionary = _main.balance.mobs.get(s[0], {})
			if base.is_empty() or nav.surface_at(float(s[1]), float(s[2])) < 0:
				bad_spawns.append(s)
			elif int(base.level) < int(m.levels[0]) or int(base.level) > int(m.levels[1]):
				bad_spawns.append(s)
		_check(bad_spawns.is_empty(), "%s: spawns are known mobs, on a surface, inside the map's level range (bad: %s)" % [m.name, str(bad_spawns)])
		var bad_portals := []
		for q in m.get("portals", []):
			var dest: Dictionary = maps.get(String(q.to), {})
			var back := false
			for r in dest.get("portals", []):
				if r.name == q.to_portal and r.to == id:
					back = true
			if not back:
				bad_portals.append(q.name)
		_check(bad_portals.is_empty(), "%s: every portal has a matching way back (broken: %s)" % [m.name, str(bad_portals)])
		_check(int(m.levels[0]) > prev_low, "%s: level range climbs from the previous map (%d-%d)" % [m.name, m.levels[0], m.levels[1]])
		prev_low = int(m.levels[0])

## Mob stats follow the player's growth: hits to kill a same-level mob stay about the same.
func _check_scaling() -> void:
	var bal: Dictionary = _main.balance
	var sc: Dictionary = bal.mob_scaling
	var base: Dictionary = bal.mobs.blue_slime
	var same = Scal.mob_stats(base, int(base.level), sc)
	_check(int(same.hp) == int(base.hp) and int(same.xp) == int(base.xp), "mob at its base level keeps its listed stats")
	var hi = Scal.mob_stats(base, 20, sc)
	_check(int(hi.hp) > int(base.hp) * 3 and int(hi.touch_damage) > int(base.touch_damage) * 3 and int(hi.xp) > int(base.xp) * 5,
		"a level 20 Blue Slime is much tougher and worth more (hp %d, dmg %d, xp %d)" % [hi.hp, hi.touch_damage, hi.xp])
	var pl: Dictionary = bal.player
	var sword: Dictionary = bal.weapons.short_sword
	var hits := []
	for lvl in [1, 10, 20, 30]:
		var per_hit: float = (float(sword.damage_min) + float(sword.damage_max)) / 2.0 + (lvl - 1) * float(pl.damage_per_level) * float(sword.cooldown) / float(pl.level_bonus_reference_cooldown)
		var m = Scal.mob_stats(bal.mobs.green_slime, lvl, sc)
		hits.append(float(m.hp) / per_hit)
	_check(hits.max() / hits.min() <= 1.3, "same-level mobs take about as many hits at every level (%s)" % ", ".join(hits.map(func(h): return "%.2f" % h)))
	var hp_share := []
	for lvl in [1, 10, 30]:
		var m = Scal.mob_stats(bal.mobs.green_slime, lvl, sc)
		hp_share.append(float(m.touch_damage) / (float(pl.max_hp) + (lvl - 1) * float(pl.hp_per_level)))
	_check(hp_share.max() / hp_share.min() <= 1.3, "same-level touch damage takes about the same share of HP (%s)" % ", ".join(hp_share.map(func(h): return "%.3f" % h)))
	# Kills per level at a fitting map grow slowly, not explode or vanish.
	var kills := []
	for id in ["green_slime", "orange_shroom", "lava_slime", "frost_slime"]:
		var b: Dictionary = bal.mobs[id]
		var lvl := int(b.level)
		var need := int(round(float(pl.xp_base) * pow(lvl, float(pl.xp_exponent))))
		kills.append(float(need) / float(Scal.mob_stats(b, lvl, sc).xp))
	_check(kills.min() >= 2.0 and kills.max() <= 10.0, "kills per level on fitting mobs stay sane (%s)" % ", ".join(kills.map(func(k): return "%.1f" % k)))

func _check_xp_rules(world, p) -> void:
	var sc: Dictionary = _main.balance.mob_scaling
	_check(is_equal_approx(Scal.xp_mult(5, 5, sc), 1.0), "same level: full XP")
	_check(is_equal_approx(Scal.xp_mult(2, 5, sc), 1.0), "%d levels under: still full XP" % int(sc.xp_grace_levels))
	_check(Scal.xp_mult(1, 8, sc) < 0.7, "7 levels under: reduced XP (x%.2f)" % Scal.xp_mult(1, 8, sc))
	_check(is_equal_approx(Scal.xp_mult(1, 30, sc), float(sc.xp_min_mult)), "far under: XP floor (x%.2f)" % Scal.xp_mult(1, 30, sc))
	_check(Scal.xp_mult(8, 5, sc) > 1.0 and Scal.xp_mult(40, 5, sc) <= float(sc.xp_max_mult) + 0.001, "higher mobs: bonus XP, capped (x%.2f, x%.2f)" % [Scal.xp_mult(8, 5, sc), Scal.xp_mult(40, 5, sc)])
	# In game: a level 20 player farming a level 1 slime gets the floor.
	var slime = world.mobs[0]
	slime.data = world.mob_data("green_slime", 1)
	slime.level = 1
	p.level = 20
	var xp0: int = p.xp
	var got: Dictionary = world.award_xp(slime, p)
	var expect := maxi(1, int(round(float(slime.data.xp) * float(sc.xp_min_mult))))
	_check(int(got.get(p, -1)) == expect and p.xp - xp0 == expect, "level 20 killing a level 1 slime gets %d XP (got %d)" % [expect, got.get(p, -1)])
	p.level = 1
	p.xp = 0
	_check(Scal.party_share(1, _main.balance.party) == 1.0, "solo: the whole kill's XP")
	var s4: float = Scal.party_share(4, _main.balance.party)
	_check(s4 > 0.25 and s4 < 1.0, "party of 4: each gets more than a quarter (x%.2f)" % s4)

## A fire imp shrugs off most fire damage and doesn't catch fire easily.
func _check_resist(world, p) -> void:
	var Comb = load("res://scripts/combat.gd")
	var imp_data: Dictionary = world.mob_data("fire_imp", 13)
	var m = world.mobs[0]
	var keep: Dictionary = m.data
	m.data = imp_data.duplicate()
	m.max_hp = 100000
	m.hp = 100000
	var r: Dictionary = Comb.hit(m, p, 100, "fire", {"crit_chance": 0.0})
	_check(int(r.amount) == 25, "fire imp takes 25%% of fire damage (100 -> %d)" % int(r.amount))
	var r2: Dictionary = Comb.hit(m, p, 100, "frost", {"crit_chance": 0.0})
	_check(int(r2.amount) == 100, "fire imp takes full frost damage (%d)" % int(r2.amount))
	var burns := 0
	for k in 400:
		m.clear_statuses()
		Comb.hit(m, p, 1, "fire", {"crit_chance": 0.0})
		if m.is_burning():
			burns += 1
	_check(burns < 160, "fire resist cuts the burn chance (%d of 400 hits burned)" % burns)
	m.clear_statuses()
	m.data = keep
	m.respawn()
	m.max_hp = int(keep.hp)
	m.hp = m.max_hp
