class_name PartyMenu
extends Control
## Right-click a party member (their frame top right, or the Simmo itself in the world) for a menu:
## Inspect, Trade, Kick. Inspect opens a window with their class, level, stats, gear and bag,
## with a Trade button. Esc or a click elsewhere closes the menu; Esc or X closes the window.

const MENU_W := 70.0
const MENU_ROW := 13.0
const ACTIONS := ["Inspect", "Trade", "Kick"]
const WIN_W := 204.0
const SLOT := 16.0
const COLS := 12

var main: Node
## The member the menu is open for (null: no menu) and where it was opened.
var menu_for: Actor = null
var menu_pos := Vector2.ZERO
## The member being inspected (null: no window).
var inspecting: Actor = null
var _font: Font

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font

func _process(_delta: float) -> void:
	# Members can leave (kick, map change frees nothing, but be safe).
	if menu_for != null and not _valid(menu_for):
		menu_for = null
	if inspecting != null and not _valid(inspecting):
		inspecting = null
	queue_redraw()

func _valid(m) -> bool:
	return is_instance_valid(m) and m.is_inside_tree() and main != null and m in main.sims

# --- hit tests ---

## The Simmo under screen point pos (party frame first, then the body in the world), or null.
func member_at(pos: Vector2) -> Actor:
	if main == null or main.hud == null:
		return null
	for fr in main.hud.party_frames():
		if fr[0].has_point(pos) and fr[1] in main.sims:
			return fr[1]
	for s in main.sims:
		if not _valid(s):
			continue
		var local: Vector2 = s.get_global_transform_with_canvas().affine_inverse() * pos
		if Rect2(-11, -38, 22, 40).has_point(local):
			return s
	return null

func menu_rect() -> Rect2:
	var vs := get_viewport_rect().size
	var h := ACTIONS.size() * MENU_ROW + 16.0
	var p := Vector2(minf(menu_pos.x, vs.x - MENU_W - 2), minf(menu_pos.y, vs.y - h - 2))
	return Rect2(p, Vector2(MENU_W, h))

func action_rect(k: int) -> Rect2:
	var r := menu_rect()
	return Rect2(r.position.x + 2, r.position.y + 14 + k * MENU_ROW, MENU_W - 4, MENU_ROW - 1)

func window_rect() -> Rect2:
	var bag_rows := 3
	if inspecting:
		bag_rows = ceili(inspecting.inventory.slots.size() / float(COLS))
	return Rect2(8, 40, WIN_W, 126 + bag_rows * SLOT)

func close_button() -> Rect2:
	var w := window_rect()
	return Rect2(w.end.x - 14, w.position.y + 3, 11, 11)

func trade_button() -> Rect2:
	var w := window_rect()
	return Rect2(w.end.x - 64, w.end.y - 17, 58, 13)

func slot_rect(k: int) -> Rect2:
	var w := window_rect()
	return Rect2(w.position.x + 6 + (k % COLS) * SLOT, w.position.y + 106 + (k / COLS) * SLOT, SLOT - 2, SLOT - 2)

# --- actions ---

func open_menu(m: Actor, pos: Vector2) -> void:
	menu_for = m
	menu_pos = pos
	Sfx.play("ui_click", 0.5)

func choose(action: String) -> void:
	var m := menu_for
	menu_for = null
	if m == null:
		return
	match action:
		"Inspect":
			inspecting = m
		"Trade":
			open_trade(m)
		"Kick":
			if inspecting == m:
				inspecting = null
			main.kick(m)

func open_trade(m: Actor) -> void:
	var tu = main.trade_ui
	var k: int = tu.partners().find(m)
	if k >= 0:
		tu.partner_idx = k
	tu.open()

# --- input ---

func _input(event: InputEvent) -> void:
	if main == null or main.get_tree().paused:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if menu_for != null:
			menu_for = null
			get_viewport().set_input_as_handled()
		elif inspecting != null:
			inspecting = null
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	var pos := get_global_mouse_position()
	if handle_click(event.button_index, pos):
		get_viewport().set_input_as_handled()

## A click at pos (screen units). Returns true when the menu or window used it.
func handle_click(button: int, pos: Vector2) -> bool:
	if menu_for != null:
		if button == MOUSE_BUTTON_LEFT:
			for k in ACTIONS.size():
				if action_rect(k).has_point(pos):
					choose(ACTIONS[k])
					return true
		menu_for = null
		if menu_rect().has_point(pos):
			return true
	if button == MOUSE_BUTTON_RIGHT:
		var m := member_at(pos)
		if m != null:
			open_menu(m, pos)
			return true
		return false
	if button == MOUSE_BUTTON_LEFT and inspecting != null:
		if close_button().has_point(pos):
			inspecting = null
			return true
		if trade_button().has_point(pos):
			open_trade(inspecting)
			return true
		return window_rect().has_point(pos)
	return false

# --- drawing ---

func _str(pos: Vector2, s: String, col: Color, fsize: int) -> void:
	draw_string_outline(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 3, Color(0, 0, 0, 0.8))
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)

func _button(r: Rect2, label: String, col: Color) -> void:
	draw_rect(r, Color(col, 0.35))
	draw_rect(r, col, false, 1.0)
	var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
	_str(r.position + Vector2((r.size.x - w) / 2.0, 10), label, Color.WHITE, 7)

func _draw() -> void:
	if inspecting != null:
		_draw_window(inspecting)
	if menu_for != null:
		_draw_menu(menu_for)

func _draw_menu(m: Actor) -> void:
	var r := menu_rect()
	draw_rect(r, Color(0.05, 0.06, 0.11, 0.95))
	draw_rect(r, m.tag_color, false, 1.0)
	_str(r.position + Vector2(4, 10), m.display_name, m.tag_color, 7)
	var mouse := get_global_mouse_position()
	for k in ACTIONS.size():
		var ar := action_rect(k)
		if ar.has_point(mouse):
			draw_rect(ar, Color(1, 1, 1, 0.12))
		_str(ar.position + Vector2(4, 9), ACTIONS[k], Color("#ff8080") if ACTIONS[k] == "Kick" else Color.WHITE, 7)

func _draw_window(m: Actor) -> void:
	var w := window_rect()
	draw_rect(w, Color(0.05, 0.06, 0.11, 0.94))
	draw_rect(w, m.tag_color, false, 1.0)
	var x := w.position.x + 6
	var y := w.position.y
	_str(Vector2(x, y + 12), m.display_name, m.tag_color, 10)
	_button(close_button(), "x", Color(0.7, 0.7, 0.7))
	var role := String(m.get("role")) if m.get("role") != null else ""
	_str(Vector2(x, y + 24), "Lv.%d %s%s" % [m.level, m.class_name_label(), "  (%s)" % role if role != "" else ""], Color(0.85, 0.87, 0.92), 7)
	_str(Vector2(x, y + 35), "HP %d / %d   MP %d / %d" % [m.hp, m.max_hp, int(m.mp), int(m.max_mp)], Color(0.85, 0.87, 0.92), 7)
	var sx := x
	for st in ["str", "dex", "int", "luk"]:
		_str(Vector2(sx, y + 46), "%s %d" % [st.to_upper(), m.stat(st)], Color("#ffd84a"), 7)
		sx += 46.0
	# Gear: weapon, ring, amulet.
	_str(Vector2(x, y + 60), "Gear", Color(0.6, 0.65, 0.75), 7)
	var gx := x
	for slot in ["weapon", "ring", "amulet"]:
		var gr := Rect2(gx, y + 64, 14, 14)
		draw_rect(gr, Color(1, 1, 1, 0.07))
		var it: Dictionary = m.equipment.get(slot, {})
		var label := String(m.weapon.get("name", "")) if slot == "weapon" else "none"
		if not it.is_empty():
			InventoryUI.draw_item(self, gr, it)
			label = String(it.name)
		elif slot == "weapon":
			Actor.draw_weapon_shape(self, m.weapon_key, m.weapon, gr.get_center() + Vector2(-4, 4), gr.get_center() + Vector2(4, -4))
		_str(Vector2(gx, y + 87), label.left(12), Gear.color(String(it.rarity)) if not it.is_empty() else Color(0.75, 0.75, 0.75), 6)
		gx += 64.0
	_str(Vector2(x, y + 101), "Bag", Color(0.6, 0.65, 0.75), 7)
	var inv: Inventory = m.inventory
	for k in inv.slots.size():
		var r := slot_rect(k)
		draw_rect(r, Color(1, 1, 1, 0.07))
		var s = inv.slots[k]
		if s == null:
			continue
		if s.has("item"):
			InventoryUI.draw_item(self, r.grow(-1), s.item)
		else:
			InventoryUI.draw_icon(self, r.grow(-2), inv.def(String(s.id)))
			var n := str(s.count)
			_str(r.position + Vector2(r.size.x - 1 - _font.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x, r.size.y), n, Color.WHITE, 6)
	_str(Vector2(x, w.end.y - 7), "Right-click a party member for this menu", Color(0.5, 0.55, 0.65), 6)
	_button(trade_button(), "Trade (T)", ChatLog.color("trade"))
