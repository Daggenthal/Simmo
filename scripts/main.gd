extends Node2D
## Entry point: loads balance data, builds the world, player, camera, HUD.

const BALANCE_PATH := "res://data/balance.json"

var balance: Dictionary
var world: World
var player: Player
var hud: Control
var _debug_draw: Node2D

func _ready() -> void:
	Log.info("Simmo starting (Godot %s)" % Engine.get_version_info().string)
	balance = load_balance()
	if balance.is_empty():
		Log.crash("Could not load %s, cannot start" % BALANCE_PATH)
		return
	Combat.setup(balance)
	_build_sky()
	world = World.new()
	world.name = "World"
	add_child(world)
	world.build(balance)

	player = Player.new()
	player.name = "Player"
	player.setup(balance.player, world.spawn_point, balance.weapons, balance.get("spells", {}))
	player.world = world
	world.add_child(player)

	var cam := Camera2D.new()
	cam.limit_left = 0
	cam.limit_right = int(World.MAP_W)
	# Bottom limit keeps the ground just above the HUD bar (22 px) with some dirt showing.
	# No camera offset: Camera2D offsets ignore limits and push the ground under the HUD.
	cam.limit_bottom = int(World.GROUND_Y + 38)
	cam.limit_top = -200
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	player.add_child(cam)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = preload("res://scripts/hud.gd").new()
	hud.player = player
	hud.world = world
	layer.add_child(hud)

	_debug_draw = Node2D.new()
	_debug_draw.z_index = 100
	_debug_draw.draw.connect(_on_debug_draw)
	world.add_child(_debug_draw)
	Log.ok("Ready")

static func load_balance() -> Dictionary:
	var f := FileAccess.open(BALANCE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

func _build_sky() -> void:
	var sky_layer := CanvasLayer.new()
	sky_layer.layer = -10
	add_child(sky_layer)
	var sky := ColorRect.new()
	sky.color = Color("#8fd0f5")
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky_layer.add_child(sky)
	var clouds := Parallax2D.new()
	clouds.scroll_scale = Vector2(0.08, 0.6)
	clouds.z_index = -6
	var cl := preload("res://scripts/background.gd").new()
	cl.kind = "clouds"
	clouds.add_child(cl)
	add_child(clouds)
	var hills := [
		[0.2, Color("#b9e3c6"), 110.0, 1.3],
		[0.45, Color("#8fcf86"), 70.0, 4.1],
	]
	for h in hills:
		var p := Parallax2D.new()
		p.scroll_scale = Vector2(h[0], 1.0)
		p.z_index = -5
		var bg := preload("res://scripts/background.gd").new()
		bg.color = h[1]
		bg.height = h[2]
		bg.seed_offset = h[3]
		p.add_child(bg)
		add_child(p)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle"):
		Log.debug = not Log.debug
		Log.info("Debug mode %s" % ("on" if Log.debug else "off"))
	elif event.is_action_pressed("help_toggle"):
		hud.show_help = not hud.show_help
	elif event.is_action_pressed("auto_battle"):
		player.set_auto_battle(not player.auto_battle)
	elif event.is_action_pressed("weapon_1"):
		player.equip("dagger")
	elif event.is_action_pressed("weapon_2"):
		player.equip("short_sword")
	elif event.is_action_pressed("weapon_3"):
		player.equip("iron_hammer")
	elif event.is_action_pressed("weapon_4"):
		player.equip("throwing_kunai")
	elif event.is_action_pressed("weapon_next"):
		var keys: Array = balance.weapons.keys()
		player.equip(keys[(keys.find(player.weapon_key) + 1) % keys.size()])
	elif event.is_action_pressed("respawn_mobs"):
		world.respawn_all()
		Log.ok("All mobs respawned")

func _process(_delta: float) -> void:
	if _debug_draw:
		_debug_draw.queue_redraw()

func _on_debug_draw() -> void:
	if not Log.debug:
		return
	for m in world.mobs:
		if m.alive:
			_debug_draw.draw_rect(m.hurt_rect(), Color(1, 0.3, 0.3, 0.8), false, 1.0)
	var pr := Rect2(player.global_position + Vector2(-Player.W / 2.0, -Player.H), Vector2(Player.W, Player.H))
	_debug_draw.draw_rect(pr, Color(0.3, 1, 0.4, 0.8), false, 1.0)
	var reach := float(player.weapon.range)
	var tall := float(player.weapon.height)
	var c := player.global_position + Vector2(player.facing * (Player.W / 2.0 + reach / 2.0), -Player.H / 2.0)
	_debug_draw.draw_rect(Rect2(c - Vector2(reach, tall) / 2.0, Vector2(reach, tall)), Color(1, 1, 0.3, 0.6), false, 1.0)
