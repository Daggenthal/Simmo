class_name Doll
extends RefCounted
## Paper-doll character drawn in code at twice the world's pixel density (1 unit = 0.5 world px),
## MapleStory style: chibi head, big eyes. Layers back to front: cape, back hair, back arm, legs,
## shoes, skirt, torso, head, face, front hair, hat, scarf, front arm. Weapons go on top (Actor).
##
## Living bits:
##   hair, capes, scarves, skirts and bandana tails are spring chains (verlet): they trail behind
##   when you move, bounce when you land and blow with WeatherState.wind;
##   eyes blink every 2 to 6 s (sometimes twice);
##   legs and arms swing with walking speed, legs tuck in the air, the body breathes when idle;
##   nearby lights (Lighting) put a colored rim light on the side of the head, hair and body facing them.

const U := 0.5
const GRAVITY := 520.0

var look: Dictionary = {}
var origin := Vector2.ZERO
var facing := 1
var t := 0.0
var walk := 0.0
var speed_frac := 0.0
var airborne := false
var vy := 0.0
var lights: Array = []
var blink_t := 3.0
var blink_left := 0.0
var _double := false
var chains: Dictionary = {}
var _started := false

func _init(lk: Dictionary = {}) -> void:
	set_look(lk)
	blink_t = randf_range(1.5, 5.0)

## Fill in missing keys and map the old look format (shirt, pants, hair_style).
static func normalize(lk: Dictionary) -> Dictionary:
	var d := {"gender": "male", "skin": "#f2c27b", "face": "calm", "eye_color": "#2a2a3a", "hair": "short", "hair_color": "#4a3426",
		"top": "tee", "top_color": "#c0392b", "bottom": "pants", "bottom_color": "#3b4a6b", "shoes": "boots", "shoes_color": "#4a3426",
		"hat": "none", "hat_color": "#9aa3ad", "cape": "none", "cape_color": "#c0392b"}
	if lk.has("shirt"):
		d.top_color = lk.shirt
	if lk.has("pants"):
		d.bottom_color = lk.pants
	if lk.has("hair_style"):
		d.hair = lk.hair_style
	if lk.get("hair", "") is String and String(lk.get("hair", "")).begins_with("#"):
		d.hair_color = lk.hair
	for k in lk:
		if d.has(k) and not (k == "hair" and String(lk[k]).begins_with("#")):
			d[k] = lk[k]
	if String(d.hat) == "":
		d.hat = "none"
	if String(d.hat) == "band":
		d.hat = "headband"
	return d

func set_look(lk: Dictionary) -> void:
	look = normalize(lk)
	_build_chains()

func c(key: String) -> Color:
	return Color(look.get(key, "#ff00ff"))

# --- spring chains ---

## anchor: units, for facing right (x mirrors). rest: hanging direction. stiff: pull toward rest (0..1).
func _chain(name: String, anchor: Vector2, segs: int, seg: float, rest: Vector2, stiff: float, weight := 1.0) -> void:
	chains[name] = {"anchor": anchor, "segs": segs, "seg": seg, "rest": rest.normalized(), "stiff": stiff, "weight": weight,
		"pts": PackedVector2Array(), "prev": PackedVector2Array(), "phase": randf() * TAU}

func _build_chains() -> void:
	chains = {}
	match String(look.hair):
		"long":
			_chain("hair_a", Vector2(-9, -56), 6, 5.0, Vector2(-0.25, 1), 0.06)
			_chain("hair_b", Vector2(-3, -60), 6, 5.0, Vector2(-0.35, 1), 0.06)
		"ponytail":
			_chain("hair_a", Vector2(-12, -60), 5, 4.5, Vector2(-0.8, 0.7), 0.1)
		"twintails":
			_chain("hair_a", Vector2(-11, -58), 5, 4.5, Vector2(-0.3, 1), 0.1)
			_chain("hair_b", Vector2(10, -58), 5, 4.5, Vector2(0.3, 1), 0.1)
		"side_tail":
			_chain("hair_a", Vector2(10, -58), 5, 4.5, Vector2(0.25, 1), 0.1)
		"long_tied":
			_chain("hair_a", Vector2(-12, -54), 4, 4.0, Vector2(-0.4, 1), 0.12)
	match String(look.hat):
		"bandana":
			_chain("hat_tail", Vector2(-13, -60), 3, 4.0, Vector2(-1, 0.4), 0.06, 0.5)
		"wizard":
			_chain("hat_tip", Vector2(-2, -82), 3, 4.0, Vector2(-0.9, -0.2), 0.25, 0.4)
	match String(look.cape):
		"cape":
			_chain("cape_a", Vector2(-7, -36), 6, 4.5, Vector2(-0.3, 1), 0.06)
			_chain("cape_b", Vector2(3, -37), 6, 4.5, Vector2(-0.15, 1), 0.06)
		"scarf":
			_chain("scarf", Vector2(-6, -40), 4, 4.5, Vector2(-1, 0.25), 0.05, 0.6)
	match String(look.bottom):
		"skirt":
			_chain("hem_a", Vector2(-8, -22), 2, 4.0, Vector2(-0.25, 1), 0.3)
			_chain("hem_b", Vector2(8, -22), 2, 4.0, Vector2(0.25, 1), 0.3)
		"long_skirt":
			_chain("hem_a", Vector2(-8, -24), 4, 5.0, Vector2(-0.15, 1), 0.2)
			_chain("hem_b", Vector2(8, -24), 4, 5.0, Vector2(0.15, 1), 0.2)
	if String(look.top) == "robe" and not chains.has("hem_a"):
		_chain("hem_a", Vector2(-9, -24), 4, 5.0, Vector2(-0.15, 1), 0.2)
		_chain("hem_b", Vector2(9, -24), 4, 5.0, Vector2(0.15, 1), 0.2)
	# Lay the chains out right away, so a look change can be drawn before the next update.
	_reset_chains()

func _anchor_world(ch: Dictionary) -> Vector2:
	var a: Vector2 = ch.anchor
	return origin + Vector2(a.x * facing, a.y + _bob()) * U

func _rest_dir(ch: Dictionary) -> Vector2:
	var r: Vector2 = ch.rest
	return Vector2(r.x * facing, r.y)

func _reset_chains() -> void:
	for name in chains:
		var ch: Dictionary = chains[name]
		var pts := PackedVector2Array()
		var p := _anchor_world(ch)
		for i in int(ch.segs) + 1:
			pts.append(p)
			p += _rest_dir(ch) * float(ch.seg) * U
		ch.pts = pts
		ch.prev = pts.duplicate()

func _simulate(ch: Dictionary, delta: float) -> void:
	var pts: PackedVector2Array = ch.pts
	var prev: PackedVector2Array = ch.prev
	var seg := float(ch.seg) * U
	var wind := Vector2(WeatherState.gust(float(ch.phase)) * 650.0, 0.0)
	var g := Vector2(0, GRAVITY * float(ch.weight))
	var dt2 := delta * delta
	pts[0] = _anchor_world(ch)
	for i in range(1, pts.size()):
		var p := pts[i]
		var v := (p - prev[i]) * 0.93
		prev[i] = p
		p += v + (g + wind * (0.5 + 0.5 * float(i) / pts.size())) * dt2
		# Spring toward the resting shape so hair keeps its style.
		var target := pts[i - 1] + _rest_dir(ch) * seg
		p += (target - p) * float(ch.stiff)
		pts[i] = p
	for _k in 3:
		for i in range(1, pts.size()):
			var d := pts[i] - pts[i - 1]
			var l := d.length()
			if l > 0.001:
				pts[i] = pts[i - 1] + d / l * seg
	ch.pts = pts
	ch.prev = prev

## Advance animation and physics. pos: the actor's feet in world space.
func update(delta: float, pos: Vector2, vel: Vector2, on_floor: bool, face: int) -> void:
	var jumped := pos.distance_to(origin) > 40.0
	origin = pos
	if face != facing:
		facing = face
	t += delta
	vy = vel.y
	airborne = not on_floor
	var target_speed := clampf(absf(vel.x) / 110.0, 0.0, 1.0) if on_floor else 0.0
	speed_frac = move_toward(speed_frac, target_speed, delta * 6.0)
	if on_floor and absf(vel.x) > 8.0:
		walk += delta * (6.0 + 8.0 * speed_frac)
	# Blinks, spaced out: every 2 to 6 s, sometimes a quick double.
	blink_left = maxf(blink_left - delta, 0.0)
	blink_t -= delta
	if blink_t <= 0.0:
		blink_left = 0.12
		if _double:
			_double = false
			blink_t = randf_range(2.0, 6.0)
		elif randf() < 0.15:
			_double = true
			blink_t = 0.22
		else:
			blink_t = randf_range(2.0, 6.0)
	if not _started or jumped:
		_started = true
		_reset_chains()
	for name in chains:
		_simulate(chains[name], minf(delta, 1.0 / 30.0))
	lights = Lighting.near(pos + Vector2(0, -16), 2)

func is_blinking() -> bool:
	return blink_left > 0.0 and String(look.face) != "cheery"

func _bob() -> float:
	return sin(t * 2.2) * 0.6 * (1.0 - speed_frac) if not airborne else 0.0

func _u(world: Vector2) -> Vector2:
	return (world - origin) / U

# --- drawing ---

## Body, in the canvas item's local space (feet at 0,0). hand: world-local position of the weapon hand.
## at / zoom place and enlarge it for previews (character creator, class cards).
func draw(ci: CanvasItem, hand: Vector2, at := Vector2.ZERO, zoom := 1.0) -> void:
	ci.draw_set_transform(at, 0.0, Vector2(U, U) * zoom)
	var f := float(facing)
	var bob := _bob()
	var swing := sin(walk) * 0.55 * speed_frac
	_draw_cape(ci, f)
	_draw_back_hair(ci, f)
	# Back arm
	var sh_b := Vector2(-f * 7.0, -36 + bob)
	var hand_b := sh_b + Vector2(sin(-swing * 0.9 - 0.15) * 13.0 * f, cos(swing * 0.9) * 13.0)
	if airborne:
		hand_b = sh_b + Vector2(-f * 8.0, -6.0)
	_limb(ci, sh_b, hand_b, c("top_color").darkened(0.25), c("skin").darkened(0.15), 5.0, _long_sleeves())
	# Legs
	var hip := Vector2(0, -20 + bob * 0.3)
	for side: float in [-1.0, 1.0]:
		var a := swing * side
		if airborne:
			a = (0.45 if side > 0 else -0.35) * (1.0 if vy < 0.0 else 0.6)
		var knee := hip + Vector2(side * 2.5 * f, 0) + Vector2(sin(a) * 8.0 * f, cos(a) * 8.0)
		var foot := knee + Vector2(sin(a * (0.4 if not airborne else 1.6)) * 8.0 * f, 8.0)
		if not airborne:
			foot.y = minf(foot.y, -1.0)
		var leg_col := c("bottom_color") if String(look.bottom) in ["pants"] else c("skin")
		var top_col := c("bottom_color")
		var shade := 0.12 if side < 0 else 0.0
		ci.draw_line(hip + Vector2(side * 2.5 * f, 0), knee, top_col.darkened(shade), 6.0)
		ci.draw_line(knee, foot, leg_col.darkened(shade), 5.5)
		_shoe(ci, foot, f, shade)
	_draw_skirt(ci, f, bob)
	_draw_torso(ci, f, bob)
	_draw_head(ci, f, bob)
	_draw_front_hair(ci, f, bob)
	_draw_hat(ci, f, bob)
	if String(look.cape) == "scarf":
		ci.draw_rect(Rect2(-7, -41 + bob, 14, 4), c("cape_color"))
		ci.draw_rect(Rect2(-7, -38 + bob, 14, 1), c("cape_color").darkened(0.3))
	# Front arm to the weapon hand.
	var sh_f := Vector2(f * 6.0, -36 + bob)
	_limb(ci, sh_f, _u(origin + hand), c("top_color"), c("skin"), 5.0, _long_sleeves())
	_draw_rim(ci, f, bob)
	ci.draw_set_transform(Vector2.ZERO)

## The hand over the weapon grip (drawn after the weapon).
func draw_hand(ci: CanvasItem, hand: Vector2, at := Vector2.ZERO, zoom := 1.0) -> void:
	ci.draw_set_transform(at, 0.0, Vector2(U, U) * zoom)
	ci.draw_circle(_u(origin + hand), 2.6, c("skin"))
	ci.draw_set_transform(Vector2.ZERO)

func _long_sleeves() -> bool:
	return String(look.top) in ["jacket", "robe", "hoodie", "tunic"]

func _limb(ci: CanvasItem, a: Vector2, b: Vector2, sleeve: Color, skin: Color, w: float, long_sleeve: bool) -> void:
	var mid := a.lerp(b, 0.55 if not long_sleeve else 0.85)
	ci.draw_line(a, mid, sleeve, w + 0.5)
	ci.draw_line(mid, b, skin, w - 0.5)
	ci.draw_circle(b, 2.4, skin)

func _shoe(ci: CanvasItem, foot: Vector2, f: float, shade: float) -> void:
	var col := c("shoes_color").darkened(shade)
	match String(look.shoes):
		"sandals":
			ci.draw_rect(Rect2(foot.x - 3.5 + f * 1.0, foot.y - 1.0, 7.0, 2.0), col)
			ci.draw_line(foot + Vector2(-1, -3), foot + Vector2(f * 2, -1), col, 1.0)
		"sneakers":
			ci.draw_rect(Rect2(foot.x - 3.5 + f * 1.5, foot.y - 3.0, 8.0, 3.0), col)
			ci.draw_rect(Rect2(foot.x - 3.5 + f * 1.5, foot.y - 1.0, 8.0, 1.0), Color.WHITE)
		_:
			ci.draw_rect(Rect2(foot.x - 3.5 + f * 1.5, foot.y - 5.0, 8.0, 5.0), col)
			ci.draw_rect(Rect2(foot.x - 3.5 + f * 1.5, foot.y - 1.0, 8.0, 1.0), col.darkened(0.35))

func _poly_from_chains(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for p in a:
		poly.append(_u(p))
	for i in range(b.size() - 1, -1, -1):
		poly.append(_u(b[i]))
	return poly

func _draw_cape(ci: CanvasItem, f: float) -> void:
	if chains.has("cape_a"):
		var poly := _poly_from_chains(chains.cape_a.pts, chains.cape_b.pts)
		if poly.size() >= 3:
			ci.draw_colored_polygon(poly, c("cape_color").darkened(0.15))
			ci.draw_polyline(poly, c("cape_color").darkened(0.4), 1.0)
	if chains.has("scarf"):
		var line := PackedVector2Array()
		for p in chains.scarf.pts:
			line.append(_u(p))
		ci.draw_polyline(line, c("cape_color"), 4.0)
		ci.draw_polyline(line, c("cape_color").darkened(0.3), 1.0)

func _strand(ci: CanvasItem, pts: PackedVector2Array, w0: float, col: Color) -> void:
	for i in range(1, pts.size()):
		var w := lerpf(w0, w0 * 0.35, float(i) / pts.size())
		ci.draw_line(_u(pts[i - 1]), _u(pts[i]), col, w)
		ci.draw_circle(_u(pts[i]), w * 0.5, col)

func _draw_back_hair(ci: CanvasItem, f: float) -> void:
	var hc := c("hair_color")
	for name in ["hair_a", "hair_b"]:
		if chains.has(name) and not _front_chain(name):
			var w := 9.0 if String(look.hair) == "long" else 6.0
			_strand(ci, chains[name].pts, w + 1.5, hc.darkened(0.35))
			_strand(ci, chains[name].pts, w, hc.darkened(0.08))
	match String(look.hair):
		"long":
			ci.draw_rect(Rect2(-f * 13.0 - (0.0 if f > 0 else 0.0) - 3.0, -58, 8, 18), hc.darkened(0.1))
		"bob":
			ci.draw_rect(Rect2(-14, -56, 28, 16), hc.darkened(0.1))

## Tails that hang on the near side of the head are drawn over it, not behind.
func _front_chain(name: String) -> bool:
	var style := String(look.hair)
	return (style == "twintails" and name == "hair_b") or (style == "side_tail" and name == "hair_a")

func _draw_skirt(ci: CanvasItem, f: float, bob: float) -> void:
	if not chains.has("hem_a"):
		if String(look.bottom) == "shorts":
			ci.draw_rect(Rect2(-8, -21 + bob * 0.3, 16, 7), c("bottom_color"))
		return
	var col := c("top_color") if String(look.top) == "robe" else c("bottom_color")
	var a: PackedVector2Array = chains.hem_a.pts
	var b: PackedVector2Array = chains.hem_b.pts
	var poly := PackedVector2Array()
	for p in a:
		poly.append(_u(p))
	for i in range(b.size() - 1, -1, -1):
		poly.append(_u(b[i]))
	ci.draw_colored_polygon(poly, col)
	ci.draw_line(_u(a[a.size() - 1]), _u(b[b.size() - 1]), col.darkened(0.3), 1.5)
	if String(look.top) == "robe":
		ci.draw_line(_u(a[a.size() - 1]), _u(b[b.size() - 1]), Color("#e8c34a"), 1.0)

func _draw_torso(ci: CanvasItem, f: float, bob: float) -> void:
	var col := c("top_color")
	var y0 := -39.0 + bob
	var body := PackedVector2Array([Vector2(-8, y0), Vector2(8, y0), Vector2(9, -19 + bob * 0.3), Vector2(-9, -19 + bob * 0.3)])
	match String(look.top):
		"vest":
			ci.draw_colored_polygon(body, Color("#ecf0f1"))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-8, y0), Vector2(-1 * f, y0), Vector2(1 * f, -19), Vector2(-9, -19)]) if f > 0 else PackedVector2Array([Vector2(1, y0), Vector2(8, y0), Vector2(9, -19), Vector2(-1, -19)]), col)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(f * 3, y0), Vector2(f * 8, y0), Vector2(f * 9, -19), Vector2(f * 5, -19)]), col)
			for k in 3:
				ci.draw_circle(Vector2(f * 4.0, y0 + 5 + k * 5), 0.8, Color("#e8c34a"))
		_:
			ci.draw_colored_polygon(body, col)
	ci.draw_line(Vector2(-f * 8.0, y0 + 1), Vector2(-f * 9.0, -20), col.darkened(0.2), 2.0)
	match String(look.top):
		"tee":
			ci.draw_line(Vector2(f * 0.5 - 3, y0 + 0.5), Vector2(f * 0.5 + 3, y0 + 0.5), col.darkened(0.3), 1.0)
		"tunic":
			ci.draw_rect(Rect2(-9, -24 + bob * 0.5, 18, 3), Color("#4a3426"))
			ci.draw_rect(Rect2(f * 2 - 1.5, -24 + bob * 0.5, 3, 3), Color("#e8c34a"))
			ci.draw_rect(Rect2(-9.5, -21 + bob * 0.3, 19, 4), col.darkened(0.1))
		"jacket":
			ci.draw_rect(Rect2(f * 3 - 1.5, y0, 3, 20), Color("#ecf0f1"))
			ci.draw_line(Vector2(f * 1.5, y0), Vector2(f * 3.5, y0 + 7), col.darkened(0.35), 1.0)
			ci.draw_line(Vector2(f * 4.5, y0), Vector2(f * 2.5, y0 + 7), col.darkened(0.35), 1.0)
		"robe":
			ci.draw_line(Vector2(f * 2, y0), Vector2(f * 2, -19), Color("#e8c34a"), 1.0)
			ci.draw_rect(Rect2(-9, -25 + bob * 0.5, 18, 2), Color("#e8c34a"))
		"hoodie":
			ci.draw_circle(Vector2(-f * 6.0, y0 + 1), 5.5, col.darkened(0.15))
			ci.draw_rect(Rect2(f * 1 - 4, -28 + bob * 0.5, 8, 5), col.darkened(0.15))
			ci.draw_line(Vector2(f * 2, y0 + 1), Vector2(f * 2, y0 + 7), Color("#ecf0f1"), 0.8)
			ci.draw_line(Vector2(f * 5, y0 + 1), Vector2(f * 5, y0 + 7), Color("#ecf0f1"), 0.8)

func _draw_head(ci: CanvasItem, f: float, bob: float) -> void:
	var skin := c("skin")
	var hc := Vector2(f * 1.0, -51 + bob)
	ci.draw_rect(Rect2(-2.5, -42 + bob, 5, 4), skin.darkened(0.12))
	ci.draw_circle(hc, 14.0, skin)
	ci.draw_circle(hc + Vector2(-f * 9.5, 2), 2.8, skin.darkened(0.08))
	# Face, 3/4 view toward facing.
	var near := hc + Vector2(f * 6.5, 1)
	var far := hc + Vector2(f * -1.0, 1)
	var face := String(look.face)
	var eye := c("eye_color")
	var big := 1.25 if face == "bright" else 1.0
	for e in [[far, 0.85], [near, 1.0]]:
		var p: Vector2 = e[0]
		var s: float = e[1] * big
		if face == "cheery":
			ci.draw_arc(p + Vector2(0, 1), 2.4 * s, PI + 0.3, TAU - 0.3, 6, Color("#2a2a3a"), 1.3)
			continue
		if is_blinking():
			ci.draw_line(p + Vector2(-2.4 * s, 0.5), p + Vector2(2.4 * s, 0.5), Color("#2a2a3a"), 1.2)
			continue
		ci.draw_rect(Rect2(p.x - 2.6 * s, p.y - 3.4 * s, 5.2 * s, 6.4 * s), Color.WHITE)
		ci.draw_rect(Rect2(p.x - 1.6 * s + f * 0.8, p.y - 2.6 * s, 3.4 * s, 5.4 * s), eye)
		ci.draw_rect(Rect2(p.x - 0.7 * s + f * 1.0, p.y - 1.2 * s, 1.6 * s, 2.6 * s), Color("#141414"))
		ci.draw_rect(Rect2(p.x - 1.4 * s + f * 0.6, p.y - 2.4 * s, 1.2, 1.2), Color(1, 1, 1, 0.95))
		if face == "sleepy":
			ci.draw_rect(Rect2(p.x - 2.8 * s, p.y - 3.6 * s, 5.6 * s, 3.0 * s), c("skin"))
			ci.draw_line(p + Vector2(-2.8 * s, -0.6 * s), p + Vector2(2.8 * s, -0.6 * s), Color("#2a2a3a"), 1.0)
		else:
			ci.draw_line(p + Vector2(-2.6 * s, -3.4 * s), p + Vector2(2.6 * s, -3.4 * s), Color("#2a2a3a"), 1.0)
	# Brows
	var brow := c("hair_color").darkened(0.2)
	if face == "fierce":
		ci.draw_line(far + Vector2(-2.5, -6), far + Vector2(2.5, -4.5), brow, 1.3)
		ci.draw_line(near + Vector2(2.5, -6), near + Vector2(-2.5, -4.5), brow, 1.3)
	else:
		ci.draw_line(far + Vector2(-2.2, -5.5), far + Vector2(2.2, -5.8), brow, 1.0)
		ci.draw_line(near + Vector2(-2.2, -5.8), near + Vector2(2.2, -5.5), brow, 1.0)
	# Mouth and blush
	var mouth := hc + Vector2(f * 3.5, 8.5)
	match face:
		"bright", "cheery":
			ci.draw_arc(mouth, 1.8, 0.2, PI - 0.2, 6, Color("#8a3a3a"), 1.2)
			ci.draw_circle(near + Vector2(f * 1.5, 4.5), 1.6, Color(1.0, 0.5, 0.55, 0.45))
			ci.draw_circle(far + Vector2(-f * 1.0, 4.5), 1.4, Color(1.0, 0.5, 0.55, 0.35))
		"fierce":
			ci.draw_line(mouth + Vector2(-1.8, 0), mouth + Vector2(1.8, -0.4), Color("#5a2a2a"), 1.0)
		_:
			ci.draw_line(mouth + Vector2(-1.4, 0), mouth + Vector2(1.4, 0), Color("#7a3a3a"), 1.0)

func _hair_cap(ci: CanvasItem, hc: Vector2, col: Color, low := 0.25) -> void:
	var pts := PackedVector2Array()
	for k in 13:
		var a := PI + low - (PI + 2.0 * low) * (1.0 - float(k) / 12.0)
		a = lerpf(PI + low, TAU - low, float(k) / 12.0)
		pts.append(hc + Vector2(cos(a), sin(a)) * 15.2)
	pts.append(hc + Vector2(14.0, -2))
	pts.append(hc + Vector2(-14.0, -2))
	ci.draw_colored_polygon(pts, col)

func _draw_front_hair(ci: CanvasItem, f: float, bob: float) -> void:
	var col := c("hair_color")
	var hc := Vector2(f * 1.0, -51 + bob)
	var style := String(look.hair)
	_hair_cap(ci, hc + Vector2(0, -0.5), col, 0.15)
	# Back of the head is covered by hair for every style (kept clear of the far eye).
	ci.draw_circle(hc + Vector2(-f * 9.0, -4), 8.0, col)
	ci.draw_rect(Rect2(hc.x - f * 14.0 - (0.0 if f > 0 else 0.0) - (0.0 if f > 0 else -0.0) - 2.5, hc.y - 6, 6, 12), col)
	match style:
		"spiky":
			for k in 5:
				var x := -12.0 + k * 5.5
				var tip := Vector2(x * f + f * (-3.0 + k * 0.5), -71 + bob + absf(k - 2) * 2.0)
				ci.draw_colored_polygon(PackedVector2Array([hc + Vector2(x * f - 3, -10), tip, hc + Vector2(x * f + 3, -10)]), col)
		"messy":
			for k in 6:
				var x := -13.0 + k * 5.0
				ci.draw_colored_polygon(PackedVector2Array([hc + Vector2(x * f, -10), hc + Vector2(x * f - f * 4, -17 - (k % 2) * 2), hc + Vector2(x * f + f * 4, -11)]), col)
		"swept":
			ci.draw_colored_polygon(PackedVector2Array([hc + Vector2(-f * 10, -12), hc + Vector2(f * 16, -9), hc + Vector2(f * 11, -1), hc + Vector2(f * 2, -6)]), col)
		"bowl":
			ci.draw_rect(Rect2(hc.x - 15, hc.y - 6, 30, 4), col)
		"bun":
			ci.draw_circle(hc + Vector2(-f * 7.0, -14), 6.0, col)
			ci.draw_circle(hc + Vector2(-f * 7.0, -14), 6.0, col.darkened(0.25))
			ci.draw_circle(hc + Vector2(-f * 7.0, -15), 4.5, col)
		"bob":
			ci.draw_rect(Rect2(hc.x + f * 7.0 - 3.0, hc.y - 5, 6, 12), col)
	if style in ["long", "ponytail", "twintails", "side_tail", "long_tied", "bob", "bun", "short"]:
		# Bangs: a zigzag fringe over the forehead.
		var fringe := PackedVector2Array([hc + Vector2(-f * 4, -12)])
		for k in 5:
			fringe.append(hc + Vector2(f * (-2 + k * 3.5), -5 - (k % 2) * 3))
		fringe.append(hc + Vector2(f * 15, -8))
		fringe.append(hc + Vector2(f * 12, -14))
		ci.draw_colored_polygon(fringe, col)
	if style == "twintails" or style == "side_tail" or style == "ponytail":
		var tie_name := "hair_a"
		if chains.has(tie_name):
			ci.draw_circle(_u(chains[tie_name].pts[0]), 2.2, Color("#e86aa0"))
	for name in ["hair_a", "hair_b"]:
		if chains.has(name) and _front_chain(name):
			_strand(ci, chains[name].pts, 7.5, col.darkened(0.35))
			_strand(ci, chains[name].pts, 6.0, col.darkened(0.05))
	# Shine
	ci.draw_arc(hc + Vector2(-f * 2, -6), 9.0, -PI * 0.85, -PI * 0.55, 6, col.lightened(0.35), 1.5)

func _draw_hat(ci: CanvasItem, f: float, bob: float) -> void:
	var col := c("hat_color")
	var hc := Vector2(f * 1.0, -51 + bob)
	match String(look.hat):
		"beanie":
			_hair_cap(ci, hc + Vector2(0, -2), col, -0.05)
			ci.draw_rect(Rect2(hc.x - 15, hc.y - 9, 30, 4), col.darkened(0.2))
			ci.draw_circle(hc + Vector2(0, -18), 2.5, col.lightened(0.3))
		"bandana":
			ci.draw_rect(Rect2(hc.x - 15, hc.y - 10, 30, 4), col)
			if chains.has("hat_tail"):
				_strand(ci, chains.hat_tail.pts, 3.0, col.darkened(0.15))
		"cap":
			_hair_cap(ci, hc + Vector2(0, -3), col, 0.1)
			ci.draw_colored_polygon(PackedVector2Array([hc + Vector2(f * 6, -8), hc + Vector2(f * 22, -6), hc + Vector2(f * 20, -4), hc + Vector2(f * 6, -5)]), col.darkened(0.25))
		"wizard":
			ci.draw_colored_polygon(PackedVector2Array([hc + Vector2(-18, -9), hc + Vector2(18, -9), hc + Vector2(16, -6), hc + Vector2(-16, -6)]), col.darkened(0.2))
			var tip := _u(chains.hat_tip.pts[0]) if chains.has("hat_tip") else hc + Vector2(-f * 3, -30)
			ci.draw_colored_polygon(PackedVector2Array([hc + Vector2(-11, -9), tip, hc + Vector2(11, -9)]), col)
			if chains.has("hat_tip"):
				_strand(ci, chains.hat_tip.pts, 4.0, col)
			ci.draw_rect(Rect2(hc.x - 11, hc.y - 12, 22, 3), Color("#e8c34a"))
		"headband":
			ci.draw_rect(Rect2(hc.x - 15, hc.y - 8, 30, 2.5), col)
		"ribbon":
			var p := hc + Vector2(-f * 8, -13)
			ci.draw_colored_polygon(PackedVector2Array([p, p + Vector2(-6, -4), p + Vector2(-6, 4)]), col)
			ci.draw_colored_polygon(PackedVector2Array([p, p + Vector2(6, -4), p + Vector2(6, 4)]), col)
			ci.draw_circle(p, 1.8, col.darkened(0.2))
		"helm":
			_hair_cap(ci, hc + Vector2(0, -1), col, -0.1)
			ci.draw_rect(Rect2(hc.x - 15, hc.y - 6, 30, 3), col.darkened(0.25))
			ci.draw_rect(Rect2(hc.x + f * 6 - 1, hc.y - 5, 2, 8), col.darkened(0.25))
			ci.draw_line(hc + Vector2(-f * 2, -16), hc + Vector2(-f * 9, -24), Color("#c43b3b"), 3.0)

## Rim light: a colored edge on the side of the head, hair and body that faces each nearby light.
func _draw_rim(ci: CanvasItem, f: float, bob: float) -> void:
	for l in lights:
		var d: Vector2 = l.dir
		var col: Color = l.color
		var s: float = l.strength
		var a := d.angle()
		var hc := Vector2(f * 1.0, -51 + bob)
		ci.draw_arc(hc, 14.5, a - 1.0, a + 1.0, 12, Color(col.lightened(0.3), 0.8 * s), 2.2)
		ci.draw_arc(hc, 12.5, a - 0.6, a + 0.6, 8, Color(col, 0.35 * s), 2.0)
		var side := signf(d.x) if absf(d.x) > 0.1 else f
		ci.draw_line(Vector2(side * 8.5, -38 + bob), Vector2(side * 9.5, -20), Color(col.lightened(0.2), 0.6 * s), 1.8)
		if d.y < 0.3:
			ci.draw_line(Vector2(side * 4.0, -19), Vector2(side * 4.0, -3), Color(col, 0.4 * s), 1.5)
		# A soft wash of the light's color over the lit side.
		ci.draw_circle(hc + d * 5.0, 10.0, Color(col, 0.10 * s))
