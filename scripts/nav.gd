class_name Nav
extends RefCounted
## Side-view navigation graph. Nodes are walkable surfaces (the ground and each
## one-way platform). Links are the moves between them:
##   jump_up      stand under a platform and jump straight up through it
##   jump_across  jump from the edge of one surface over a gap to another
##   walk_off     walk off an edge and fall onto a lower surface
##   drop         Down + Jump through the platform you stand on
## find_route() runs Dijkstra on walking distance plus a small cost per move,
## so auto-battle (and later SimPlayers) take the cheapest real route.

const JUMP_ACROSS_UP := 56.0    # max horizontal gap when jumping to a higher surface (with a running start)
const JUMP_ACROSS_DOWN := 64.0  # max horizontal gap when jumping to a lower surface
const WALK_OFF_REACH := 8.0     # a lower surface this close past an edge catches a walk-off
const MIN_OVERLAP := 16.0       # width needed to jump straight up through a platform
const MOVE_COST := {"jump_up": 24.0, "jump_across": 30.0, "walk_off": 8.0, "drop": 12.0}

var surfaces: Array = []   # {id, x0, x1, y, one_way}
var links: Array = []      # {from, to, kind, depart_x, land_x, dir}
var max_up := 70.0

func build(ground_y: float, map_w: float, platforms: Array, jump_height: float) -> void:
	max_up = jump_height - 6.0
	surfaces = [{"id": 0, "x0": 0.0, "x1": map_w, "y": ground_y, "one_way": false}]
	for p in platforms:
		surfaces.append({"id": surfaces.size(), "x0": float(p[0]), "x1": float(p[0] + p[2]), "y": float(p[1]), "one_way": true})
	links.clear()
	for a in surfaces:
		for b in surfaces:
			if a.id != b.id:
				_link(a, b)

func _link(a: Dictionary, b: Dictionary) -> void:
	var ov0: float = maxf(a.x0, b.x0)
	var ov1: float = minf(a.x1, b.x1)
	var overlap := ov1 - ov0
	if b.y < a.y:
		# b is higher
		if a.y - b.y > max_up:
			return
		if overlap >= MIN_OVERLAP:
			var x := (ov0 + ov1) / 2.0
			links.append({"from": a.id, "to": b.id, "kind": "jump_up", "depart_x": x, "land_x": x, "dir": 0})
		else:
			_across(a, b, JUMP_ACROSS_UP)
	elif b.y > a.y:
		# b is lower
		if a.one_way and overlap >= MIN_OVERLAP:
			var x := (ov0 + ov1) / 2.0
			links.append({"from": a.id, "to": b.id, "kind": "drop", "depart_x": x, "land_x": x, "dir": 0})
		# Walk off either edge if b catches the fall.
		for side: int in [-1, 1]:
			var edge: float = a.x0 if side < 0 else a.x1
			var land: float = edge + side * 10.0
			if land >= b.x0 - WALK_OFF_REACH and land <= b.x1 + WALK_OFF_REACH and not (land > a.x0 and land < a.x1):
				land = clampf(land, b.x0 + 4.0, b.x1 - 4.0)
				links.append({"from": a.id, "to": b.id, "kind": "walk_off", "depart_x": edge - side * 2.0, "land_x": land, "dir": side})
		if not _has_link(a.id, b.id):
			_across(a, b, JUMP_ACROSS_DOWN)

func _across(a: Dictionary, b: Dictionary, max_gap: float) -> void:
	var side := 1 if b.x0 >= a.x1 else (-1 if b.x1 <= a.x0 else 0)
	if side == 0:
		return
	var gap: float = (b.x0 - a.x1) if side > 0 else (a.x0 - b.x1)
	if gap > max_gap:
		return
	var depart: float = (a.x1 - 3.0) if side > 0 else (a.x0 + 3.0)
	var land: float = (b.x0 + 14.0) if side > 0 else (b.x1 - 14.0)
	links.append({"from": a.id, "to": b.id, "kind": "jump_across", "depart_x": depart, "land_x": land, "dir": side})

func _has_link(from_id: int, to_id: int) -> bool:
	for l in links:
		if l.from == from_id and l.to == to_id:
			return true
	return false

## Which surface a point at (x, feet_y) stands on, or -1.
func surface_at(x: float, feet_y: float) -> int:
	var best := -1
	for s in surfaces:
		if absf(s.y - feet_y) < 8.0 and x >= s.x0 - 6.0 and x <= s.x1 + 6.0:
			if best < 0 or s.one_way:
				best = s.id
	return best

## Cheapest route from (from_surface, x) to to_surface.
## Returns {cost, links: [...]}; cost is INF when unreachable.
func find_route(from_surface: int, from_x: float, to_surface: int, to_x: float) -> Dictionary:
	if from_surface < 0 or to_surface < 0:
		return {"cost": INF, "links": []}
	if from_surface == to_surface:
		return {"cost": absf(to_x - from_x), "links": []}
	var dist := {from_surface: 0.0}
	var at_x := {from_surface: from_x}
	var prev := {}
	var open := [from_surface]
	var done := {}
	while not open.is_empty():
		var cur: int = open[0]
		for n in open:
			if dist[n] < dist[cur]:
				cur = n
		open.erase(cur)
		if done.has(cur):
			continue
		done[cur] = true
		if cur == to_surface:
			break
		for l in links:
			if l.from != cur:
				continue
			var c: float = dist[cur] + absf(l.depart_x - at_x[cur]) + MOVE_COST[l.kind]
			if not dist.has(l.to) or c < dist[l.to]:
				dist[l.to] = c
				at_x[l.to] = l.land_x
				prev[l.to] = l
				open.append(l.to)
	if not dist.has(to_surface):
		return {"cost": INF, "links": []}
	var route := []
	var n2 := to_surface
	while prev.has(n2):
		route.push_front(prev[n2])
		n2 = prev[n2].from
	return {"cost": dist[to_surface] + absf(to_x - at_x[to_surface]), "links": route}
