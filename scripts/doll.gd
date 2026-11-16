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
# MapleStory-style rendering: every part is a smooth shape (ellipses, capsules, rounded boxes)
# with an antialiased dark outline in a deep shade of its own color, a shadow side away from the
# light (back and below), and a highlight edge toward it. Units: 1 = 0.5 world px; at 1080p and up
# that's 1.5+ screen pixels per unit, so the fine lines here land on real pixels.

const OUTLINE := 1.1
const HEAD_R := 15.0

func _hc(f: float, bob: float) -> Vector2:
	return Vector2(f * 1.0, -52 + bob)

## Outline color for a fill: much darker, slightly cooler.
static func _ol(col: Color) -> Color:
	return Color(col.r * 0.28, col.g * 0.26, col.b * 0.34, 1.0)

static func _ellipse(c: Vector2, rx: float, ry: float, segs := 28, rot := 0.0) -> PackedVector2Array:
	var p := PackedVector2Array()
	for k in segs:
		var a := TAU * k / segs
		p.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	return p

## Rounded box.
static func _rrect(r: Rect2, rad: float, segs := 4) -> PackedVector2Array:
	rad = minf(rad, minf(r.size.x, r.size.y) / 2.0)
	var p := PackedVector2Array()
	var corners := [[r.end.x - rad, r.position.y + rad, -PI / 2.0], [r.end.x - rad, r.end.y - rad, 0.0], [r.position.x + rad, r.end.y - rad, PI / 2.0], [r.position.x + rad, r.position.y + rad, PI]]
	for cdef in corners:
		for k in segs + 1:
			var a: float = cdef[2] + (PI / 2.0) * k / segs
			p.append(Vector2(cdef[0], cdef[1]) + Vector2(cos(a), sin(a)) * rad)
	return p

## Tapered capsule from a (radius ra) to b (radius rb): limbs, sleeves, hair locks. Always convex.
static func _capsule(a: Vector2, b: Vector2, ra: float, rb: float, segs := 7) -> PackedVector2Array:
	var d := b - a
	if d.length() < 0.01:
		d = Vector2(0, 0.01)
	var ang := d.angle()
	var p := PackedVector2Array()
	for k in segs + 1:
		var t := PI / 2.0 + PI * k / segs
		p.append(a + Vector2(cos(ang + t), sin(ang + t)) * ra)
	for k in segs + 1:
		var t := -PI / 2.0 + PI * k / segs
		p.append(b + Vector2(cos(ang + t), sin(ang + t)) * rb)
	return p

## Fill, then outline (antialiased).
func _shape(ci: CanvasItem, poly: PackedVector2Array, fill: Color, line := OUTLINE) -> void:
	if poly.size() < 3:
		return
	ci.draw_colored_polygon(poly, fill)
	var closed := poly.duplicate()
	closed.append(poly[0])
	ci.draw_polyline(closed, _ol(fill), line, true)

## A filled shape with a shadow band on the side away from `light_dir` (unit), then the outline.
func _shaded(ci: CanvasItem, poly: PackedVector2Array, fill: Color, shade: PackedVector2Array, line := OUTLINE) -> void:
	ci.draw_colored_polygon(poly, fill)
	if shade.size() >= 3:
		ci.draw_colored_polygon(shade, fill.darkened(0.2))
	var closed := poly.duplicate()
	closed.append(poly[0])
	ci.draw_polyline(closed, _ol(fill), line, true)

## Body, in the canvas item's local space (feet at 0,0). hand: world-local position of the weapon hand.
## at / zoom place and enlarge it for previews (character creator, class cards).
func draw(ci: CanvasItem, hand: Vector2, at := Vector2.ZERO, zoom := 1.0) -> void:
	ci.draw_set_transform(at, 0.0, Vector2(U, U) * zoom)
	var f := float(facing)
	var bob := _bob()
	var swing := sin(walk) * 0.55 * speed_frac
	_draw_cape(ci, f)
	_draw_back_hair(ci, f, bob)
	# Back arm
	var sh_b := Vector2(-f * 6.5, -37 + bob)
	var hand_b := sh_b + Vector2(sin(-swing * 0.9 - 0.15) * 13.0 * f, cos(swing * 0.9) * 13.0)
	if airborne:
		hand_b = sh_b + Vector2(-f * 8.0, -6.0)
	_arm(ci, sh_b, hand_b, true)
	# Legs: back leg, then front leg.
	var hip := Vector2(0, -21 + bob * 0.3)
	for side: float in [-1.0, 1.0]:
		var a := swing * side
		if airborne:
			a = (0.45 if side > 0 else -0.35) * (1.0 if vy < 0.0 else 0.6)
		var top := hip + Vector2(side * 2.6 * f, 0)
		var knee := top + Vector2(sin(a) * 9.5 * f, cos(a) * 9.5)
		var foot := knee + Vector2(sin(a * (0.4 if not airborne else 1.6)) * 10.0 * f, 10.0)
		if not airborne:
			# Planted: soles on the ground (y 0); the swinging foot lifts a little.
			foot.y = -0.8 - maxf(0.0, -sin(walk) * side) * 2.5 * speed_frac
		_leg(ci, top, knee, foot, f, side < 0)
	_draw_skirt(ci, f, bob)
	_draw_torso(ci, f, bob)
	_draw_head(ci, f, bob)
	_draw_front_hair(ci, f, bob)
	_draw_hat(ci, f, bob)
	if String(look.cape) == "scarf":
		var sc := c("cape_color")
		_shape(ci, _rrect(Rect2(-8, -43 + bob, 16, 5), 2.2), sc)
		ci.draw_line(Vector2(-7, -40.5 + bob), Vector2(7, -40.5 + bob), sc.darkened(0.25), 1.0, true)
	# Front arm, to the weapon hand.
	_arm(ci, Vector2(f * 6.0, -37 + bob), _u(origin + hand), false)
	_draw_rim(ci, f, bob)
	ci.draw_set_transform(Vector2.ZERO)

## The hand over the weapon grip (drawn after the weapon).
func draw_hand(ci: CanvasItem, hand: Vector2, at := Vector2.ZERO, zoom := 1.0) -> void:
	ci.draw_set_transform(at, 0.0, Vector2(U, U) * zoom)
	_hand(ci, _u(origin + hand), float(facing), false)
	ci.draw_set_transform(Vector2.ZERO)

func _long_sleeves() -> bool:
	return String(look.top) in ["jacket", "robe", "hoodie", "tunic"]

func _hand(ci: CanvasItem, p: Vector2, f: float, back: bool) -> void:
	var skin := c("skin").darkened(0.12 if back else 0.0)
	_shape(ci, _ellipse(p, 2.7, 2.5, 14), skin, 0.9)
	ci.draw_circle(p + Vector2(f * 1.9, -1.1), 1.1, skin)
	ci.draw_arc(p + Vector2(f * 1.9, -1.1), 1.1, 0, TAU, 8, _ol(skin), 0.7, true)

func _arm(ci: CanvasItem, sh: Vector2, hand: Vector2, back: bool) -> void:
	var f := float(facing)
	var dim := 0.18 if back else 0.0
	var sleeve := c("top_color").darkened(dim)
	if String(look.top) == "vest":
		sleeve = Color("#ecf0f1").darkened(dim)
	var skin := c("skin").darkened(dim * 0.7)
	var elbow := sh.lerp(hand, 0.5) + Vector2(-f * 0.8, 0.8)
	if _long_sleeves():
		_shape(ci, _capsule(sh, elbow, 3.2, 2.8), sleeve)
		_shape(ci, _capsule(elbow, hand.lerp(elbow, 0.2), 2.8, 2.5), sleeve)
		ci.draw_line(hand.lerp(elbow, 0.25) + Vector2(-2.4, 0), hand.lerp(elbow, 0.25) + Vector2(2.4, 0), sleeve.darkened(0.3), 1.0, true)
	else:
		_shape(ci, _capsule(sh, elbow, 2.6, 2.3), skin)
		_shape(ci, _capsule(elbow, hand, 2.3, 2.1), skin)
		# Short sleeve over the shoulder.
		_shape(ci, _capsule(sh, sh.lerp(elbow, 0.55), 3.4, 3.0), sleeve)
	if back:
		_hand(ci, hand, f, true)

func _leg(ci: CanvasItem, top: Vector2, knee: Vector2, foot: Vector2, f: float, back: bool) -> void:
	var dim := 0.16 if back else 0.0
	var bottom := String(look.bottom)
	var pants := c("bottom_color").darkened(dim)
	var skin := c("skin").darkened(dim * 0.8)
	var thigh_col := pants if bottom in ["pants", "shorts"] else skin
	var shin_col := pants if bottom == "pants" else skin
	_shape(ci, _capsule(knee, foot + Vector2(0, -2.5), 2.7, 2.4), shin_col)
	_shape(ci, _capsule(top, knee, 3.4, 2.8), thigh_col)
	if bottom == "pants":
		ci.draw_line(knee + Vector2(-f * 1.2, -1.5), knee + Vector2(f * 1.0, 1.0), pants.darkened(0.3), 0.8, true)
	_shoe(ci, foot, f, dim)

func _shoe(ci: CanvasItem, foot: Vector2, f: float, dim: float) -> void:
	var col := c("shoes_color").darkened(dim)
	match String(look.shoes):
		"sandals":
			_shape(ci, _rrect(Rect2(foot.x - 4.0 + f * 1.0, foot.y - 1.6, 8.5, 1.8), 0.8), Color("#8b6238").darkened(dim))
			ci.draw_circle(foot + Vector2(f * 3.0, -2.2), 1.6, c("skin").darkened(dim))
			ci.draw_line(foot + Vector2(-1.5, -3.5), foot + Vector2(f * 2.5, -1.6), col, 1.2, true)
		"sneakers":
			_shape(ci, _rrect(Rect2(foot.x - 4.0 + f * 1.4, foot.y - 4.2, 9.0, 4.2), 1.8), col)
			ci.draw_line(Vector2(foot.x - 3.6 + f * 1.4, foot.y - 0.8), Vector2(foot.x + 4.6 + f * 1.4, foot.y - 0.8), Color.WHITE, 1.4, true)
			ci.draw_circle(foot + Vector2(f * 1.5, -3.4), 0.6, Color.WHITE)
		_:
			_shape(ci, _rrect(Rect2(foot.x - 4.0 + f * 1.4, foot.y - 6.0, 9.0, 6.0), 2.0), col)
			ci.draw_line(Vector2(foot.x - 3.6 + f * 1.4, foot.y - 0.9), Vector2(foot.x + 4.6 + f * 1.4, foot.y - 0.9), col.darkened(0.45), 1.3, true)
			ci.draw_line(Vector2(foot.x - 2.5 + f * 1.4, foot.y - 4.8), Vector2(foot.x + 3.0 + f * 1.4, foot.y - 4.8), col.lightened(0.3), 0.8, true)

## Cloth between two physics chains, drawn as a strip of quads (one per segment). The chains can
## cross when the cloth folds in the wind; a single polygon would then intersect itself and the
## renderer can't fill it ("triangulation failed"). A quad strip just draws the fold.
func _ribbon(ci: CanvasItem, a: PackedVector2Array, b: PackedVector2Array, col: Color, edge: Color) -> void:
	var n := mini(a.size(), b.size())
	var cols := PackedColorArray([col, col, col, col])
	for i in n - 1:
		ci.draw_primitive(PackedVector2Array([_u(a[i]), _u(a[i + 1]), _u(b[i + 1]), _u(b[i])]), cols, PackedVector2Array())
	var la := PackedVector2Array()
	var lb := PackedVector2Array()
	for i in n:
		la.append(_u(a[i]))
		lb.append(_u(b[i]))
	ci.draw_polyline(la, edge, OUTLINE, true)
	ci.draw_polyline(lb, edge, OUTLINE, true)
	ci.draw_line(la[n - 1], lb[n - 1], edge, OUTLINE, true)

func _draw_cape(ci: CanvasItem, f: float) -> void:
	if chains.has("cape_a"):
		var cc := c("cape_color")
		_ribbon(ci, chains.cape_a.pts, chains.cape_b.pts, cc.darkened(0.12), _ol(cc))
		# Lining glimpse along the trailing edge.
		var la := PackedVector2Array()
		for p in chains.cape_a.pts:
			la.append(_u(p) + Vector2(f * 0.8, 0))
		ci.draw_polyline(la, cc.darkened(0.4), 1.2, true)
	if chains.has("scarf"):
		_strand(ci, chains.scarf.pts, 4.5, c("cape_color"))

## A physics lock of hair (or a tail): outline pass, fill pass tapering toward the tip, then a shine line.
func _strand(ci: CanvasItem, pts: PackedVector2Array, w0: float, col: Color) -> void:
	var n := pts.size()
	for pass_i in 2:
		for i in range(1, n):
			var w := lerpf(w0, w0 * 0.3, float(i) / n) + (1.6 if pass_i == 0 else 0.0)
			var a := _u(pts[i - 1])
			var b := _u(pts[i])
			ci.draw_line(a, b, _ol(col) if pass_i == 0 else col, w, true)
			ci.draw_circle(b, w * 0.5, _ol(col) if pass_i == 0 else col)
	var shine := PackedVector2Array()
	for i in mini(n, 4):
		shine.append(_u(pts[i]) + Vector2(-float(facing) * w0 * 0.15, 0))
	if shine.size() >= 2:
		ci.draw_polyline(shine, col.lightened(0.3), maxf(w0 * 0.22, 0.8), true)

func _draw_back_hair(ci: CanvasItem, f: float, bob: float) -> void:
	var hc_col := c("hair_color").darkened(0.12)
	var hc := _hc(f, bob)
	match String(look.hair):
		"long":
			_shape(ci, _rrect(Rect2(hc.x - f * 9.0 - 7.0, hc.y - 6.0, 14, 24), 6.0), hc_col)
		"bob":
			_shape(ci, _rrect(Rect2(hc.x - 15.5, hc.y - 8.0, 31, 20), 7.0), hc_col)
	for name in ["hair_a", "hair_b"]:
		if chains.has(name) and not _front_chain(name):
			_strand(ci, chains[name].pts, 9.5 if String(look.hair) == "long" else 6.5, hc_col)

## Tails that hang on the near side of the head are drawn over it, not behind.
func _front_chain(name: String) -> bool:
	var style := String(look.hair)
	return (style == "twintails" and name == "hair_b") or (style == "side_tail" and name == "hair_a")

func _draw_skirt(ci: CanvasItem, f: float, bob: float) -> void:
	if not chains.has("hem_a"):
		if String(look.bottom) == "shorts":
			var pc := c("bottom_color")
			_shape(ci, _rrect(Rect2(-8.5, -24 + bob * 0.3, 17, 8), 2.5), pc)
			ci.draw_line(Vector2(0, -20 + bob * 0.3), Vector2(0, -16.5 + bob * 0.3), pc.darkened(0.35), 0.8, true)
		return
	var col := c("top_color") if String(look.top) == "robe" else c("bottom_color")
	var a: PackedVector2Array = chains.hem_a.pts
	var b: PackedVector2Array = chains.hem_b.pts
	_ribbon(ci, a, b, col, _ol(col))
	# Pleats
	for k in [0.3, 0.55, 0.8]:
		var top := _u(a[0]).lerp(_u(b[0]), k)
		var bottom := _u(a[a.size() - 1]).lerp(_u(b[b.size() - 1]), k)
		ci.draw_line(top, bottom, col.darkened(0.2), 0.8, true)
	if String(look.top) == "robe":
		ci.draw_line(_u(a[a.size() - 1]), _u(b[b.size() - 1]), Color("#e8c34a"), 1.2, true)

func _draw_torso(ci: CanvasItem, f: float, bob: float) -> void:
	var col := c("top_color")
	var y0 := -41.0 + bob
	var r := Rect2(-8.6, y0, 17.2, 21.5 - bob * 0.7)
	var body := _rrect(r, 4.0)
	# Shadow band on the back side.
	var back_x := -f * 8.6
	var shade := _rrect(Rect2(minf(back_x, back_x + f * 5.0), y0 + 1.0, 5.0, r.size.y - 2.0), 3.0)
	var top := String(look.top)
	if top == "vest":
		_shaded(ci, body, Color("#ecf0f1"), shade)
		# Vest panels with buttons.
		_shape(ci, _rrect(Rect2(-8.6, y0, 7.0, r.size.y), 3.0), col)
		_shape(ci, _rrect(Rect2(1.6, y0, 7.0, r.size.y), 3.0), col)
		for k in 3:
			ci.draw_circle(Vector2(f * 2.6, y0 + 5 + k * 5), 0.9, Color("#e8c34a"))
		return
	_shaded(ci, body, col, shade)
	var line := col.darkened(0.35)
	match top:
		"tee":
			ci.draw_arc(Vector2(f * 1.0, y0 - 0.5), 3.5, 0.2, PI - 0.2, 10, line, 1.0, true)
			ci.draw_line(Vector2(f * 0.5, y0 + 9), Vector2(f * 3.5, y0 + 14), col.lightened(0.15), 0.8, true)
		"tunic":
			_shape(ci, _rrect(Rect2(-8.8, -26 + bob * 0.5, 17.6, 3.2), 1.0), Color("#5a3a24"))
			_shape(ci, _rrect(Rect2(f * 2.0 - 2.0, -26.5 + bob * 0.5, 4.0, 4.0), 0.8), Color("#e8c34a"))
			ci.draw_line(Vector2(f * 1.5, y0), Vector2(f * 1.5, -27 + bob * 0.5), line, 0.9, true)
			ci.draw_arc(Vector2(f * 1.0, y0 - 0.5), 3.8, 0.2, PI - 0.2, 10, Color("#e8c34a"), 1.0, true)
		"jacket":
			_shape(ci, _rrect(Rect2(f * 2.8 - 2.2, y0, 4.4, r.size.y - 1.0), 1.5), Color("#ecf0f1"))
			ci.draw_line(Vector2(f * 0.6, y0), Vector2(f * 3.2, y0 + 8), line, 1.2, true)
			ci.draw_line(Vector2(f * 5.0, y0), Vector2(f * 2.4, y0 + 8), line, 1.2, true)
			ci.draw_line(Vector2(-f * 3.5, y0 + 12), Vector2(-f * 0.5, y0 + 12), line, 0.8, true)
		"robe":
			ci.draw_line(Vector2(f * 2.0, y0), Vector2(f * 2.0, -20 + bob * 0.3), Color("#e8c34a"), 1.3, true)
			_shape(ci, _rrect(Rect2(-8.8, -27 + bob * 0.5, 17.6, 2.6), 1.0), Color("#e8c34a"))
			ci.draw_arc(Vector2(f * 1.0, y0 - 0.5), 4.0, 0.2, PI - 0.2, 10, Color("#e8c34a"), 1.2, true)
		"hoodie":
			_shape(ci, _ellipse(Vector2(-f * 5.5, y0 + 1.0), 6.0, 4.0, 18), col.darkened(0.12))
			_shape(ci, _rrect(Rect2(f * 1.0 - 4.5, -30 + bob * 0.5, 9.0, 5.0), 2.0), col.darkened(0.1))
			ci.draw_line(Vector2(f * 2.0, y0 + 1), Vector2(f * 2.2, y0 + 8), Color("#ecf0f1"), 0.9, true)
			ci.draw_line(Vector2(f * 5.0, y0 + 1), Vector2(f * 5.2, y0 + 8), Color("#ecf0f1"), 0.9, true)
	# Highlight along the front edge.
	ci.draw_line(Vector2(f * 7.2, y0 + 3), Vector2(f * 7.4, y0 + r.size.y - 4), col.lightened(0.25), 1.0, true)

func _draw_head(ci: CanvasItem, f: float, bob: float) -> void:
	var skin := c("skin")
	var hc := _hc(f, bob)
	# Neck with a shadow under the chin.
	_shape(ci, _rrect(Rect2(-2.8, -43 + bob, 5.6, 5), 1.5), skin.darkened(0.15), 0.9)
	# Ear on the back side.
	var ear := hc + Vector2(-f * 12.8, 1.5)
	_shape(ci, _ellipse(ear, 2.6, 3.4, 14), skin)
	ci.draw_arc(ear, 1.3, 0, TAU, 10, skin.darkened(0.25), 0.9, true)
	# Head: round with a soft chin toward the facing side.
	var head := _ellipse(hc, HEAD_R - 0.5, HEAD_R - 1.2, 36)
	for k in head.size():
		var p: Vector2 = head[k]
		if p.y > hc.y + 6.0:
			head[k] = p + Vector2(f * 1.2 * (p.y - hc.y - 6.0) / 8.0, 0)
	ci.draw_colored_polygon(head, skin)
	# Shadow on the back of the face.
	ci.draw_colored_polygon(_ellipse(hc + Vector2(-f * 8.5, 2), 5.5, 10.0, 18), skin.darkened(0.08))
	var closed := head.duplicate()
	closed.append(head[0])
	ci.draw_polyline(closed, _ol(skin), OUTLINE, true)
	_draw_face(ci, f, hc)

func _draw_face(ci: CanvasItem, f: float, hc: Vector2) -> void:
	var face := String(look.face)
	var eye := c("eye_color")
	var big := 1.15 if face == "bright" else 1.0
	var near := hc + Vector2(f * 6.0, 2.5)
	var far := hc + Vector2(-f * 2.2, 2.5)
	var lash := Color("#1e1a24")
	for e in [[far, 0.82], [near, 1.0]]:
		var p: Vector2 = e[0]
		var s: float = e[1] * big
		var rx := 2.9 * s
		var ry := 3.9 * s * (0.85 if face == "fierce" else 1.0)
		if face == "cheery":
			ci.draw_arc(p + Vector2(0, 1.5), rx, PI + 0.35, TAU - 0.35, 10, lash, 1.5, true)
			continue
		if is_blinking():
			ci.draw_arc(p + Vector2(0, -1.0), rx, 0.35, PI - 0.35, 10, lash, 1.4, true)
			continue
		# White, two-tone iris, pupil, catch-lights.
		ci.draw_colored_polygon(_ellipse(p, rx, ry, 18), Color.WHITE)
		var ic := p + Vector2(f * 0.6, 0.4)
		ci.draw_colored_polygon(_ellipse(ic, rx * 0.74, ry * 0.8, 16), eye.darkened(0.35))
		ci.draw_colored_polygon(_ellipse(ic + Vector2(0, ry * 0.25), rx * 0.62, ry * 0.5, 14), eye.lightened(0.15))
		ci.draw_colored_polygon(_ellipse(ic + Vector2(0, 0.2), rx * 0.32, ry * 0.42, 10), Color("#101014"))
		ci.draw_circle(ic + Vector2(-f * rx * 0.25 + rx * 0.1, -ry * 0.35), 1.0 * s, Color(1, 1, 1, 0.95))
		ci.draw_circle(ic + Vector2(f * rx * 0.3, ry * 0.35), 0.5 * s, Color(1, 1, 1, 0.8))
		if face == "bright":
			ci.draw_circle(ic + Vector2(-f * rx * 0.1, ry * 0.05), 0.45, Color(1, 1, 1, 0.7))
		# Upper lash line with a flick at the outer corner, lower lid.
		var top := PackedVector2Array()
		for k in 9:
			var a := PI + PI * k / 8.0
			top.append(p + Vector2(cos(a) * rx * 1.05, sin(a) * ry * 1.02))
		ci.draw_polyline(top, lash, 1.5, true)
		var outer := p + Vector2(f * rx * 1.05, -ry * 0.1)
		ci.draw_line(outer, outer + Vector2(f * 1.4, -1.2), lash, 1.1, true)
		ci.draw_arc(p, rx * 0.85, 0.5, PI - 0.5, 8, Color(0.45, 0.3, 0.28, 0.6), 0.7, true)
		if face == "sleepy":
			ci.draw_colored_polygon(_rrect(Rect2(p.x - rx * 1.1, p.y - ry * 1.15, rx * 2.2, ry * 1.0), 1.0), c("skin"))
			ci.draw_line(p + Vector2(-rx * 1.05, -ry * 0.18), p + Vector2(rx * 1.05, -ry * 0.18), lash, 1.4, true)
	# Brows
	var brow := c("hair_color").darkened(0.25)
	if face == "fierce":
		ci.draw_line(far + Vector2(-2.6, -6.6), far + Vector2(2.4, -5.0), brow, 1.4, true)
		ci.draw_line(near + Vector2(2.8, -6.8), near + Vector2(-2.6, -5.0), brow, 1.4, true)
	else:
		ci.draw_arc(far + Vector2(0, -3.5), 3.0, PI + 0.6, TAU - 0.6, 8, brow, 1.1, true)
		ci.draw_arc(near + Vector2(0, -3.8), 3.2, PI + 0.6, TAU - 0.6, 8, brow, 1.1, true)
	# Nose and mouth
	var skin := c("skin")
	ci.draw_line(hc + Vector2(f * 8.5, 6.5), hc + Vector2(f * 9.2, 7.5), skin.darkened(0.3), 0.9, true)
	var mouth := hc + Vector2(f * 4.5, 10.2)
	match face:
		"bright", "cheery":
			ci.draw_colored_polygon(_ellipse(mouth + Vector2(0, 0.4), 1.9, 1.3, 12).slice(0, 7) + PackedVector2Array([mouth + Vector2(-1.9, 0.4)]), Color("#8a2a3a"))
			ci.draw_circle(mouth + Vector2(0, 1.0), 0.7, Color("#ff8a9a"))
			ci.draw_colored_polygon(_ellipse(near + Vector2(f * 1.2, 5.3), 2.2, 1.1, 12), Color(1.0, 0.5, 0.55, 0.45))
			ci.draw_colored_polygon(_ellipse(far + Vector2(-f * 0.8, 5.3), 1.8, 1.0, 12), Color(1.0, 0.5, 0.55, 0.35))
		"fierce":
			ci.draw_line(mouth + Vector2(-1.8, 0.3), mouth + Vector2(1.8, -0.3), Color("#5a2a2a"), 1.0, true)
		"sleepy":
			ci.draw_arc(mouth, 1.0, 0, TAU, 8, Color("#7a3a3a"), 0.9, true)
		_:
			ci.draw_arc(mouth + Vector2(0, -1.2), 1.8, 0.4, PI - 0.4, 8, Color("#7a3a3a"), 1.0, true)

## Hair cap: covers the top and back of the head, down to the forehead on the face side.
func _cap_poly(hc: Vector2, f: float, r: float) -> PackedVector2Array:
	# From just above center on the back side, over the top, to the hairline on the face side,
	# so the edge never crosses the eyes.
	var back := asin(1.0 / r)
	var front := asin(6.0 / r)
	var a0 := PI + (back if f > 0 else front)
	var a1 := TAU - (front if f > 0 else back)
	var p := PackedVector2Array()
	for k in 25:
		var a := lerpf(a0, a1, float(k) / 24.0)
		p.append(hc + Vector2(cos(a) * r, sin(a) * r * 0.98))
	# Convex on purpose: the nape is its own shape (see _draw_front_hair), so this always fills.
	return p

## A pointed lock: base from a to b, tip at `tip`, sides bowed out a little.
func _lock(ci: CanvasItem, a: Vector2, b: Vector2, tip: Vector2, col: Color) -> void:
	var mid := (a + b) / 2.0
	var bow := (tip - mid).orthogonal().normalized() * 0.8
	var poly := PackedVector2Array([a, a.lerp(tip, 0.5) - bow, tip, b.lerp(tip, 0.5) + bow, b])
	_shape(ci, poly, col, 0.9)

func _draw_front_hair(ci: CanvasItem, f: float, bob: float) -> void:
	var col := c("hair_color")
	var hc := _hc(f, bob)
	var style := String(look.hair)
	# Hair down the back of the head to the nape, then the cap over the top.
	_shape(ci, _capsule(hc + Vector2(-f * 10.0, -3.0), hc + Vector2(-f * 8.5, 8.5), 6.0, 4.0), col)
	var cap := _cap_poly(hc, f, HEAD_R + 0.8)
	_shape(ci, cap, col)
	# Underlayer shadow near the nape.
	ci.draw_colored_polygon(_ellipse(hc + Vector2(-f * 9.0, 2.0), 5.0, 6.0, 14), col.darkened(0.15))
	match style:
		"spiky":
			for k in 6:
				var ang := lerpf(-2.6, -0.4, float(k) / 5.0)
				if f < 0:
					ang = -PI - ang
				var base := hc + Vector2(cos(ang), sin(ang)) * (HEAD_R - 1.0)
				var tip := hc + Vector2(cos(ang - f * 0.25), sin(ang - f * 0.25)) * (HEAD_R + 8.0 + (k % 2) * 3.0)
				var side := Vector2(cos(ang), sin(ang)).orthogonal() * 3.2
				_lock(ci, base - side, base + side, tip, col)
		"messy":
			for k in 7:
				var ang := lerpf(-2.8, -0.3, float(k) / 6.0)
				var base := hc + Vector2(cos(ang), sin(ang)) * (HEAD_R - 0.5)
				var tip := base + Vector2(cos(ang + (0.5 if k % 2 else -0.5)), sin(ang + (0.5 if k % 2 else -0.5))) * 5.5
				var side := Vector2(cos(ang), sin(ang)).orthogonal() * 2.6
				_lock(ci, base - side, base + side, tip, col)
		"bun":
			var bp := hc + Vector2(-f * 7.0, -15.0)
			_shape(ci, _ellipse(bp, 6.5, 6.0, 20), col)
			ci.draw_arc(bp, 4.0, PI * 1.1, PI * 1.6, 6, col.lightened(0.3), 1.2, true)
		"bob":
			_shape(ci, _rrect(Rect2(hc.x + f * 9.0 - 3.5, hc.y - 4.0, 7.0, 14.0), 3.0), col)
		"long":
			_shape(ci, _capsule(hc + Vector2(f * 12.6, -3.0), hc + Vector2(f * 13.4, 13.0), 3.0, 2.0), col)
		"bowl":
			_shape(ci, _rrect(Rect2(hc.x - HEAD_R - 0.8, hc.y - 7.0, (HEAD_R + 0.8) * 2.0, 5.0), 2.0), col)
	# Bangs over the forehead, lock by lock.
	if style == "swept":
		_lock(ci, hc + Vector2(-f * 8.0, -12.0), hc + Vector2(f * 4.0, -13.0), hc + Vector2(f * 17.0, -6.0), col)
		_lock(ci, hc + Vector2(f * 2.0, -11.0), hc + Vector2(f * 10.0, -10.0), hc + Vector2(f * 15.0, -4.5), col)
	elif style != "bowl":
		var n := 5 if style != "spiky" else 4
		for k in n:
			var x0 := -2.0 + k * 3.6
			var x1 := x0 + 4.6
			var drop := 4.5 + (k % 2) * 1.6 + (1.0 if k == n - 1 else 0.0)  # tips stop above the eyes
			_lock(ci, hc + Vector2(f * x0, -13.0 + absf(x0) * 0.1), hc + Vector2(f * x1, -12.0 + x1 * 0.15), hc + Vector2(f * (x0 + 3.2), -12.0 + drop), col)
	# Sideburn by the ear.
	_shape(ci, _capsule(hc + Vector2(-f * 11.0, -2.0), hc + Vector2(-f * 10.5, 6.0), 2.4, 1.4), col)
	for name in ["hair_a", "hair_b"]:
		if chains.has(name) and _front_chain(name):
			_strand(ci, chains[name].pts, 6.5, col)
	if style in ["twintails", "side_tail", "ponytail"] and chains.has("hair_a"):
		var tie := _u(chains.hair_a.pts[0])
		_shape(ci, _ellipse(tie, 2.4, 2.0, 12), Color("#e86aa0"), 0.8)
		if style == "twintails" and chains.has("hair_b"):
			_shape(ci, _ellipse(_u(chains.hair_b.pts[0]), 2.4, 2.0, 12), Color("#e86aa0"), 0.8)
	# Strand lines and the anime shine band.
	for k in 3:
		var a0 := PI + 0.6 + k * 0.5
		ci.draw_arc(hc + Vector2(-f * 2.0, 3.0), HEAD_R - 3.0 - k * 1.5, a0, a0 + 0.6, 6, col.darkened(0.25), 0.7, true)
	ci.draw_arc(hc + Vector2(-f * 1.0, 1.0), HEAD_R - 4.5, PI * 1.18, PI * 1.5, 10, col.lightened(0.45), 2.0, true)
	ci.draw_arc(hc + Vector2(-f * 1.0, 1.0), HEAD_R - 4.5, PI * 1.56, PI * 1.62, 3, col.lightened(0.45), 2.0, true)

func _draw_hat(ci: CanvasItem, f: float, bob: float) -> void:
	var col := c("hat_color")
	var hc := _hc(f, bob)
	match String(look.hat):
		"beanie":
			var dome := PackedVector2Array()
			for k in 17:
				var a := lerpf(PI, TAU, float(k) / 16.0)
				dome.append(hc + Vector2(cos(a) * (HEAD_R + 1.5), sin(a) * (HEAD_R + 0.5) - 3.0))
			_shape(ci, dome, col)
			_shape(ci, _rrect(Rect2(hc.x - HEAD_R - 1.5, hc.y - 7.0, (HEAD_R + 1.5) * 2.0, 4.5), 2.0), col.darkened(0.2))
			_shape(ci, _ellipse(hc + Vector2(0, -HEAD_R - 2.0), 3.0, 2.8, 12), col.lightened(0.3))
		"bandana":
			_shape(ci, _rrect(Rect2(hc.x - HEAD_R - 0.8, hc.y - 11.0, (HEAD_R + 0.8) * 2.0, 4.5), 1.5), col)
			for k in 3:
				ci.draw_circle(hc + Vector2(f * (-6.0 + k * 5.0), -8.8), 0.7, Color(1, 1, 1, 0.7))
			if chains.has("hat_tail"):
				_strand(ci, chains.hat_tail.pts, 3.4, col.darkened(0.1))
		"cap":
			var dome := PackedVector2Array()
			for k in 17:
				var a := lerpf(PI, TAU, float(k) / 16.0)
				dome.append(hc + Vector2(cos(a) * (HEAD_R + 1.0), sin(a) * (HEAD_R - 1.0) - 3.0))
			_shape(ci, dome, col)
			_shape(ci, PackedVector2Array([hc + Vector2(f * 6, -4), hc + Vector2(f * 23, -3), hc + Vector2(f * 22, -0.5), hc + Vector2(f * 6, -1.5)]), col.darkened(0.25), 0.9)
			ci.draw_circle(hc + Vector2(0, -HEAD_R - 3.5), 1.2, col.darkened(0.3))
		"wizard":
			_shape(ci, _ellipse(hc + Vector2(0, -9.0), 20.0, 3.6, 28), col.darkened(0.2))
			var tip := _u(chains.hat_tip.pts[0]) if chains.has("hat_tip") else hc + Vector2(-f * 3, -32)
			_shape(ci, PackedVector2Array([hc + Vector2(-11.5, -9.5), hc.lerp(tip, 0.55) + Vector2(-4.0, 0), tip, hc.lerp(tip, 0.55) + Vector2(4.0, 0), hc + Vector2(11.5, -9.5)]), col)
			if chains.has("hat_tip"):
				_strand(ci, chains.hat_tip.pts, 4.2, col)
			_shape(ci, _rrect(Rect2(hc.x - 11.5, hc.y - 13.0, 23, 3.2), 1.0), Color("#e8c34a"), 0.8)
			ci.draw_circle(hc.lerp(tip, 0.45) + Vector2(f * 2.0, 0), 1.4, Color("#ffe66b"))
		"headband":
			_shape(ci, _rrect(Rect2(hc.x - HEAD_R - 0.6, hc.y - 9.5, (HEAD_R + 0.6) * 2.0, 3.0), 1.2), col, 0.9)
			_shape(ci, _rrect(Rect2(hc.x + f * 4.0 - 2.5, hc.y - 10.2, 5.0, 4.4), 1.0), Color("#c9d3dd"), 0.8)
		"ribbon":
			var p := hc + Vector2(-f * 8.5, -13.0)
			_shape(ci, PackedVector2Array([p, p + Vector2(-7, -5), p + Vector2(-7.5, 4.5)]), col, 0.9)
			_shape(ci, PackedVector2Array([p, p + Vector2(7, -5), p + Vector2(7.5, 4.5)]), col, 0.9)
			_shape(ci, _ellipse(p, 2.0, 2.0, 10), col.darkened(0.2), 0.8)
		"helm":
			var dome := PackedVector2Array()
			for k in 19:
				var a := lerpf(PI, TAU, float(k) / 18.0)
				dome.append(hc + Vector2(cos(a) * (HEAD_R + 1.8), sin(a) * (HEAD_R + 1.0) - 4.0))
			_shape(ci, dome, col)
			_shape(ci, _rrect(Rect2(hc.x - HEAD_R - 1.8, hc.y - 7.5, (HEAD_R + 1.8) * 2.0, 3.5), 1.0), col.darkened(0.25))
			# Nose guard in front of the face, between the eyes and the nose tip.
			_shape(ci, _rrect(Rect2(hc.x + f * 10.5 - 1.1, hc.y - 6.0, 2.2, 10.0), 1.0), col.darkened(0.25), 0.8)
			ci.draw_arc(hc + Vector2(-f * 2.0, -2.0), HEAD_R - 2.0, PI * 1.2, PI * 1.5, 8, col.lightened(0.45), 1.6, true)
			_strand(ci, PackedVector2Array([origin + (hc + Vector2(-f * 2, -HEAD_R - 1)) * U, origin + (hc + Vector2(-f * 8, -HEAD_R - 7)) * U, origin + (hc + Vector2(-f * 15, -HEAD_R - 6)) * U]), 4.0, Color("#c43b3b"))

## Rim light: a colored edge on the side of the head, hair and body that faces each nearby light.
func _draw_rim(ci: CanvasItem, f: float, bob: float) -> void:
	for l in lights:
		var d: Vector2 = l.dir
		var col: Color = l.color
		var s: float = l.strength
		var a := d.angle()
		var hc := _hc(f, bob)
		ci.draw_arc(hc, HEAD_R + 1.0, a - 1.0, a + 1.0, 14, Color(col.lightened(0.3), 0.85 * s), 2.0, true)
		ci.draw_arc(hc, HEAD_R - 1.5, a - 0.6, a + 0.6, 10, Color(col, 0.3 * s), 2.0, true)
		var side := signf(d.x) if absf(d.x) > 0.1 else f
		ci.draw_line(Vector2(side * 8.6, -39 + bob), Vector2(side * 8.8, -22), Color(col.lightened(0.2), 0.6 * s), 1.6, true)
		if d.y < 0.3:
			ci.draw_line(Vector2(side * 4.5, -20), Vector2(side * 4.5, -4), Color(col, 0.4 * s), 1.4, true)
		ci.draw_circle(hc + d * 5.0, 11.0, Color(col, 0.08 * s))
