class_name Combat
extends RefCounted
## One place for damage rules, so every source (melee, spells, thrown weapons,
## damage-over-time ticks) plays by the same element and combo rules.
##
## Elements and what they do (numbers live in data/balance.json -> elements):
##   fire       burn: damage every second for a few seconds. Thaws chill and freeze.
##   frost      chill: slows movement. Chance to freeze (can't move or touch-damage).
##   poison     stacks up to a cap; each stack ticks damage every second.
##   lightning  instant; chain lightning jumps between nearby mobs.
## Combos:
##   frost on a frozen mob      bonus crit chance
##   lightning on a frozen mob  always crits, splashes nearby mobs, shatters the ice
##   fire on a poisoned mob     ignite: the poison bursts for damage per stack around it
## Resists (mob data "resist": {element: 0..1}) cut damage and the chance the effect applies.

static var elements: Dictionary = {}
static var combo_counts: Dictionary = {}  # combo name -> times triggered (for tests and stats)

static func setup(balance: Dictionary) -> void:
	elements = balance.get("elements", {})

static func element_color(element: String) -> Color:
	return Color(elements.get(element, {}).get("color", "#ffffff"))

## Deal one hit. opts:
##   crit_chance   base crit chance (attacker's)
##   crit_mult     crit multiplier
##   knockback     push strength
##   dir           push direction (-1 / 1)
##   proc          chance the element's effect is applied (default 1)
##   strength      scales the element's effect (default 1)
##   no_combo      skip splash/ignite (used for the splash and ignite hits themselves)
## Returns {amount, crit, combo} for tests and logs.
static func hit(mob: Mob, attacker: Node2D, base: int, element: String, opts: Dictionary = {}) -> Dictionary:
	if mob == null or not mob.alive:
		return {"amount": 0, "crit": false, "combo": ""}
	var e: Dictionary = elements.get(element, {})
	var crit_chance := float(opts.get("crit_chance", 0.0))
	var combo := ""
	var forced_crit := false
	var was_frozen := mob.is_frozen()

	if element == "frost" and was_frozen:
		crit_chance += float(e.get("crit_bonus_vs_frozen", 0.0))
		combo = "frozen_crit_bonus"
	if element == "lightning" and was_frozen and e.get("frozen_always_crits", false):
		forced_crit = true
		combo = "conduct"

	var crit := forced_crit or randf() < crit_chance
	var amount := base
	if crit:
		amount = int(round(amount * float(opts.get("crit_mult", 2.0))))
	# Resists cut the damage and the chance the element's effect sticks.
	# Holy light burns the undead.
	if element == "holy" and bool(mob.data.get("undead", false)):
		amount = int(round(amount * float(e.get("undead_mult", 1.0))))
	var res := mob.resist(element)
	if res > 0.0:
		amount = maxi(1, int(round(amount * (1.0 - res))))
	var knock := 0.0 if mob.is_frozen() else float(opts.get("knockback", 0.0))
	mob.take_hit(amount, crit, int(opts.get("dir", 1)), attacker, knock, element)
	var mine: bool = attacker != null and is_instance_valid(attacker) and attacker.is_in_group("player")
	if attacker != null and is_instance_valid(attacker) and "damage_dealt" in attacker:
		attacker.damage_dealt += amount
	Sfx.play("crit" if crit else "hit", 1.0 if mine else 0.3, randf_range(0.9, 1.1))
	if attacker and is_instance_valid(attacker) and attacker.is_in_group("player"):
		ChatLog.add("combat", "You hit %s for %d%s%s" % [mob.data.get("name", mob.id), amount, " (crit)" if crit else "", "" if element == "physical" else " " + element])

	# Element effects (only if the mob survived the hit).
	var proc := float(opts.get("proc", 1.0)) * (1.0 - res)
	var strength := float(opts.get("strength", 1.0))
	if mob.alive and randf() < proc:
		match element:
			"fire":
				if mob.poison_stacks > 0 and not opts.get("no_combo", false):
					combo = "ignite"
					_ignite(mob, attacker, e)
				if e.get("thaws", false):
					mob.thaw()
				if mob.alive:
					mob.apply_burn(float(e.burn_dps) * strength, float(e.burn_time), attacker)
			"frost":
				mob.apply_chill(float(e.slow), float(e.slow_time))
				if randf() < float(e.freeze_chance) * strength:
					mob.apply_freeze(float(e.freeze_time))
			"poison":
				mob.add_poison(float(e.dps_per_stack) * strength, int(e.max_stacks), float(e.time), attacker)

	if combo == "conduct" and not opts.get("no_combo", false):
		var radius := float(e.get("frozen_splash_radius", 50.0))
		var mult := float(e.get("frozen_splash_mult", 0.6))
		for other in mob.get_tree().get_nodes_in_group("mobs"):
			if other != mob and other.alive and other.global_position.distance_to(mob.global_position) <= radius:
				hit(other, attacker, int(round(amount * mult)), "lightning", {"no_combo": true, "dir": opts.get("dir", 1)})
		if e.get("shatters_ice", false):
			mob.thaw()
	if combo != "":
		combo_counts[combo] = int(combo_counts.get(combo, 0)) + 1
		Log.dbg("combo %s on %s" % [combo, mob.id])
	return {"amount": amount, "crit": crit, "combo": combo}

static func _ignite(mob: Mob, attacker: Node2D, fire: Dictionary) -> void:
	var dmg := int(round(mob.poison_stacks * float(fire.ignite_per_stack)))
	var radius := float(fire.ignite_radius)
	var center := mob.global_position
	mob.clear_poison()
	FloatText.spawn(mob.get_parent(), center + Vector2(0, -mob.size.y - 22), "IGNITE!", element_color("fire"), 1.1)
	Fx.burst(mob.get_parent(), center + Vector2(0, -mob.size.y / 2.0), radius, element_color("fire"))
	for other in mob.get_tree().get_nodes_in_group("mobs"):
		if other.alive and other.global_position.distance_to(center) <= radius:
			hit(other, attacker, dmg, "fire", {"no_combo": true, "proc": 0.0})
