extends SceneTree
## Renders a staged magic scene: frozen, burning, poisoned and chilled mobs, a chain
## lightning strike and a kunai mid-arc. xvfb-run godot --path . --script res://tools/screenshot_magic.gd
var _main
var _f := 0
func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)
func _process(_d: float) -> bool:
	_f += 1
	var p = _main.player
	var w = _main.world
	if _f == 5:
		_main.hud._hint_time = 0.0
		p.position = Vector2(520, 330)
		p.facing = 1
		var spots := [Vector2(580, 329), Vector2(620, 329), Vector2(660, 329), Vector2(700, 329)]
		for k in w.mobs.size():
			var m = w.mobs[k]
			m.data = m.data.duplicate()
			m.data.speed = 0.0
			m.data.hop_velocity = 0.0
			m.data.touch_damage = 0
			m.max_hp = 9999
			if k < 4:
				m.home = spots[k]
				m.set_bounds(w.nav)
				m.respawn()
		var C = load("res://scripts/combat.gd")
		w.mobs[0].apply_freeze(9.0)
		w.mobs[1].apply_burn(4, 9.0, p)
		for k in 4:
			w.mobs[2].add_poison(2, 5, 9.0, p)
		w.mobs[3].apply_chill(0.45, 9.0)
		p.spell_cd.fireball = 0.6
		p.spell_cd.frost_bolt = 0.3
		p.mp = 23
	if _f == 40:
		p._cast_cd = 0.0
		p.spell_cd.chain_lightning = 0.0
		p.mp += 12
		p.cast("chain_lightning")
		p.equip("throwing_kunai")
		p.imbue_element = "lightning"
	if _f == 90:
		for k in 4:
			var m = w.mobs[k]
			print("mob%d flash=%.3f color=%s frozen=%.2f burn=%.2f poison=%d chill=%.2f alive=%s phys=%s" % [k, m._flash, m.color, m.frozen_t, m.burn_t, m.poison_stacks, m.chill_t, m.alive, m.is_physics_processing()])
		var img := root.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://screenshots/magic.png"))
		quit(0)
	return false
