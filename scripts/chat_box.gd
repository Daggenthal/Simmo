class_name ChatBox
extends Control
## Chat box, bottom left above the status bar. Tabs: All (no damage spam), Chat (local + party),
## Combat (your damage, kills, XP). Click a tab, or press Y to cycle. Lines are colored by channel.

const TABS := {
	"All": ["local", "party", "system", "xp", "loot", "trade", "warning"],
	"Chat": ["local", "party"],
	"Combat": ["combat", "xp"],
}
const W := 250.0
const ROWS := 6
const ROW_H := 10.0

var tab := "All"
var _font: Font
var _seen := -1

func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP

func _process(_delta: float) -> void:
	var vs := get_viewport_rect().size
	size = Vector2(W, 14 + ROWS * ROW_H + 4)
	# Bottom edge above the heads of anyone standing on the ground (ground sits 50 px up),
	# so the party isn't hidden at the left edge of a map where portals drop you.
	position = Vector2(4, vs.y - 80 - size.y)
	if ChatLog.version != _seen:
		_seen = ChatLog.version
		queue_redraw()

func tab_rect(n: int) -> Rect2:
	return Rect2(4 + n * 44, 2, 42, 11)

func cycle_tab() -> void:
	var names := TABS.keys()
	tab = names[(names.find(tab) + 1) % names.size()]
	queue_redraw()

## The lines the current tab shows, newest last.
func visible_lines() -> Array:
	var allowed: Array = TABS[tab]
	var out: Array = []
	for k in range(ChatLog.lines.size() - 1, -1, -1):
		var l: Dictionary = ChatLog.lines[k]
		if l.channel in allowed:
			out.push_front(l)
			if out.size() >= ROWS:
				break
	return out

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var names := TABS.keys()
		for n in names.size():
			if tab_rect(n).has_point(event.position):
				tab = names[n]
				queue_redraw()
				accept_event()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.08, 0.55))
	var names := TABS.keys()
	for n in names.size():
		var r := tab_rect(n)
		var on: bool = names[n] == tab
		draw_rect(r, Color(1, 1, 1, 0.22 if on else 0.07))
		_str(r.position + Vector2(4, 8), names[n], Color.WHITE if on else Color(0.7, 0.7, 0.7), 7)
	_str(Vector2(W - 34, 10), "Y: tab", Color(0.55, 0.6, 0.7), 6)
	var y := 14.0 + ROW_H - 2
	for l in visible_lines():
		var s: String = l.text
		while s.length() > 4 and _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x > W - 8:
			s = s.substr(0, s.length() - 2)
		var lc: Color = l.get("color", Color(0, 0, 0, 0))
		_str(Vector2(4, y), s, lc if lc.a > 0.0 else ChatLog.color(l.channel), 7)
		y += ROW_H

func _str(pos: Vector2, s: String, col: Color, fsize: int) -> void:
	draw_string_outline(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 3, Color(0, 0, 0, 0.85))
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
