class_name Player
extends Actor
## The human player: keyboard/controller input, plus optional auto-battle (Q / Tab).
## Manual input takes over movement, but auto keeps swinging at anything in front;
## auto resumes after auto_pause_after_input with a fresh target.
## Owns the inventory: potions (R / F or click in the I window) and XP tonics.
## During auto-battle it drinks potions on its own when HP or MP runs low, and once you reach
## the next map's level it walks to that map's portal and goes through (auto_advance_zones).

var auto_battle := false
var _auto_pause := 0.0
var _auto_was_manual := false
## Auto-battle drinks potions when HP or MP runs low (like a MapleStory pet).
func _auto_potions() -> void:
	if hp > 0 and float(hp) / max_hp < float(cfg.get("auto_potion_hp_below", 0.0)):
		use_best("heal_hp")
	if mp / max_mp < float(cfg.get("auto_potion_mp_below", 0.0)) and not spells.is_empty():
		use_best("heal_mp")

func _ready() -> void:
	super()
	add_to_group("player")

func _uses_brain() -> bool:
	return auto_battle

func _get_intent(delta: float) -> Dictionary:
	_auto_pause = max(_auto_pause - delta, 0.0)
	if auto_battle:
		_auto_potions()
	var intent := _read_manual()
	if not auto_battle:
		return intent
	if intent.active:
		# Manual movement wins, but auto keeps swinging at anything in front of you.
		_auto_pause = float(cfg.auto_pause_after_input)
		_auto_was_manual = true
		if not intent.attack and _mob_in_front():
			intent.attack = true
	elif _auto_pause <= 0.0:
		if _auto_was_manual:
			# Pick a fresh target from wherever the player steered to.
			_auto_was_manual = false
			brain.target = null
		var portal := next_zone_portal()
		if world and world.chest != null and is_instance_valid(world.chest) and not world.chest.opened and (world.boss == null or not is_instance_valid(world.boss)):
			intent = _loot_chest(delta)
		elif not portal.is_empty():
			intent = _advance(portal, delta)
		else:
			advancing_to = ""
			intent = brain.think(delta)
	elif _mob_in_front():
		intent.attack = true
	return intent

## What the player is asking for this frame.
func _read_manual() -> Dictionary:
	var i := {
		"dir": Input.get_axis("move_left", "move_right"),
		"jump": Input.is_action_just_pressed("jump"),
		"jump_release": Input.is_action_just_released("jump"),
		"down": Input.is_action_pressed("move_down"),
		"attack": Input.is_action_pressed("attack"),
	}
	i.spell = ""
	i.ult = Input.is_action_just_pressed("ultimate")
	for n in 4:
		if Input.is_action_pressed("spell_%d" % (n + 1)):
			i.spell = _spell_by_slot(n)
	i.active = i.dir != 0.0 or i.jump or i.down or i.attack or Input.is_action_pressed("jump") or i.spell != "" or i.ult
	return i

func _spell_by_slot(n: int) -> String:
	var keys := spells.keys()
	return keys[n] if n < keys.size() else ""

## Walk to the boss chest and open it.
func _loot_chest(delta: float) -> Dictionary:
	var c: Chest = world.chest
	if world.chest_at(global_position) == c and is_on_floor():
		c.open(self)
		return Actor.blank_intent()
	var i := brain.go_to(world.nav.surface_at(c.global_position.x, c.global_position.y), c.global_position.x, delta)
	i.attack = _mob_in_front()
	return i

## The portal to the next map once you meet its level (only forward, never back), or {}.
## Not while a boss is up or its chest is waiting.
func next_zone_portal() -> Dictionary:
	if world == null or not bool(cfg.get("auto_advance_zones", false)):
		return {}
	if (world.boss != null and is_instance_valid(world.boss)) or (world.chest != null and is_instance_valid(world.chest) and not world.chest.opened):
		return {}
	var here: Array = world.map.get("levels", [0, 0])
	for p in world.portals:
		var dest: Dictionary = world.maps.get(String(p.to), {})
		var lv: Array = dest.get("levels", [])
		if lv.size() == 2 and int(lv[0]) > int(here[0]) and level >= int(lv[0]):
			return p
	return {}

## Walk to the portal along the nav graph (still swinging at anything in the way), then take it.
func _advance(portal: Dictionary, delta: float) -> Dictionary:
	var dest_name := String(world.maps[String(portal.to)].name)
	if advancing_to != dest_name:
		advancing_to = dest_name
		Log.ok("Auto-battle: level %d reached, heading to %s" % [level, dest_name])
	var pp := world.portal_pos(portal)
	if is_on_floor() and not world.portal_at(global_position).is_empty() and absf(global_position.x - pp.x) <= 8.0:
		world.travel(portal)
		return Actor.blank_intent()
	var i := brain.go_to(world.nav.surface_at(pp.x, pp.y), pp.x, delta)
	i.attack = _mob_in_front()
	return i

func set_auto_battle(on: bool) -> void:
	auto_battle = on
	brain.reset()
	_auto_pause = 0.0
	Log.info("Auto-battle %s" % ("on" if on else "off"))
	stats_changed.emit()
