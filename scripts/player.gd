class_name Player
extends Actor
## The human player: keyboard/controller input, plus optional auto-battle (Q / Tab).
## Manual input takes over movement, but auto keeps swinging at anything in front;
## auto resumes after auto_pause_after_input with a fresh target.

var auto_battle := false
var _auto_pause := 0.0
var _auto_was_manual := false

func _ready() -> void:
	super()
	add_to_group("player")

func _uses_brain() -> bool:
	return auto_battle

func _get_intent(delta: float) -> Dictionary:
	_auto_pause = max(_auto_pause - delta, 0.0)
	var intent := _read_manual()
	if not auto_battle:
		return intent
	if intent.active:
		# Manual movement wins, but auto keeps swinging at anything in front of you.
		_auto_pause = float(cfg.auto_pause_after_input)
		_auto_was_manual = true
		if not intent.attack and _mob_in_front():
			intent.attack = true
	elif _auto_pause <= 0.0:
		if _auto_was_manual:
			# Pick a fresh target from wherever the player steered to.
			_auto_was_manual = false
			brain.target = null
		intent = brain.think(delta)
	elif _mob_in_front():
		intent.attack = true
	return intent

## What the player is asking for this frame.
func _read_manual() -> Dictionary:
	var i := {
		"dir": Input.get_axis("move_left", "move_right"),
		"jump": Input.is_action_just_pressed("jump"),
		"jump_release": Input.is_action_just_released("jump"),
		"down": Input.is_action_pressed("move_down"),
		"attack": Input.is_action_pressed("attack"),
	}
	i.spell = ""
	for n in 4:
		if Input.is_action_pressed("spell_%d" % (n + 1)):
			i.spell = _spell_by_slot(n)
	i.active = i.dir != 0.0 or i.jump or i.down or i.attack or Input.is_action_pressed("jump") or i.spell != ""
	return i

func _spell_by_slot(n: int) -> String:
	var keys := spells.keys()
	return keys[n] if n < keys.size() else ""

func set_auto_battle(on: bool) -> void:
	auto_battle = on
	brain.reset()
	_auto_pause = 0.0
	Log.info("Auto-battle %s" % ("on" if on else "off"))
	stats_changed.emit()
