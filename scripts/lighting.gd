class_name Lighting
extends RefCounted
## Dynamic 2D lights. Lighting.add(parent, color, radius, energy) attaches a PointLight2D
## (soft radial texture, optional shadows from platform occluders) and registers it, so
## characters can draw rim light on the side facing it (Doll reads Lighting.near()).
## Moving lights follow their parent: a fireball's light flies with the fireball.

static var _texture: GradientTexture2D
static var _lights: Array = []     # PointLight2D nodes that are alive
## Global ambient darkness 0 (noon) .. 1 (black); Weather sets it. Rim light matters more in the dark.
static var darkness := 0.0
## Off in headless tests and for low settings.
static var enabled := true

static func texture() -> GradientTexture2D:
	if _texture == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.55))
		_texture = GradientTexture2D.new()
		_texture.gradient = g
		_texture.fill = GradientTexture2D.FILL_RADIAL
		_texture.fill_from = Vector2(0.5, 0.5)
		_texture.fill_to = Vector2(1.0, 0.5)
		_texture.width = 128
		_texture.height = 128
	return _texture

## Attach a light to `parent`. radius in world px. Returns the light (or null when lighting is off).
static func add(parent: Node, col: Color, radius: float, energy := 1.0, shadows := false) -> PointLight2D:
	if not enabled or parent == null:
		return null
	var l := PointLight2D.new()
	l.texture = texture()
	l.color = col
	l.energy = energy
	l.texture_scale = radius / 64.0
	l.shadow_enabled = shadows
	l.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	l.shadow_color = Color(0, 0, 0, 0.7)
	l.set_meta("radius", radius)
	parent.add_child(l)
	_lights.append(l)
	return l

## A light that fades out over `life` seconds and frees itself (flashes: lightning, bursts).
static func flash(parent: Node, at: Vector2, col: Color, radius: float, energy: float, life: float, shadows := false) -> void:
	if not enabled or parent == null or not parent.is_inside_tree():
		return
	var holder := Node2D.new()
	parent.add_child(holder)
	holder.global_position = at
	var l := add(holder, col, radius, energy, shadows)
	var tw := holder.create_tween()
	tw.tween_property(l, "energy", 0.0, life)
	tw.tween_callback(holder.queue_free)

## Lights near `pos` that reach it, strongest first: [{dir (unit, from pos toward the light), color, strength 0..1}].
static func near(pos: Vector2, limit := 2) -> Array:
	var out: Array = []
	for k in range(_lights.size() - 1, -1, -1):
		var l = _lights[k]
		if not is_instance_valid(l) or not l.is_inside_tree():
			_lights.remove_at(k)
			continue
		if not l.visible or l.energy <= 0.01:
			continue
		var r := float(l.get_meta("radius", 64.0))
		var d: Vector2 = l.global_position - pos
		var dist := d.length()
		if dist >= r:
			continue
		var s := clampf((1.0 - dist / r) * l.energy, 0.0, 1.0)
		out.append({"dir": d.normalized() if dist > 0.5 else Vector2.UP, "color": l.color, "strength": s})
	out.sort_custom(func(a, b): return a.strength > b.strength)
	return out.slice(0, limit)

static func count() -> int:
	return _lights.size()
