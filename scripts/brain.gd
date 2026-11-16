class_name Brain
extends RefCounted
## Auto-battle brain, shared by the player's auto mode and every SimPlayer.
## think() looks at the world and returns an intent for its actor; it never moves the body itself.
##
## Solo (no leader): nearest mob by real travel distance on the nav graph, follow the route
## (jump up, jump across, walk off, drop), weave weapon attacks between spells, set up combos.
## With a leader (SimPlayers): stay within the leash, only fight mobs near the leader,
## and play a role:
##   tank    stands in front of the leader, picks the mobs closest to the leader
##   healer  stands behind, heals whoever drops under heal_below, fights only close mobs
##   ranged  throws from a platform above the target when one is in reach (a perch)

var a: Actor
var target: Mob = null
var leader: Actor = null
var role := ""
## Role tuning from balance.json sim_roles (follow_offset, engage_radius).
var role_cfg: Dictionary = {}
## Party tuning from balance.json party (follow_leash, engage_radius, heal_below).
var party_cfg: Dictionary = {}
var _retarget := 0.0
var _nav_link: Dictionary = {}
var _chase_time := 0.0
var _ignored: Dictionary = {} # mob -> seconds left; targets we gave up on
var _leader_surface := -1
var _perch: Dictionary = {}   # {id, x, y} surface a ranged sim throws from
var _perch_check := 0.0

func _init(actor: Actor) -> void:
	a = actor

func reset() -> void:
	target = null
	_ignored.clear()
	_chase_time = 0.0
	_nav_link = {}
	_retarget = 0.0
	_perch = {}
	_leader_surface = -1

func has_leader() -> bool:
	return leader != null and is_instance_valid(leader) and leader.is_inside_tree()

func think(delta: float) -> Dictionary:
	var i := Actor.blank_intent()
	var cfg: Dictionary = a.cfg
	_retarget -= delta
	for m in _ignored.keys():
		_ignored[m] -= delta
		if _ignored[m] <= 0.0 or not is_instance_valid(m):
			_ignored.erase(m)
	# Give up on a target we've chased too long without landing a swing (unreachable).
	_chase_time += delta
	if target and _chase_time > float(cfg.auto_give_up_time):
		Log.dbg("auto-battle giving up on %s at %s" % [target.id, target.position])
		_ignored[target] = 4.0
		target = null
	var following := has_leader()
	if following:
		if leader.is_on_floor() and a.world:
			_leader_surface = a.world.nav.surface_at(leader.global_position.x, leader.global_position.y)
		if role == "healer":
			_try_heal(i)
		# Too far from the leader: drop everything and catch up.
		if a.global_position.distance_to(leader.global_position) > float(party_cfg.get("follow_leash", 220.0)):
			target = null
			return _follow(i)
	var lost: bool = target == null or not is_instance_valid(target) or not target.alive
	# Once a target is wounded we stay on it until it dies (or we give up on it).
	var engaged: bool = not lost and target.hp < target.max_hp
	# Only re-plan while standing on something, so routes start from a known surface.
	if lost or (_retarget <= 0.0 and a.is_on_floor() and not engaged):
		_retarget = float(cfg.auto_retarget)
		var picked := _pick_target()
		if picked != target:
			_chase_time = 0.0
			_perch = {}
		target = picked
		if target and role == "ranged":
			_perch = _find_perch(target)
	var t: Mob = target
	if t == null:
		return _follow(i) if following else i
	var x := a.global_position.x
	var dx := t.global_position.x - x
	var weapon: Dictionary = a.weapon
	var thrown: bool = weapon.get("thrown", false)
	var t_dy := absf(mob_surface_y(t) - a.global_position.y)
	var weapon_can_hit: bool = thrown and absf(dx) <= float(weapon.range) and t_dy < 90.0
	# Weave: use the weapon whenever it's ready and in reach, spells in between.
	var weapon_ready: bool = a._attack_cd <= 0.0 and (weapon_can_hit or a._mob_in_front())
	if bool(cfg.get("auto_use_spells", true)) and i.spell == "":
		# Combo finishers (lightning on frozen, fire on stacked poison) beat a weapon swing;
		# other spells wait until the weapon is busy.
		var pick := pick_spell(t)
		if pick != "" and (not weapon_ready or is_combo_finisher(pick, t)):
			i.spell = pick
			_chase_time = 0.0
	# Ranged role: get up on a perch above the target, throwing on the way when it can.
	# Targets get knocked around, so re-pick the perch when it stops covering the target.
	_perch_check -= delta
	if role == "ranged" and target and _perch_check <= 0.0 and not _perch_covers(_perch, t):
		_perch_check = 0.5
		_perch = _find_perch(t)
	if thrown and role == "ranged" and a.is_on_floor() and not _perch.is_empty() and a.world:
		if weapon_can_hit and a._attack_cd <= 0.0:
			i.attack = true
			_chase_time = 0.0
		var my_s := a.world.nav.surface_at(x, a.global_position.y)
		if my_s != int(_perch.id):
			_nav_link = {}
			return _route_to(i, int(_perch.id), float(_perch.x))
		if weapon_can_hit:
			a.facing = 1 if dx >= 0.0 else -1
			return i
	# Thrown weapons attack from range, any height they can arc to,
	# and keep closing to a comfortable distance while the throw cools down.
	if thrown and a.is_on_floor() and weapon_can_hit:
		a.facing = 1 if dx >= 0.0 else -1
		if a._attack_cd <= 0.0:
			i.attack = true
			_chase_time = 0.0
		var preferred := float(weapon.range) * float(cfg.get("thrown_preferred_range", 0.6))
		if absf(dx) > preferred and t_dy < 20.0:
			i.dir = signf(dx)
		return i
	# In the air: steer toward where the current move should land.
	if not a.is_on_floor():
		return _air(i)
	_nav_link = {}
	var t_y := mob_surface_y(t)
	var my_s := a.world.nav.surface_at(x, a.global_position.y) if a.world else -1
	var t_s := a.world.nav.surface_at(t.global_position.x, t_y) if a.world else -1
	var reach := float(weapon.range) * 0.8 + Actor.W / 2.0 + t.size.x / 2.0
	if my_s == t_s or my_s < 0 or t_s < 0:
		if absf(dx) > reach:
			i.dir = signf(dx)
		elif absf(t_y - a.global_position.y) < 20.0:
			a.facing = 1 if dx >= 0.0 else -1
			i.attack = true
			_chase_time = 0.0
		return i
	var route: Dictionary = a.world.nav.find_route(my_s, x, t_s, t.global_position.x)
	if route.links.is_empty():
		i.dir = signf(dx)
		return i
	return _take_link(i, route.links[0])

func _air(i: Dictionary) -> Dictionary:
	if not _nav_link.is_empty():
		var to_land: float = _nav_link.land_x - a.global_position.x
		i.dir = signf(to_land) if absf(to_land) > 3.0 else 0.0
	return i

## Walk to the link's departure point, then make the move.
func _take_link(i: Dictionary, l: Dictionary) -> Dictionary:
	var to_depart: float = l.depart_x - a.global_position.x
	if absf(to_depart) > 4.0 and not (l.kind == "walk_off" and signf(to_depart) != l.dir):
		i.dir = signf(to_depart)
		return i
	_nav_link = l
	match l.kind:
		"jump_up":
			i.jump = true
		"jump_across":
			i.jump = true
			i.dir = l.dir
		"walk_off":
			i.dir = l.dir
		"drop":
			i.down = true
			i.jump = true
	Log.dbg("auto: %s from surface %d to %d" % [l.kind, l.from, l.to])
	return i

## Public: head for (surface, x) along the nav graph (used for walking to portals).
func go_to(to_s: int, to_x: float, _delta: float) -> Dictionary:
	var i := Actor.blank_intent()
	if absf(to_x - a.global_position.x) <= 6.0 and a.is_on_floor() and a.world and a.world.nav.surface_at(a.global_position.x, a.global_position.y) == to_s:
		return i
	return _route_to(i, to_s, to_x)

## Head for (surface, x) along the nav graph.
func _route_to(i: Dictionary, to_s: int, to_x: float) -> Dictionary:
	if not a.is_on_floor():
		return _air(i)
	_nav_link = {}
	var x := a.global_position.x
	var my_s := a.world.nav.surface_at(x, a.global_position.y) if a.world else -1
	if my_s < 0 or to_s < 0 or my_s == to_s:
		if absf(to_x - x) > 4.0:
			i.dir = signf(to_x - x)
		return i
	var route: Dictionary = a.world.nav.find_route(my_s, x, to_s, to_x)
	if route.links.is_empty():
		i.dir = signf(to_x - x)
		return i
	return _take_link(i, route.links[0])

## Stand near the leader: tanks in front, healers and ranged behind (role follow_offset).
func _follow(i: Dictionary) -> Dictionary:
	if not has_leader():
		return i
	if not a.is_on_floor():
		return _air(i)
	var lx := leader.global_position.x
	var off := float(role_cfg.get("follow_offset", -30.0)) * leader.facing
	if _leader_surface < 0 or a.world == null:
		if absf(lx + off - a.global_position.x) > 12.0:
			i.dir = signf(lx + off - a.global_position.x)
		return i
	var s: Dictionary = a.world.nav.surfaces[_leader_surface]
	var gx := clampf(lx + off, float(s.x0) + 6.0, float(s.x1) - 6.0)
	var my_s := a.world.nav.surface_at(a.global_position.x, a.global_position.y)
	if my_s == _leader_surface:
		_nav_link = {}
		if absf(gx - a.global_position.x) > 12.0:
			i.dir = signf(gx - a.global_position.x)
		else:
			a.facing = leader.facing
		return i
	return _route_to(i, _leader_surface, gx)

## Healers: heal the most hurt party member under the threshold who is in range.
func _try_heal(i: Dictionary) -> void:
	if not a.spells.has("heal") or not a.can_cast("heal") or a.world == null:
		return
	var below := float(party_cfg.get("heal_below", 0.65))
	var reach := float(a.spells.heal.range)
	var best: Node2D = null
	var best_frac := below
	for m in a.world.party:
		if not is_instance_valid(m) or not m.is_inside_tree() or not m.is_alive():
			continue
		var frac := float(m.hp) / float(m.max_hp)
		if frac < best_frac and m.global_position.distance_to(a.global_position) <= reach:
			best_frac = frac
			best = m
	if best:
		a.spell_target = best
		i.spell = "heal"

## A platform above the target the ranged sim can throw from, or {}.
func _find_perch(t: Mob) -> Dictionary:
	if a.world == null:
		return {}
	var nav: Nav = a.world.nav
	var t_y := mob_surface_y(t)
	var max_dx := float(a.weapon.range) * 0.7
	var my_s := nav.surface_at(a.global_position.x, a.global_position.y)
	var best := {}
	var best_cost := INF
	for s in nav.surfaces:
		var dy: float = t_y - float(s.y)
		if not s.one_way or dy < 20.0 or dy > 85.0:
			continue
		var px := clampf(t.global_position.x, float(s.x0) + 8.0, float(s.x1) - 8.0)
		if absf(px - t.global_position.x) > max_dx:
			continue
		var cost: float = nav.find_route(my_s, a.global_position.x, s.id, px).cost if my_s >= 0 else INF
		if cost < best_cost:
			best_cost = cost
			best = {"id": s.id, "x": px, "y": float(s.y)}
	return best

func _perch_covers(perch: Dictionary, t: Mob) -> bool:
	if perch.is_empty():
		return false
	var dy: float = mob_surface_y(t) - float(perch.y)
	return dy >= 20.0 and dy <= 85.0 and absf(t.global_position.x - float(perch.x)) <= float(a.weapon.range) * 0.85

## Which spell to cast at `t` right now, or "" for none.
## Sets up combos: freeze then lightning, stack poison then ignite with fire.
## Skips elements the target mostly resists.
func pick_spell(t: Mob) -> String:
	var dist := absf(t.global_position.x - a.global_position.x)
	var dy := absf(mob_surface_y(t) - a.global_position.y)
	var wants: Array = []
	if t.is_frozen():
		wants.append("chain_lightning")
	if t.poison_stacks >= 3:
		wants.append("fireball")
	if not t.is_frozen() and not t.is_chilled():
		wants.append("frost_bolt")
	if t.poison_stacks < 3:
		wants.append("venom_glob")
	if not t.is_burning():
		wants.append("fireball")
	for id in wants:
		if not a.spells.has(id) or not a.can_cast(id):
			continue
		var sp: Dictionary = a.spells[id]
		if t.resist(String(sp.element)) >= 0.5:
			continue
		var max_dy := 90.0 if sp.kind == "lob" else 22.0
		if dist <= float(sp.range) and dy <= max_dy:
			return id
	# Class skills (warrior, rogue): use whatever is ready and fits the distance.
	var reach := float(a.weapon.get("range", 30.0)) + Actor.W / 2.0 + t.size.x / 2.0
	for id in a.spells:
		var sp: Dictionary = a.spells[id]
		if not a.can_cast(id):
			continue
		match String(sp.kind):
			"strike":
				if dist <= float(sp.range) + t.size.x / 2.0 and dy < 20.0 and _facing_ok(t):
					return id
			"slam":
				if dist <= float(sp.radius) and dy < 20.0:
					return id
			"volley":
				if dist <= float(sp.range) and dy < 90.0:
					return id
			"dash":
				if dist >= reach * 0.8 and dist <= float(sp.distance) + reach and dy < 12.0 and a.is_on_floor():
					return id
			"buff":
				if not a.buffs.has(id) and dist <= 140.0:
					return id
	return ""

func _facing_ok(t: Mob) -> bool:
	return signf(t.global_position.x - a.global_position.x) == float(a.facing) or absf(t.global_position.x - a.global_position.x) < 6.0

static func is_combo_finisher(id: String, t: Mob) -> bool:
	return (id == "chain_lightning" and t.is_frozen()) or (id == "fireball" and t.poison_stacks >= 3)

static func mob_surface_y(m: Mob) -> float:
	return m.global_position.y if m.is_on_floor() else m.home.y

## Nearest live mob by travel cost along the nav graph. Unreachable mobs are skipped.
## With a leader, only mobs near the leader count; tanks also weigh distance to the leader.
func _pick_target() -> Mob:
	var best: Mob = null
	var best_cost := INF
	var cfg: Dictionary = a.cfg
	var world: World = a.world
	var my_s := world.nav.surface_at(a.global_position.x, a.global_position.y) if world else -1
	var following := has_leader()
	var engage := float(role_cfg.get("engage_radius", party_cfg.get("engage_radius", 260.0)))
	for m in a.get_tree().get_nodes_in_group("mobs"):
		if not m.alive or _ignored.has(m):
			continue
		if following and m.global_position.distance_to(leader.global_position) > engage:
			continue
		var cost: float
		if world and my_s >= 0:
			var t_s := world.nav.surface_at(m.global_position.x, mob_surface_y(m))
			cost = world.nav.find_route(my_s, a.global_position.x, t_s, m.global_position.x).cost
		else:
			cost = absf(m.global_position.x - a.global_position.x) + absf(mob_surface_y(m) - a.global_position.y) * 3.0
		if cost == INF:
			continue
		# Finish wounded mobs first (hammer cleave leaves several), and stick with the current target.
		if m.hp < m.max_hp:
			cost -= float(cfg.get("auto_wounded_bonus", 150.0))
		if m == target:
			cost -= float(cfg.get("auto_stick_bonus", 40.0))
		if following and role == "tank":
			cost += m.global_position.distance_to(leader.global_position)
		if cost < best_cost:
			best_cost = cost
			best = m
	return best
