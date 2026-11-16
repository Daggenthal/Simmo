extends Control
## MapleStory-style bottom status bar plus the debug overlay (F3).
## Anchored to the screen edges, so wider screens just get more world.

var player: Player
var world: World
var map_name := "Mossy Meadow"
var _hint_time := 8.0
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
	_bar(Rect2(52, vs.y - 17, 150, 11), hp_frac, Color("#e04848"), "HP %d / %d" % [player.hp, player.max_hp])
	var need := player.xp_to_next()
	_bar(Rect2(210, vs.y - 17, 150, 11), float(player.xp) / need, Color("#e8c34a"),
		"XP %d / %d  (%.1f%%)" % [player.xp, need, 100.0 * player.xp / need])
	_text(Vector2(vs.x - 110, vs.y - 7), "Kills %d" % player.kills, Color("#cfd8e3"), 9)
	var spd_col: Color = {"Fast": Color("#7fe39b"), "Normal": Color("#e8f3ff"), "Slow": Color("#ffb347")}.get(player.weapon.speed_label, Color.WHITE)
	_text(Vector2(368, vs.y - 7), "%s" % player.weapon.name, Color("#e8f3ff"), 9)
	_text(Vector2(368 + _font.get_string_size(player.weapon.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 6, vs.y - 7), player.weapon.speed_label, spd_col, 9)
	if player.auto_battle:
		_text(Vector2(vs.x / 2.0 - 30, 16), "AUTO BATTLE", Color("#ffd84a"), 11)
	# Map name, top left
	_text(Vector2(8, 16), map_name, Color("#e8f3ff"), 11)
	# Controls hint fades out
	if _hint_time > 0.0:
		var a := clampf(_hint_time / 2.0, 0.0, 1.0)
		_text(Vector2(8, 32), "Move: Arrows / WASD   Jump: Alt / Space   Attack: Ctrl / J", Color(1, 1, 1, a), 9)
		_text(Vector2(8, 44), "Drop down: Down + Jump   Auto: Q / Tab   Weapons: 1 2 3 / E   Debug: F3", Color(1, 1, 1, a), 9)
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
