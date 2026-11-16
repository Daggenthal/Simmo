class_name World
extends Node2D
## Builds maps from data/maps.json: solid ground, one-way platforms, edge walls,
## mob spawns and portals. Everything is drawn in code as placeholder art.
## Travel: stand on a portal and press Up; the party comes along.
## Map pieces (bodies, mobs) live under one child node so a map change can drop them all.

signal map_changed(map_id: String)

const MAPS_PATH := "res://data/maps.json"
const PORTAL_REACH := 16.0

var maps: Dictionary = {}
var map_id := ""
var map: Dictionary = {}
var ground_y := 330.0
var map_w := 1800.0
## [x, y, width] for one-way platforms (MapleStory style: jump up through them).
var platforms: Array = []
## [mob id, x, y]. y is the surface the mob starts on.
var spawns: Array = []
var portals: Array = []
var theme: Dictionary = {}
var spawn_point := Vector2(120, 330)
var nav := Nav.new()
var mobs: Array[Mob] = []
## Actors that travel together (the player first, then SimPlayers). Shares kill XP.
var party: Array = []
## Loot table from data/items.json: [{item, chance, min_level?}]. Party kills drop into the player's inventory.
var loot_table: Array = []
var _balance: Dictionary
var _respawn_queue: Array = []
var _map_root: Node2D
var _font: Font

static func load_maps() -> Dictionary:
	var f := FileAccess.open(MAPS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

func build(balance: Dictionary, start_map := "") -> void:
	_balance = balance
	_font = ThemeDB.fallback_font
	var data := load_maps()
	maps = data.get("maps", {})
	if not Log.check(not maps.is_empty(), "no maps in %s" % MAPS_PATH):
		return
	load_map(start_map if start_map != "" else String(data.get("start", maps.keys()[0])))

## Drop the current map and build `id`. With `arrive_portal`, the spawn point is that portal.
func load_map(id: String, arrive_portal := "") -> void:
	if not Log.check(maps.has(id), "unknown map '%s'" % id):
		return
	_clear_map()
	map_id = id
	map = maps[id]
	ground_y = float(map.ground_y)
	map_w = float(map.width)
	platforms = map.platforms
	spawns = map.spawns
	portals = map.get("portals", [])
	theme = map.get("theme", {})
	spawn_point = Vector2(map.spawn[0], map.spawn[1])
	for p in portals:
		if p.name == arrive_portal:
			spawn_point = portal_pos(p) + Vector2(30.0 if float(p.x) < map_w / 2.0 else -30.0, 0)
	_map_root = Node2D.new()
	_map_root.name = "Map"
	add_child(_map_root)
	move_child(_map_root, 0)
	_solid(Rect2(-40, ground_y, map_w + 80, 60))
	_solid(Rect2(-40, -200, 40, 600))
	_solid(Rect2(map_w, -200, 40, 600))
	for p in platforms:
		_platform(Rect2(p[0], p[1], p[2], 8))
	for s in spawns:
		_spawn_mob(s[0], Vector2(s[1], s[2] - 1))
	var pl: Dictionary = _balance.player
	nav = Nav.new()
	nav.build(ground_y, map_w, platforms, pow(float(pl.jump_velocity), 2) / (2.0 * float(pl.gravity)))
	for m in mobs:
		m.set_bounds(nav)
	Log.dbg("nav graph: %d surfaces, %d links" % [nav.surfaces.size(), nav.links.size()])
	Log.ok("Map %s built: %d platforms, %d mobs, %d portals" % [map.name, platforms.size(), mobs.size(), portals.size()])
	queue_redraw()
	map_changed.emit(id)

func _clear_map() -> void:
	_respawn_queue.clear()
	mobs.clear()
	if _map_root:
		remove_child(_map_root)
		_map_root.queue_free()
		_map_root = null
	# Projectiles, effects and damage numbers from the old map.
	for c in get_children():
		if not c.is_in_group("persist"):
			remove_child(c)
			c.queue_free()

func _solid(r: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = Actor.LAYER_GROUND
	body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = r.size
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = r.get_center()
	body.add_child(col)
	_map_root.add_child(body)

func _platform(r: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = Actor.LAYER_PLATFORMS
	body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = Vector2(r.size.x, 4)
	var col := CollisionShape2D.new()
	col.shape = shape
	col.one_way_collision = true
	col.position = r.position + Vector2(r.size.x / 2.0, 2)
	body.add_child(col)
	_map_root.add_child(body)

## Mob data for type `mob_id` at `level` (scaled from its base level).
func mob_data(mob_id: String, level: int) -> Dictionary:
	return Scaling.mob_stats(_balance.mobs[mob_id], level, _balance.get("mob_scaling", {}))

func _spawn_mob(mob_id: String, pos: Vector2) -> void:
	var base: Dictionary = _balance.mobs.get(mob_id, {})
	if not Log.check(not base.is_empty(), "unknown mob id '%s'" % mob_id):
		return
	var spread := int(_balance.get("mob_scaling", {}).get("level_spread", 0))
	var level := int(base.level) + randi_range(0, spread)
	var lv: Array = map.get("levels", [])
	if lv.size() == 2:
		level = clampi(level, int(lv[0]), int(lv[1]))
	var mob := Mob.new()
	mob.setup(mob_id, mob_data(mob_id, level), pos, float(_balance.player.gravity))
	mob.killed.connect(_on_mob_killed)
	_map_root.add_child(mob)
	mobs.append(mob)

func _on_mob_killed(mob: Mob, attacker: Node2D) -> void:
	_respawn_queue.append({"mob": mob, "t": float(_balance.respawn_time)})
	if attacker == null or not is_instance_valid(attacker) or not attacker.has_method("gain_xp"):
		return
	attacker.kills += 1
	award_xp(mob, attacker)
	if attacker in party:
		give_loot(mob)

## Items a kill of `mob` drops (each loot entry rolls once).
func roll_loot(mob: Mob) -> Array:
	var got: Array = []
	for e in loot_table:
		if mob.level >= int(e.get("min_level", 0)) and randf() < float(e.chance):
			got.append(String(e.item))
	return got

## Roll loot for a party kill and put it straight into the player's inventory.
func give_loot(mob: Mob) -> Array:
	var pl = party[0] if not party.is_empty() else null
	if pl == null or not is_instance_valid(pl) or pl.get("inventory") == null:
		return []
	var got := roll_loot(mob)
	var k := 0
	for id in got:
		var d: Dictionary = pl.inventory.def(id)
		var at := mob.global_position + Vector2(0, -mob.size.y - 28 - k * 10)
		if pl.inventory.add(id) > 0:
			FloatText.spawn(mob.get_parent(), at, "+%s" % d.get("name", id), Color(d.get("color", "#ffffff")).lightened(0.2), 1.4)
			Log.dbg("loot: %s from %s" % [id, mob.id])
		else:
			FloatText.spawn(mob.get_parent(), at, "Inventory full", Color("#ff6b6b"), 1.2)
		k += 1
	return got

## Split a kill's XP: every party member on the map gets a share (if the killer is in the party),
## each adjusted for their own level against the mob's.
func award_xp(mob: Mob, killer: Node2D) -> Dictionary:
	var members: Array = []
	if killer in party:
		for a in party:
			if is_instance_valid(a) and a.is_inside_tree() and a.is_alive():
				members.append(a)
	if not killer in members:
		members.append(killer)
	var share := Scaling.party_share(members.size(), _balance.get("party", {}))
	var scfg: Dictionary = _balance.get("mob_scaling", {})
	var got := {}
	for a in members:
		var amount := maxi(1, int(round(float(mob.data.xp) * share * Scaling.xp_mult(int(mob.data.level), a.level, scfg) * a.xp_mult())))
		a.gain_xp(amount)
		got[a] = amount
	# Show what the player got (or the killer, when the player isn't around).
	var shown: Node2D = party[0] if not party.is_empty() and got.has(party[0]) else killer
	FloatText.spawn(mob.get_parent(), mob.global_position + Vector2(0, -mob.size.y - 16), "+%d XP" % got[shown], Color("#9be37d"))
	return got

func _process(delta: float) -> void:
	for entry in _respawn_queue.duplicate():
		entry.t -= delta
		if entry.t <= 0.0:
			if is_instance_valid(entry.mob) and not entry.mob.alive:
				entry.mob.respawn()
			_respawn_queue.erase(entry)

func respawn_all() -> void:
	_respawn_queue.clear()
	for m in mobs:
		if not m.alive:
			m.respawn()

func portal_pos(p: Dictionary) -> Vector2:
	return Vector2(float(p.x), float(p.get("y", ground_y)))

## The portal the feet at `pos` stand on, or {}.
func portal_at(pos: Vector2) -> Dictionary:
	for p in portals:
		var pp := portal_pos(p)
		if absf(pos.x - pp.x) <= PORTAL_REACH and absf(pos.y - pp.y) < 10.0:
			return p
	return {}

## Take a portal at the end of this frame (map changes mid-physics are not safe).
func travel(portal: Dictionary) -> void:
	_do_travel.call_deferred(portal)

func _do_travel(portal: Dictionary) -> void:
	var to := String(portal.to)
	if not maps.has(to):
		Log.warn("Portal leads to unknown map '%s'" % to)
		return
	load_map(to, String(portal.get("to_portal", "")))
	var k := 0
	for a in party:
		if is_instance_valid(a):
			a.arrive(spawn_point + Vector2(-k * 14.0 * (1.0 if spawn_point.x > map_w / 2.0 else -1.0), 0))
			k += 1
	Log.ok("Entered %s (Lv %d-%d)" % [map.name, map.levels[0], map.levels[1]])
	var d := danger(map_id, _player_level())
	if d != "":
		Log.warn("%s: mobs here are Lv %d-%d and you're Lv %d, expect a %s fight" % [map.name, map.levels[0], map.levels[1], _player_level(), "very hard" if d == "deadly" else "harder"])

## How dangerous map `id` is for a player of `player_level`: "" (fine), "hard" (under the
## map's minimum level) or "deadly" (map_warning.deadly_gap or more levels under it).
## Only a warning: portals never block travel.
func danger(id: String, player_level: int) -> String:
	var lv: Array = maps.get(id, {}).get("levels", [])
	if lv.size() != 2:
		return ""
	var gap := int(lv[0]) - player_level
	if gap >= int(_balance.get("map_warning", {}).get("deadly_gap", 5)):
		return "deadly"
	return "hard" if gap > 0 else ""

static func danger_color(d: String) -> Color:
	match d:
		"deadly":
			return Color("#ff5a5a")
		"hard":
			return Color("#ffb347")
	return Color("#e8f3ff")

func _player_level() -> int:
	return party[0].level if not party.is_empty() and is_instance_valid(party[0]) else 1

func level_label() -> String:
	var lv: Array = map.get("levels", [])
	return "Lv %d-%d" % [lv[0], lv[1]] if lv.size() == 2 else ""

func _draw() -> void:
	var grass := Color(theme.get("grass", "#5fb548"))
	var dirt := Color(theme.get("dirt", "#7a5232"))
	var speck := Color(theme.get("speck", "#5e3d24"))
	var decor := String(theme.get("decor", ""))
	_draw_decor(decor)
	draw_rect(Rect2(-40, ground_y, map_w + 80, 60), dirt)
	draw_rect(Rect2(-40, ground_y, map_w + 80, 5), grass)
	for x in range(0, int(map_w), 24):
		draw_rect(Rect2(x + (x * 7) % 11, ground_y + 12 + (x * 13) % 20, 3, 2), speck)
	for p in platforms:
		var r := Rect2(p[0], p[1], p[2], 8)
		draw_rect(r, Color(theme.get("plat", "#8b6238")))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color(theme.get("plat_top", "#6cc552")))
		draw_rect(Rect2(r.position + Vector2(0, 8), Vector2(r.size.x, 2)), Color(0, 0, 0, 0.18))
	for p in portals:
		_draw_portal(p)

func _draw_portal(p: Dictionary) -> void:
	var c := portal_pos(p) + Vector2(0, -18)
	draw_circle(c, 15, Color(0.55, 0.8, 1.0, 0.3))
	draw_arc(c, 12, 0, TAU, 20, Color(0.75, 0.9, 1.0, 0.8), 2.0)
	draw_circle(c, 7, Color(0.85, 0.95, 1.0, 0.6))
	var dest: Dictionary = maps.get(String(p.to), {})
	if dest.is_empty() or _font == null:
		return
	# Destination and its level range, colored by how dangerous it is for the player right now.
	var lv: Array = dest.get("levels", [])
	var col := danger_color(danger(String(p.to), _player_level()))
	var lines := [String(dest.name)]
	if lv.size() == 2:
		lines.append("Lv %d-%d" % [lv[0], lv[1]])
	for k in lines.size():
		var w := _font.get_string_size(lines[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		var pos := c + Vector2(-w / 2.0, -30 + k * 10)
		draw_string_outline(_font, pos, lines[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, 3, Color(0, 0, 0, 0.7))
		draw_string(_font, pos, lines[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, col if k == 1 else Color("#e8f3ff"))

func _draw_decor(decor: String) -> void:
	match decor:
		"town":
			_house(Vector2(30, ground_y), Vector2(70, 50), Color("#c98f5a"), Color("#a3423a"))
			_house(Vector2(150, ground_y), Vector2(56, 40), Color("#d6b88a"), Color("#3a6aa3"))
			draw_rect(Rect2(236, ground_y - 22, 3, 22), Color("#6b4a2b"))
			draw_rect(Rect2(222, ground_y - 30, 32, 12), Color("#9a7044"))
		"shrooms":
			for k in range(0, int(map_w), 170):
				var x := float(k + (k * 37) % 60)
				var h := 26.0 + (k * 13) % 22
				draw_rect(Rect2(x - 3, ground_y - h, 6, h), Color("#e8dcc0"))
				var cap := Color("#c0503a") if (k / 170) % 2 == 0 else Color("#8a5ad0")
				draw_colored_polygon(PackedVector2Array([Vector2(x - 18, ground_y - h + 2), Vector2(x, ground_y - h - 14), Vector2(x + 18, ground_y - h + 2)]), cap)
				draw_circle(Vector2(x - 5, ground_y - h - 4), 2.0, Color(1, 1, 1, 0.7))
		"rocks":
			for k in range(0, int(map_w), 120):
				var x := float(k + (k * 31) % 50)
				var h := 20.0 + (k * 17) % 30
				draw_colored_polygon(PackedVector2Array([Vector2(x - 12, ground_y), Vector2(x - 2, ground_y - h), Vector2(x + 12, ground_y)]), Color("#5a3a2e"))
				draw_rect(Rect2(x - 3, ground_y - 3, 8, 3), Color(1.0, 0.45, 0.1, 0.8))
		"snow":
			for k in range(0, int(map_w), 140):
				var x := float(k + (k * 29) % 60)
				draw_rect(Rect2(x - 2, ground_y - 10, 4, 10), Color("#5a4a3a"))
				for t in 3:
					var w := 16.0 - t * 4.0
					var y := ground_y - 10 - t * 9
					draw_colored_polygon(PackedVector2Array([Vector2(x - w, y), Vector2(x, y - 14), Vector2(x + w, y)]), Color("#3f6f5a"))
					draw_rect(Rect2(x - w * 0.5, y - 5, w, 2), Color(1, 1, 1, 0.85))

func _house(base: Vector2, sz: Vector2, wall: Color, roof: Color) -> void:
	draw_rect(Rect2(base.x, base.y - sz.y, sz.x, sz.y), wall)
	draw_colored_polygon(PackedVector2Array([
		Vector2(base.x - 6, base.y - sz.y), Vector2(base.x + sz.x / 2.0, base.y - sz.y - 22),
		Vector2(base.x + sz.x + 6, base.y - sz.y)]), roof)
	draw_rect(Rect2(base.x + sz.x / 2.0 - 6, base.y - 18, 12, 18), wall.darkened(0.45))
	draw_rect(Rect2(base.x + 8, base.y - sz.y + 10, 10, 9), Color("#ffe9a8"))
