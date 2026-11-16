class_name CreatorScreen
extends Control
## Character creator (after class select), MapleStory style: name, gender, skin, face, eyes,
## hair style and color, top, bottom, shoes, hat, cape and their colors. Live preview with
## blinking, wind in the hair and cloth, and a walk toggle. Options come from data/appearance.json.
## Mouse: click the arrows or swatches. Keys: Up / Down pick a row, Left / Right change it,
## R randomizes, Enter starts, Esc goes back.

signal done(look: Dictionary, player_name: String)
signal back

const ROW_H := 15.0
const NAMES := ["Aeris", "Kaito", "Mira", "Rowan", "Sable", "Toma", "Wren", "Yuki", "Bastian", "Lyra", "Pip", "Nox"]

var balance: Dictionary
var app: Dictionary
var class_id := ""
var look: Dictionary = {}
var row := 1
var walking := false
var face := 1
var _doll: Doll
var _font: Font
var _name_edit: LineEdit
var _t := 0.0

## [key, label, kind]: kind "list" uses app[list], "color" a palette.
func rows() -> Array:
	return [
		["name", "Name", "name"],
		["gender", "Gender", "genders"],
		["skin", "Skin", "skin"],
		["face", "Face", "faces"],
		["eye_color", "Eyes", "eye_colors"],
		["hair", "Hair", "hair"],
		["hair_color", "Hair color", "hair_colors"],
		["top", "Top", "tops"],
		["top_color", "Top color", "cloth_colors"],
		["bottom", "Bottom", "bottoms"],
		["bottom_color", "Bottom color", "cloth_colors"],
		["shoes", "Shoes", "shoes"],
		["shoes_color", "Shoe color", "cloth_colors"],
		["hat", "Hat", "hats"],
		["hat_color", "Hat color", "cloth_colors"],
		["cape", "Cape", "capes"],
		["cape_color", "Cape color", "cloth_colors"],
	]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	if look.is_empty():
		look = Doll.normalize(balance.classes.get(class_id, {}).get("look", {}))
	_doll = Doll.new(look)
	_name_edit = LineEdit.new()
	_name_edit.text = NAMES.pick_random()
	_name_edit.max_length = 14
	_name_edit.add_theme_font_size_override("font_size", 9)
	_name_edit.custom_minimum_size = Vector2(0, 13)
	add_child(_name_edit)

func options(kind: String) -> Array:
	if kind == "hair":
		return app.hair.get(String(look.gender), app.hair.male)
	return app.get(kind, [])

## Step the value in row r by `step` (wraps).
func change(r: int, step: int) -> void:
	var spec: Array = rows()[r]
	if spec[2] == "name":
		return
	var opts := options(spec[2])
	if opts.is_empty():
		return
	var k := opts.find(look.get(spec[0], opts[0]))
	look[spec[0]] = opts[posmod(k + step, opts.size())]
	if spec[0] == "gender":
		# Hair lists differ per gender.
		var hl := options("hair")
		if not look.hair in hl:
			look.hair = hl[0]
	_doll.set_look(look)
	Sfx.play("ui_click", 0.6)

func randomize_look() -> void:
	for r in rows().size():
		var spec: Array = rows()[r]
		if spec[2] == "name":
			continue
		if spec[0] == "gender":
			look.gender = app.genders.pick_random()
			continue
		look[spec[0]] = options(spec[2]).pick_random()
	if not look.hair in options("hair"):
		look.hair = options("hair")[0]
	_doll.set_look(look)
	_name_edit.text = NAMES.pick_random()

func player_name() -> String:
	var n := _name_edit.text.strip_edges()
	return n if n != "" else "Hero"

func finish() -> void:
	done.emit(look.duplicate(), player_name())

# --- layout ---

func panel_rect() -> Rect2:
	var vs := get_viewport_rect().size
	var w := 270.0
	return Rect2(vs.x / 2.0 + 10, 40, w, rows().size() * ROW_H + 8)

func row_rect(r: int) -> Rect2:
	var p := panel_rect()
	return Rect2(p.position.x + 4, p.position.y + 4 + r * ROW_H, p.size.x - 8, ROW_H - 1)

func arrow_rect(r: int, right: bool) -> Rect2:
	var rr := row_rect(r)
	return Rect2(rr.position.x + (rr.size.x - 14 if right else 88), rr.position.y + 1, 12, ROW_H - 3)

func buttons() -> Dictionary:
	var vs := get_viewport_rect().size
	var y := vs.y - 26
	return {
		"random": Rect2(vs.x / 2.0 - 230, y, 80, 18),
		"walk": Rect2(vs.x / 2.0 - 145, y, 70, 18),
		"turn": Rect2(vs.x / 2.0 - 70, y, 60, 18),
		"back": Rect2(vs.x / 2.0 + 10, y, 70, 18),
		"start": Rect2(vs.x / 2.0 + 100, y, 180, 18),
	}

func preview_pos() -> Vector2:
	var vs := get_viewport_rect().size
	return Vector2(vs.x / 2.0 - 130, 280)

func _process(delta: float) -> void:
	_t += delta
	var r := row_rect(0)
	_name_edit.position = Vector2(r.position.x + 88, r.position.y)
	_name_edit.size = Vector2(r.size.x - 88, ROW_H - 1)
	# Walking in place: move the doll's origin so its hair and cloth trail like the real thing.
	var vel := Vector2(face * 110.0, 0) if walking else Vector2.ZERO
	_doll.update(delta, Vector2(_t * vel.x, 0), vel, true, face)
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not visible or _name_edit.has_focus():
		if event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE] and _name_edit.has_focus():
			_name_edit.release_focus()
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_UP, KEY_W:
			row = posmod(row - 1, rows().size())
		KEY_DOWN, KEY_S:
			row = posmod(row + 1, rows().size())
		KEY_LEFT, KEY_A:
			change(row, -1)
		KEY_RIGHT, KEY_D:
			change(row, 1)
		KEY_R:
			randomize_look()
		KEY_ENTER, KEY_KP_ENTER:
			finish()
		KEY_ESCAPE:
			back.emit()
		_:
			return
	get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var pos: Vector2 = event.position
	for r in rows().size():
		if arrow_rect(r, false).has_point(pos):
			row = r
			change(r, -1)
		elif arrow_rect(r, true).has_point(pos):
			row = r
			change(r, 1)
		elif row_rect(r).has_point(pos):
			row = r
	var b := buttons()
	if b.random.has_point(pos):
		randomize_look()
	elif b.walk.has_point(pos):
		walking = not walking
	elif b.turn.has_point(pos):
		face = -face
	elif b.back.has_point(pos):
		back.emit()
	elif b.start.has_point(pos):
		finish()

func _str(pos: Vector2, s: String, col: Color, fsize: int) -> void:
	draw_string_outline(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 3, Color(0, 0, 0, 0.8))
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)

func _button(r: Rect2, label: String, col: Color) -> void:
	draw_rect(r, Color(col, 0.3))
	draw_rect(r, col, false, 1.0)
	var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	_str(r.position + Vector2((r.size.x - w) / 2.0, 12), label, Color.WHITE, 8)

func _draw() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color("#141a2e"))
	draw_rect(Rect2(0, vs.y * 0.6, vs.x, vs.y * 0.4), Color("#1b2440"))
	var cc := Color(balance.classes.get(class_id, {}).get("color", "#ffffff"))
	var title := "Create your %s" % balance.classes.get(class_id, {}).get("name", "character")
	var tw := _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	_str(Vector2((vs.x - tw) / 2.0, 26), title, cc, 16)
	# Preview on a little patch of grass.
	var pp := preview_pos()
	draw_rect(Rect2(pp.x - 70, pp.y, 140, 6), Color("#5fb548"))
	draw_rect(Rect2(pp.x - 70, pp.y + 6, 140, 18), Color("#7a5232"))
	var weapon_id := String(balance.classes.get(class_id, {}).get("weapons", ["short_sword"])[0])
	Actor.draw_preview(self, _doll, weapon_id, balance.weapons.get(weapon_id, {}), pp, 4.0)
	_str(Vector2(pp.x - 70, pp.y + 40), "Hair and cloth move with the wind", Color(0.6, 0.65, 0.75), 7)
	# Option rows.
	var p := panel_rect()
	draw_rect(p, Color(0.06, 0.07, 0.12, 0.9))
	draw_rect(p, Color(cc, 0.6), false, 1.0)
	for r in rows().size():
		var spec: Array = rows()[r]
		var rr := row_rect(r)
		if r == row:
			draw_rect(rr, Color(cc, 0.18))
		_str(rr.position + Vector2(3, 10), spec[1], Color(0.85, 0.87, 0.92), 8)
		if spec[2] == "name":
			continue
		_str(arrow_rect(r, false).position + Vector2(3, 9), "<", Color.WHITE, 8)
		_str(arrow_rect(r, true).position + Vector2(3, 9), ">", Color.WHITE, 8)
		var val = look.get(spec[0], "")
		var mid := Vector2(rr.position.x + 104, rr.position.y + 10)
		if String(val).begins_with("#"):
			draw_rect(Rect2(mid + Vector2(0, -8), Vector2(rr.size.x - 124, 9)), Color(val))
			draw_rect(Rect2(mid + Vector2(0, -8), Vector2(rr.size.x - 124, 9)), Color(1, 1, 1, 0.4), false, 1.0)
		else:
			_str(mid, String(val).capitalize(), Color.WHITE, 8)
	_str(Vector2(p.position.x, p.end.y + 11), "Up / Down: row   Left / Right: change   R: random   Enter: start", Color(0.55, 0.6, 0.7), 7)
	var b := buttons()
	_button(b.random, "Randomize (R)", Color(0.7, 0.7, 0.9))
	_button(b.walk, "Walk: %s" % ("on" if walking else "off"), Color(0.7, 0.7, 0.9))
	_button(b.turn, "Turn", Color(0.7, 0.7, 0.9))
	_button(b.back, "Back (Esc)", Color(0.7, 0.7, 0.7))
	_button(b.start, "Start as %s  (Enter)" % player_name(), cc)
