class_name Inventory
extends RefCounted
## Slot inventory with stacking. Item definitions come from data/items.json.
## Slots are null or {id, count}; stacks fill the first matching slot up to the item's
## "stack" size, then spill into the first empty slot.

signal changed

const ITEMS_PATH := "res://data/items.json"

var defs: Dictionary = {}
var slots: Array = []

static func load_data() -> Dictionary:
	var f := FileAccess.open(ITEMS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

func _init(item_defs: Dictionary = {}, size := 24) -> void:
	defs = item_defs
	slots.resize(size)

func def(id: String) -> Dictionary:
	return defs.get(id, {})

## Add up to n of item id. Returns how many fit.
func add(id: String, n := 1) -> int:
	if not Log.check(defs.has(id), "unknown item '%s'" % id):
		return 0
	var cap := int(defs[id].get("stack", 1))
	var left := n
	for s in slots:
		if left > 0 and s != null and s.id == id and int(s.count) < cap:
			var put := mini(left, cap - int(s.count))
			s.count = int(s.count) + put
			left -= put
	for k in slots.size():
		if left <= 0:
			break
		if slots[k] == null:
			var put := mini(left, cap)
			slots[k] = {"id": id, "count": put}
			left -= put
	if left < n:
		changed.emit()
	return n - left

## Remove up to n of item id (latest stacks first). Returns how many were removed.
func remove(id: String, n := 1) -> int:
	var left := n
	for k in range(slots.size() - 1, -1, -1):
		var s = slots[k]
		if left > 0 and s != null and s.id == id:
			var take := mini(left, int(s.count))
			s.count = int(s.count) - take
			left -= take
			if int(s.count) <= 0:
				slots[k] = null
	if left < n:
		changed.emit()
	return n - left

## Put a one-of-a-kind item (boss gear or junk, see Gear) in the first empty slot. Returns the slot or -1.
func add_item(item: Dictionary) -> int:
	for k in slots.size():
		if slots[k] == null:
			slots[k] = {"id": "item", "count": 1, "item": item}
			changed.emit()
			return k
	return -1

func take_slot(k: int) -> Dictionary:
	var s = slots[k]
	if s == null:
		return {}
	slots[k] = null
	changed.emit()
	return s

func items_of_rarity(rarity: String) -> int:
	var n := 0
	for s in slots:
		if s != null and s.has("item") and String(s.item.rarity) == rarity:
			n += 1
	return n

func count(id: String) -> int:
	var c := 0
	for s in slots:
		if s != null and s.id == id:
			c += int(s.count)
	return c

func is_full_for(id: String) -> bool:
	var cap := int(defs.get(id, {}).get("stack", 1))
	for s in slots:
		if s == null or (s.id == id and int(s.count) < cap):
			return false
	return true
