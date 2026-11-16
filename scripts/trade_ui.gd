class_name TradeUI
extends Control
## Trade window (T): your bag on the left, a party member's bag on the right, both offers in the middle.
## Click your items to offer them, their items to ask for them, an offer line to take one back.
## < / > switch partner. The sim answers in party chat (Trade.sim_verdict decides).

const SLOT := 15.0
const COLS := 6
const W := 404.0
const H := 150.0

var player: Actor
var main: Node
var trade_cfg: Dictionary = {}
var chat: Dictionary = {}
var partner_idx := 0
var my_offer: Dictionary = {}
var their_offer: Dictionary = {}
var status := ""
var _font: Font

func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func partners() -> Array:
	var out: Array = []
	for s in main.sims:
		if is_instance_valid(s) and s.is_inside_tree():
			out.append(s)
	return out

func partner() -> Actor:
	var p := partners()
	if p.is_empty():
		return null
	partner_idx = posmod(partner_idx, p.size())
	return p[partner_idx]

func open() -> void:
	visible = true
	my_offer.clear()
	their_offer.clear()
	status = "Click items to offer or ask for them" if partner() else "No one in your party to trade with"

func _process(_delta: float) -> void:
	if not visible:
		return
	var vs := get_viewport_rect().size
	size = Vector2(W, H)
	position = Vector2((vs.x - W) / 2.0, 52)
	queue_redraw()

func my_grid() -> Vector2:
	return Vector2(6, 30)

func their_grid() -> Vector2:
	return Vector2(W - 6 - COLS * SLOT, 30)

func slot_rect(origin: Vector2, k: int) -> Rect2:
	return Rect2(origin + Vector2((k % COLS) * SLOT, (k / COLS) * SLOT), Vector2(SLOT - 1, SLOT - 1))

func trade_button() -> Rect2:
	return Rect2(W / 2.0 - 64, H - 34, 60, 14)

func clear_button() -> Rect2:
	return Rect2(W / 2.0 + 4, H - 34, 60, 14)

func prev_button() -> Rect2:
	return Rect2(W - 52, 3, 14, 12)

func next_button() -> Rect2:
	return Rect2(W - 34, 3, 14, 12)

func offer_rect(row: int, mine: bool) -> Rect2:
	return Rect2(108, (36 if mine else 82) + row * 10, W - 216, 10)

## Add one of the item in slot k of `inv` to `offer` (capped at what's there).
func _add_to(offer: Dictionary, inv: Inventory, k: int) -> void:
	var s = inv.slots[k]
	if s == null:
		return
	if s.has("item"):
		status = "Gear can't be traded yet"
		return
	var id := String(s.id)
	if int(offer.get(id, 0)) < inv.count(id):
		offer[id] = int(offer.get(id, 0)) + 1

func _take_back(offer: Dictionary, row: int) -> void:
	var keys := offer.keys()
	if row < keys.size():
		var id = keys[row]
		offer[id] = int(offer[id]) - 1
		if offer[id] <= 0:
			offer.erase(id)

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	accept_event()
	var p := partner()
	var pos: Vector2 = event.position
	if prev_button().has_point(pos):
		partner_idx -= 1
		open()
		return
	if next_button().has_point(pos):
		partner_idx += 1
		open()
		return
	if p == null:
		return
	for k in player.inventory.slots.size():
		if slot_rect(my_grid(), k).has_point(pos):
			_add_to(my_offer, player.inventory, k)
	for k in p.inventory.slots.size():
		if slot_rect(their_grid(), k).has_point(pos):
			_add_to(their_offer, p.inventory, k)
	for row in 4:
		if offer_rect(row, true).has_point(pos):
			_take_back(my_offer, row)
		if offer_rect(row, false).has_point(pos):
			_take_back(their_offer, row)
	if clear_button().has_point(pos):
		my_offer.clear()
		their_offer.clear()
	if trade_button().has_point(pos):
		propose()

## Offer the current trade to the partner. Returns "" when it went through.
func propose() -> String:
	var p := partner()
	if p == null:
		return "no partner"
	var verdict := Trade.sim_verdict(p.inventory, their_offer, my_offer, trade_cfg)
	if verdict == "empty":
		status = "Put something on the table first"
		return verdict
	if verdict != "":
		_say(p, "trade_no")
		status = "%s said no (%s)" % [p.display_name, "they need their potions" if verdict == "needs" else "not a fair deal for them"]
		return verdict
	var gift := their_offer.is_empty()
	var gave := Trade.describe(player.inventory, my_offer)
	var got := Trade.describe(player.inventory, their_offer)
	var r := Trade.execute(player.inventory, p.inventory, my_offer, their_offer)
	if r != "":
		status = "Trade failed: %s" % ("a bag is full" if r == "full" else "items missing")
		return r
	ChatLog.add("trade", "Traded with %s: gave %s, got %s" % [p.display_name, gave, got])
	_say(p, "trade_gift" if gift else "trade_yes")
	status = "Trade done"
	my_offer.clear()
	their_offer.clear()
	player.stats_changed.emit()
	return ""

func _say(p: Actor, kind: String) -> void:
	var lines: Array = chat.get("party", {}).get(kind, ["ok"])
	var line: String = lines.pick_random()
	ChatLog.add("party", "%s: %s" % [p.display_name, line])
	p.say(line)

func _str(pos: Vector2, s: String, col: Color, fsize: int) -> void:
	draw_string_outline(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 3, Color(0, 0, 0, 0.8))
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)

func _draw_grid(origin: Vector2, inv: Inventory) -> void:
	for k in inv.slots.size():
		var r := slot_rect(origin, k)
		draw_rect(r, Color(1, 1, 1, 0.07))
		var s = inv.slots[k]
		if s == null:
			continue
		InventoryUI.draw_icon(self, r.grow(-2), inv.def(String(s.id)))
		_str(r.position + Vector2(r.size.x - 1 - _font.get_string_size(str(s.count), HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x, r.size.y), str(s.count), Color.WHITE, 6)

func _draw_offer(offer: Dictionary, mine: bool, inv: Inventory) -> void:
	var row := 0
	for id in offer:
		var r := offer_rect(row, mine)
		InventoryUI.draw_icon(self, Rect2(r.position + Vector2(2, 1), Vector2(8, 8)), inv.def(id))
		_str(r.position + Vector2(13, 8), "%s x%d" % [inv.def(id).get("name", id), offer[id]], Color.WHITE, 7)
		row += 1
	if offer.is_empty():
		_str(offer_rect(0, mine).position + Vector2(13, 8), "nothing", Color(0.5, 0.5, 0.5), 7)

func _button(r: Rect2, label: String, col: Color) -> void:
	draw_rect(r, Color(col, 0.35))
	draw_rect(r, col, false, 1.0)
	var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	_str(r.position + Vector2((r.size.x - w) / 2.0, 10), label, Color.WHITE, 8)

func _draw() -> void:
	if player == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.11, 0.94))
	draw_rect(Rect2(Vector2.ZERO, size), ChatLog.color("trade"), false, 1.0)
	var p := partner()
	var title := "Trade with %s" % (p.display_name if p else "nobody")
	_str(Vector2(6, 12), title + "   (T to close)", ChatLog.color("trade"), 9)
	_button(prev_button(), "<", Color(0.6, 0.6, 0.7))
	_button(next_button(), ">", Color(0.6, 0.6, 0.7))
	_str(Vector2(6, 26), "Your bag: click to offer", Color(0.75, 0.8, 0.9), 7)
	_draw_grid(my_grid(), player.inventory)
	_str(Vector2(108, 30), "You give (click to take back), worth %d" % Trade.value(player.inventory, my_offer), Color("#ffd84a"), 7)
	_draw_offer(my_offer, true, player.inventory)
	if p:
		_str(Vector2(their_grid().x, 26), "%s's bag: click to ask" % p.display_name, Color(0.75, 0.8, 0.9), 7)
		_draw_grid(their_grid(), p.inventory)
		_str(Vector2(108, 76), "You get, worth %d" % Trade.value(p.inventory, their_offer), Color("#ffd84a"), 7)
		_draw_offer(their_offer, false, p.inventory)
	_button(trade_button(), "Trade", Color("#7fe39b"))
	_button(clear_button(), "Clear", Color(0.7, 0.7, 0.7))
	_str(Vector2(6, H - 6), status, Color(0.85, 0.85, 0.9), 7)
