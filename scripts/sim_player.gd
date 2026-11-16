class_name SimPlayer
extends Actor
## A simulated party member: same body as the player, always driven by a Brain
## that follows the leader and plays a role (tank, healer, ranged).
## When knocked out it disappears for party.respawn_time seconds and comes back next to the leader.

var role := ""
var down_t := 0.0

## info: one entry of balance.json "sims" ({name, role, look}).
func setup_sim(info: Dictionary, balance: Dictionary, leader: Actor, spawn: Vector2) -> void:
	role = String(info.get("role", "tank"))
	var role_cfg: Dictionary = balance.get("sim_roles", {}).get(role, {})
	var c: Dictionary = balance.player.duplicate(true)
	var mult := float(role_cfg.get("hp_mult", 1.0))
	c.max_hp = int(round(float(c.max_hp) * mult))
	c.hp_per_level = int(round(float(c.hp_per_level) * mult))
	c.starting_weapon = String(role_cfg.get("weapon", c.starting_weapon))
	c.spells = role_cfg.get("spells", [])
	c.look = info.get("look", {})
	c.auto_use_spells = true
	setup(c, spawn, balance.weapons, balance.get("spells", {}))
	display_name = String(info.get("name", "Sim"))
	tag_color = Color(role_cfg.get("color", "#ffffff"))
	brain.leader = leader
	brain.role = role
	brain.role_cfg = role_cfg
	brain.party_cfg = balance.get("party", {})
	# Start at the leader's level so the party fights the same mobs.
	while level < leader.level:
		level += 1
		max_hp += int(cfg.hp_per_level)
		max_mp += int(cfg.get("mp_per_level", 0))
	hp = max_hp
	mp = max_mp

func _ready() -> void:
	super()
	add_to_group("sims")

func is_alive() -> bool:
	return down_t <= 0.0 and hp > 0

func _physics_process(delta: float) -> void:
	if down_t > 0.0:
		down_t -= delta
		if down_t <= 0.0:
			_revive()
		return
	super(delta)

func _on_death() -> void:
	Log.warn("%s was knocked out" % display_name)
	down_t = float(brain.party_cfg.get("respawn_time", 5.0))
	visible = false
	remove_from_group("actors")
	collision_mask = 0
	brain.reset()
	died.emit()

func _revive() -> void:
	hp = max_hp
	mp = max_mp
	visible = true
	add_to_group("actors")
	collision_mask = LAYER_GROUND | LAYER_PLATFORMS
	var at: Vector2 = brain.leader.global_position if brain.has_leader() else _spawn_point
	position = at
	velocity = Vector2.ZERO
	_invuln = 2.0
	stats_changed.emit()
