extends Control
## MapleStory-style bottom status bar plus the debug overlay (F3).
## Anchored to the screen edges, so wider screens just get more world.

var player: Player
var world: World
var map_name := "Mossy Meadow"
var _hint_time := 8.0
var show_help := true
const HELP_LINES := [
	"Move: Arrows / WASD    Jump: Alt / Space    Attack: Ctrl / J",
	"Drop down: Down + Jump    Auto-battle: Q / Tab    Weapons: 1-4 or E",
	"Spells: Z Fire   X Frost   C Venom   V Lightning",
	"Respawn mobs: F5    Debug: F3    Hide this: F1",
]
var _font: Font
var _auto_btn: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	Log.debug_changed.connect(func(_on: bool) -> void: queue_redraw())
	# AUTO toggle: a real button so it works with mouse now and touch later.
	_auto_btn = Button.new()
	_auto_btn.text = "AUTO"
	_auto_btn.toggle_mode = true
	_auto_btn.focus_mode = Control.FOCUS_NONE
	_auto_btn.add_theme_font_size_override("font_size", 9)
	_auto_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_auto_btn.offset_left = -46
	_auto_btn.offset_top = -20
	_auto_btn.offset_right = -4
	_auto_btn.offset_bottom = -2
	_auto_btn.toggled.connect(func(on: bool) -> void:
		if player and player.auto_battle != on:
			player.set_auto_battle(on))
	add_child(_auto_btn)

func _process(delta: float) -> void:
	_hint_time = max(_hint_time - delta, 0.0)
	if player and _auto_btn.button_pressed != player.auto_battle:
		_auto_btn.set_pressed_no_signal(player.auto_battle)
	_auto_btn.modulate = Color("#ffd84a") if player and player.auto_battle else Color.WHITE
	queue_redraw()

func _text(pos: Vector2, s: String, col := Color.WHITE, fsize := 10) -> void:
	draw_string_outline(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 3, Color(0, 0, 0, 0.8))
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)

func _bar(r: Rect2, frac: float, fill: Color, label: String) -> void:
	draw_rect(r, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), fill)
	draw_rect(r, Color(1, 1, 1, 0.35), false, 1.0)
	var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	_text(r.position + Vector2((r.size.x - w) / 2.0, r.size.y - 2), label, Color.WHITE, 8)

func _draw() -> void:
	if not player:
		return
	var vs := get_viewport_rect().size
	# Bottom bar
	var bar_h := 22.0
	draw_rect(Rect2(0, vs.y - bar_h, vs.x, bar_h), Color(0.08, 0.09, 0.14, 0.85))
	_text(Vector2(8, vs.y - 7), "Lv. %d" % player.level, Color("#ffd84a"), 11)
	var hp_frac := float(player.hp) / player.max_hp
	_bar(Rect2(46, vs.y - 17, 110, 11), hp_frac, Color("#e04848"), "HP %d / %d" % [player.hp, player.max_hp])
	_bar(Rect2(160, vs.y - 17, 100, 11), player.mp / player.max_mp, Color("#4a8be0"), "MP %d / %d" % [int(player.mp), player.max_mp])
	var need := player.xp_to_next()
	_bar(Rect2(264, vs.y - 17, 110, 11), float(player.xp) / need, Color("#e8c34a"),
		"XP %.1f%%" % (100.0 * player.xp / need))
	var spd_col: Color = {"Fast": Color("#7fe39b"), "Normal": Color("#e8f3ff"), "Slow": Color("#ffb347")}.get(player.weapon.speed_label, Color.WHITE)
	_text(Vector2(380, vs.y - 7), player.weapon.name, Color("#e8f3ff"), 9)
	_text(Vector2(380 + _font.get_string_size(player.weapon.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 5, vs.y - 7), player.weapon.speed_label, spd_col, 9)
	if player.weapon.get("thrown", false) and player.imbue_element != "":
		_text(Vector2(vs.x - 96 - _font.get_string_size("Imbued: " + player.imbue_element.capitalize(), HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x, vs.y - 30), "Imbued: %s" % player.imbue_element.capitalize(), Combat.element_color(player.imbue_element), 8)
	_draw_skill_bar(vs)
	if player.auto_battle:
		_text(Vector2(vs.x / 2.0 - 30, 16), "AUTO BATTLE", Color("#ffd84a"), 11)
	# Map name, top left
	_text(Vector2(8, 16), map_name, Color("#e8f3ff"), 11)
	_text(Vector2(8 + _font.get_string_size(map_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 10, 16), "Kills %d" % player.kills, Color("#cfd8e3"), 9)
	# Controls panel: stays on screen, F1 hides or shows it.
	if show_help:
		_draw_help()
	if Log.debug:
		_draw_debug(vs)

func _draw_debug(vs: Vector2) -> void:
	var alive := 0
	for m in world.mobs:
		if m.alive:
			alive += 1
	var lines := [
		"DEBUG",
		"FPS %d" % Engine.get_frames_per_second(),
		"pos %.0f, %.0f" % [player.position.x, player.position.y],
		"vel %.0f, %.0f" % [player.velocity.x, player.velocity.y],
		"on floor %s" % player.is_on_floor(),
		"%s dps %.1f" % [player.weapon.name, player.weapon_dps(player.weapon)],
		"mobs alive %d / %d" % [alive, world.mobs.size()],
		"view %dx%d" % [vs.x, vs.y],
	]
	var y := 16.0
	for l in lines:
		_text(Vector2(vs.x - 120, y), l, Color("#7fe3ff"), 9)
		y += 11.0
	# Hit boxes in world space are drawn by main.gd when debug is on.

## Four spell slots above the bottom bar: key, element color, cooldown sweep, dim when out of MP.
func _draw_skill_bar(vs: Vector2) -> void:
	var size := 18.0
	var gap := 4.0
	var keys: Array = player.spells.keys()
	# Bottom-right, above the bar: the camera keeps the player centered, so the middle stays clear.
	var x0 := vs.x - 6.0 - (keys.size() * (size + gap) - gap)
	var y := vs.y - 22.0 - size - 4.0
	for n in keys.size():
		var id: String = keys[n]
		var sp: Dictionary = player.spells[id]
		var r := Rect2(x0 + n * (size + gap), y, size, size)
		var col := Color(sp.color)
		var usable := player.mp >= float(sp.mp)
		draw_rect(r, Color(0, 0, 0, 0.6))
		draw_rect(r.grow(-3), col if usable else col.darkened(0.6))
		var cd: float = player.spell_cd[id]
		if cd > 0.0:
			var frac := cd / float(sp.cooldown)
			draw_rect(Rect2(r.position, Vector2(size, size * frac)), Color(0, 0, 0, 0.6))
		draw_rect(r, Color(1, 1, 1, 0.4), false, 1.0)
		_text(r.position + Vector2(2, 9), String(sp.key), Color.WHITE, 8)

func _draw_help() -> void:
	var w := 0.0
	for line in HELP_LINES:
		w = maxf(w, _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x)
	var r := Rect2(6, 22, w + 10, HELP_LINES.size() * 11 + 6)
	draw_rect(r, Color(0.05, 0.06, 0.1, 0.45))
	var y := r.position.y + 11
	for line in HELP_LINES:
		_text(Vector2(r.position.x + 5, y), line, Color(1, 1, 1, 0.9), 8)
		y += 11.0
