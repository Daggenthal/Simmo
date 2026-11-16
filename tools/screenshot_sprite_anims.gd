extends SceneTree
## Every PixelLab sprite pose staged in a grid, zoomed: idle, walk, jump (rising and falling), each
## weapon's attack mid-swing, facing left, and the hair palette swaps.
## Saves screenshots/sprite_anims.png.
## Run: godot --path . --rendering-driver opengl3 --script res://tools/screenshot_sprite_anims.gd

const ZOOM := 1.5
var _canvas: Node2D
var _cells: Array = []   # [label, doll]
var _frame := 0

func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	var DollS = load("res://scripts/doll.gd")
	var app: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/appearance.json"))
	var base := {"sprite": "test_heroine"}
	var poses := [
		["idle", {}], ["walk 1", {"walk": 0.3}], ["walk 2", {"walk": 2.4}], ["walk 3", {"walk": 4.5}],
		["jump up", {"air": -300.0}], ["jump down", {"air": 250.0}],
		["slash early", {"act": ["attack_slash", 0.3]}], ["slash hit", {"act": ["attack_slash", 0.7]}],
		["stab", {"act": ["attack_stab", 0.7]}], ["throw", {"act": ["attack_throw", 0.6]}],
		["cast", {"act": ["attack_cast", 0.6]}], ["facing left", {"face": -1}],
	]
	for pz in poses:
		var d = DollS.new(base)
		var o: Dictionary = pz[1]
		d.facing = int(o.get("face", 1))
		if o.has("walk"):
			d.speed_frac = 1.0
			d.walk = float(o.walk)
		if o.has("air"):
			d.airborne = true
			d.vy = float(o.air)
		if o.has("act"):
			d.action = {"kind": o.act[0], "t": o.act[1]}
		_cells.append([pz[0], d])
	for hc in (app.hair_colors as Array).slice(0, 6):
		var lk := base.duplicate()
		lk.sprite_hair = hc
		_cells.append(["hair " + String(hc), DollS.new(lk)])
	_canvas = Node2D.new()
	_canvas.draw.connect(_draw_grid)
	root.add_child(_canvas)

func _draw_grid() -> void:
	var font := ThemeDB.fallback_font
	_canvas.draw_rect(Rect2(0, 0, 640, 360), Color("#3a4a5e"))
	for k in _cells.size():
		var col := k % 6
		var row := k / 6
		var at := Vector2(55 + col * 105, 95 + row * 95)
		_canvas.draw_line(at + Vector2(-45, 0), at + Vector2(45, 0), Color("#5fb548"), 1.0)
		_cells[k][1].draw(_canvas, Vector2.ZERO, at, ZOOM)
		_canvas.draw_string(font, at + Vector2(-45, 11), _cells[k][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)

func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 2:
		root.get_node("Log").debug = false
	_canvas.queue_redraw()
	if _frame == 20:
		var img := root.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://screenshots/sprite_anims.png"))
		root.get_node("Log").ok("saved screenshots/sprite_anims.png")
		quit(0)
	return false
