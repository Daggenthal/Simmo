class_name Trade
extends RefCounted
## Trade rules between two actors' inventories. Offers are {item id: count}.
## SimPlayers judge a trade by item value (items.json "value"): a gift is always welcome,
## otherwise what they get must be worth at least trade.accept_ratio of what they give,
## and they keep trade.keep_hp_potions HP potions for themselves.

## Total value of an offer.
static func value(inv: Inventory, offer: Dictionary) -> int:
	var v := 0
	for id in offer:
		v += int(inv.def(id).get("value", 1)) * int(offer[id])
	return v

## Whether `inv` holds everything in `offer`.
static func has_all(inv: Inventory, offer: Dictionary) -> bool:
	for id in offer:
		if inv.count(id) < int(offer[id]):
			return false
	return true

## Would the sim agree? Returns "" for yes, or its reason ("gift" counts as yes).
## sim_gives: what the sim hands over. sim_gets: what the player hands over.
static func sim_verdict(sim_inv: Inventory, sim_gives: Dictionary, sim_gets: Dictionary, cfg: Dictionary) -> String:
	if sim_gives.is_empty() and sim_gets.is_empty():
		return "empty"
	if sim_gives.is_empty():
		return ""
	var hp_left := 0
	for id in sim_inv.defs:
		if String(sim_inv.defs[id].get("effect", "")) == "heal_hp":
			hp_left += sim_inv.count(id) - int(sim_gives.get(id, 0)) + int(sim_gets.get(id, 0))
	var gives_hp := false
	for id in sim_gives:
		if String(sim_inv.def(id).get("effect", "")) == "heal_hp":
			gives_hp = true
	if gives_hp and hp_left < int(cfg.get("keep_hp_potions", 2)):
		return "needs"
	if float(value(sim_inv, sim_gets)) < float(value(sim_inv, sim_gives)) * float(cfg.get("accept_ratio", 0.8)):
		return "unfair"
	return ""

## Swap the offers between two inventories, all or nothing. Returns "" or why it failed.
static func execute(a: Inventory, b: Inventory, a_gives: Dictionary, b_gives: Dictionary) -> String:
	if not has_all(a, a_gives) or not has_all(b, b_gives):
		return "missing"
	# Try it on copies first so a full bag can't eat items.
	var ta := _copy(a)
	var tb := _copy(b)
	for id in a_gives:
		ta.remove(id, int(a_gives[id]))
	for id in b_gives:
		tb.remove(id, int(b_gives[id]))
	for id in b_gives:
		if ta.add(id, int(b_gives[id])) < int(b_gives[id]):
			return "full"
	for id in a_gives:
		if tb.add(id, int(a_gives[id])) < int(a_gives[id]):
			return "full"
	a.slots = ta.slots
	b.slots = tb.slots
	a.changed.emit()
	b.changed.emit()
	return ""

static func _copy(inv: Inventory) -> Inventory:
	var c := Inventory.new(inv.defs, inv.slots.size())
	for k in inv.slots.size():
		c.slots[k] = inv.slots[k].duplicate() if inv.slots[k] != null else null
	return c

static func describe(inv: Inventory, offer: Dictionary) -> String:
	var parts: Array = []
	for id in offer:
		parts.append("%s x%d" % [inv.def(id).get("name", id), int(offer[id])])
	return ", ".join(parts) if not parts.is_empty() else "nothing"
