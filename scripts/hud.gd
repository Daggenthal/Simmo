extends Control
## MapleStory-style bottom status bar plus the debug overlay (F3).
## Anchored to the screen edges, so wider screens just get more world.

var player: Player
var world: World
var _hint_time := 8.0
## Shown for a few seconds after entering a map that's above the player's level.
var warning_text := ""
var warning_danger := ""
var _warning_t := 0.0
var show_help := true
const HELP_LINES := [
	"Move: Arrows / WASD    Jump: Alt / Space    Attack: Ctrl / J",
	"Drop down: Down + Jump    Auto-battle: Q / Tab    Weapons: 1-2 or E",
	"Skills: Z X C V    Ultimate: G    Stats: K",
	"Portal: stand on it + Up    Party on/off: P",
	"Inventory: I    HP potion: R    MP potion: F    Trade: T    Chat tab: Y",
	"Respawn mobs: F5    Debug: F3    Hide this: F1",
]
const SLOT_KEYS := ["Z", "X", "C", "V"]
var _font: Font
var _auto_btn: Button

var _flash_col := Color.TRANSPARENT
var _flash_t := 0.0
var _flash_len := 1.0

## Full-screen flash that fades out (ultimates).
func flash(col: Color, duration: float) -> void:
	_flash_col = col
	_flash_t = duration
	_flash_len = duration

func _ready() -> void:
	add_to_group("hud")
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

## Called by main when the map changes (after the party has arrived).
func on_map_entered() -> void:
	warning_text = ""
	warning_danger = world.danger(world.map_id, player.level)
	if warning_danger == "":
		return
	# Gap to the map's weakest mobs; the banner color still shows hard (orange) vs deadly (red).
	warning_text = warning_for(int(world.map.levels[0]) - player.level)
	_warning_t = float(world._balance.get("map_warning", {}).get("banner_time", 6.0))
	ChatLog.add("warning", warning_text)

## "Warning! Mobs here are N level(s) above you", singular for one level.
func warning_for(gap: int) -> String:
	return "Warning! Mobs here are %d %s above you" % [gap, "level" if gap == 1 else "levels"]

func _process(delta: float) -> void:
	_hint_time = max(_hint_time - delta, 0.0)
	_warning_t = maxf(_warning_t - delta, 0.0)
	_flash_t = maxf(_flash_t - delta, 0.0)
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
	if player.ap > 0:
		_text(Vector2(8, vs.y - 26), "AP %d: press K" % player.ap, Color("#ffd84a"), 8)
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
	_draw_quick_slots(vs)
	_draw_buffs(vs)
	if player.auto_battle:
		var auto_label := "AUTO BATTLE" if player.advancing_to == "" else "AUTO: heading to %s" % player.advancing_to
		var aw := _font.get_string_size(auto_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		# With a boss bar up top, the auto label moves below it.
		var boss_up: bool = world != null and world.boss != null and is_instance_valid(world.boss) and world.boss.alive
		_text(Vector2((vs.x - aw) / 2.0, 62 if boss_up else 16), auto_label, Color("#ffd84a"), 11 if not boss_up else 9)
	# Map name and level range, top left
	var map_name: String = world.map.get("name", "") if world else ""
	var x := 8 + _font.get_string_size(map_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 8
	_text(Vector2(8, 16), map_name, Color("#e8f3ff"), 11)
	var lv := world.level_label() if world else ""
	_text(Vector2(x, 16), lv, Color("#ffd84a"), 9)
	x += _font.get_string_size(lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 8
	_text(Vector2(x, 16), "Kills %d" % player.kills, Color("#cfd8e3"), 9)
	_draw_portal_hint(vs)
	_draw_warning(vs)
	_draw_boss_bar(vs)
	var party_bottom := _draw_party(vs)
	# Controls panel: stays on screen, F1 hides or shows it.
	if show_help:
		_draw_help()
	if Log.debug:
		_draw_debug(vs, party_bottom)
	if _flash_t > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(_flash_col, 0.7 * _flash_t / _flash_len))

## Standing on a portal: say where it goes, just above the bottom bar.
func _draw_portal_hint(vs: Vector2) -> void:
	if world == null:
		return
	var p := world.portal_at(player.global_position)
	if p.is_empty():
		return
	var dest: Dictionary = world.maps.get(String(p.to), {})
	var lv: Array = dest.get("levels", [])
	var msg := "Up: Enter %s%s" % [dest.get("name", p.to), (" (Lv %d-%d)" % [lv[0], lv[1]]) if lv.size() == 2 else ""]
	var d := world.danger(String(p.to), player.level)
	match d:
		"deadly":
			msg += "  Far too strong for you!"
		"hard":
			msg += "  Stronger than you"
	var w := _font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	_text(Vector2((vs.x - w) / 2.0, vs.y - 30), msg, Color("#bfe6ff") if d == "" else World.danger_color(d), 10)

## Boss HP bar across the top with the enrage countdown (red and pulsing when close, then ENRAGED).
func _draw_boss_bar(vs: Vector2) -> void:
	if world == null or world.boss == null or not is_instance_valid(world.boss) or not world.boss.alive:
		return
	var b: Mob = world.boss
	var w := minf(320.0, vs.x - 260.0)
	var r := Rect2((vs.x - w) / 2.0, 26, w, 9)
	var name := "Lv.%d %s" % [b.level, b.data.name]
	var nw := _font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	_text(Vector2((vs.x - nw) / 2.0, 23), name, Color("#ff9a7a") if not b.enraged else Color("#ff4a3a"), 10)
	draw_rect(r.grow(1), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(float(b.hp) / b.max_hp, 0.0, 1.0), r.size.y)), Color("#c0392b") if not b.enraged else Color("#ff2a1a"))
	draw_rect(r, Color(1, 1, 1, 0.4), false, 1.0)
	var hp_label := "%d / %d" % [maxi(b.hp, 0), b.max_hp]
	var hw := _font.get_string_size(hp_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
	_text(Vector2((vs.x - hw) / 2.0, r.position.y + 8), hp_label, Color.WHITE, 7)
	var left := b.enrage_left()
	var t := "ENRAGED!" if b.enraged else "Enrage in %d:%02d" % [int(left) / 60, int(left) % 60]
	var urgent: bool = b.enraged or left < 15.0
	var col := Color("#ffd84a") if not urgent else Color(1.0, 0.3, 0.25, 0.6 + 0.4 * sin(Time.get_ticks_msec() / 120.0))
	# Under the bar, centered (the party frames own the top right).
	var tw := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	_text(Vector2((vs.x - tw) / 2.0, r.end.y + 11), t, col, 9)

## Banner under the top edge after entering a map that's above the player's level.
func _draw_warning(vs: Vector2) -> void:
	if _warning_t <= 0.0 or warning_text == "":
		return
	var w := _font.get_string_size(warning_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	# Below the controls panel while it's open (it spans most of the top on narrow screens).
	var y := 22.0 + (HELP_LINES.size() * 11.0 + 10.0 if show_help else 0.0)
	var r := Rect2((vs.x - w) / 2.0 - 8, y, w + 16, 16)
	var a := clampf(_warning_t, 0.0, 1.0)  # fades out over the last second
	draw_rect(r, Color(0.15, 0.02, 0.02, 0.7 * a))
	draw_rect(r, Color(World.danger_color(warning_danger), a), false, 1.0)
	_text(Vector2(r.position.x + 8, r.position.y + 12), warning_text, Color(World.danger_color(warning_danger), a), 10)

## Party frames, top right: name, level, role color, HP bar. Returns the y below them.
func _draw_party(vs: Vector2) -> float:
	var y := 8.0
	if world == null:
		return y
	for m in world.party:
		if m == player or not is_instance_valid(m):
			continue
		var x := vs.x - 108.0
		var down: bool = not m.is_alive()
		var label := "%s Lv.%d" % [m.display_name, m.level]
		_text(Vector2(x, y + 8), label, Color(0.6, 0.6, 0.6) if down else m.tag_color, 8)
		var r := Rect2(x, y + 11, 100, 4)
		draw_rect(r, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(float(m.hp) / m.max_hp, 0.0, 1.0), r.size.y)), Color("#e04848"))
		if down:
			_text(Vector2(x + 70, y + 8), "KO", Color("#ff6b6b"), 8)
		y += 19.0
	return y

func _draw_debug(vs: Vector2, y0 := 16.0) -> void:
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
	var y := maxf(y0 + 8.0, 16.0)
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
		_text(r.position + Vector2(2, 9), SLOT_KEYS[n] if n < SLOT_KEYS.size() else "", Color.WHITE, 8)
		_draw_cd_text(r, cd)
	_draw_ult_slot(Vector2(x0, y))

## Seconds left on a cooldown, centered low in the slot: "12", then "0.8" under a second.
static func cd_label(cd: float) -> String:
	if cd <= 0.0:
		return ""
	return "%.1f" % cd if cd < 1.0 else str(int(ceil(cd)))

func _draw_cd_text(r: Rect2, cd: float) -> void:
	var s := cd_label(cd)
	if s == "":
		return
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	_text(Vector2(r.get_center().x - w / 2.0, r.end.y - 2), s, Color("#ffe9a8"), 8)

## Ultimate slot (G / Shift): bigger, glowing when ready, left of the potion slots.
func ult_slot_rect(vs: Vector2) -> Rect2:
	var size := 22.0
	var x0 := vs.x - 6.0 - (player.spells.size() * 22.0 - 4.0) - 2 * 22.0 - 6.0 - size - 6.0
	return Rect2(x0, vs.y - 22.0 - size - 2.0, size, size)

func _draw_ult_slot(_skills_pos: Vector2) -> void:
	if player.ult.is_empty():
		return
	var vs := get_viewport_rect().size
	var r := ult_slot_rect(vs)
	var col := Color(player.ult.color)
	var ready: bool = player.ult_cd <= 0.0
	if ready:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 200.0)
		draw_rect(r.grow(2), Color(col, 0.35 + 0.35 * pulse))
	draw_rect(r, Color(0, 0, 0, 0.7))
	draw_rect(r.grow(-3), col if player.mp >= float(player.ult.get("mp", 0)) else col.darkened(0.6))
	draw_colored_polygon(PackedVector2Array([r.get_center() + Vector2(0, -6), r.get_center() + Vector2(5, 0), r.get_center() + Vector2(0, 6), r.get_center() + Vector2(-5, 0)]), Color(1, 1, 1, 0.85))
	if not ready:
		draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * player.ult_cd / float(player.ult.cooldown))), Color(0, 0, 0, 0.65))
	draw_rect(r, Color(1, 1, 1, 0.5), false, 1.0)
	_text(r.position + Vector2(2, 9), "G", Color.WHITE, 8)
	_draw_cd_text(r, player.ult_cd)

## HP and MP potion quick slots (R / F), left of the skill bar: best potion's icon and total count.
func _draw_quick_slots(vs: Vector2) -> void:
	if player.inventory == null:
		return
	var size := 18.0
	var x := vs.x - 6.0 - (player.spells.size() * 22.0 - 4.0) - 2 * (size + 4.0) - 6.0
	var y := vs.y - 22.0 - size - 4.0
	var k := 0
	for pair in [["heal_hp", "R"], ["heal_mp", "F"]]:
		var r := Rect2(x + k * (size + 4.0), y, size, size)
		draw_rect(r, Color(0, 0, 0, 0.6))
		var id: String = player.best_item(pair[0])
		var total := 0
		for iid in player.inventory.defs:
			if String(player.inventory.defs[iid].get("effect", "")) == pair[0]:
				total += player.inventory.count(iid)
		if id != "":
			InventoryUI.draw_icon(self, r.grow(-4), player.inventory.def(id))
		draw_rect(r, Color(1, 1, 1, 0.4), false, 1.0)
		_text(r.position + Vector2(2, 9), pair[1], Color.WHITE, 8)
		var c := str(total)
		_text(r.position + Vector2(size - 1 - _font.get_string_size(c, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x, size - 1), c, Color.WHITE if total > 0 else Color("#ff6b6b"), 7)
		k += 1

## Active buffs, bottom left above the bar: name, bonus and time left.
func _draw_buffs(vs: Vector2) -> void:
	var y := vs.y - 28.0
	for b in player.buffs.values():
		var t := int(ceil(float(b.t)))
		var bonus: String = b.get("label", "XP +%d%%" % int(round((float(b.get("mult", 1.0)) - 1.0) * 100.0)))
		var label := "%s  %s  %d:%02d" % [b.name, bonus, t / 60, t % 60]
		draw_rect(Rect2(6, y - 8, 6, 6), Color(b.color))
		_text(Vector2(15, y - 1), label, Color(b.color), 8)
		y -= 11.0

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
