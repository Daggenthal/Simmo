class_name PauseMenu
extends Control
## Esc pauses everything and opens this menu. Tabs (click, or 1 / 2 / 3):
##   Settings   volume sliders (master, effects, ambient), mute, weather, day / night cycle and
##              time of day, auto-advance, controls panel. Saved to user://settings.cfg.
##   Inventory  your bag; click an item to use it (works while paused)
##   Party      members with class, level and HP and a Kick button; the rest of your Simmo roster
##              with Invite buttons
## Esc closes it and resumes.

const TABS := ["Settings", "Inventory", "Party"]
const W := 420.0
const H := 318.0
const ROW := 16.0
## Window sizes: whole multiples of the 640x360 canvas, so everything stays pixel sharp.
const WINDOW_SIZES := ["auto", "1280x720", "1920x1080", "2560x1440", "3840x2160"]
const FPS_CAPS := [0, 60, 120, 144, 165, 240]

var main: Node
var tab := "Settings"
var settings_path := "user://settings.cfg"
const DEFAULTS := {"master": 0.9, "effects": 0.8, "ambient": 0.6, "mute": false, "weather": true, "day_cycle": true,
	"time": 0.4, "auto_advance": true, "show_help": true,
	"window": "auto", "fullscreen": false, "vsync": false, "fps_cap": 0, "show_fps": false}
var settings := DEFAULTS.duplicate()
var status := ""
var _font: Font
var _drag := ""
var _hover := -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	visible = false

func open() -> void:
	visible = true
	get_tree().paused = true
	status = ""
	Sfx.play("ui_click", 0.6)

func close() -> void:
	visible = false
	get_tree().paused = false
	save_settings()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

# --- settings ---

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(settings_path) == OK:
		for k in settings:
			settings[k] = cf.get_value("settings", k, settings[k])
	apply_settings()

func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings:
		cf.set_value("settings", k, settings[k])
	cf.save(settings_path)

## Push the settings into the game.
## Window size, fullscreen, VSync and frame cap. Gameplay runs on the fixed 60 Hz physics tick
## (with interpolation for smooth drawing), so none of these change how the game plays.
func apply_display() -> void:
	Engine.max_fps = int(settings.fps_cap)
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(settings.vsync) else DisplayServer.VSYNC_DISABLED)
	if bool(settings.fullscreen):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var size := window_size(String(settings.window))
	if DisplayServer.window_get_size() != size:
		DisplayServer.window_set_size(size)
		var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)

## Pixel size for a WINDOW_SIZES entry; "auto" is the biggest that fits the screen.
static func window_size(choice: String) -> Vector2i:
	if choice != "auto":
		var parts := choice.split("x")
		return Vector2i(int(parts[0]), int(parts[1]))
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
	var best := Vector2i(1280, 720)
	for c in WINDOW_SIZES.slice(1):
		var parts: PackedStringArray = String(c).split("x")
		var sz := Vector2i(int(parts[0]), int(parts[1]))
		if sz.x <= usable.x * 0.97 and sz.y <= usable.y * 0.95:
			best = sz
	return best

func apply_settings() -> void:
	# Saved files from older versions miss newer keys: fill them from the defaults.
	for k in DEFAULTS:
		if not settings.has(k):
			settings[k] = DEFAULTS[k]
	apply_display()
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(settings.master), 0.0001)))
	AudioServer.set_bus_mute(0, bool(settings.mute))
	Sfx.sfx_volume = float(settings.effects)
	Sfx.ambient_volume = float(settings.ambient)
	Sfx.muted = bool(settings.mute)
	if main == null:
		return
	if main.weather:
		main.weather.weather_on = bool(settings.weather)
		main.weather.day_cycle = bool(settings.day_cycle)
		if not bool(settings.day_cycle):
			main.weather.time_of_day = float(settings.time)
	if main.player:
		main.player.cfg.auto_advance_zones = bool(settings.auto_advance)
	if main.hud:
		main.hud.show_help = bool(settings.show_help)
		main.hud.show_fps = bool(settings.show_fps)

func set_setting(key: String, value) -> void:
	settings[key] = value
	apply_settings()

## [key, label, kind]: slider (0..1) or toggle.
func setting_rows() -> Array:
	return [
		["master", "Master volume", "slider"],
		["effects", "Effects volume", "slider"],
		["ambient", "Ambient volume (rain, wind)", "slider"],
		["mute", "Mute all sound", "toggle"],
		["weather", "Weather (rain, storms, snow)", "toggle"],
		["day_cycle", "Day / night cycle", "toggle"],
		["time", "Time of day (cycle off)", "slider"],
		["auto_advance", "Auto-battle moves to the next map", "toggle"],
		["show_help", "Show the controls panel", "toggle"],
		["window", "Window size", "choice", WINDOW_SIZES],
		["fullscreen", "Fullscreen", "toggle"],
		["vsync", "VSync (off = uncapped)", "toggle"],
		["fps_cap", "Frame rate cap", "choice", FPS_CAPS],
		["show_fps", "Show FPS", "toggle"],
	]

# --- layout ---

func panel() -> Rect2:
	var vs := get_viewport_rect().size
	return Rect2((vs.x - W) / 2.0, (vs.y - H) / 2.0, W, H)

func tab_rect(n: int) -> Rect2:
	var p := panel()
	return Rect2(p.position.x + 8 + n * 86, p.position.y + 22, 82, 14)

func setting_rect(n: int) -> Rect2:
	var p := panel()
	return Rect2(p.position.x + 12, p.position.y + 44 + n * ROW, W - 24, ROW - 2)

func slider_rect(n: int) -> Rect2:
	var r := setting_rect(n)
	return Rect2(r.position.x + 200, r.position.y + 3, r.size.x - 240, 7)

func inv_slot(k: int) -> Rect2:
	var p := panel()
	return Rect2(p.position.x + 14 + (k % 8) * 24, p.position.y + 50 + (k / 8) * 24, 22, 22)

const EQUIP_SLOTS := ["weapon", "ring", "amulet"]

func equip_rect(n: int) -> Rect2:
	var p := panel()
	return Rect2(p.position.x + 12, p.position.y + 142 + n * 22, W - 24, 20)

func member_rect(n: int) -> Rect2:
	var p := panel()
	return Rect2(p.position.x + 12, p.position.y + 58 + n * 22, W - 24, 20)

func roster_rect(n: int) -> Rect2:
	var p := panel()
	return Rect2(p.position.x + 12, p.position.y + 170 + n * 20, W - 24, 18)

func button_in(r: Rect2) -> Rect2:
	return Rect2(r.end.x - 58, r.position.y + 2, 54, r.size.y - 4)

func roster_free() -> Array:
	var out: Array = []
	for info in main.balance.get("sims", []):
		if not main.in_party(String(info.name)):
			out.append(info)
	return out

# --- input ---

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if main and main.player == null:
			return  # still on the title screens, which handle Esc themselves
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_3:
			tab = TABS[event.keycode - KEY_1]
			get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _drag != "":
			_set_slider(_drag, event.position)
		_hover = -1
		if tab == "Inventory":
			for k in main.player.inventory.slots.size():
				if inv_slot(k).has_point(event.position):
					_hover = k
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			if _drag != "":
				save_settings()
			_drag = ""
			return
		click(event.position)
	accept_event()

## Handle a click at `pos` (also used by tests).
func click(pos: Vector2) -> void:
	for n in TABS.size():
		if tab_rect(n).has_point(pos):
			tab = TABS[n]
			Sfx.play("ui_click", 0.5)
			return
	match tab:
		"Settings":
			var rows := setting_rows()
			for n in rows.size():
				if rows[n][2] == "slider" and slider_rect(n).grow(4).has_point(pos):
					_drag = rows[n][0]
					_set_slider(_drag, pos)
				elif rows[n][2] == "choice" and setting_rect(n).has_point(pos):
					# Right half steps forward, left half back.
					var opts: Array = rows[n][3]
					var step := 1 if pos.x > setting_rect(n).get_center().x else -1
					set_setting(rows[n][0], opts[posmod(opts.find(settings[rows[n][0]]) + step, opts.size())])
					Sfx.play("ui_click", 0.5)
				elif rows[n][2] == "toggle" and setting_rect(n).has_point(pos):
					set_setting(rows[n][0], not bool(settings[rows[n][0]]))
					Sfx.play("ui_click", 0.5)
		"Inventory":
			var inv: Inventory = main.player.inventory
			for k in inv.slots.size():
				if inv_slot(k).has_point(pos) and inv.slots[k] != null:
					var label: String = inv.slots[k].item.name if inv.slots[k].has("item") else inv.def(String(inv.slots[k].id)).get("name", "")
					var r: String = InventoryUI.use_or_equip(main.player, k)
					status = r if r != "" else "%s %s" % ["Equipped" if inv.slots[k] == null or inv.slots[k].has("item") else "Used", label]
					return
			for n in EQUIP_SLOTS.size():
				if equip_rect(n).has_point(pos) and not main.player.equipment[EQUIP_SLOTS[n]].is_empty():
					status = "Unequip: not yet (equip something else to swap)"
		"Party":
			var members: Array = main.sims.duplicate()
			for n in members.size():
				if button_in(member_rect(n)).has_point(pos):
					var nm: String = members[n].display_name
					main.kick(members[n])
					status = "%s left the party" % nm
					return
			var free := roster_free()
			for n in free.size():
				if button_in(roster_rect(n)).has_point(pos):
					var r: String = main.invite(free[n])
					status = r if r != "" else "%s joined the party" % free[n].name
					return

func _set_slider(key: String, pos: Vector2) -> void:
	var rows := setting_rows()
	for n in rows.size():
		if rows[n][0] == key:
			var r := slider_rect(n)
			set_setting(key, clampf((pos.x - r.position.x) / r.size.x, 0.0, 1.0))

# --- drawing ---

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

func _str(pos: Vector2, s: String, col: Color, fsize: int) -> void:
	draw_string_outline(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 3, Color(0, 0, 0, 0.8))
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)

func _button(r: Rect2, label: String, col: Color) -> void:
	draw_rect(r, Color(col, 0.3))
	draw_rect(r, col, false, 1.0)
	var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	_str(r.position + Vector2((r.size.x - w) / 2.0, r.size.y - 4), label, Color.WHITE, 8)

func _draw() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.55))
	var p := panel()
	draw_rect(p, Color(0.06, 0.07, 0.12, 0.96))
	draw_rect(p, Color(1, 1, 1, 0.35), false, 1.0)
	_str(p.position + Vector2(8, 14), "Paused", Color("#ffd84a"), 11)
	_str(p.position + Vector2(W - 120, 14), "Esc: resume   1-3: tabs", Color(0.6, 0.65, 0.75), 7)
	for n in TABS.size():
		var r := tab_rect(n)
		var on: bool = TABS[n] == tab
		draw_rect(r, Color(1, 1, 1, 0.2 if on else 0.06))
		_str(r.position + Vector2(6, 10), "%d  %s" % [n + 1, TABS[n]], Color.WHITE if on else Color(0.7, 0.7, 0.7), 8)
	match tab:
		"Settings":
			_draw_settings()
		"Inventory":
			_draw_inventory()
		"Party":
			_draw_party()
	if status != "":
		_str(p.position + Vector2(10, H - 8), status, Color("#bfe6ff"), 8)

func _draw_settings() -> void:
	var rows := setting_rows()
	for n in rows.size():
		var r := setting_rect(n)
		var key: String = rows[n][0]
		_str(r.position + Vector2(2, 11), rows[n][1], Color(0.88, 0.9, 0.95), 8)
		if rows[n][2] == "slider":
			var s := slider_rect(n)
			var v := float(settings[key])
			var dim: bool = key == "time" and bool(settings.day_cycle)
			draw_rect(s, Color(1, 1, 1, 0.12))
			draw_rect(Rect2(s.position, Vector2(s.size.x * v, s.size.y)), Color("#4a8be0") if not dim else Color(0.4, 0.4, 0.4))
			draw_rect(Rect2(s.position.x + s.size.x * v - 2, s.position.y - 2, 4, s.size.y + 4), Color.WHITE)
			var label := "%d%%" % int(round(v * 100.0)) if key != "time" else _time_label(v)
			_str(Vector2(s.end.x + 6, s.position.y + 8), label, Color(0.8, 0.85, 0.9), 7)
		elif rows[n][2] == "choice":
			var v = settings[key]
			var label := str(v)
			if key == "fps_cap":
				label = "Uncapped" if int(v) == 0 else "%d FPS" % int(v)
			elif key == "window" and String(v) == "auto":
				var a := window_size("auto")
				label = "Fit screen (%dx%d)" % [a.x, a.y]
			var cr := Rect2(r.end.x - 150, r.position.y + 1, 146, r.size.y - 2)
			draw_rect(cr, Color(1, 1, 1, 0.08))
			_str(cr.position + Vector2(4, 10), "<", Color.WHITE, 8)
			_str(cr.position + Vector2(cr.size.x - 10, 10), ">", Color.WHITE, 8)
			var lw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			_str(cr.position + Vector2((cr.size.x - lw) / 2.0, 10), label, Color.WHITE, 8)
		else:
			var on := bool(settings[key])
			var b := Rect2(r.end.x - 36, r.position.y + 2, 32, 12)
			draw_rect(b, Color("#3a7a4a") if on else Color(0.3, 0.3, 0.35))
			_str(b.position + Vector2(6, 9), "ON" if on else "OFF", Color.WHITE, 7)

func _time_label(v: float) -> String:
	var hours := int(v * 24.0)
	var mins := int(fmod(v * 24.0, 1.0) * 60.0)
	return "%02d:%02d" % [hours, mins]

func _draw_inventory() -> void:
	var inv: Inventory = main.player.inventory
	var p := panel()
	_str(p.position + Vector2(14, 46), "Click: use a potion, equip gear", Color(0.7, 0.75, 0.85), 7)
	for k in inv.slots.size():
		var r := inv_slot(k)
		draw_rect(r, Color(1, 1, 1, 0.14 if k == _hover else 0.06))
		draw_rect(r, Color(1, 1, 1, 0.2), false, 1.0)
		var s = inv.slots[k]
		if s == null:
			continue
		if s.has("item"):
			InventoryUI.draw_item(self, r.grow(-2), s.item)
		else:
			InventoryUI.draw_icon(self, r.grow(-4), inv.def(String(s.id)))
		_str(r.end - Vector2(_font.get_string_size(str(s.count), HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x + 1, 1), str(s.count), Color.WHITE, 7)
	# Stats summary on the right.
	var pl: Actor = main.player
	var x := p.position.x + 220
	var y := p.position.y + 58
	_str(Vector2(x, y), "%s  Lv %d %s" % [pl.display_name, pl.level, pl.class_name_label()], Color("#ffd84a"), 9)
	y += 14
	for k in Actor.STATS:
		_str(Vector2(x, y), "%s %d" % [k.to_upper(), pl.stats[k]], Color.WHITE, 8)
		y += 11
	_str(Vector2(x, y + 4), "HP %d / %d   MP %d / %d" % [pl.hp, pl.max_hp, int(pl.mp), pl.max_mp], Color(0.85, 0.85, 0.9), 8)
	# Worn gear
	_str(Vector2(p.position.x + 14, p.position.y + 136), "Equipped", Color("#ffd84a"), 8)
	for n in EQUIP_SLOTS.size():
		var er := equip_rect(n)
		var it: Dictionary = pl.equipment[EQUIP_SLOTS[n]]
		draw_rect(er, Color(1, 1, 1, 0.06))
		if it.is_empty():
			_str(er.position + Vector2(4, 13), "%s: none" % EQUIP_SLOTS[n].capitalize(), Color(0.55, 0.6, 0.7), 8)
		else:
			InventoryUI.draw_item(self, Rect2(er.position + Vector2(2, 2), Vector2(16, 16)), it)
			_str(er.position + Vector2(22, 13), "%s  %s" % [it.name, ", ".join(it.lines)], Color(it.color), 7)
	if _hover >= 0 and inv.slots[_hover] != null:
		var tip := ""
		var tcol := Color.WHITE
		if inv.slots[_hover].has("item"):
			var it: Dictionary = inv.slots[_hover].item
			tip = "[%s] %s  %s" % [Gear.rarity_name(String(it.rarity)), it.name, ", ".join(it.lines)]
			tcol = Color(it.color)
		else:
			var d: Dictionary = inv.def(String(inv.slots[_hover].id))
			tip = "%s: %s" % [d.get("name", ""), d.get("desc", "")]
			tcol = Color(d.get("color", "#ffffff"))
		_str(Vector2(p.position.x + 14, p.position.y + 128), tip, tcol, 8)

func _draw_party() -> void:
	var p := panel()
	var sims: Array = main.sims
	_str(p.position + Vector2(14, 52), "Party (%d / %d)" % [sims.size() + 1, int(main.balance.party.get("max_size", 4))], Color("#ffd84a"), 9)
	for n in sims.size():
		var s: Actor = sims[n]
		var r := member_rect(n)
		draw_rect(r, Color(1, 1, 1, 0.05))
		_str(r.position + Vector2(4, 13), "%s   Lv %d %s (%s)" % [s.display_name, s.level, s.class_name_label(), s.role], s.tag_color, 8)
		var hb := Rect2(r.position.x + 200, r.position.y + 7, 90, 5)
		draw_rect(hb, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(hb.position, Vector2(hb.size.x * clampf(float(s.hp) / s.max_hp, 0.0, 1.0), hb.size.y)), Color("#e04848"))
		_button(button_in(r), "Kick", Color("#e0645a"))
	_str(p.position + Vector2(14, 164), "Your Simmo roster", Color("#ffd84a"), 9)
	var free := roster_free()
	if free.is_empty():
		_str(p.position + Vector2(14, 182), "Everyone you know is in your party", Color(0.6, 0.65, 0.75), 8)
	var full: bool = sims.size() + 1 >= int(main.balance.party.get("max_size", 4))
	for n in free.size():
		var r := roster_rect(n)
		var role: String = String(free[n].role)
		_str(r.position + Vector2(4, 12), "%s   %s" % [free[n].name, main.balance.sim_roles.get(role, {}).get("label", role)], Color(0.85, 0.87, 0.92), 8)
		_button(button_in(r), "Invite", Color(0.5, 0.5, 0.5) if full else Color("#7fe39b"))
