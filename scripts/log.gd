extends Node
## Colored logging, matching the Incarnate run-server.sh convention.
## Red = errors, yellow = warnings / expected issues, green = success,
## cyan = stack frames / trace, plain = info.
## print_rich turns colors into ANSI on a terminal and stays plain in godot.log.
## Set SIMMO_NO_COLOR=1 to turn colors off.
## Debug mode: SIMMO_DEBUG=1, the --debug-game user arg, or F3 in game.

signal debug_changed(enabled: bool)

var use_color := true
var debug := false:
	set(value):
		debug = value
		debug_changed.emit(value)

func _init() -> void:
	use_color = OS.get_environment("SIMMO_NO_COLOR").is_empty()
	debug = OS.get_environment("SIMMO_DEBUG") == "1" or "--debug-game" in OS.get_cmdline_user_args()

func _ready() -> void:
	if debug:
		warn("Debug mode is on: full logging, errors are reported and play continues")

func _emit(color: String, tag: String, msg: String, bold := false) -> void:
	var line := "[%s] %s" % [tag, msg]
	if use_color:
		var body := "[color=%s]%s[/color]" % [color, line]
		if bold:
			body = "[b]%s[/b]" % body
		print_rich(body)
	else:
		print(line)

func info(msg: String) -> void:
	print("[info] " + msg)

func ok(msg: String) -> void:
	_emit("green", "ok", msg)

func warn(msg: String) -> void:
	_emit("yellow", "warn", msg)

func error(msg: String) -> void:
	_emit("red", "error", msg)
	push_error(msg)

func crash(msg: String) -> void:
	_emit("red", "CRASH", msg, true)

func trace(msg: String) -> void:
	_emit("cyan", "trace", msg)

func dbg(msg: String) -> void:
	if debug:
		_emit("cyan", "debug", msg)

## Use in debug mode instead of assert(): reports the problem and keeps running.
func check(condition: bool, msg: String) -> bool:
	if not condition:
		error("check failed: " + msg)
		for frame in get_stack():
			trace("  %s:%d in %s()" % [frame.source, frame.line, frame.function])
	return condition
