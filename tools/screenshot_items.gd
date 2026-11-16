extends SceneTree
## Screenshot of the inventory window (with a hover tooltip), an active XP buff and the potion quick slots.
## Run: godot --path . --rendering-driver opengl3 --script res://tools/screenshot_items.gd

var _main
var _frame := 0

func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)

func _process(_d: float) -> bool:
	_frame += 1
	var p = _main.player
	if _frame == 5:
		p.position = Vector2(560, 330)
		p.use_item("xp_tonic")
		p.inventory.add("white_potion", 3)
		p.inventory.add("xp_elixir", 1)
		_main.inventory_ui.visible = true
	if _frame == 8:
		var ev := InputEventMouseMotion.new()
		ev.position = _main.inventory_ui.slot_center(2)
		_main.inventory_ui._gui_input(ev)
	if _frame == 40:
		var img := root.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://screenshots/items.png"))
		root.get_node("Log").ok("saved screenshots/items.png")
		quit(0)
	return false
