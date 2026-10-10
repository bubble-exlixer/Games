extends Node3D
## Hammy, the class hamster. Feed him three times (500 each) and he breaks out and bites zombies for you.

const HOME := Vector3(31.25, 0.81, -3.3)
const FEED_SPOT := Vector3(29.5, 0.0, -3.3)
const COST := 500

var game
var g: Node3D          # the hamster
var head: Node3D
var wheel: MeshInstance3D
var fed := 0
var free := false
var t := 0.0
var run := 0.0
var wheel_t := 0.0
var bite_cd := 0.0
var retarget := 0.0
var tgt = null
var leash_t := 0.0
var sq_t := 3.0
var vy := 0.0
var pos := Vector3.ZERO
var ry := 0.0
# Pack-a-Punched: HAMSTER OF THE APOCALYPSE
const PAP_COST := 5000
var mega := false
var in_pap := 0.0
var fur_mat: StandardMaterial3D
var eye_mat: StandardMaterial3D
var glow: OmniLight3D

func setup(gm) -> void:
	game = gm
	var fur := _m(Color8(200, 132, 62))
	fur_mat = fur
	var belly := _m(Color8(240, 226, 200))
	var pink := _m(Color8(224, 160, 160))
	var eye := _m(Color8(10, 10, 10))
	eye_mat = eye
	g = Node3D.new()
	add_child(g)
	var body := _ball(g, fur, Vector3(0, 0.075, 0), Vector3(0.085, 0.07, 0.11))
	_ball(g, belly, Vector3(0, 0.05, 0.025), Vector3(0.07, 0.05, 0.085))
	head = Node3D.new()
	head.position = Vector3(0, 0.1, 0.1)
	g.add_child(head)
	_ball(head, fur, Vector3.ZERO, Vector3(0.06, 0.055, 0.06))
	_ball(head, belly, Vector3(0, -0.015, 0.045), Vector3(0.035, 0.03, 0.03))
	_ball(head, pink, Vector3(0, -0.005, 0.063), Vector3(0.012, 0.01, 0.01))
	for s in [-1, 1]:
		_ball(head, eye, Vector3(s * 0.032, 0.015, 0.045), Vector3(0.011, 0.012, 0.01))
		_ball(head, pink, Vector3(s * 0.035, 0.055, -0.015), Vector3(0.018, 0.022, 0.008))
	for f in [[-0.05, 0.06], [0.05, 0.06], [-0.05, -0.06], [0.05, -0.06]]:
		_ball(g, pink, Vector3(f[0], 0.012, f[1]), Vector3(0.018, 0.012, 0.022))
	body.name = "Body"
	# the wheel he runs in after a meal
	wheel = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.108
	tm.outer_radius = 0.132
	tm.rings = 14
	tm.ring_segments = 5
	wheel.mesh = tm
	wheel.material_override = _m(Color8(154, 160, 168))
	add_child(wheel)
	wheel.global_position = Vector3(31.45, 1.0, -3.3)
	wheel.rotation = Vector3(0, 0, PI / 2)
	pos = HOME + Vector3(-0.12, 0.05, 0)

func _m(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m

func _ball(parent: Node3D, mat: Material, p: Vector3, s: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 10
	sm.rings = 6
	m.mesh = sm
	m.material_override = mat
	m.position = p
	m.scale = s
	parent.add_child(m)
	return m

func prompt() -> String:
	if fed >= 3:
		return ""
	var d: Vector3 = game.player.global_position - FEED_SPOT
	if Vector2(d.x, d.z).length() > 1.6 or absf(d.y) > 1.5:
		return ""
	return ("Press {use} to feed the class hamster  [%d]" % COST) if fed == 0 else ("Press {use} to feed Hammy (%d/3)  [%d]" % [fed, COST])

## look at Hammy next to the upgrade machine to put him in it
func pap_prompt() -> String:
	if not free or mega or in_pap > 0:
		return ""
	var P = game.player
	var d: Vector3 = P.global_position - game.shop.PAP_SPOT
	if Vector2(d.x, d.z).length() > 2.2 or absf(d.y) > 1.5 or pos.distance_to(game.shop.PAP_SPOT) > 4.5:
		return ""
	var to: Vector3 = (pos + Vector3(0, 0.1, 0)) - P.cam.global_position
	if (-P.cam.global_transform.basis.z).angle_to(to.normalized()) > deg_to_rad(35):
		return ""
	if not game.world.powered:
		return ""
	return "Press {use} to Pack-a-Punch HAMMY  [%d]" % PAP_COST

func pap_buy() -> void:
	if mega or in_pap > 0 or game.shop.pap_busy > 0:
		return
	if game.points < PAP_COST:
		game._deny()
		return
	game.points -= PAP_COST
	game.hud.points_pop(-PAP_COST)
	in_pap = 3.4
	game.shop.pap_busy = 3.4
	game.shop.pap_slot_i = -1
	game.audio.play("papStart", game.shop.PAP_POS + Vector3(0, 1.3, 0.5), 2)
	game.audio.play("squeak", pos, 2, 1.3)
	game.fx.puff(pos + Vector3(0, 0.1, 0), Color8(216, 200, 168), false, 0.05, 0.4, 0.3, 0.3, 0.05, 0.6)
	g.visible = false

func _go_mega() -> void:
	mega = true
	g.visible = true
	pos = game.shop.PAP_SPOT + Vector3(0, 0.2, 0.3)
	vy = 4.0
	g.scale = Vector3.ONE * 2.0
	fur_mat.albedo_color = Color8(120, 50, 200)
	fur_mat.emission_enabled = true
	fur_mat.emission = Color8(150, 70, 255)
	fur_mat.emission_energy_multiplier = 0.6
	eye_mat.albedo_color = Color8(255, 30, 20)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color8(255, 30, 20)
	eye_mat.emission_energy_multiplier = 3.0
	glow = OmniLight3D.new()
	glow.light_color = Color8(170, 100, 255)
	glow.omni_range = 2.5
	glow.light_energy = 1.2
	glow.position.y = 0.15
	g.add_child(glow)
	game.audio.play("papDone", game.shop.PAP_POS + Vector3(0, 1.3, 0.5), 2)
	game.audio.play("hamroar", pos, 6)
	game.fx.flash_light(pos + Vector3(0, 0.5, 0), Color8(170, 120, 255), 6.0, 8.0, 0.6)
	game.fx.arc(pos + Vector3(0, 0.3, 0), pos + Vector3(randf_range(-1, 1), 1.6, randf_range(-1, 1)), Color(0.75, 0.5, 1.0))
	game.hud.banner("HAMSTER OF THE APOCALYPSE", "HAMMY HAS BEEN UPGRADED", 2.6)
	game.player.shake = maxf(game.player.shake, 0.2)

func feed() -> void:
	fed += 1
	wheel_t = 3.2
	game.audio.play("squeak", pos + Vector3(0, 0.2, 0))
	game.fx.spray(HOME + Vector3(0, 0.5, 0), Vector3.UP, Color8(200, 160, 96), 10, 1.5, 0.35)
	if fed >= 3:
		get_tree().create_timer(1.4).timeout.connect(_break_out)
	else:
		game.callout("HAMMY", "%d / 3 FED" % fed)

func _break_out() -> void:
	free = true
	pos = HOME + Vector3(0, 0, 0.4)
	vy = 3.0
	game.fx.puff(pos + Vector3(0, 0.1, 0), Color8(216, 200, 168), false, 0.05, 0.5, 0.4, 0.3, 0.05, 0.6)
	game.audio.play("squeak", pos)
	get_tree().create_timer(0.16).timeout.connect(func(): game.audio.play("squeak", pos, 0, 1.2))
	game.hud.banner("HAMMY IS FREE", "HE BITES FOR YOU NOW", 2.2)

func _bite(z) -> void:
	var dmg: float = (0.35 if z.kind == "boss" else 1.0) * (22.0 + game.wave * 5.0) * (3.0 if mega else 1.0)
	var at: Vector3 = z.global_position + Vector3(randf_range(-0.1, 0.1), 0.25 if z.crawler else 0.3, randf_range(-0.1, 0.1))
	var away: Vector3 = (z.global_position - pos)
	away.y = 0.3
	var res: Dictionary = z.damage(dmg, "leg", away.normalized(), 3.0, false, at)
	game.fx.spray(at, Vector3.UP, Color8(122, 10, 10), 7, 2.5, 0.8, true)
	game.audio.play("chomp", at)
	if not res.kill:
		game.add_points(10)
	elif mega:
		game.add_points(50)
		game.hud.callout_small("HAMMY KILL +50")
	if mega:
		if randf() < 0.18:
			game.audio.play("hamroar", pos, 0, randf_range(1.0, 1.25))
		# the zap jumps to one more zombie
		var best = null
		var bd := 6.0
		for o in game.zombies:
			if o == z or not o.alive:
				continue
			var dd: float = o.global_position.distance_to(z.global_position)
			if dd < bd:
				bd = dd
				best = o
		if best != null:
			var b2: Vector3 = best.global_position + Vector3(0, 1.0, 0)
			game.fx.arc(at, b2, Color(0.75, 0.5, 1.0))
			game.audio.play("zap", b2, -4, 1.3)
			var r2: Dictionary = best.damage(dmg * 0.5, "body", (b2 - at).normalized(), 2.0, false, b2)
			if r2.kill:
				game.add_points(50)

func _floor(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.35, 0), p + Vector3(0, -3, 0), 1)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	return r.position.y if not r.is_empty() else p.y - 3.0

func _process(dt: float) -> void:
	t += dt
	var P = game.player
	if not free:
		if wheel_t > 0:
			wheel_t -= dt
			wheel.rotate_object_local(Vector3.UP, dt * 14)
			pos = Vector3(31.45, HOME.y + 0.06, -3.3)
			ry = PI
			run = 1
		else:
			pos = HOME + Vector3(-0.12 + sin(t * 0.6) * 0.1, 0.03, sin(t * 0.37) * 0.08)
			ry = sin(t * 0.5) * 1.8
			run = 1.0 if maxf(0, sin(t * 1.7)) > 0.8 else 0.0
	elif in_pap > 0:
		in_pap -= dt
		if in_pap <= 0:
			_go_mega()
	elif game.state == "play" or game.state == "inter":
		bite_cd -= dt
		retarget -= dt
		if retarget <= 0 or (tgt != null and (not is_instance_valid(tgt) or not tgt.alive)):
			retarget = 0.3
			tgt = null
			var bd := 10.0
			for z in game.zombies:
				if not z.alive or z.emerge > 0:
					continue
				if z.global_position.distance_to(P.global_position) > 8 or absf(z.global_position.y - pos.y) > 1.2:
					continue
				var dh: float = Vector2(z.global_position.x - pos.x, z.global_position.z - pos.z).length()
				if dh < bd:
					bd = dh
					tgt = z
		var target: Vector3
		if tgt != null:
			target = tgt.global_position
		else:
			var f: Vector3 = -P.global_transform.basis.z
			target = P.global_position - f * 1.3 + Vector3(f.z, 0, -f.x) * 0.6
		var dx := target.x - pos.x
		var dz := target.z - pos.z
		var d := maxf(Vector2(dx, dz).length(), 0.001)
		var stop := 0.55 if tgt != null else 0.4
		if d > stop:
			var spd := (8.5 if tgt != null else 6.5) * (1.35 if d > 4 else 1.0) * (1.4 if mega else 1.0)
			var step := minf(d - stop, spd * dt)
			var np := pos + Vector3(dx / d * step, 0, dz / d * step)
			var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.12, 0), np + Vector3(dx / d * 0.1, 0.12, dz / d * 0.1), 1)
			if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				pos.x = np.x
				pos.z = np.z
			run = 1
			var dr := wrapf(atan2(dx, dz) - ry, -PI, PI)
			ry += dr * minf(1.0, dt * 14)
		else:
			run = 0
		var fy := _floor(pos)
		if fy >= pos.y - 0.02 and vy <= 0:
			pos.y = fy
			vy = 0
		else:
			vy -= 20 * dt
			pos.y = maxf(fy, pos.y + vy * dt)
		if tgt != null and d < stop + 0.3 and bite_cd <= 0:
			bite_cd = 0.32 if mega else 0.42
			_bite(tgt)
		# never lose him: if he falls behind he pops up at your heels
		var far: bool = Vector2(P.global_position.x - pos.x, P.global_position.z - pos.z).length() > 15 or absf(P.global_position.y - pos.y) > 2.2
		leash_t = leash_t + dt if far else 0.0
		if leash_t > 1.2:
			leash_t = 0
			var f2: Vector3 = -P.global_transform.basis.z
			pos = P.global_position - f2 * 1.1
			vy = 2.5
			tgt = null
			game.fx.puff(pos + Vector3(0, 0.1, 0), Color8(216, 200, 168), false, 0.05, 0.45, 0.35, 0.3, 0.05, 0.5)
		sq_t -= dt
		if sq_t <= 0:
			sq_t = randf_range(4, 9)
			if P.global_position.distance_to(pos) < 10:
				game.audio.play("squeak", pos + Vector3(0, 0.1, 0))
	var hop := absf(sin(t * 24)) * 0.035 if run > 0 else 0.0
	g.global_position = pos + Vector3(0, hop, 0)
	g.rotation.y = ry
	head.rotation.x = 0.0 if run > 0 else sin(t * 9) * 0.12
