class_name StatsUI
extends Control
## Stats window (K): STR / DEX / INT / LUK with + buttons for free AP, what they do right now,
## and the auto-assign toggle. Sits on the right edge, left of the inventory when both are open.

const W := 150.0
const ROW := 12.0
const STAT_LINES := {
	"str": "Damage for STR weapons and skills, +HP",
	"dex": "Damage for DEX weapons and skills, +crit",
	"int": "Damage for staffs and spells, +MP",
	"luk": "+Crit chance, +item drops",
}

var player: Player
var inventory_ui: Control
var top := 72.0
var _font: Font

func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func _process(_delta: float) -> void:
	if not visible or player == null:
		return
	var vs := get_viewport_rect().size
	size = Vector2(W, 22 + ROW * 4 + 70)
	var right := vs.x - 6.0
	if inventory_ui and inventory_ui.visible:
		right = inventory_ui.position.x - 6.0
	position = Vector2(right - size.x, top)
	queue_redraw()

func plus_rect(n: int) -> Rect2:
	return Rect2(W - 18, 24 + n * ROW - 8, 12, 10)

func auto_rect() -> Rect2:
	return Rect2(6, size.y - 16, W - 12, 12)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for n in Actor.STATS.size():
			if plus_rect(n).has_point(event.position):
				player.add_stat(Actor.STATS[n])
		if auto_rect().has_point(event.position):
			player.auto_assign = not player.auto_assign
			if player.auto_assign:
				player.auto_spend()
				player.recalc()
			player.stats_changed.emit()
		accept_event()

func _str(pos: Vector2, s: String, col: Color, fsize: int) -> void:
	draw_string_outline(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 3, Color(0, 0, 0, 0.8))
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)

func _draw() -> void:
	if player == null:
		return
	var p := player
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.07, 0.12, 0.88))
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.3), false, 1.0)
	_str(Vector2(6, 11), "Stats (K)   Lv %d %s" % [p.level, p.class_name_label()], Color("#e8f3ff"), 8)
	_str(Vector2(W - 40, 11), "AP %d" % p.ap, Color("#ffd84a") if p.ap > 0 else Color(0.6, 0.6, 0.6), 8)
	var main := String(p.class_cfg.get("primary", ""))
	for n in Actor.STATS.size():
		var k: String = Actor.STATS[n]
		var y := 24 + n * ROW
		_str(Vector2(6, y), k.to_upper(), Color("#ffd84a") if k == main else Color.WHITE, 8)
		_str(Vector2(30, y), str(p.stats[k]), Color.WHITE, 8)
		_str(Vector2(52, y), STAT_LINES[k], Color(0.65, 0.7, 0.8), 6)
		var pr := plus_rect(n)
		draw_rect(pr, Color(0.3, 0.6, 0.3, 0.9) if p.ap > 0 else Color(0.3, 0.3, 0.3, 0.6))
		_str(pr.position + Vector2(3, 8), "+", Color.WHITE, 8)
	var y := 24 + 4 * ROW + 4
	var dr: Vector2i = p.damage_range(p.weapon)
	_str(Vector2(6, y), "%s  %d-%d dmg" % [p.weapon.name, dr.x, dr.y], Color(0.9, 0.9, 0.9), 7)
	y += 10
	_str(Vector2(6, y), "HP %d   MP %d   Crit %.1f%%" % [p.max_hp, p.max_mp, p.crit_chance() * 100.0], Color(0.9, 0.9, 0.9), 7)
	y += 10
	_str(Vector2(6, y), "Item drops +%d%%" % int(round((p.drop_mult() - 1.0) * 100.0)), Color(0.9, 0.9, 0.9), 7)
	var ar := auto_rect()
	draw_rect(ar, Color(0.25, 0.45, 0.25, 0.8) if p.auto_assign else Color(0.3, 0.3, 0.3, 0.6))
	_str(ar.position + Vector2(4, 9), "Auto-assign AP: %s (click)" % ("ON" if p.auto_assign else "OFF"), Color.WHITE, 7)
