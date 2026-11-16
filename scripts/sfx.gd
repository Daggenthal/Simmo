extends Node
## Sound effects, synthesized in code (no audio files): Sfx.play("hit").
## Each sound is built once on first use and cached as a 16-bit mono AudioStreamWAV.
## Volumes: Sfx.sfx_volume and Sfx.ambient_volume (0..1), set from the settings menu.

const RATE := 22050
const VOICES := 12

var sfx_volume := 0.8
var ambient_volume := 0.6
var muted := false
var played: Dictionary = {}   # name -> times played (tests)
var _cache: Dictionary = {}
var _players: Array = []
var _next := 0
var _ambient: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for k in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_ambient = AudioStreamPlayer.new()
	add_child(_ambient)

## Play a sound by name. pitch varies it a little so repeats don't sound robotic.
func play(sound: String, volume := 1.0, pitch := 1.0) -> void:
	played[sound] = int(played.get(sound, 0)) + 1
	if muted or sfx_volume <= 0.0:
		return
	var stream := get_stream(sound)
	if stream == null:
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = stream
	p.volume_db = linear_to_db(clampf(volume * sfx_volume, 0.0001, 1.0))
	p.pitch_scale = pitch
	p.play()

## Looping background sound (rain), or "" to stop.
func set_ambient(sound: String, volume := 1.0) -> void:
	if sound == "" or muted:
		_ambient.stop()
		return
	var stream := get_stream(sound)
	if _ambient.stream != stream:
		_ambient.stream = stream
		_ambient.play()
	elif not _ambient.playing:
		_ambient.play()
	_ambient.volume_db = linear_to_db(clampf(volume * ambient_volume, 0.0001, 1.0))

func get_stream(sound: String) -> AudioStreamWAV:
	if _cache.has(sound):
		return _cache[sound]
	var gen := Callable(self, "_gen_" + sound)
	if not gen.is_valid():
		Log.warn("No sound named '%s'" % sound)
		return null
	var samples: PackedFloat32Array = gen.call()
	var loop := sound.begins_with("loop_")
	var s := _to_wav(samples, loop)
	_cache[sound] = s
	return s

func _to_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w

# --- building blocks ---

static func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b

## Add a decaying sine "bell" at `start` seconds.
static func _bell(b: PackedFloat32Array, start: float, freq: float, amp: float, decay: float) -> void:
	var i0 := int(start * RATE)
	var n := mini(int(decay * 5.0 * RATE), b.size() - i0)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t / decay) * minf(t / 0.004, 1.0)
		b[i0 + i] += amp * env * (sin(TAU * freq * t) + 0.3 * sin(TAU * freq * 2.01 * t))

## Add an echo of the whole buffer `delay` seconds later.
static func _echo(b: PackedFloat32Array, delay: float, gain: float) -> void:
	var d := int(delay * RATE)
	for i in range(b.size() - 1, d - 1, -1):
		b[i] += b[i - d] * gain

static func _fade(b: PackedFloat32Array, fin: float, fout: float) -> void:
	var a := int(fin * RATE)
	var z := int(fout * RATE)
	for i in mini(a, b.size()):
		b[i] *= float(i) / a
	for i in mini(z, b.size()):
		b[b.size() - 1 - i] *= float(i) / z

## Simple one-pole low-pass on noise for soft whooshes and rain.
static func _noise(b: PackedFloat32Array, amp: float, smooth: float, env: Callable) -> void:
	var y := 0.0
	for i in b.size():
		y += (randf_range(-1.0, 1.0) - y) * smooth
		b[i] += amp * y * float(env.call(float(i) / b.size()))

# --- sounds ---

## Zone warp out (.hack style): rising shimmer sweep, bell arpeggio climbing, echoes.
func _gen_warp_out() -> PackedFloat32Array:
	var dur := 1.6
	var b := _buf(dur)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := 180.0 * pow(2.0, 2.6 * t / dur)
		ph += TAU * f / RATE
		var trem := 0.6 + 0.4 * sin(TAU * (8.0 + 10.0 * t) * t)
		b[i] += 0.22 * trem * (sin(ph) + 0.5 * sin(ph * 2.0) + 0.25 * sin(ph * 3.0)) * minf(t / 0.2, 1.0)
	var notes := [523.25, 659.25, 783.99, 1046.5, 1318.5, 1568.0, 2093.0]
	for k in notes.size():
		_bell(b, 0.1 + k * 0.13, notes[k], 0.16, 0.35)
	_noise(b, 0.12, 0.35, func(x: float) -> float: return x * x)
	_echo(b, 0.17, 0.35)
	_fade(b, 0.02, 0.35)
	return b

## Zone warp in: a soft falling shimmer and a resolving chord.
func _gen_warp_in() -> PackedFloat32Array:
	var dur := 1.1
	var b := _buf(dur)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := 900.0 * pow(2.0, -1.6 * t / dur)
		ph += TAU * f / RATE
		b[i] += 0.16 * sin(ph) * exp(-t * 2.0)
	for n in [1046.5, 783.99, 659.25, 523.25]:
		_bell(b, 0.05 + [1046.5, 783.99, 659.25, 523.25].find(n) * 0.07, n, 0.14, 0.4)
	_noise(b, 0.08, 0.3, func(x: float) -> float: return 1.0 - x)
	_echo(b, 0.15, 0.3)
	_fade(b, 0.01, 0.3)
	return b

## Hit: a short thump plus a click, a little noise.
func _gen_hit() -> PackedFloat32Array:
	var b := _buf(0.14)
	for i in b.size():
		var t := float(i) / RATE
		b[i] += 0.55 * sin(TAU * (140.0 - 400.0 * t) * t) * exp(-t * 30.0)
	_noise(b, 0.45, 0.6, func(x: float) -> float: return exp(-x * 12.0))
	return b

## Crit: a brighter, louder hit with a ring.
func _gen_crit() -> PackedFloat32Array:
	var b := _gen_hit()
	_bell(b, 0.0, 1400.0, 0.18, 0.06)
	for i in b.size():
		b[i] *= 1.2
	return b

## Weapon swing: a quick airy whoosh.
func _gen_swing() -> PackedFloat32Array:
	var b := _buf(0.16)
	_noise(b, 0.35, 0.25, func(x: float) -> float: return sin(x * PI))
	return b

## Footstep: a soft low tap (grass and dirt).
func _gen_step() -> PackedFloat32Array:
	var b := _buf(0.06)
	_noise(b, 0.3, 0.12, func(x: float) -> float: return exp(-x * 8.0))
	for i in b.size():
		var t := float(i) / RATE
		b[i] += 0.15 * sin(TAU * 90.0 * t) * exp(-t * 60.0)
	return b

func _gen_jump() -> PackedFloat32Array:
	var b := _buf(0.12)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += TAU * (300.0 + 900.0 * t / 0.12) / RATE
		b[i] = 0.18 * sin(ph) * (1.0 - t / 0.12)
	return b

func _gen_land() -> PackedFloat32Array:
	var b := _buf(0.09)
	_noise(b, 0.35, 0.1, func(x: float) -> float: return exp(-x * 6.0))
	return b

## Spell casts by element.
func _gen_cast_fire() -> PackedFloat32Array:
	var b := _buf(0.35)
	_noise(b, 0.4, 0.2, func(x: float) -> float: return minf(x * 8.0, 1.0) * (1.0 - x))
	for i in b.size():
		var t := float(i) / RATE
		b[i] += 0.12 * sin(TAU * (200.0 + 300.0 * t) * t) * (1.0 - t / 0.35)
	return b

func _gen_cast_frost() -> PackedFloat32Array:
	var b := _buf(0.4)
	for n in [1760.0, 2093.0, 2637.0]:
		_bell(b, [1760.0, 2093.0, 2637.0].find(n) * 0.04, n, 0.12, 0.12)
	_noise(b, 0.1, 0.8, func(x: float) -> float: return 1.0 - x)
	return b

func _gen_cast_poison() -> PackedFloat32Array:
	var b := _buf(0.3)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = 0.25 * sin(TAU * (120.0 + 40.0 * sin(TAU * 18.0 * t)) * t) * exp(-t * 6.0)
	return b

func _gen_cast_lightning() -> PackedFloat32Array:
	var b := _buf(0.3)
	_noise(b, 0.6, 0.9, func(x: float) -> float: return exp(-x * 5.0) * (0.5 + 0.5 * sign(sin(x * 90.0))))
	return b

func _gen_cast_heal() -> PackedFloat32Array:
	var b := _buf(0.6)
	for k in 4:
		_bell(b, k * 0.07, [659.25, 783.99, 987.77, 1318.5][k], 0.12, 0.2)
	return b

## Ultimate: a deep boom with a rising shimmer.
func _gen_ultimate() -> PackedFloat32Array:
	var b := _buf(1.2)
	for i in b.size():
		var t := float(i) / RATE
		b[i] += 0.5 * sin(TAU * (70.0 - 30.0 * t) * t) * exp(-t * 2.5)
	_noise(b, 0.35, 0.3, func(x: float) -> float: return exp(-x * 4.0))
	for k in 5:
		_bell(b, 0.05 + k * 0.06, 523.25 * pow(1.26, k), 0.08, 0.3)
	return b

func _gen_level_up() -> PackedFloat32Array:
	var b := _buf(1.0)
	for k in 5:
		_bell(b, k * 0.09, [523.25, 659.25, 783.99, 1046.5, 1318.5][k], 0.16, 0.3)
	_echo(b, 0.12, 0.3)
	return b

func _gen_potion() -> PackedFloat32Array:
	var b := _buf(0.3)
	for k in 3:
		var i0 := int((0.02 + k * 0.08) * RATE)
		for i in int(0.06 * RATE):
			var t := float(i) / RATE
			b[i0 + i] += 0.25 * sin(TAU * (500.0 + 900.0 * t / 0.06) * t) * (1.0 - t / 0.06)
	return b

func _gen_loot() -> PackedFloat32Array:
	var b := _buf(0.4)
	_bell(b, 0.0, 1318.5, 0.16, 0.12)
	_bell(b, 0.07, 1975.5, 0.16, 0.18)
	return b

func _gen_mob_die() -> PackedFloat32Array:
	var b := _buf(0.3)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += TAU * (400.0 - 1000.0 * t) / RATE
		b[i] = 0.22 * sin(ph) * (1.0 - t / 0.3)
	return b

func _gen_player_hurt() -> PackedFloat32Array:
	var b := _buf(0.2)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = 0.3 * sin(TAU * (220.0 - 300.0 * t) * t) * exp(-t * 12.0)
	_noise(b, 0.2, 0.5, func(x: float) -> float: return exp(-x * 10.0))
	return b

func _gen_ui_click() -> PackedFloat32Array:
	var b := _buf(0.05)
	_bell(b, 0.0, 1800.0, 0.15, 0.015)
	return b

func _gen_thunder() -> PackedFloat32Array:
	var b := _buf(2.4)
	_noise(b, 0.9, 0.04, func(x: float) -> float: return minf(x * 30.0, 1.0) * exp(-x * 2.5) * (0.6 + 0.4 * sin(x * 37.0)))
	_noise(b, 0.4, 0.5, func(x: float) -> float: return exp(-x * 25.0))
	return b

func _gen_boss_roar() -> PackedFloat32Array:
	var b := _buf(1.4)
	for i in b.size():
		var t := float(i) / RATE
		var f := 90.0 + 30.0 * sin(TAU * 6.0 * t)
		b[i] = 0.35 * (sin(TAU * f * t) + 0.5 * sin(TAU * f * 1.5 * t)) * minf(t / 0.1, 1.0) * exp(-t * 1.5)
	_noise(b, 0.3, 0.2, func(x: float) -> float: return exp(-x * 2.0))
	return b

func _gen_chest_open() -> PackedFloat32Array:
	var b := _buf(1.0)
	_noise(b, 0.25, 0.15, func(x: float) -> float: return exp(-x * 15.0))
	for k in 6:
		_bell(b, 0.1 + k * 0.06, 784.0 * pow(1.122, k), 0.12, 0.25)
	_echo(b, 0.1, 0.3)
	return b

## Looping rain: smoothed noise with a few drops.
func _gen_loop_rain() -> PackedFloat32Array:
	var b := _buf(2.0)
	_noise(b, 0.35, 0.5, func(_x: float) -> float: return 1.0)
	for k in 40:
		var i0 := randi_range(0, b.size() - 400)
		for i in 300:
			b[i0 + i] += 0.08 * sin(TAU * randf_range(2500.0, 4000.0) * i / RATE) * exp(-float(i) / 60.0)
	_crossfade_loop(b)
	return b

## Looping wind: slow-moving filtered noise.
func _gen_loop_wind() -> PackedFloat32Array:
	var b := _buf(3.0)
	_noise(b, 0.5, 0.02, func(x: float) -> float: return 0.6 + 0.4 * sin(x * TAU * 2.0))
	_crossfade_loop(b)
	return b

## Smooth the loop seam by blending the end into the start.
static func _crossfade_loop(b: PackedFloat32Array) -> void:
	var n := int(0.1 * RATE)
	for i in n:
		var a := float(i) / n
		b[i] = b[i] * a + b[b.size() - n + i] * (1.0 - a)

## Splash: a bright burst of noise with a low plop.
func _gen_splash() -> PackedFloat32Array:
	var b := _buf(0.3)
	_noise(b, 0.4, 0.7, func(x: float) -> float: return exp(-x * 7.0))
	for i in b.size():
		var t := float(i) / RATE
		b[i] += 0.2 * sin(TAU * (300.0 - 500.0 * t) * t) * exp(-t * 18.0)
	return b
