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
var inventory: Inventory
var item_cfg: Dictionary = {}
var items_used := 0
var _item_cd := 0.0
## Name of the map auto-battle is heading to, or "" (shown on the HUD).
var advancing_to := ""

## items: data/items.json. Fills the starter kit.
func setup_items(items: Dictionary) -> void:
	item_cfg = items
	inventory = Inventory.new(items.get("items", {}), int(items.get("inventory_slots", 24)))
	for e in items.get("starter_kit", []):
		inventory.add(String(e[0]), int(e[1]))

## Use one of item `id`. Returns "" on success, or why it couldn't be used.
func use_item(id: String) -> String:
	if inventory == null or inventory.count(id) <= 0:
		return "None left"
	if _item_cd > 0.0:
		return "Not yet"
	var d: Dictionary = inventory.def(id)
	match String(d.get("effect", "")):
		"heal_hp":
			if hp >= max_hp:
				return "HP is full"
			heal(int(d.amount))
		"heal_mp":
			if mp >= max_mp:
				return "MP is full"
			var before := mp
			mp = minf(mp + float(d.amount), max_mp)
			FloatText.spawn(get_parent(), global_position + Vector2(0, -H - 4), "+%d MP" % int(mp - before), Color("#7fb3ff"))
		"xp_buff":
			var cur: Dictionary = buffs.get("xp", {})
			if not cur.is_empty() and float(cur.mult) > float(d.mult):
				return "A stronger XP buff is active"
			buffs["xp"] = {"mult": float(d.mult), "t": float(d.duration), "max_t": float(d.duration), "name": String(d.name), "color": String(d.color)}
			FloatText.spawn(get_parent(), global_position + Vector2(0, -H - 14), "XP +%d%%" % int(round((float(d.mult) - 1.0) * 100.0)), Color(d.color), 1.4)
			Log.ok("%s: %s" % [d.name, d.desc])
		_:
			return "Can't use that"
	inventory.remove(id)
	items_used += 1
	_item_cd = float(item_cfg.get("use_cooldown", 0.5))
	stats_changed.emit()
	return ""

## Use the best owned item with `effect` (heal_hp / heal_mp): the smallest one that covers
## what's missing, or the biggest when none does. Returns "" on success or the reason.
func use_best(effect: String) -> String:
	var id := best_item(effect)
	if id == "":
		return "No potions"
	return use_item(id)

func best_item(effect: String) -> String:
	if inventory == null:
		return ""
	var missing := float(max_hp - hp) if effect == "heal_hp" else max_mp - mp
	var best := ""
	var best_amt := 0.0
	for id in inventory.defs:
		var d: Dictionary = inventory.defs[id]
		if String(d.get("effect", "")) != effect or inventory.count(id) <= 0:
			continue
		var amt := float(d.get("amount", 0))
		var better: bool = best == "" \
			or (amt >= missing and (best_amt < missing or amt < best_amt)) \
			or (amt < missing and best_amt < missing and amt > best_amt)
		if better:
			best = id
			best_amt = amt
	return best

## Manual use: show why it didn't work over the player's head.
func use_and_report(result: String) -> void:
	if result != "":
		FloatText.spawn(get_parent(), global_position + Vector2(0, -H - 10), result, Color("#c8c8c8"), 0.9)

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
	_item_cd = maxf(_item_cd - delta, 0.0)
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
		if not portal.is_empty():
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
	for n in 4:
		if Input.is_action_pressed("spell_%d" % (n + 1)):
			i.spell = _spell_by_slot(n)
	i.active = i.dir != 0.0 or i.jump or i.down or i.attack or Input.is_action_pressed("jump") or i.spell != ""
	return i

func _spell_by_slot(n: int) -> String:
	var keys := spells.keys()
	return keys[n] if n < keys.size() else ""

## The portal to the next map once you meet its level (only forward, never back), or {}.
func next_zone_portal() -> Dictionary:
	if world == null or not bool(cfg.get("auto_advance_zones", false)):
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
