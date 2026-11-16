class_name InventoryUI
extends Control
## Inventory window (I): a grid of slots on the right edge. Click (or tap) a slot to use it.
## Hovering a slot shows its name and description. Icons are drawn in code.

const COLS := 6
const SLOT := 20.0
const PAD := 4.0

var player: Player
var top := 72.0
var _hover := -1
var _font: Font

func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func rows() -> int:
	return int(ceil(float(player.inventory.slots.size()) / COLS)) if player and player.inventory else 0

func _process(_delta: float) -> void:
	if not visible or player == null:
		return
	var vs := get_viewport_rect().size
	size = Vector2(COLS * SLOT + PAD * 2.0, rows() * SLOT + PAD * 2.0 + 12.0)
	position = Vector2(vs.x - size.x - 6.0, top)
	queue_redraw()

## Slot index under a local point, or -1.
func slot_at(p: Vector2) -> int:
	var g := p - Vector2(PAD, PAD + 12.0)
	if g.x < 0 or g.y < 0:
		return -1
	var c := int(g.x / SLOT)
	var r := int(g.y / SLOT)
	if c >= COLS or r >= rows():
		return -1
	return r * COLS + c

## Center of slot k in local coordinates (for tests and touch).
func slot_center(k: int) -> Vector2:
	return Vector2(PAD + (k % COLS) * SLOT + SLOT / 2.0, PAD + 12.0 + (k / COLS) * SLOT + SLOT / 2.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = slot_at(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var k := slot_at(event.position)
		if k >= 0 and player.inventory.slots[k] != null:
			player.use_and_report(player.use_item(String(player.inventory.slots[k].id)))
		accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = -1

func _draw() -> void:
	if player == null or player.inventory == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.07, 0.12, 0.88))
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.3), false, 1.0)
	_str(Vector2(PAD, 10), "Inventory  (I)", Color("#e8f3ff"), 8)
	var inv: Inventory = player.inventory
	for k in inv.slots.size():
		var c := slot_center(k)
		var r := Rect2(c - Vector2(SLOT, SLOT) / 2.0 + Vector2(1, 1), Vector2(SLOT - 2, SLOT - 2))
		draw_rect(r, Color(1, 1, 1, 0.12 if k == _hover else 0.06))
		draw_rect(r, Color(1, 1, 1, 0.2), false, 1.0)
		var s = inv.slots[k]
		if s == null:
			continue
		draw_icon(self, r.grow(-3), inv.def(String(s.id)))
		_str(r.position + Vector2(r.size.x - 1 - _font.get_string_size(str(s.count), HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x, r.size.y - 1), str(s.count), Color.WHITE, 7)
	if _hover >= 0 and _hover < inv.slots.size() and inv.slots[_hover] != null:
		var d: Dictionary = inv.def(String(inv.slots[_hover].id))
		var lines := [String(d.get("name", "")), String(d.get("desc", "")), "Click to use"]
		var w := 0.0
		for l in lines:
			w = maxf(w, _font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x)
		var tip := Rect2(Vector2(-w - 14, slot_center(_hover).y - 14), Vector2(w + 10, 36))
		draw_rect(tip, Color(0.04, 0.05, 0.08, 0.92))
		draw_rect(tip, Color(d.get("color", "#ffffff")), false, 1.0)
		for i in lines.size():
			_str(tip.position + Vector2(5, 10 + i * 10), lines[i], Color(d.get("color", "#ffffff")) if i == 0 else Color(0.85, 0.85, 0.85), 8)

func _str(pos: Vector2, s: String, col: Color, fsize: int) -> void:
	draw_string_outline(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 3, Color(0, 0, 0, 0.8))
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)

## Item icon in rect r on canvas item ci: bottles for potions, a flask for tonics.
static func draw_icon(ci: CanvasItem, r: Rect2, d: Dictionary) -> void:
	var col := Color(d.get("color", "#ffffff"))
	var cx := r.get_center().x
	match String(d.get("kind", "")):
		"tonic":
			var base := r.position.y + r.size.y
			ci.draw_colored_polygon(PackedVector2Array([Vector2(cx - 2, r.position.y + 3), Vector2(cx + 2, r.position.y + 3),
				Vector2(r.end.x - 1, base), Vector2(r.position.x + 1, base)]), col)
			ci.draw_rect(Rect2(cx - 2, r.position.y, 4, 3), Color("#c8a46a"))
			ci.draw_rect(Rect2(cx - 3, base - 4, 2, 2), Color(1, 1, 1, 0.7))
		_:
			ci.draw_rect(Rect2(r.position.x + 1, r.position.y + r.size.y * 0.35, r.size.x - 2, r.size.y * 0.65), col)
			ci.draw_rect(Rect2(cx - 2, r.position.y + 1, 4, r.size.y * 0.35), col.lightened(0.3))
			ci.draw_rect(Rect2(cx - 2, r.position.y, 4, 2), Color("#8a5a3a"))
			ci.draw_rect(Rect2(r.position.x + 2, r.position.y + r.size.y * 0.45, 2, 3), Color(1, 1, 1, 0.6))
