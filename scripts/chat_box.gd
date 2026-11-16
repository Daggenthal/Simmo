class_name ChatBox
extends Control
## Chat box, bottom left above the status bar. Tabs: All (no damage spam), Chat (local + party),
## Combat (your damage, kills, XP). Click a tab, or press Y to cycle. Lines are colored by channel.
## Resize: drag the grip in the top-right corner (wider / taller). The - button minimizes it to
## its tabs. Scroll: mouse wheel or Page Up / Page Down over the box; while scrolled up new lines
## don't move the view, and a "new messages" marker jumps back to the bottom.
## Size and minimized state are saved with the settings (pause menu).

signal layout_changed

const TABS := {
	"All": ["local", "party", "system", "xp", "loot", "trade", "warning"],
	"Chat": ["local", "party"],
	"Combat": ["combat", "xp"],
}
const ROW_H := 10.0
const MIN_W := 160.0
const MAX_W := 420.0
const MIN_ROWS := 3
const MAX_ROWS := 18
const HEADER := 14.0

var tab := "All"
var box_w := 250.0
var rows := 6
var minimized := false
## Lines scrolled up from the newest (0 = following the newest line).
var scroll := 0
var _font: Font
var _seen := -1
var _resizing := false
var _drag_from := Vector2.ZERO
var _size_from := Vector2.ZERO
var _unread := 0
var _last_total := 0

func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP

func box_size() -> Vector2:
	return Vector2(box_w, HEADER + (0.0 if minimized else rows * ROW_H + 4.0))

func _process(_delta: float) -> void:
	var vs := get_viewport_rect().size
	size = box_size()
	# Bottom edge above the heads of anyone standing on the ground (ground sits 50 px up),
	# so the party isn't hidden at the left edge of a map where portals drop you.
	position = Vector2(4, vs.y - 80 - size.y)
	if ChatLog.version != _seen:
		_seen = ChatLog.version
		var total := matching().size()
		var added := maxi(total - _last_total, 0)
		_last_total = total
		if scroll > 0:
			# Reading older lines: keep the view where it is.
			scroll = mini(scroll + added, max_scroll())
			_unread += added
		queue_redraw()

func tab_rect(n: int) -> Rect2:
	return Rect2(4 + n * 44, 2, 42, 11)

func grip_rect() -> Rect2:
	return Rect2(box_w - 12, 0, 12, 12)

func min_rect() -> Rect2:
	return Rect2(box_w - 26, 1, 12, 11)

func new_rect() -> Rect2:
	return Rect2(box_w - 90, box_size().y - 12, 72, 11)

func _reset_view() -> void:
	scroll = 0
	_unread = 0
	_last_total = matching().size()
	queue_redraw()

func cycle_tab() -> void:
	var names := TABS.keys()
	tab = names[(names.find(tab) + 1) % names.size()]
	_reset_view()

## All lines the current tab shows, oldest first.
func matching() -> Array:
	var allowed: Array = TABS[tab]
	return ChatLog.lines.filter(func(l): return l.channel in allowed)

## The lines on screen, newest last, after scrolling.
func visible_lines() -> Array:
	var all := matching()
	var end := all.size() - scroll
	return all.slice(maxi(end - rows, 0), maxi(end, 0))

func max_scroll() -> int:
	return maxi(matching().size() - rows, 0)

func scroll_by(n: int) -> void:
	scroll = clampi(scroll + n, 0, max_scroll())
	if scroll == 0:
		_unread = 0
	queue_redraw()

func set_layout(w: float, r: int, mini: bool) -> void:
	box_w = clampf(w, MIN_W, MAX_W)
	rows = clampi(r, MIN_ROWS, MAX_ROWS)
	minimized = mini
	queue_redraw()

## Begin a resize from the grip, then drag_resize() with the mouse movement so far.
func start_resize() -> void:
	_resizing = true
	_size_from = Vector2(box_w, rows)

## Right = wider, up = taller (it grows upward from its bottom edge).
func drag_resize(d: Vector2) -> void:
	box_w = clampf(_size_from.x + d.x, MIN_W, MAX_W)
	rows = clampi(int(round(_size_from.y - d.y / ROW_H)), MIN_ROWS, MAX_ROWS)
	scroll = clampi(scroll, 0, max_scroll())
	queue_redraw()

func end_resize() -> void:
	if _resizing:
		_resizing = false
		layout_changed.emit()

func toggle_minimized() -> void:
	minimized = not minimized
	layout_changed.emit()
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		scroll_by(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if grip_rect().has_point(event.position) and not minimized:
				start_resize()
				_drag_from = get_global_mouse_position()
			elif min_rect().has_point(event.position):
				toggle_minimized()
			elif _unread > 0 and scroll > 0 and new_rect().has_point(event.position):
				_reset_view()
			else:
				var names := TABS.keys()
				for n in names.size():
					if tab_rect(n).has_point(event.position):
						tab = names[n]
						_reset_view()
		else:
			end_resize()
		accept_event()
	elif event is InputEventMouseMotion and _resizing:
		drag_resize(get_global_mouse_position() - _drag_from)
		accept_event()

func _input(event: InputEvent) -> void:
	# Page Up / Page Down scroll the chat while the mouse is over it.
	if event is InputEventKey and event.pressed and visible and not minimized and get_global_rect().has_point(get_global_mouse_position()):
		if event.keycode == KEY_PAGEUP:
			scroll_by(rows - 1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_PAGEDOWN:
			scroll_by(-(rows - 1))
			get_viewport().set_input_as_handled()

func _draw() -> void:
	var sz := box_size()
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.03, 0.04, 0.08, 0.55))
	var names := TABS.keys()
	for n in names.size():
		var r := tab_rect(n)
		var on: bool = names[n] == tab
		draw_rect(r, Color(1, 1, 1, 0.22 if on else 0.07))
		_str(r.position + Vector2(4, 8), names[n], Color.WHITE if on else Color(0.7, 0.7, 0.7), 7)
	var mr := min_rect()
	draw_rect(mr, Color(1, 1, 1, 0.1))
	_str(mr.position + Vector2(3, 8), "+" if minimized else "-", Color.WHITE, 8)
	if minimized:
		return
	var g := grip_rect()
	for k in 3:
		draw_line(g.position + Vector2(4 + k * 3, 2), g.position + Vector2(10, 8 - k * 3), Color(1, 1, 1, 0.5), 1.0)
	var y := HEADER + ROW_H - 2
	for l in visible_lines():
		var s: String = l.text
		while s.length() > 4 and _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x > box_w - 12:
			s = s.substr(0, s.length() - 2)
		var lc: Color = l.get("color", Color(0, 0, 0, 0))
		_str(Vector2(4, y), s, lc if lc.a > 0.0 else ChatLog.color(l.channel), 7)
		y += ROW_H
	# Scrollbar: where this view sits in the whole history.
	var total := matching().size()
	if total > rows:
		var track := Rect2(box_w - 4, HEADER + 1, 3, rows * ROW_H)
		draw_rect(track, Color(1, 1, 1, 0.08))
		var pos := 1.0 - float(scroll + rows) / total
		draw_rect(Rect2(track.position.x, track.position.y + track.size.y * pos, 3, maxf(track.size.y * float(rows) / total, 4.0)), Color(1, 1, 1, 0.45))
	if _unread > 0 and scroll > 0:
		var nr := new_rect()
		draw_rect(nr, Color(0.2, 0.4, 0.7, 0.85))
		_str(nr.position + Vector2(3, 8), "v %d new" % _unread, Color.WHITE, 7)

func _str(pos: Vector2, s: String, col: Color, fsize: int) -> void:
	draw_string_outline(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 3, Color(0, 0, 0, 0.85))
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
