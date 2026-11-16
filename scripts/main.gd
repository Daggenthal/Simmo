extends Node2D
## Entry point: loads balance data, builds the world, player, party, camera, HUD.
## Tests can set spawn_sims = false (before adding the scene) for a solo run.

const BALANCE_PATH := "res://data/balance.json"

var balance: Dictionary
var world: World
var player: Player
var hud: Control
var _debug_draw: Node2D
var sims: Array = []
## SimPlayers join at start (P toggles them in game).
var spawn_sims := true
var start_map := ""
var _cam: Camera2D
var _sky: ColorRect
var _hills: Array = []
var items: Dictionary = {}
var inventory_ui: InventoryUI

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
	world.map_changed.connect(_on_map_changed)
	world.build(balance, start_map)

	player = Player.new()
	player.name = "Player"
	player.setup(balance.player, world.spawn_point, balance.weapons, balance.get("spells", {}))
	player.world = world
	world.add_child(player)
	world.party = [player]
	items = Inventory.load_data()
	if not Log.check(not items.is_empty(), "could not load %s" % Inventory.ITEMS_PATH):
		items = {}
	player.setup_items(items)
	world.loot_table = items.get("loot", [])

	_cam = Camera2D.new()
	_cam.limit_left = 0
	_cam.limit_top = -200
	_cam.position_smoothing_enabled = true
	_cam.position_smoothing_speed = 8.0
	player.add_child(_cam)
	_on_map_changed(world.map_id)
	if spawn_sims:
		summon_party()

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = preload("res://scripts/hud.gd").new()
	hud.player = player
	hud.world = world
	layer.add_child(hud)
	inventory_ui = InventoryUI.new()
	inventory_ui.player = player
	layer.add_child(inventory_ui)
	# Portal labels are colored by danger for the player's level; redraw when it changes.
	player.stats_changed.connect(world.queue_redraw)

	_debug_draw = Node2D.new()
	_debug_draw.add_to_group("persist")
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

## SimPlayers from balance.json "sims", lined up behind the player.
func summon_party() -> void:
	if not sims.is_empty():
		return
	var k := 0
	for info in balance.get("sims", []):
		var s := SimPlayer.new()
		s.name = "Sim_%s" % info.name
		s.setup_sim(info, balance, player, player.global_position + Vector2(-20 - k * 14, 0))
		s.world = world
		world.add_child(s)
		sims.append(s)
		world.party.append(s)
		k += 1
	Log.ok("Party: %s joined" % ", ".join(sims.map(func(x): return "%s (%s)" % [x.display_name, x.role])))

func dismiss_party() -> void:
	for s in sims:
		world.party.erase(s)
		s.queue_free()
	sims.clear()
	Log.info("Party dismissed")

## New map: camera limits and sky colors follow it.
func _on_map_changed(_id: String) -> void:
	# The party is placed after the map is built, so warn once everything has settled.
	if hud:
		hud.on_map_entered.call_deferred()
	if _cam:
		_cam.limit_right = int(world.map_w)
		# Bottom limit keeps the ground just above the HUD bar (22 px) with some dirt showing.
		# No camera offset: Camera2D offsets ignore limits and push the ground under the HUD.
		_cam.limit_bottom = int(world.ground_y + 38)
		_cam.reset_smoothing()
	var th: Dictionary = world.theme
	if _sky:
		_sky.color = Color(th.get("sky", "#8fd0f5"))
	var hc: Array = th.get("hills", [])
	for k in mini(hc.size(), _hills.size()):
		_hills[k].color = Color(hc[k])
		_hills[k].queue_redraw()

func _build_sky() -> void:
	var sky_layer := CanvasLayer.new()
	sky_layer.layer = -10
	add_child(sky_layer)
	var sky := ColorRect.new()
	sky.color = Color("#8fd0f5")
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky_layer.add_child(sky)
	_sky = sky
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
		_hills.append(bg)
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
	elif event.is_action_pressed("move_up"):
		var portal := world.portal_at(player.global_position)
		if not portal.is_empty() and player.is_on_floor():
			world.travel(portal)
	elif event.is_action_pressed("inventory_toggle"):
		inventory_ui.visible = not inventory_ui.visible
	elif event.is_action_pressed("potion_hp"):
		player.use_and_report(player.use_best("heal_hp"))
	elif event.is_action_pressed("potion_mp"):
		player.use_and_report(player.use_best("heal_mp"))
	elif event.is_action_pressed("party_toggle"):
		if sims.is_empty():
			summon_party()
		else:
			dismiss_party()
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
	var pr := Rect2(player.global_position + Vector2(-Actor.W / 2.0, -Actor.H), Vector2(Actor.W, Actor.H))
	_debug_draw.draw_rect(pr, Color(0.3, 1, 0.4, 0.8), false, 1.0)
	var reach := float(player.weapon.range)
	var tall := float(player.weapon.height)
	var c := player.global_position + Vector2(player.facing * (Actor.W / 2.0 + reach / 2.0), -Actor.H / 2.0)
	_debug_draw.draw_rect(Rect2(c - Vector2(reach, tall) / 2.0, Vector2(reach, tall)), Color(1, 1, 0.3, 0.6), false, 1.0)
