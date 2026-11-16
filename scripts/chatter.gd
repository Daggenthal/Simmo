class_name Chatter
extends Node
## Fake chat. Passers-by talk in local chat now and then; SimPlayers talk in party chat:
## idle banter, reactions to level ups, ultimates, new maps and drops, and calls for help
## when they're low on HP or out of potions. Lines live in data/chat.json.

var main: Node
var data: Dictionary = {}
var _local_t := 0.0
var _party_t := 0.0
var _poll_t := 0.0
var _said_t: Dictionary = {}   # sim -> seconds until it may talk again
var _asked: Dictionary = {}    # sim -> already asked for potions
var _party_gap := 0.0
## Its own random numbers, so chat never shifts gameplay rolls (crits, loot).
var rng := RandomNumberGenerator.new()          # party-wide pause between ordinary lines, so Simmos don't chain-chat

func setup(m: Node, chat_data: Dictionary) -> void:
	main = m
	data = chat_data
	rng.seed = randi()  # one draw at setup: chat stays reproducible with the game's seed
	_local_t = _roll("local_every")
	_party_t = _roll("party_every")
	main.world.map_changed.connect(_on_map)
	main.world.looted.connect(_on_loot)
	watch(main.player)

## Hook up an actor's events (the player, and each sim as it joins).
func watch(a: Actor) -> void:
	if not a.leveled_up.is_connected(_on_level):
		a.leveled_up.connect(_on_level)
		a.ultimate_used.connect(_on_ult)

func _pick(arr: Array):
	return arr[rng.randi() % arr.size()] if not arr.is_empty() else null

func _roll(key: String) -> float:
	var r: Array = data.get(key, [10, 20])
	return rng.randf_range(float(r[0]), float(r[1]))

func _fill(s: String, extra := {}) -> String:
	var p = main.player
	# Real values first; only lines without one (passers-by bragging) get a made-up level.
	for k in extra:
		s = s.replace("{%s}" % k, str(extra[k]))
	return s.replace("{player}", "you" if p == null or p.display_name == "" else p.display_name).replace("{lvl}", str(rng.randi_range(5, 40)))

## A sim says a line of `kind` in party chat (rate-limited per sim unless forced).
func party_say(sim: Actor, kind: String, extra := {}, force := false) -> void:
	if sim == null or not is_instance_valid(sim):
		return
	if not force and (float(_said_t.get(sim, 0.0)) > 0.0 or _party_gap > 0.0):
		return
	var lines: Array = data.get("party", {}).get(kind, [])
	if lines.is_empty():
		return
	_said_t[sim] = 8.0
	_party_gap = 2.5
	var line := _fill(_pick(lines), extra)
	ChatLog.add("party", "%s: %s" % [sim.display_name, line])
	sim.say(line)

func _sims() -> Array:
	var out: Array = []
	for s in main.sims:
		if is_instance_valid(s) and s.is_inside_tree():
			out.append(s)
	return out

func _physics_process(delta: float) -> void:
	_party_gap = maxf(_party_gap - delta, 0.0)
	for k in _said_t.keys():
		_said_t[k] = float(_said_t[k]) - delta
	_local_t -= delta
	if _local_t <= 0.0:
		_local_t = _roll("local_every")
		var who: String = _pick(data.get("passersby", ["Someone"]))
		ChatLog.add("local", "%s: %s" % [who, _fill(_pick(data.get("local", ["hi"])))])
	_party_t -= delta
	if _party_t <= 0.0:
		_party_t = _roll("party_every")
		var s := _sims()
		if not s.is_empty():
			party_say(_pick(s), "idle")
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = 0.5
		_poll_sims()

## Low HP calls and potion requests.
func _poll_sims() -> void:
	for s in _sims():
		if not s.is_alive():
			continue
		var frac := float(s.hp) / float(s.max_hp)
		var hp_pots := 0
		if s.inventory:
			for id in s.inventory.defs:
				if String(s.inventory.defs[id].get("effect", "")) == "heal_hp":
					hp_pots += s.inventory.count(id)
		if hp_pots == 0 and not _asked.get(s, false):
			_asked[s] = true
			party_say(s, "out_of_potions", {}, true)
		elif hp_pots > 0:
			_asked[s] = false
		if frac < 0.3:
			party_say(s, "low_hp")

func _on_level(a: Actor, lvl: int) -> void:
	if a == main.player:
		ChatLog.add("system", "You reached level %d!" % lvl)
		var s := _sims()
		if not s.is_empty():
			party_say(_pick(s), "level_up", {}, true)
	else:
		party_say(a, "own_level", {"lvl": lvl}, true)

func _on_ult(a: Actor, ult_name: String) -> void:
	if a == main.player:
		ChatLog.add("system", "You unleash %s!" % ult_name)
	else:
		party_say(a, "ultimate", {"ult": ult_name}, true)

func _on_map(_id: String) -> void:
	if main.world == null or main.world.map.is_empty():
		return
	ChatLog.add("system", "Entered %s (%s)" % [main.world.map.name, main.world.level_label()])
	var s := _sims()
	if not s.is_empty():
		party_say(_pick(s), "map", {"map": main.world.map.name}, true)

func _on_loot(item_name: String) -> void:
	var s := _sims()
	if not s.is_empty() and rng.randf() < 0.3:
		party_say(_pick(s), "loot", {"item": item_name})
