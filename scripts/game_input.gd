extends Node
## Registers input actions in code so the bindings live in one readable place.
## Keyboard follows MapleStory habits (arrows + Alt jump + Ctrl attack) with WASD/Space/J as alternates.

const BINDINGS := {
	"move_left": [KEY_LEFT, KEY_A],
	"move_right": [KEY_RIGHT, KEY_D],
	"move_up": [KEY_UP, KEY_W],
	"move_down": [KEY_DOWN, KEY_S],
	"jump": [KEY_ALT, KEY_SPACE],
	"attack": [KEY_CTRL, KEY_J],
	"auto_battle": [KEY_Q, KEY_TAB],
	"weapon_1": [KEY_1],
	"weapon_2": [KEY_2],
	"weapon_3": [KEY_3],
	"weapon_4": [KEY_4],
	"weapon_next": [KEY_E],
	"spell_1": [KEY_Z],
	"spell_2": [KEY_X],
	"spell_3": [KEY_C],
	"spell_4": [KEY_V],
	"help_toggle": [KEY_F1],
	"debug_toggle": [KEY_F3],
	"respawn_mobs": [KEY_F5],
	"party_toggle": [KEY_P],
}

const PAD_BUTTONS := {
	"jump": [JOY_BUTTON_A],
	"attack": [JOY_BUTTON_X],
	"move_left": [JOY_BUTTON_DPAD_LEFT],
	"move_right": [JOY_BUTTON_DPAD_RIGHT],
	"move_up": [JOY_BUTTON_DPAD_UP],
	"move_down": [JOY_BUTTON_DPAD_DOWN],
	"auto_battle": [JOY_BUTTON_Y],
	"weapon_next": [JOY_BUTTON_RIGHT_SHOULDER],
	"spell_1": [JOY_BUTTON_B],
	"spell_2": [JOY_BUTTON_LEFT_SHOULDER],
	"spell_3": [JOY_BUTTON_LEFT_STICK],
	"spell_4": [JOY_BUTTON_RIGHT_STICK],
	"debug_toggle": [JOY_BUTTON_BACK],
	"help_toggle": [JOY_BUTTON_START],
}

func _ready() -> void:
	for action in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.3)
		for key in BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	for action in PAD_BUTTONS:
		for button in PAD_BUTTONS[action]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = button
			InputMap.action_add_event(action, ev)
	_add_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_axis("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_add_axis("move_down", JOY_AXIS_LEFT_Y, 1.0)

func _add_axis(action: String, axis: JoyAxis, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)
