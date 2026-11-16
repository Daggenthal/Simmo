extends SceneTree
## Headless magic test: every status effect, combo, spell, mana and the thrown kunai.
## Run: godot --headless --fixed-fps 60 --path . --script res://tests/magic_test.gd

var _main
var _log
var _frame := 0
var _pf := 0
var _phase := "boot"
var _failures := 0
var _bal: Dictionary
var _m = null
var _n = null
var _x0 := 0.0
var _hp0 := 0
var _v_norm := 0.0
var _min_y := 0.0
var _pr = null
var _casts0 := 0
var _kills0 := 0
var Comb   # res://scripts/combat.gd, loaded at runtime (class names would compile before autoloads)
var ProjS
var WorldS

func _initialize() -> void:
	_log = root.get_node("Log")
	seed(4242)
	Comb = load("res://scripts/combat.gd")
	ProjS = load("res://scripts/projectile.gd")
	WorldS = load("res://scripts/world.gd")
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
	_pf = 0

## Park every mob, then set one up at pos as a sturdy, still training dummy.
func _dummy(idx: int, pos: Vector2, hp := 100000):
	var world = _main.world
	var m = world.mobs[idx]
	m.data = m.data.duplicate()
	m.data.speed = 0.0
	m.data.hop_velocity = 0.0
	m.data.touch_damage = 0
	m.home = pos
	m.max_hp = hp
	m.set_bounds(world.nav)
	m.respawn()
	return m

func _park_all() -> void:
	var world = _main.world
	world._respawn_queue.clear()
	for m in world.mobs:
		m.alive = false
		m.visible = false
		m.set_physics_process(false)
		m.clear_statuses()

func _physics_process(_d: float) -> bool:
	_frame += 1
	_pf += 1
	var p = _main.player
	var e: Dictionary = _main.balance.elements
	match _phase:
		"boot":
			if _pf == 5:
				_bal = _main.balance
				p.set_auto_battle(false)
				_instant_checks(p, e)
				_goto("burn")
		"burn":
			if _pf == 1:
				_park_all()
				_m = _dummy(0, Vector2(600, 329))
				Comb.hit(_m, p, 1, "fire", {})
			if _pf == int(float(e.fire.burn_time) * 60.0) + 30:
				var expect := int(float(e.fire.burn_dps) * float(e.fire.burn_time))
				_check(_m.dot_damage_taken == expect, "burn ticks %d dmg/s for %.0fs = %d total (got %d)" % [e.fire.burn_dps, e.fire.burn_time, expect, _m.dot_damage_taken])
				_check(not _m.is_burning(), "burn wears off")
				_goto("poison_dot")
		"poison_dot":
			if _pf == 1:
				_park_all()
				_m = _dummy(0, Vector2(600, 329))
				for k in 3:
					Comb.hit(_m, p, 1, "poison", {})
			if _pf == 61:
				var per := int(float(e.poison.dps_per_stack) * 3)
				_check(_m.dot_damage_taken == per, "3 poison stacks tick %d per second (got %d in 1s)" % [per, _m.dot_damage_taken])
				_goto("slow")
		"slow":
			# Same walking mob with and without chill: chilled covers less ground.
			if _pf == 1:
				_park_all()
				_m = _dummy(0, Vector2(400, 329))
				_m.data.speed = 40.0
				_m.wander_range = 9999.0
				_m._dir = 1
				_m._think = 999.0
				_x0 = _m.position.x
			if _pf == 61:
				_v_norm = _m.position.x - _x0
				_m.position.x = 400.0
				_m._dir = 1
				_x0 = 400.0
				Comb.hit(_m, p, 1, "frost", {"proc": 1.0})
				_m.frozen_t = 0.0
				_m._aggro = null
				_m._think = 999.0
				_m._dir = 1
				_m.velocity = Vector2.ZERO
			if _pf == 121:
				var chilled: float = _m.position.x - _x0
				_check(_v_norm > 20.0 and chilled > 0.0 and chilled < _v_norm * (1.0 - float(e.frost.slow) * 0.6), "chill slows movement (%.0f px normal vs %.0f px chilled in 1s)" % [_v_norm, chilled])
				_goto("frozen")
		"frozen":
			# Frozen: can't move, can't hurt the player by touch.
			if _pf == 1:
				_park_all()
				_m = _dummy(0, Vector2(500, 329))
				_m.data.touch_damage = 10
				_m.data.speed = 40.0
				_m.apply_freeze(5.0)
				p.position = Vector2(500, 330)
				p.velocity = Vector2.ZERO
				p._invuln = 0.0
				_hp0 = p.hp
				_x0 = _m.position.x
			if _pf == 60:
				_check(absf(_m.position.x - _x0) < 0.5 and p.hp == _hp0, "frozen mob can't move or touch-damage (moved %.1f px, player hp %d -> %d)" % [absf(_m.position.x - _x0), _hp0, p.hp])
				p.position = Vector2(120, 330)
				_goto("chain")
		"chain":
			if _pf == 1:
				_park_all()
				p.position = Vector2(500, 330)
				p.velocity = Vector2.ZERO
				p.facing = 1
				p.mp = p.max_mp
				for k in 5:
					_dummy(k, Vector2(540 + k * 40 + (60 if k == 4 else 0), 329))
				p.spell_cd.chain_lightning = 0.0
				p._cast_cd = 0.0
				p.cast("chain_lightning")
				var sp: Dictionary = _bal.spells.chain_lightning
				_check(p.last_chain.size() == int(sp.chains) + 1, "chain lightning hits the target plus %d jumps (hit %d)" % [sp.chains, p.last_chain.size()])
				var far = _main.world.mobs[4]
				_check(not p.last_chain.has(far), "chain lightning doesn't jump past %d px" % int(sp.chain_range))
				_goto("kunai")
		"kunai":
			if _pf == 1:
				_park_all()
				p.position = Vector2(500, 330)
				p.velocity = Vector2.ZERO
				p.facing = 1
				p.equip("throwing_kunai")
				p.imbue_element = ""
				_m = _dummy(0, Vector2(630, 329))
				_hp0 = _m.hp
				p._attack_cd = 0.0
				p.last_projectile = null
				p.attack()
				_min_y = 9999.0
			_pr = p.last_projectile
			if _pr and is_instance_valid(_pr):
				_min_y = min(_min_y, _pr.global_position.y)
			if _pf == 90:
				_check(_min_y < 286.0, "kunai flies in a visible arc (peak %.0f px above the throw)" % (316.0 - _min_y))
				_check(_m.hp < _hp0, "kunai arc lands on a mob 130 px away (%d dmg)" % (_hp0 - _m.hp))
				# Imbue: after casting frost, throws carry frost at reduced strength.
				p.imbue_element = "frost"
				p._throw()
				var pr = p.last_projectile
				var w: Dictionary = _bal.weapons.throwing_kunai
				_check(pr.element == "frost" and is_equal_approx(float(pr.opts.proc), float(w.imbue_chance)), "kunai imbued with last spell's element (%s, %.0f%% proc)" % [pr.element, 100.0 * float(pr.opts.proc)])
				p.equip("short_sword")
				p.imbue_element = ""
				_goto("auto")
		"auto":
			# Hands-off on the full map: auto-battle should mix in spells and land combos.
			if _pf == 1:
				_main.world._respawn_queue.clear()
				for k in _main.world.mobs.size():
					var m = _main.world.mobs[k]
					var sp: Array = WorldS.SPAWNS[k]
					m.data = _main.balance.mobs[m.id].duplicate()
					m.max_hp = int(m.data.hp)
					m.home = Vector2(sp[1], sp[2] - 1)
					m.set_bounds(_main.world.nav)
					m.respawn()
				p.position = Vector2(120, 330)
				p.mp = p.max_mp
				Comb.combo_counts.clear()
				p.cast_log.clear()
				_casts0 = p.casts
				_kills0 = p.kills
				p.set_auto_battle(true)
			if _pf == 3600:
				var combos := 0
				for k in Comb.combo_counts:
					combos += Comb.combo_counts[k]
				_check(p.casts - _casts0 >= 10 and p.casts - _casts0 <= 45, "auto-battle casts spells at a sane pace (%d casts in 60s)" % (p.casts - _casts0))
				_check(p.kills - _kills0 >= 10, "auto-battle still kills steadily with spells (%d kills in 60s)" % (p.kills - _kills0))
				_check(combos >= 1, "auto-battle sets up combos on its own (%s)" % str(Comb.combo_counts))
				_check_pacing(p)
				p.set_auto_battle(false)
				_goto("done")
		"done":
			if _failures == 0:
				_log.ok("ALL MAGIC CHECKS PASSED (%d frames)" % _frame)
			else:
				_log.error("%d MAGIC CHECK(S) FAILED" % _failures)
			quit(1 if _failures > 0 else 0)
	if _frame > 20000:
		_log.error("timeout in phase " + _phase)
		quit(1)
	return false

## Checks that don't need time to pass: rolls, stacks, combos, mana.
func _instant_checks(p, e: Dictionary) -> void:
	_park_all()
	var m = _dummy(0, Vector2(600, 329))
	var n = _dummy(1, Vector2(625, 329))
	var base_crit := float(p.cfg.crit_chance)
	var trials := 3000

	# Freeze chance
	var frozen := 0
	for k in trials:
		m.clear_statuses()
		Comb.hit(m, p, 1, "frost", {})
		if m.is_frozen():
			frozen += 1
	var rate := float(frozen) / trials
	_check(absf(rate - float(e.frost.freeze_chance)) < 0.04, "frost freezes about %.0f%% of the time (%.1f%%)" % [100 * float(e.frost.freeze_chance), 100 * rate])

	# Frost crit bonus vs frozen
	var crit_normal := 0
	var crit_frozen := 0
	for k in trials:
		m.clear_statuses()
		if Comb.hit(m, p, 1, "frost", {"crit_chance": base_crit, "proc": 0.0}).crit:
			crit_normal += 1
		m.clear_statuses()
		m.apply_freeze(5.0)
		if Comb.hit(m, p, 1, "frost", {"crit_chance": base_crit, "proc": 0.0}).crit:
			crit_frozen += 1
	var cn := float(crit_normal) / trials
	var cf := float(crit_frozen) / trials
	_check(absf(cf - (base_crit + float(e.frost.crit_bonus_vs_frozen))) < 0.04 and cf > cn + 0.3,
		"frost crits far more on frozen targets (%.0f%% vs %.0f%% normally)" % [100 * cf, 100 * cn])

	# Lightning on frozen: always crit, splash, shatter
	var all_crit := true
	var splashed := true
	var shattered := true
	for k in 50:
		m.clear_statuses()
		n.clear_statuses()
		var n_hp: int = n.hp
		m.apply_freeze(5.0)
		var r: Dictionary = Comb.hit(m, p, 10, "lightning", {"crit_chance": 0.0})
		all_crit = all_crit and r.crit and r.combo == "conduct"
		splashed = splashed and n.hp < n_hp
		shattered = shattered and not m.is_frozen()
	_check(all_crit, "lightning always crits a frozen target (conducts through the ice)")
	_check(splashed, "lightning on a frozen target splashes a mob 25 px away")
	_check(shattered, "lightning shatters the ice (no endless freeze-crit loop)")
	m.clear_statuses()
	var normal_crits := 0
	for k in 200:
		if Comb.hit(m, p, 10, "lightning", {"crit_chance": 0.0}).crit:
			normal_crits += 1
	_check(normal_crits == 0, "lightning on an unfrozen target has no guaranteed crit")

	# Poison stacks cap
	m.clear_statuses()
	for k in 9:
		Comb.hit(m, p, 1, "poison", {})
	_check(m.poison_stacks == int(e.poison.max_stacks), "poison stacks cap at %d (got %d)" % [e.poison.max_stacks, m.poison_stacks])

	# Fire thaws frost
	m.clear_statuses()
	m.apply_freeze(5.0)
	m.apply_chill(0.5, 5.0)
	Comb.hit(m, p, 1, "fire", {})
	_check(not m.is_frozen() and not m.is_chilled() and m.is_burning(), "fire thaws chill and freeze, then burns")

	# Ignite: poisoned + fire = burst around the target
	m.clear_statuses()
	n.clear_statuses()
	for k in 4:
		Comb.hit(m, p, 1, "poison", {})
	var n_hp2: int = n.hp
	var r2: Dictionary = Comb.hit(m, p, 1, "fire", {})
	var expect := int(4 * float(e.fire.ignite_per_stack))
	_check(r2.combo == "ignite" and m.poison_stacks == 0, "fire ignites poison (stacks consumed)")
	_check(n_hp2 - n.hp >= expect, "ignite burst hits a nearby mob for %d (4 stacks x %d; got %d)" % [expect, e.fire.ignite_per_stack, n_hp2 - n.hp])

	# Mana
	p.mp = 5.0
	p.spell_cd.fireball = 0.0
	p._cast_cd = 0.0
	_check(not p.cast("fireball"), "can't cast with too little MP (5 MP, Fireball costs %d)" % _bal.spells.fireball.mp)
	p.mp = p.max_mp
	var before: float = p.mp
	_check(p.cast("fireball") and absf((before - p.mp) - float(_bal.spells.fireball.mp)) < 0.01, "casting spends MP (%.0f -> %.0f)" % [before, p.mp])
	_check(not p.cast("fireball"), "spell cooldown blocks an instant recast")
	for node in _main.world.get_children():
		if node.get_script() == ProjS:
			node.queue_free()

## No two spells within the global cooldown, and no spell again before its own cooldown.
func _check_pacing(p) -> void:
	var gcd_frames := int(round(float(p.cfg.global_cast_cooldown) * 60.0))
	var min_gap := 99999
	var last_by_id := {}
	var early := []
	for k in p.cast_log.size():
		var f: int = p.cast_log[k][0]
		var id: String = p.cast_log[k][1]
		if k > 0:
			min_gap = mini(min_gap, f - int(p.cast_log[k - 1][0]))
		if last_by_id.has(id):
			var need := int(round(float(p.spells[id].cooldown) * 60.0))
			if f - int(last_by_id[id]) < need - 1:
				early.append("%s after %d frames" % [id, f - int(last_by_id[id])])
		last_by_id[id] = f
	_check(min_gap >= gcd_frames - 1, "at least %.1fs between any two spells (closest pair %.2fs)" % [p.cfg.global_cast_cooldown, min_gap / 60.0])
	_check(early.is_empty(), "no spell recast before its own cooldown %s" % (str(early) if not early.is_empty() else ""))
	# Casting must lock out the weapon: no swing in the same frame as a cast.
	var b0: int = p.swings
	p._attack_cd = 0.0
	p._cast_cd = 0.0
	for k in p.spell_cd:
		p.spell_cd[k] = 0.0
	p.mp = p.max_mp
	p._apply({"dir": 0.0, "jump": false, "jump_release": false, "down": false, "attack": true, "spell": "fireball"}, 1.0 / 60.0)
	_check(p.swings == b0, "casting blocks a weapon swing in the same moment")
