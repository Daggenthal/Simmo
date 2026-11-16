extends SceneTree
## Headless test for PixelLab sprites: animations load, each weapon plays its own attack, the swing
## steps through the clip, landing squashes, the hair palette swap leaves the dress alone, and a
## missing sprite falls back to the drawn character.
## Run: godot --headless --fixed-fps 60 --path . --script res://tests/sprite_test.gd

var _main
var _log
var _frame := 0
var _pf := 0
var _phase := "boot"
var _failures := 0
var _seen: Dictionary = {}
var _frames: Dictionary = {}   # sprite frames shown during the swing
var DollS

func _initialize() -> void:
	_log = root.get_node("Log")
	var env_seed := OS.get_environment("SIMMO_SEED")
	seed(int(env_seed) if env_seed != "" else 4242)
	DollS = load("res://scripts/doll.gd")
	_main = load("res://main.tscn").instantiate()
	_main.load_user_settings = false
	_main.show_start_screen = false
	_main.start_class = "warrior"
	_main.spawn_sims = false
	root.add_child(_main)

func _check(cond: bool, msg: String) -> void:
	if cond:
		_log.ok("PASS " + msg)
	else:
		_failures += 1
		_log.error("FAIL " + msg)

func _goto(p: String) -> void:
	_phase = p
	_pf = 0

func _park_all() -> void:
	_main.world._respawn_queue.clear()
	for m in _main.world.mobs:
		m.alive = false
		m.visible = false
		m.set_physics_process(false)

func _physics_process(_d: float) -> bool:
	_frame += 1
	_pf += 1
	var p = _main.player
	match _phase:
		"boot":
			if _pf == 5:
				_park_all()
				_check_loading()
				_check_hair()
				var lk: Dictionary = p.look.duplicate()
				lk.sprite = "test_heroine"
				p.custom_look = true
				p.set_look(lk)
				_check(p.doll.has_sprite(), "the player wears the test sprite")
				# Regression: with an attack clip present the drawn sword was painted over the sprite's own.
				_check(not p.draws_weapon(), "a sprite never gets a drawn weapon on top of its own")
				var want := {"short_sword": "attack_slash", "iron_hammer": "attack_slash", "dagger": "attack_stab",
					"throwing_kunai": "attack_throw", "oak_staff": "attack_cast", "holy_scepter": "attack_cast"}
				var got := {}
				for w in want:
					p.switch_to_weapon_class(w)
					got[w] = p.sprite_attack()
				_check(got == want, "each weapon picks its attack animation (%s)" % str(got))
				p.switch_to_weapon_class("short_sword")
				p.position = Vector2(500, 330)
				p.velocity = Vector2.ZERO
				_goto("swing")
		"swing":
			# One sword swing: the doll plays attack_slash from start to end, through several frames.
			if _pf == 2:
				_seen.clear()
				p.attack()
			if _pf > 2 and _pf < 60:
				if not p.doll.action.is_empty():
					_check_once("kind", p.doll.action.kind == "attack_slash", "a sword swing plays attack_slash (%s)" % p.doll.action.kind)
					_frames[p.doll._sprite_frame()[0]] = true
			if _pf == 60:
				_check(_frames.size() >= 3, "the swing steps through the clip (%d different frames)" % _frames.size())
				_check(p.doll.action.is_empty(), "and goes back to idle afterwards")
				_goto("land")
		"land":
			# Jump and land: the squash spring takes a hit on landing and settles back.
			if _pf == 2:
				p.velocity.y = -360.0
			if _pf > 5 and p.is_on_floor() and not _seen.has("landed"):
				_seen.landed = _pf
			if _seen.has("landed") and _pf == int(_seen.landed) + 4:
				_check(p.doll._sq > 0.02, "landing squashes the sprite (%.3f)" % p.doll._sq)
			if _pf == 200:
				_check(_seen.has("landed") and absf(p.doll._sq) < 0.01, "and it springs back to rest (%.3f)" % p.doll._sq)
				_goto("done")
		"done":
			if _failures == 0:
				_log.ok("ALL SPRITE CHECKS PASSED (%d frames)" % _frame)
			else:
				_log.error("%d SPRITE CHECK(S) FAILED" % _failures)
			quit(1 if _failures > 0 else 0)
	if _frame > 2000:
		_log.error("timeout in phase " + _phase)
		quit(1)
	return false

func _check_once(key: String, cond: bool, msg: String) -> void:
	if _seen.has("once_" + key):
		return
	_seen["once_" + key] = true
	_check(cond, msg)

func _check_loading() -> void:
	var d = DollS.new({"sprite": "test_heroine"})
	var missing: Array = []
	for a in DollS.SPRITE_ANIMS:
		if not d.has_anim(a):
			missing.append(a)
	_check(d.has_sprite() and missing.is_empty(), "every sprite animation loads (missing: %s)" % str(missing))
	# Clips on bigger canvases keep their feet where the still's are: the anchor sits at the bottom
	# of the opaque art in each clip's first frame.
	var ok := true
	for a in DollS.SPRITE_ANIMS:
		var anim: Dictionary = d._sprite.anims[a]
		var img: Image = anim.frames[0].get_image()
		ok = ok and absf(anim.feet.y - img.get_used_rect().end.y) < 0.5
	_check(ok, "each clip is anchored at its feet")
	var gone = DollS.new({"sprite": "no_such_sprite"})
	_check(not gone.has_sprite(), "a missing sprite falls back to the drawn character")

func _check_hair() -> void:
	var a: Image = DollS.new({"sprite": "test_heroine"})._sprite.still_e.get_image()
	var b: Image = DollS.new({"sprite": "test_heroine", "sprite_hair": "#2b1d14"})._sprite.still_e.get_image()
	var hair := 0
	var dress_changed := 0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			if ca.a <= 0.01:
				continue
			var cb := b.get_pixel(x, y)
			if not ca.is_equal_approx(cb):
				hair += 1
			# The dress's reds (hue near 0, strongly saturated) must not change.
			if (ca.h > 0.985 or ca.h < 0.03) and ca.s > 0.72 and not ca.is_equal_approx(cb):
				dress_changed += 1
	_check(hair > 200, "the hair swap recolors the hair (%d pixels)" % hair)
	_check(dress_changed == 0, "and leaves the dress alone (%d dress pixels changed)" % dress_changed)
