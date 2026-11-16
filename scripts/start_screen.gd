class_name StartScreen
extends Control
## Class select: three class cards on top, the selected class's weapons, stats and skills below.
## Pick with a click / tap (click again or Start to begin), 1 / 2 / 3, Left / Right, Enter or Space.

signal class_chosen(id: String)

const CARD := Vector2(150, 100)
const GAP := 12.0
const SLOT_KEYS := ["Z", "X", "C", "V"]

var balance: Dictionary
var selected := 0
var ids: Array = []
var _hover := -1
var _font: Font
var _t := 0.0
var _chosen := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	ids = balance.get("classes", {}).keys()

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func class_id() -> String:
	return String(ids[selected])

func select(n: int) -> void:
	selected = clampi(n, 0, ids.size() - 1)

func choose() -> void:
	if _chosen:
		return
	_chosen = true
	Log.info("Class chosen: %s" % class_id())
	class_chosen.emit(class_id())

func _width() -> float:
	return ids.size() * CARD.x + (ids.size() - 1) * GAP

func card_rect(n: int) -> Rect2:
	var vs := get_viewport_rect().size
	var x0 := (vs.x - _width()) / 2.0
	return Rect2(Vector2(x0 + n * (CARD.x + GAP), 50), CARD)

func details_rect() -> Rect2:
	var vs := get_viewport_rect().size
	var x0 := (vs.x - _width()) / 2.0
	return Rect2(x0, 158, _width(), vs.y - 158 - 30)

func start_rect() -> Rect2:
	var vs := get_viewport_rect().size
	return Rect2(vs.x / 2.0 - 90, vs.y - 25, 180, 18)

func _input(event: InputEvent) -> void:
	if not visible or _chosen:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4:
				select(event.keycode - KEY_1)
			KEY_LEFT, KEY_A:
				select(selected - 1)
			KEY_RIGHT, KEY_D:
				select(selected + 1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				choose()
			_:
				return
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_DPAD_LEFT:
				select(selected - 1)
			JOY_BUTTON_DPAD_RIGHT:
				select(selected + 1)
			JOY_BUTTON_A, JOY_BUTTON_START:
				choose()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = -1
		for n in ids.size():
			if card_rect(n).has_point(event.position):
				_hover = n
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if start_rect().has_point(event.position):
			choose()
			return
		for n in ids.size():
			if card_rect(n).has_point(event.position):
				if n == selected:
					choose()
				else:
					select(n)

func _str(pos: Vector2, s: String, col: Color, fsize: int) -> void:
	draw_string_outline(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 3, Color(0, 0, 0, 0.8))
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)

func _wrap(pos: Vector2, s: String, width: float, col: Color, fsize: int, max_lines := -1) -> float:
	var lines := 0
	var words := s.split(" ")
	var line := ""
	var y := pos.y
	for w in words:
		var test := w if line == "" else line + " " + w
		if _font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > width and line != "":
			_str(Vector2(pos.x, y), line, col, fsize)
			y += fsize + 2
			lines += 1
			line = w
			if max_lines > 0 and lines >= max_lines:
				return y
		else:
			line = test
	if line != "":
		_str(Vector2(pos.x, y), line, col, fsize)
		y += fsize + 2
	return y

func _centered(y: float, s: String, col: Color, fsize: int) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	_str(Vector2((get_viewport_rect().size.x - w) / 2.0, y), s, col, fsize)

func _draw() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color("#141a2e"))
	draw_rect(Rect2(0, vs.y * 0.55, vs.x, vs.y * 0.45), Color("#1b2440"))
	for k in 40:
		var p := Vector2(fmod(k * 97.0, vs.x), fmod(k * 53.0, vs.y * 0.5))
		draw_rect(Rect2(p, Vector2(1, 1)), Color(1, 1, 1, 0.3 + 0.3 * sin(_t * 2.0 + k)))
	_centered(28, "SIMMO", Color("#ffd84a"), 24)
	_centered(42, "Choose your class", Color("#cfd8e3"), 9)
	var classes: Dictionary = balance.classes
	for n in ids.size():
		_draw_card(n, classes[ids[n]])
	_draw_details(classes[class_id()])
	var sr := start_rect()
	var cc := Color(classes[class_id()].get("color", "#ffffff"))
	draw_rect(sr, Color(cc, 0.25 + 0.1 * sin(_t * 4.0)))
	draw_rect(sr, cc, false, 1.0)
	var label := "Start as %s  (Enter)" % classes[class_id()].name
	var lw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	_str(Vector2(sr.position.x + (sr.size.x - lw) / 2.0, sr.position.y + 13), label, Color.WHITE, 9)

func _draw_card(n: int, c: Dictionary) -> void:
	var r := card_rect(n)
	var col := Color(c.get("color", "#ffffff"))
	var sel := n == selected
	draw_rect(r, Color(0.1, 0.12, 0.2, 0.95) if sel else Color(0.08, 0.09, 0.15, 0.85))
	draw_rect(r, col if sel else Color(1, 1, 1, 0.25 if n != _hover else 0.5), false, 2.0 if sel else 1.0)
	_str(r.position + Vector2(6, 11), str(n + 1), Color(1, 1, 1, 0.5), 8)
	# Paper doll with the starting weapon, scaled up.
	var weapon_id := String(c.weapons[0])
	var bob := sin(_t * 3.0 + n) * 1.5 if sel else 0.0
	draw_set_transform(r.position + Vector2(34, 82 + bob), 0.0, Vector2(2.5, 2.5))
	Actor.draw_doll(self, c.get("look", {}), 1)
	Actor.draw_idle_weapon(self, weapon_id, balance.weapons[weapon_id], 1)
	draw_set_transform(Vector2.ZERO)
	var tx := r.position.x + 74
	_str(Vector2(tx, r.position.y + 18), String(c.name), col, 12)
	_str(Vector2(tx, r.position.y + 30), "Main stat: %s" % String(c.primary).to_upper(), Color("#ffd84a"), 8)
	_wrap(Vector2(tx, r.position.y + 42), String(c.desc), r.size.x - 78, Color(0.85, 0.87, 0.92), 8, 5)

func _draw_details(c: Dictionary) -> void:
	var r := details_rect()
	var col := Color(c.get("color", "#ffffff"))
	draw_rect(r, Color(0.06, 0.07, 0.12, 0.9))
	draw_rect(r, Color(col, 0.6), false, 1.0)
	var x := r.position.x + 8
	var y := r.position.y + 13
	var st: Dictionary = c.get("stats", {})
	_str(Vector2(x, y), "%s   STR %d  DEX %d  INT %d  LUK %d   HP x%.2f  MP x%.2f" % [c.name, st.get("str", 4), st.get("dex", 4), st.get("int", 4), st.get("luk", 4), c.get("hp_mult", 1.0), c.get("mp_mult", 1.0)], col, 9)
	y += 14
	# Weapons (left column)
	var col_w := r.size.x * 0.42
	_str(Vector2(x, y), "WEAPONS  (Attack: Ctrl / J,  switch: 1 / 2 / E)", Color("#ffd84a"), 8)
	var wy := y + 11
	for k in c.weapons.size():
		var wid := String(c.weapons[k])
		var w: Dictionary = balance.weapons[wid]
		_str(Vector2(x, wy), "%d  %s%s" % [k + 1, w.name, "  (starting)" if k == 0 else ""], Color.WHITE, 8)
		wy = _wrap(Vector2(x + 10, wy + 10), String(w.get("action", "")), col_w - 12, Color(0.75, 0.78, 0.85), 7)
		wy += 2
	_str(Vector2(x, wy + 6), "Auto-battle (Q) uses all of this for you.", Color(0.6, 0.65, 0.75), 7)
	# Skills (right column)
	var sx := r.position.x + col_w + 12
	var sw := r.size.x - col_w - 20
	_str(Vector2(sx, y), "SKILLS", Color("#ffd84a"), 8)
	var sy := y + 11
	var spells: Dictionary = balance.spells
	for k in c.spells.size():
		var sp: Dictionary = spells.get(String(c.spells[k]), {})
		var head := "%s  %s" % [SLOT_KEYS[k] if k < SLOT_KEYS.size() else "", sp.get("name", "")]
		_str(Vector2(sx, sy), head, Color(sp.get("color", "#ffffff")), 8)
		var meta := "%d MP, %ss" % [int(sp.get("mp", 0)), str(sp.get("cooldown", 0))]
		var mw := _font.get_string_size(meta, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
		_str(Vector2(sx + sw - mw, sy), meta, Color(0.6, 0.65, 0.75), 7)
		sy = _wrap(Vector2(sx + 10, sy + 10), String(sp.get("desc", "")), sw - 12, Color(0.75, 0.78, 0.85), 7, 2)
		sy += 1
