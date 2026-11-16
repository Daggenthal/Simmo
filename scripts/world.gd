class_name World
extends Node2D
## Builds one test map from data: solid ground, one-way platforms, edge walls,
## mob spawn points. Everything is drawn in code as placeholder art.

const GROUND_Y := 330.0
const MAP_W := 1800.0

## [x, y, width] for one-way platforms (MapleStory style: jump up through them).
const PLATFORMS := [
	[300, 270, 140],
	[470, 225, 160],
	[760, 270, 120],
	[930, 208, 200],
	[1180, 268, 150],
	[1380, 205, 180],
	[1600, 268, 140],
]

## [mob id, x, y]. y is the surface the mob starts on.
const SPAWNS := [
	["green_slime", 420, GROUND_Y],
	["green_slime", 600, GROUND_Y],
	["green_slime", 360, 270],
	["green_slime", 560, 225],
	["blue_slime", 840, GROUND_Y],
	["blue_slime", 1010, 208],
	["blue_slime", 1100, GROUND_Y],
	["green_slime", 1240, 268],
	["stump", 1320, GROUND_Y],
	["blue_slime", 1460, 205],
	["stump", 1560, GROUND_Y],
	["blue_slime", 1650, 268],
]

var spawn_point := Vector2(120, GROUND_Y)
var nav := Nav.new()
var mobs: Array[Mob] = []
var _balance: Dictionary
var _respawn_queue: Array = []

func build(balance: Dictionary) -> void:
	_balance = balance
	_solid(Rect2(-40, GROUND_Y, MAP_W + 80, 60))
	_solid(Rect2(-40, -200, 40, 600))
	_solid(Rect2(MAP_W, -200, 40, 600))
	for p in PLATFORMS:
		_platform(Rect2(p[0], p[1], p[2], 8))
	for s in SPAWNS:
		_spawn_mob(s[0], Vector2(s[1], s[2] - 1))
	var pl: Dictionary = balance.player
	nav.build(GROUND_Y, MAP_W, PLATFORMS, pow(float(pl.jump_velocity), 2) / (2.0 * float(pl.gravity)))
	for m in mobs:
		m.set_bounds(nav)
	Log.dbg("nav graph: %d surfaces, %d links" % [nav.surfaces.size(), nav.links.size()])
	Log.ok("World built: %d platforms, %d mobs" % [PLATFORMS.size(), mobs.size()])
	queue_redraw()

func _solid(r: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = Player.LAYER_GROUND
	body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = r.size
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = r.get_center()
	body.add_child(col)
	add_child(body)

func _platform(r: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = Player.LAYER_PLATFORMS
	body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = Vector2(r.size.x, 4)
	var col := CollisionShape2D.new()
	col.shape = shape
	col.one_way_collision = true
	col.position = r.position + Vector2(r.size.x / 2.0, 2)
	body.add_child(col)
	add_child(body)

func _spawn_mob(mob_id: String, pos: Vector2) -> void:
	var mob_data: Dictionary = _balance.mobs.get(mob_id, {})
	if not Log.check(not mob_data.is_empty(), "unknown mob id '%s'" % mob_id):
		return
	var mob := Mob.new()
	mob.setup(mob_id, mob_data, pos, float(_balance.player.gravity))
	mob.killed.connect(_on_mob_killed)
	add_child(mob)
	mobs.append(mob)

func _on_mob_killed(mob: Mob) -> void:
	_respawn_queue.append({"mob": mob, "t": float(_balance.respawn_time)})

func _process(delta: float) -> void:
	for entry in _respawn_queue.duplicate():
		entry.t -= delta
		if entry.t <= 0.0:
			if not entry.mob.alive:
				entry.mob.respawn()
			_respawn_queue.erase(entry)

## The one-way platform whose top is at surface_y and spans x, or {} for the ground.
func platform_at(x: float, surface_y: float) -> Dictionary:
	for p in PLATFORMS:
		if absf(p[1] - surface_y) < 6.0 and x >= p[0] - 4 and x <= p[0] + p[2] + 4:
			return {"x": float(p[0]), "y": float(p[1]), "w": float(p[2])}
	return {}

func respawn_all() -> void:
	for entry in _respawn_queue:
		entry.mob.respawn()
	_respawn_queue.clear()

func _draw() -> void:
	# Ground: grass strip over dirt.
	draw_rect(Rect2(-40, GROUND_Y, MAP_W + 80, 60), Color("#7a5232"))
	draw_rect(Rect2(-40, GROUND_Y, MAP_W + 80, 5), Color("#5fb548"))
	for x in range(0, int(MAP_W), 24):
		draw_rect(Rect2(x + (x * 7) % 11, GROUND_Y + 12 + (x * 13) % 20, 3, 2), Color("#5e3d24"))
	# Platforms
	for p in PLATFORMS:
		var r := Rect2(p[0], p[1], p[2], 8)
		draw_rect(r, Color("#8b6238"))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color("#6cc552"))
		draw_rect(Rect2(r.position + Vector2(0, 8), Vector2(r.size.x, 2)), Color(0, 0, 0, 0.18))
	# Town area: a few placeholder buildings and a sign.
	_house(Vector2(30, GROUND_Y), Vector2(70, 50), Color("#c98f5a"), Color("#a3423a"))
	_house(Vector2(150, GROUND_Y), Vector2(56, 40), Color("#d6b88a"), Color("#3a6aa3"))
	draw_rect(Rect2(236, GROUND_Y - 22, 3, 22), Color("#6b4a2b"))
	draw_rect(Rect2(222, GROUND_Y - 30, 32, 12), Color("#9a7044"))
	# Portal glow at the far end.
	draw_circle(Vector2(MAP_W - 40, GROUND_Y - 18), 14, Color(0.55, 0.8, 1.0, 0.35))
	draw_circle(Vector2(MAP_W - 40, GROUND_Y - 18), 8, Color(0.75, 0.9, 1.0, 0.6))

func _house(base: Vector2, sz: Vector2, wall: Color, roof: Color) -> void:
	draw_rect(Rect2(base.x, base.y - sz.y, sz.x, sz.y), wall)
	draw_colored_polygon(PackedVector2Array([
		Vector2(base.x - 6, base.y - sz.y), Vector2(base.x + sz.x / 2.0, base.y - sz.y - 22),
		Vector2(base.x + sz.x + 6, base.y - sz.y)]), roof)
	draw_rect(Rect2(base.x + sz.x / 2.0 - 6, base.y - 18, 12, 18), wall.darkened(0.45))
	draw_rect(Rect2(base.x + 8, base.y - sz.y + 10, 10, 9), Color("#ffe9a8"))
