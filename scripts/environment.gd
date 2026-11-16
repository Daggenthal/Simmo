class_name MapEnvironment
extends Node2D
## The living parts of a map, rebuilt with it (World/Map/Environment):
##   trees      behind everything, canopies sway in the wind
##   grass      blades along the ground and platform tops, lean with the wind and part around feet
##   snow       a height field on the ground and platforms: builds up while it snows, flakes land on it,
##              feet dig trenches that slowly fill back in
##   water      ponds you wade through (slower) and rivers / lava under plank bridges; the surface is
##              a 1D wave simulation, so walking, jumping in and landing make ripples that spread and settle
##   lamps      posts with lanterns that light up at night (real 2D lights)
##   rain/snow  falling in world space around the camera, leaning with the wind, splashing / settling
## Only what's near the camera is drawn.

const COL := 2.0           # snow and water column width (world px)
const BLADE_GAP := 4.0

var world: Node
var map: Dictionary
var weather: Weather
var env_cfg: Dictionary = {}
var ground_y := 330.0
var waters: Array = []      # {x0, x1, kind, h: PackedFloat32Array, v: PackedFloat32Array, inside: {}}
var snow: Dictionary = {}   # surface key ("g" or platform index) -> {x0, y, h: PackedFloat32Array}
var snowy := false
var drops: Array = []       # {p, v, kind}
var lamps: Array = []       # {pos, light}
var lava_lights: Array = []
var _layers: Dictionary = {}
## Visual-only randomness (trees, rain). Never the global RNG, so frame rate can't shift gameplay rolls.
var _rng := RandomNumberGenerator.new()
var _trees: Array = []

func setup(w: Node, m: Dictionary, wea: Weather, env: Dictionary) -> void:
	world = w
	map = m
	weather = wea
	env_cfg = env
	ground_y = float(m.ground_y)
	_rng.seed = hash(String(m.get("name", "")))
	for wd in m.get("water", []):
		var n := int((float(wd[1]) - float(wd[0])) / COL)
		var h := PackedFloat32Array()
		h.resize(n)
		var v := PackedFloat32Array()
		v.resize(n)
		waters.append({"x0": float(wd[0]), "x1": float(wd[1]), "kind": String(wd[2]), "h": h, "v": v, "inside": {}})
	snowy = String(m.get("climate", "")) == "snow"
	if snowy:
		_add_snow("g", 0.0, float(m.width), ground_y, 2.5)
		for k in m.platforms.size():
			var p: Array = m.platforms[k]
			_add_snow(str(k), float(p[0]), float(p[0]) + float(p[2]), float(p[1]), 2.0)
	for k in 26:
		var x := _rng.randf_range(0.0, float(m.width))
		if not _in_water(x, 20.0):
			_trees.append({"x": x, "s": _rng.randf_range(0.8, 1.3), "far": _rng.randf() < 0.5})
	_trees.sort_custom(func(a, b): return a.far and not b.far)
	for spec in [["trees", -3], ["water_back", -1], ["bridges", 2], ["grass", 3], ["water_front", 7], ["sky_fx", 30]]:
		var layer := Node2D.new()
		layer.z_index = spec[1]
		layer.name = spec[0]
		layer.draw.connect(Callable(self, "_draw_" + spec[0]).bind(layer))
		add_child(layer)
		_layers[spec[0]] = layer
	for l in m.get("lamps", []):
		var holder := Node2D.new()
		holder.position = Vector2(float(l[0]), float(l[1]) - 26)
		add_child(holder)
		lamps.append({"pos": Vector2(float(l[0]), float(l[1])), "light": Lighting.add(holder, Color("#ffd27a"), 110.0, 0.0, true)})
	for wd in waters:
		if wd.kind == "lava":
			var holder := Node2D.new()
			holder.position = Vector2((wd.x0 + wd.x1) / 2.0, ground_y + 6)
			add_child(holder)
			lava_lights.append(Lighting.add(holder, Color("#ff6a1f"), 120.0, 0.8))

func _add_snow(key: String, x0: float, x1: float, y: float, start: float) -> void:
	var n := int((x1 - x0) / COL) + 1
	var h := PackedFloat32Array()
	h.resize(n)
	for i in n:
		h[i] = start * (0.85 + 0.3 * sin(i * 0.37) * 0.5)
	snow[key] = {"x0": x0, "x1": x1, "y": y, "h": h}

func _in_water(x: float, pad := 0.0) -> bool:
	for wd in waters:
		if x >= wd.x0 - pad and x <= wd.x1 + pad:
			return true
	return false

## The water body at ground x (on the ground line), or {}.
func water_at(x: float) -> Dictionary:
	for wd in waters:
		if x >= wd.x0 and x <= wd.x1:
			return wd
	return {}

## Camera view in world coordinates, padded.
func view_rect() -> Rect2:
	var vp := get_viewport()
	if vp == null:
		return Rect2(-1e9, -1e9, 2e9, 2e9)
	var inv := vp.get_canvas_transform().affine_inverse()
	var r := Rect2(inv * Vector2.ZERO, vp.get_visible_rect().size / vp.get_canvas_transform().get_scale())
	return r.grow(40.0)

## Water and snow are simulation (they react to feet), so they run on the fixed physics tick:
## the same result at any frame rate. Rain and snowflakes are visual and move per frame.
func _physics_process(delta: float) -> void:
	_tick_water(delta)
	_tick_snow(delta)

func _process(delta: float) -> void:
	_tick_precip(delta)
	var lamp_e := clampf(Lighting.darkness * 1.6 - 0.15, 0.0, 1.0)
	for l in lamps:
		if l.light:
			l.light.energy = lamp_e * (0.95 + 0.05 * sin(WeatherState.clock * 9.0 + l.pos.x))
	for ll in lava_lights:
		if ll:
			ll.energy = 0.7 + 0.15 * sin(WeatherState.clock * 3.0)
	for k in _layers:
		_layers[k].queue_redraw()

# --- water ---

func _tick_water(delta: float) -> void:
	var dt := minf(delta, 1.0 / 30.0)
	for wd in waters:
		if wd.kind == "ice":
			continue
		var h: PackedFloat32Array = wd.h
		var v: PackedFloat32Array = wd.v
		var n := h.size()
		# Feet in the water push it around; landing in it makes a big splash.
		for a in get_tree().get_nodes_in_group("actors") + get_tree().get_nodes_in_group("mobs"):
			if not a.visible:
				continue
			var x: float = a.global_position.x
			var inside: bool = x >= wd.x0 and x <= wd.x1 and absf(a.global_position.y - ground_y) < 14.0
			var was: bool = wd.inside.get(a, false)
			if inside:
				var i := clampi(int((x - wd.x0) / COL), 0, n - 1)
				var vx: float = a.velocity.x
				if not was:
					v[i] += 70.0 + absf(a.velocity.y) * 0.25
					if wd.kind == "pond" and a.is_in_group("actors"):
						Fx.burst(a.get_parent(), Vector2(x, ground_y - 2), 10.0, Color("#bfe8ff"))
						a.sfx("splash", 0.6)
				elif absf(vx) > 10.0:
					v[i] += vx * 0.9 * dt * 10.0
			wd.inside[a] = inside
		# Spring each column back to rest, let neighbors pull on each other, damp.
		for i in n:
			v[i] += (-h[i] * 60.0 - v[i] * 1.8) * dt
		for _pass in 2:
			for i in n:
				var l := h[i - 1] if i > 0 else h[i]
				var r := h[i + 1] if i < n - 1 else h[i]
				v[i] += (l + r - 2.0 * h[i]) * 40.0 * dt
		for i in n:
			h[i] = clampf(h[i] + v[i] * dt, -6.0, 6.0)
		wd.h = h
		wd.v = v

func _surface(wd: Dictionary, i: int) -> float:
	var h: PackedFloat32Array = wd.h
	var calm := sin(WeatherState.clock * 2.0 + i * 0.5) * 0.5 + sin(WeatherState.clock * 3.1 + i * 0.23) * 0.3
	return h[clampi(i, 0, h.size() - 1)] + calm * (1.0 + weather.rain * 1.5 if weather else 1.0)

func _water_color(kind: String) -> Color:
	match kind:
		"lava":
			return Color("#ff5a1f")
		"ice":
			return Color("#bfe6ff")
	return Color("#3a8fd0")

func _draw_water_back(layer: Node2D) -> void:
	var view := view_rect()
	for wd in waters:
		if wd.x1 < view.position.x or wd.x0 > view.end.x:
			continue
		var col := _water_color(wd.kind)
		var deep: float = 34.0 if wd.kind in ["river", "lava"] else 14.0
		var top: float = ground_y - (6.0 if wd.kind == "pond" else 2.0)
		# Cut the ground: banks and the body.
		layer.draw_rect(Rect2(wd.x0, ground_y - 1, wd.x1 - wd.x0, deep + 3), col.darkened(0.45))
		var poly := PackedVector2Array()
		var n: int = wd.h.size()
		for i in n:
			poly.append(Vector2(wd.x0 + i * COL, top + _surface(wd, i) * (0.0 if wd.kind == "ice" else 1.0)))
		poly.append(Vector2(wd.x1, ground_y + deep))
		poly.append(Vector2(wd.x0, ground_y + deep))
		layer.draw_colored_polygon(poly, Color(col, 0.85))
		var line := poly.slice(0, n)
		layer.draw_polyline(line, col.lightened(0.45), 1.5)
		if wd.kind == "lava":
			for i in range(0, n, 6):
				var ph := fmod(WeatherState.clock * 0.7 + i * 0.13, 1.0)
				layer.draw_circle(Vector2(wd.x0 + i * COL, top + 6 - ph * 8.0), 1.5 * (1.0 - ph), Color("#ffd27a"))
		elif wd.kind == "ice":
			for i in range(0, n, 10):
				layer.draw_line(Vector2(wd.x0 + i * COL, top + 2), Vector2(wd.x0 + i * COL + 6, top + 5), Color(1, 1, 1, 0.6), 1.0)

## In front of actors: the water's surface over their feet (ponds only), with a highlight.
func _draw_water_front(layer: Node2D) -> void:
	var view := view_rect()
	for wd in waters:
		if wd.kind != "pond" or wd.x1 < view.position.x or wd.x0 > view.end.x:
			continue
		var col := _water_color(wd.kind)
		var top := ground_y - 6.0
		var poly := PackedVector2Array()
		var n: int = wd.h.size()
		for i in n:
			poly.append(Vector2(wd.x0 + i * COL, top + _surface(wd, i)))
		poly.append(Vector2(wd.x1, ground_y + 2))
		poly.append(Vector2(wd.x0, ground_y + 2))
		layer.draw_colored_polygon(poly, Color(col, 0.45))
		layer.draw_polyline(poly.slice(0, n), Color(1, 1, 1, 0.55), 1.0)

func _draw_bridges(layer: Node2D) -> void:
	var view := view_rect()
	for wd in waters:
		if not wd.kind in ["river", "lava"] or wd.x1 < view.position.x or wd.x0 > view.end.x:
			continue
		var x0: float = wd.x0 - 8.0
		var x1: float = wd.x1 + 8.0
		var sag := 3.0
		var pts := PackedVector2Array()
		var k := 0
		var x := x0
		while x < x1:
			var t := (x - x0) / (x1 - x0)
			var y := ground_y - 2.0 + sin(t * PI) * sag * 0.3
			layer.draw_rect(Rect2(x, y, 5.0, 4.0), Color("#8b6238") if k % 2 == 0 else Color("#7a5232"))
			layer.draw_rect(Rect2(x, y + 3, 5.0, 1.0), Color("#4a3426"))
			k += 1
			x += 5.5
		for px in [x0, x1]:
			layer.draw_rect(Rect2(px - 1.5, ground_y - 16, 3, 16), Color("#5e3d24"))
		for i in 13:
			var t := float(i) / 12.0
			pts.append(Vector2(lerpf(x0, x1, t), ground_y - 15 + sin(t * PI) * 6.0 + sin(WeatherState.clock * 2.0 + t * 6.0) * WeatherState.wind * 0.8))
		layer.draw_polyline(pts, Color("#c9a66b"), 1.0)

# --- grass, trees, lamps ---

func _surfaces() -> Array:
	var out := [[0.0, float(map.width), ground_y]]
	for p in map.platforms:
		out.append([float(p[0]), float(p[0]) + float(p[2]), float(p[1])])
	return out

func _draw_grass(layer: Node2D) -> void:
	var view := view_rect()
	var t := WeatherState.clock
	var feet: Array = []
	for a in get_tree().get_nodes_in_group("actors") + get_tree().get_nodes_in_group("mobs"):
		if a.visible and view.has_point(a.global_position):
			feet.append(a.global_position)
	var grass_col := Color(map.get("theme", {}).get("plat_top", "#6cc552"))
	if not snowy:
		for s in _surfaces():
			var x: float = maxf(s[0] + 2.0, view.position.x)
			var x_end: float = minf(s[1] - 2.0, view.end.x)
			var y: float = s[2]
			var grass_here := grass_col if y < ground_y - 1 else Color(map.get("theme", {}).get("grass", "#5fb548"))
			x = floor(x / BLADE_GAP) * BLADE_GAP
			while x <= x_end:
				if y >= ground_y - 1 and _in_water(x, 2.0):
					x += BLADE_GAP
					continue
				var seed := fmod(x * 12.9898, 1.0)
				var hgt := 3.0 + fmod(x * 7.31, 3.5)
				var lean := WeatherState.gust(x * 0.03) * 3.0 + sin(t * 2.2 + x * 0.08) * 0.6
				for f in feet:
					var d: float = x - f.x
					if absf(d) < 9.0 and absf(f.y - y) < 4.0:
						lean += signf(d) * (9.0 - absf(d)) * 0.5
				var tip := Vector2(x + lean, y - hgt + absf(lean) * 0.2)
				layer.draw_line(Vector2(x, y + 1), tip, grass_here.darkened(0.15 + seed * 0.2), 1.0)
				if int(x) % 3 == 0:
					layer.draw_line(Vector2(x + 1.5, y + 1), Vector2(x + 1.5 + lean * 0.7, y - hgt * 0.7), grass_here.lightened(0.1), 1.0)
				x += BLADE_GAP
	_draw_snow(layer, view)
	_draw_lamps(layer, view)

func _draw_lamps(layer: Node2D, view: Rect2) -> void:
	var lit := clampf(Lighting.darkness * 1.6 - 0.15, 0.0, 1.0)
	for l in lamps:
		var p: Vector2 = l.pos
		if not view.has_point(p):
			continue
		layer.draw_rect(Rect2(p.x - 1, p.y - 24, 2, 24), Color("#3a3a44"))
		layer.draw_rect(Rect2(p.x - 3, p.y - 30, 6, 7), Color("#2a2a33"))
		layer.draw_rect(Rect2(p.x - 2, p.y - 29, 4, 5), Color("#5a4a2a").lerp(Color("#ffe9a8"), lit))
		if lit > 0.05:
			layer.draw_circle(Vector2(p.x, p.y - 26.5), 6.0, Color(1.0, 0.85, 0.5, 0.18 * lit))

func _draw_trees(layer: Node2D) -> void:
	var view := view_rect()
	var kind := String(map.get("trees", "oak"))
	for tr in _trees:
		var x: float = tr.x
		if x < view.position.x - 40 or x > view.end.x + 40:
			continue
		var s: float = tr.s * (0.75 if tr.far else 1.0)
		var dark := 0.35 if tr.far else 0.1
		var sway := WeatherState.gust(x * 0.02) * 4.0 * s
		var base := Vector2(x, ground_y)
		match kind:
			"pine":
				layer.draw_rect(Rect2(x - 2 * s, ground_y - 12 * s, 4 * s, 12 * s), Color("#4a3a2a").darkened(dark))
				for k in 4:
					var w := (20.0 - k * 4.0) * s
					var y := ground_y - (12.0 + k * 11.0) * s
					var off := sway * (0.3 + k * 0.25)
					layer.draw_colored_polygon(PackedVector2Array([Vector2(x - w, y), Vector2(x + off, y - 16 * s), Vector2(x + w, y)]), Color("#2f5a48").darkened(dark))
					if snowy:
						layer.draw_colored_polygon(PackedVector2Array([Vector2(x - w * 0.6, y - 5 * s), Vector2(x + off, y - 16 * s), Vector2(x + w * 0.6, y - 5 * s)]), Color(0.95, 0.97, 1.0, 0.9).darkened(dark * 0.5))
			"dead":
				layer.draw_line(base, base + Vector2(sway * 0.3, -40 * s), Color("#3a2a24").darkened(dark), 3.0 * s)
				for k in 3:
					var by := -18.0 - k * 8.0
					var side := 1.0 if k % 2 == 0 else -1.0
					layer.draw_line(base + Vector2(sway * 0.15, by * s), base + Vector2(side * 12 * s + sway * 0.5, (by - 8) * s), Color("#3a2a24").darkened(dark), 2.0 * s)
			_:
				layer.draw_rect(Rect2(x - 3 * s, ground_y - 26 * s, 6 * s, 26 * s), Color("#6b4a2b").darkened(dark))
				var leaf := Color(map.get("theme", {}).get("hills", ["#8fcf86", "#8fcf86"])[1]).darkened(0.25 + dark)
				for k in 4:
					var c := Vector2(x + sway * (0.6 + k * 0.15) + [-10.0, 9.0, -3.0, 4.0][k] * s, ground_y - [30.0, 32.0, 42.0, 36.0][k] * s)
					layer.draw_circle(c, [12.0, 11.0, 12.0, 9.0][k] * s, leaf.lightened(k * 0.04))
				layer.draw_circle(Vector2(x + sway - 4 * s, ground_y - 44 * s), 5.0 * s, leaf.lightened(0.2))

# --- snow ---

func _tick_snow(delta: float) -> void:
	if snow.is_empty():
		return
	# Snow builds up only while it's snowing (trenches fill back in the same way).
	var falling := weather != null and weather.state == "snow"
	var add := float(env_cfg.get("snow_build_rate", 0.15)) * weather.rain * delta if falling else 0.0
	var cap := float(env_cfg.get("snow_max", 5.0))
	if add > 0.0:
		for key in snow:
			var sd: Dictionary = snow[key]
			var h: PackedFloat32Array = sd.h
			for i in h.size():
				h[i] = minf(h[i] + add, cap)
			sd.h = h
	# Feet press the snow flat; what's pushed aside piles up a little at the trench edges.
	var floor_h := maxf(cap - float(env_cfg.get("footprint_depth", 3.0)), 0.0) * 0.2
	for a in get_tree().get_nodes_in_group("actors") + get_tree().get_nodes_in_group("mobs"):
		if not a.visible or not a.is_on_floor():
			continue
		var p: Vector2 = a.global_position
		for key in snow:
			var sd: Dictionary = snow[key]
			if absf(p.y - sd.y) > 3.0 or p.x < sd.x0 or p.x > sd.x1:
				continue
			var h: PackedFloat32Array = sd.h
			var c := int((p.x - sd.x0) / COL)
			var half := 2 if a.is_in_group("actors") else maxi(int(a.size.x / 4.0), 2)
			for i in range(c - half, c + half + 1):
				if i >= 0 and i < h.size() and h[i] > floor_h:
					var pushed := h[i] - floor_h
					h[i] = floor_h
					for e in [c - half - 1, c + half + 1]:
						if e >= 0 and e < h.size():
							h[e] = minf(h[e] + pushed * 0.15, cap + 1.0)
			sd.h = h

func _draw_snow(layer: Node2D, view: Rect2) -> void:
	for key in snow:
		var sd: Dictionary = snow[key]
		if sd.x1 < view.position.x or sd.x0 > view.end.x:
			continue
		var h: PackedFloat32Array = sd.h
		var i0 := maxi(int((view.position.x - sd.x0) / COL), 0)
		var i1 := mini(int((view.end.x - sd.x0) / COL) + 1, h.size() - 1)
		var poly := PackedVector2Array()
		poly.append(Vector2(sd.x0 + i0 * COL, sd.y + 1))
		for i in range(i0, i1 + 1):
			var x: float = sd.x0 + i * COL
			if key == "g" and _in_water(x):
				poly.append(Vector2(x, sd.y + 1))
				continue
			poly.append(Vector2(x, sd.y - h[i]))
		poly.append(Vector2(sd.x0 + i1 * COL, sd.y + 1))
		if poly.size() >= 3:
			layer.draw_colored_polygon(poly, Color("#f4f8fc"))
			layer.draw_polyline(poly.slice(1, poly.size() - 1), Color("#ffffff"), 1.0)

## Snow depth at x on the surface at y (tests).
func snow_depth(x: float, y: float) -> float:
	for key in snow:
		var sd: Dictionary = snow[key]
		if absf(y - sd.y) < 3.0 and x >= sd.x0 and x <= sd.x1:
			return sd.h[clampi(int((x - sd.x0) / COL), 0, sd.h.size() - 1)]
	return 0.0

# --- rain and snow ---

func _tick_precip(delta: float) -> void:
	if weather == null:
		return
	var view := view_rect()
	var is_snow := weather.state == "snow" or (snowy and weather.rain > 0.0)
	var target := int(weather.rain * (160.0 if not is_snow else 120.0))
	while drops.size() < target:
		drops.append({"p": Vector2(_rng.randf_range(view.position.x, view.end.x), view.position.y - _rng.randf_range(0, 120)), "kind": "snow" if is_snow else "rain", "ph": _rng.randf() * TAU})
	if drops.size() > target:
		drops.resize(target)
	var wind := WeatherState.wind
	for d in drops:
		var p: Vector2 = d.p
		if d.kind == "rain":
			p += Vector2(wind * 140.0, 420.0) * delta
		else:
			p += Vector2(wind * 45.0 + sin(WeatherState.clock * 1.5 + d.ph) * 12.0, 38.0) * delta
		var floor_y := _floor_under(p.x, p.y)
		if p.y >= floor_y or p.x < view.position.x - 60 or p.x > view.end.x + 60:
			if p.y >= floor_y and d.kind == "rain" and _layers.has("sky_fx") and _rng.randf() < 0.25:
				d.splash = 0.15
				d.sp = Vector2(p.x, floor_y)
			p = Vector2(_rng.randf_range(view.position.x, view.end.x), view.position.y - _rng.randf_range(0, 40))
		d.p = p
		if d.has("splash"):
			d.splash = float(d.splash) - delta

func _floor_under(x: float, y: float) -> float:
	var best := ground_y
	for p in map.platforms:
		if x >= float(p[0]) and x <= float(p[0]) + float(p[2]) and float(p[1]) >= y - 2.0 and float(p[1]) < best:
			best = float(p[1])
	return best

func _draw_sky_fx(layer: Node2D) -> void:
	var wind := WeatherState.wind
	for d in drops:
		var p: Vector2 = d.p
		if d.kind == "rain":
			layer.draw_line(p, p - Vector2(wind * 140.0, 420.0) * 0.022, Color(0.75, 0.85, 1.0, 0.55), 1.0)
		else:
			layer.draw_rect(Rect2(p - Vector2(1.6, 1.6), Vector2(3.2, 3.2)), Color(0.55, 0.65, 0.8, 0.5))
			layer.draw_rect(Rect2(p - Vector2(1.1, 1.1), Vector2(2.2, 2.2)), Color(1, 1, 1, 0.95))
		if d.has("splash") and float(d.splash) > 0.0:
			var sp: Vector2 = d.sp
			var a := float(d.splash) / 0.15
			layer.draw_line(sp, sp + Vector2(-2, -2 * a), Color(0.8, 0.9, 1.0, a), 1.0)
			layer.draw_line(sp, sp + Vector2(2, -2 * a), Color(0.8, 0.9, 1.0, a), 1.0)
