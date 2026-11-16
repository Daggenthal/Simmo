class_name Weather
extends Node
## Time of day and weather. A day lasts environment.day_length seconds: dawn, noon, dusk, night.
## Weather cycles through clear, cloudy, rain and storm (snow instead of rain where the map's
## climate is "snow"; no rain where it is "dry"). It drives:
##   WeatherState.wind     hair, cloth, grass, rain and snow all lean with it
##   Lighting.darkness     night and storms darken the world (CanvasModulate); lights shine more
##   sky and cloud colors, the sun, moon and stars (SkyArt), rain and snow amounts (Precipitation)
##   lightning flashes and thunder in storms, rain and wind ambience.
## Settings can freeze the time of day or turn weather off.

signal lightning(at_x: float)

var cfg: Dictionary = {}
var main: Node
var time_of_day := 0.4        # 0 midnight, 0.25 dawn, 0.5 noon, 0.75 dusk
var day_cycle := true          # settings: false freezes the time
var weather_on := true         # settings: false keeps it clear
var state := "clear"
var rain := 0.0                # 0..1 current amount (rain or snow)
var cloud := 0.0               # 0..1 overcast
var climate := ""
var _state_t := 30.0
var _target_rain := 0.0
var _target_cloud := 0.0
var _target_wind := 0.25
var _bolt_t := 8.0
var flash := 0.0               # 0..1 lightning flash, fades fast
var modulate_node: CanvasModulate

func setup(m: Node, env: Dictionary) -> void:
	main = m
	cfg = env
	time_of_day = float(env.get("start_time", 0.4))
	modulate_node = CanvasModulate.new()
	main.add_child(modulate_node)
	_enter("clear")

## The map changed: its climate decides rain or snow.
func set_climate(c: String) -> void:
	climate = c
	if climate == "snow" and weather_on:
		_enter("snow")
	elif state == "snow":
		_enter("clear")

func set_state(s: String) -> void:
	_enter(s)
	rain = _target_rain
	cloud = _target_cloud
	WeatherState.wind = _target_wind

func _enter(s: String) -> void:
	state = s
	var spans: Dictionary = cfg.get("weather", {})
	var span: Array = spans.get(s if s != "snow" else "rain", [40, 80])
	_state_t = randf_range(float(span[0]), float(span[1]))
	match s:
		"clear":
			_target_rain = 0.0
			_target_cloud = 0.0
		"cloudy":
			_target_rain = 0.0
			_target_cloud = 0.5
		"rain":
			_target_rain = 0.6
			_target_cloud = 0.8
		"storm":
			_target_rain = 1.0
			_target_cloud = 1.0
		"snow":
			_target_rain = 0.55
			_target_cloud = 0.6
	var winds: Dictionary = cfg.get("wind", {})
	var w := float(winds.get(s, 0.3))
	_target_wind = w * (1.0 if randf() < 0.6 else -1.0)
	Log.dbg("weather: %s for %.0fs" % [s, _state_t])

func _next_state() -> String:
	if climate == "snow":
		return "snow" if state != "snow" else "cloudy"
	match state:
		"clear":
			return "cloudy"
		"cloudy":
			if climate == "dry":
				return "clear"
			return "rain" if randf() < 0.65 else "clear"
		"rain":
			return "storm" if randf() < float(cfg.get("storm_chance", 0.3)) else "clear"
		_:
			return "rain" if state == "storm" else "clear"

## How dark it is from the time of day alone: 0 at noon, 1 at midnight, smooth at dawn and dusk.
func night_amount() -> float:
	var d := cos((time_of_day - 0.5) * TAU)   # 1 at noon, -1 at midnight
	return clampf(0.5 - d * 0.9, 0.0, 1.0)

## On the physics tick: wind and the clock drive hair, cloth and grass, which simulate on it too.
func _physics_process(delta: float) -> void:
	WeatherState.clock += delta
	if day_cycle:
		time_of_day = fmod(time_of_day + delta / float(cfg.get("day_length", 480.0)), 1.0)
	if weather_on:
		_state_t -= delta
		if _state_t <= 0.0:
			_enter(_next_state())
	elif state != "clear":
		_enter("clear")
	rain = move_toward(rain, _target_rain if weather_on else 0.0, delta * 0.08)
	cloud = move_toward(cloud, _target_cloud if weather_on else 0.0, delta * 0.08)
	WeatherState.wind = move_toward(WeatherState.wind, _target_wind, delta * 0.15)
	flash = maxf(flash - delta * 3.0, 0.0)
	if state == "storm" and rain > 0.6:
		_bolt_t -= delta
		if _bolt_t <= 0.0:
			var span: Array = cfg.get("lightning_every", [6, 12])
			_bolt_t = randf_range(float(span[0]), float(span[1]))
			_strike()
	var dark := night_amount() * float(cfg.get("night_darkness", 0.6)) + cloud * 0.18
	Lighting.darkness = clampf(dark, 0.0, 0.85)
	_apply_colors()
	Sfx.set_ambient("loop_rain" if rain > 0.05 and state != "snow" else "loop_wind", clampf(rain, 0.0, 1.0) if state != "snow" else 0.25 + absf(WeatherState.wind) * 0.4)

## World tint: warm at dawn and dusk, blue at night, gray under clouds; white flash for lightning.
func world_tint() -> Color:
	var n := night_amount()
	var dusk := clampf(1.0 - absf(fmod(time_of_day + 1.0, 1.0) - 0.75) * 10.0, 0.0, 1.0) + clampf(1.0 - absf(time_of_day - 0.25) * 10.0, 0.0, 1.0)
	var c := Color(1, 1, 1)
	c = c.lerp(Color("#ffb07a"), dusk * 0.35)
	c = c.lerp(Color("#3a4a8a"), n * float(cfg.get("night_darkness", 0.6)))
	c = c.lerp(Color("#8a93a3"), cloud * 0.35)
	return c.lerp(Color(1.3, 1.3, 1.45), flash * 0.6)

func sky_color(base: Color) -> Color:
	var n := night_amount()
	var c := base
	var dusk := clampf(1.0 - absf(time_of_day - 0.75) * 9.0, 0.0, 1.0) + clampf(1.0 - absf(time_of_day - 0.25) * 9.0, 0.0, 1.0)
	c = c.lerp(Color("#f59a6a"), dusk * 0.55)
	c = c.lerp(Color("#0b1030"), n)
	c = c.lerp(Color("#5d6675"), cloud * 0.55 * (1.0 - n * 0.6))
	return c.lerp(Color("#d8e0ff"), flash * 0.7)

func _apply_colors() -> void:
	if modulate_node:
		modulate_node.color = world_tint()

func _strike() -> void:
	flash = 1.0
	var at: float = main.player.global_position.x + randf_range(-260, 260) if main and main.player else 0.0
	lightning.emit(at)
	get_tree().create_timer(randf_range(0.25, 1.1), false).timeout.connect(func() -> void: Sfx.play("thunder", 0.9))
