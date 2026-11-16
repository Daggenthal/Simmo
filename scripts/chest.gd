class_name Chest
extends Node2D
## Boss loot chest. Glows (a real light and a beam of light) in the color of the best item inside,
## Diablo style. Stand on it and press Up to open, or let auto-battle walk over and open it.
## Items go straight into the player's bag; each is announced in chat in its rarity's color.

var items: Array = []
var level := 1
var opened := false
var best := "common"
var _t := 0.0
var _open_t := 0.0
var _light: PointLight2D

func setup(loot: Array, lvl: int) -> void:
	items = loot
	level = lvl
	best = Gear.best(items)

func _ready() -> void:
	z_index = 4
	_light = Lighting.add(self, Gear.color(best), 90.0, 0.9)
	if _light:
		_light.position = Vector2(0, -10)

## Hand everything to `player`. Returns the items given (empty if already open).
func open(player: Actor) -> Array:
	if opened:
		return []
	opened = true
	Sfx.play("chest_open")
	var given: Array = []
	var k := 0
	for it in items:
		if player.inventory.add_item(it) >= 0:
			given.append(it)
			ChatLog.add("loot", "[%s] %s" % [Gear.rarity_name(String(it.rarity)), it.name], Gear.color(String(it.rarity)))
			FloatText.spawn(get_parent(), global_position + Vector2(0, -26 - k * 11), it.name, Gear.color(String(it.rarity)), 2.2)
		else:
			ChatLog.add("warning", "Inventory full: %s stayed in the chest" % it.name)
		k += 1
	Fx.burst(get_parent(), global_position + Vector2(0, -8), 30.0, Gear.color(best))
	return given

func _process(delta: float) -> void:
	_t += delta
	if opened:
		_open_t += delta
		if _light:
			_light.energy = maxf(0.9 - _open_t * 0.3, 0.0)
		if _open_t > 8.0:
			queue_free()
	queue_redraw()

func _draw() -> void:
	var col := Gear.color(best)
	if not opened:
		# Beam of light in the best item's color.
		for i in 5:
			var w := 14.0 - i * 2.5
			draw_rect(Rect2(-w / 2.0, -90, w, 80), Color(col, 0.05 + 0.02 * sin(_t * 3.0)))
		for i in 4:
			var ph := fmod(_t * 0.6 + i * 0.25, 1.0)
			draw_rect(Rect2(sin(i * 2.1) * 6.0, -10 - ph * 60.0, 1.5, 1.5), Color(col.lightened(0.4), 1.0 - ph))
	var lid := -minf(_open_t * 6.0, 1.0) * 0.9
	draw_rect(Rect2(-11, -10, 22, 10), Color("#7a5232"))
	draw_rect(Rect2(-11, -10, 22, 2), Color("#e8c34a"))
	draw_rect(Rect2(-11, -2, 22, 2), Color("#5e3d24"))
	draw_set_transform(Vector2(-11, -10), lid, Vector2.ONE)
	draw_rect(Rect2(0, -6, 22, 6), Color("#8b6238"))
	draw_rect(Rect2(0, -6, 22, 1.5), Color("#e8c34a"))
	draw_rect(Rect2(9.5, -3, 3, 4), Color("#e8c34a"))
	draw_set_transform(Vector2.ZERO)
	if not opened:
		draw_circle(Vector2(0, -6), 3.0, Color(col, 0.5 + 0.3 * sin(_t * 5.0)))
