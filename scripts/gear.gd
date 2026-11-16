class_name Gear
extends RefCounted
## Loot from boss chests, Diablo style (data/loot.json). An item is a Dictionary:
##   {kind: "junk" | "gear", name, rarity, level, value, color}
##   gear also has: base, slot ("weapon", "ring", "amulet"), weapon (weapon id or ""), mods {stat: value}, lines [text]
## Rarity picks by weight; gear gets a base bonus (weapons: damage %, jewels: a stat) plus as many random
## affixes as the rarity allows. Legendaries add a unique name and a special bonus.
## Mods: str / dex / int / luk (points), damage (%), crit (%), hp, mp.

static var data: Dictionary = {}

static func load_data() -> Dictionary:
	if data.is_empty():
		var f := FileAccess.open("res://data/loot.json", FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			data = parsed if parsed is Dictionary else {}
	return data

static func color(rarity: String) -> Color:
	return Color(load_data().get("rarities", {}).get(rarity, {}).get("color", "#ffffff"))

static func rarity_name(rarity: String) -> String:
	return String(load_data().get("rarities", {}).get(rarity, {}).get("name", rarity.capitalize()))

## Weighted rarity roll.
static func roll_rarity() -> String:
	var r: Dictionary = load_data().rarities
	var total := 0.0
	for k in r:
		total += float(r[k].weight)
	var pick := randf() * total
	for k in r:
		pick -= float(r[k].weight)
		if pick <= 0.0:
			return k
	return "common"

## One item of `rarity` at `level`. class_weapons: weapons the player can use (drops lean toward them).
static func make(rarity: String, level: int, class_weapons: Array = []) -> Dictionary:
	var d := load_data()
	var r: Dictionary = d.rarities[rarity]
	var item := {"rarity": rarity, "level": level, "value": int(r.value) * maxi(level, 1), "color": String(r.color)}
	if rarity == "junk":
		item.kind = "junk"
		item.name = String(d.junk.pick_random())
		item.lines = ["Junk. Worth a few coins."]
		return item
	item.kind = "gear"
	# Base: 60% a weapon your class can use, otherwise anything.
	var base_key: String
	if not class_weapons.is_empty() and randf() < 0.6:
		base_key = String(class_weapons.pick_random())
	else:
		base_key = String(d.bases.keys().pick_random())
	var base: Dictionary = d.bases[base_key]
	item.base = base_key
	item.slot = String(base.slot)
	item.weapon = String(base.get("weapon", ""))
	var mods := {}
	var bb: Dictionary = d.base_bonus
	if item.slot == "weapon":
		mods.damage = maxi(1, int(round(float(bb.weapon_damage_per_level) * level)))
	else:
		var st: String = ["str", "dex", "int", "luk"].pick_random()
		mods[st] = maxi(1, int(round(float(bb.jewel_stat_per_level) * level)))
	var pool: Array = d.affixes.keys()
	pool.shuffle()
	var picked: Array = pool.slice(0, int(r.affixes))
	for k in picked:
		var v := maxi(1, int(round(float(d.affixes[k].per_level) * level * randf_range(0.7, 1.3))))
		mods[k] = int(mods.get(k, 0)) + v
	var name := String(base.name)
	if not picked.is_empty():
		name = "%s %s" % [d.prefixes.get(picked[0], ""), name]
	if rarity == "legendary":
		var sp: Dictionary = d.legendary_specials.pick_random()
		mods[sp.key] = int(mods.get(sp.key, 0)) + maxi(1, int(round(float(sp.per_level) * level)))
		name = "%s (%s)" % [d.legendary_names.pick_random(), base.name]
	item.name = name
	item.mods = mods
	item.lines = describe_mods(mods)
	return item

static func describe_mods(mods: Dictionary) -> Array:
	var d := load_data()
	var out: Array = []
	for k in mods:
		var label := String(d.affixes.get(k, {}).get("label", "+{v} " + k))
		out.append(label.replace("{v}", str(mods[k])))
	return out

## A boss chest's contents: a few items at the boss's level.
static func roll_chest(level: int, class_weapons: Array) -> Array:
	var span: Array = load_data().get("drops", [3, 5])
	var items: Array = []
	for k in randi_range(int(span[0]), int(span[1])):
		items.append(make(roll_rarity(), level, class_weapons))
	return items

## Best rarity among items (for the chest's glow).
static func best(items: Array) -> String:
	var order: Array = load_data().get("rarity_order", [])
	var best_i := 0
	for it in items:
		best_i = maxi(best_i, order.find(String(it.rarity)))
	return order[best_i] if not order.is_empty() else "common"
