extends Node3D
## The silly weapons: Textbook Launcher (arcing hardcovers), Dodgeball Cannon (ricochets between zombies),
## Trombone (a sonic cone) and the Detention Slip (sends a zombie away).

var game
var shots: Array = []      # {n, v, kind, t, up, bounces, chains, hit:[]}
var wah_cd := 0.0
var book_mats: Array = []
var ball_mat: StandardMaterial3D
var slip_mat: StandardMaterial3D

func setup(g) -> void:
	game = g
	for c in [Color8(150, 30, 30), Color8(30, 70, 150), Color8(40, 110, 50), Color8(120, 60, 140), Color8(200, 140, 30)]:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.8
		book_mats.append(m)
	ball_mat = StandardMaterial3D.new()
	ball_mat.albedo_color = Color8(200, 40, 40)
	ball_mat.roughness = 0.5
	slip_mat = StandardMaterial3D.new()
	slip_mat.albedo_color = Color8(250, 160, 200)
	slip_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

## called by the player instead of the hitscan loop
func fire(wd: Dictionary, origin: Vector3, dir: Vector3, muzzle: Vector3) -> void:
	var up: bool = wd.get("up", false)
	if wd.get("cone", false):
		_cone(wd, origin, dir, muzzle, up)
		return
	match String(wd.proj):
		"book":
			var n := 3 if up else 1
			for i in n:
				var d := dir
				if i > 0:
					d = dir.rotated(Vector3.UP, deg_to_rad(5.0 if i == 1 else -5.0)).normalized()
				_spawn("book", muzzle, d * 21.0 + Vector3(0, 2.0, 0), wd, up)
		"dodge":
			_spawn("dodge", muzzle, dir * 27.0, wd, up)
		"slip":
			_spawn("slip", muzzle, dir * 30.0, wd, up)
		"volc":
			_spawn("volc", muzzle, dir * 19.0 + Vector3(0, 3.0, 0), wd, up)

func _spawn(kind: String, at: Vector3, v: Vector3, wd: Dictionary, up: bool) -> void:
	var m := MeshInstance3D.new()
	match kind:
		"book":
			var b := BoxMesh.new()
			b.size = Vector3(0.24, 0.06, 0.32)
			m.mesh = b
			m.material_override = book_mats[randi() % book_mats.size()]
			var pages := MeshInstance3D.new()
			var pb := BoxMesh.new()
			pb.size = Vector3(0.22, 0.045, 0.302)
			pages.mesh = pb
			var pm := StandardMaterial3D.new()
			pm.albedo_color = Color8(236, 230, 214)
			pages.material_override = pm
			pages.position.x = 0.012
			m.add_child(pages)
		"dodge":
			var s := SphereMesh.new()
			s.radius = 0.13
			s.height = 0.26
			s.radial_segments = 10
			s.rings = 6
			m.mesh = s
			m.material_override = ball_mat
			if up:
				var l := OmniLight3D.new()
				l.light_color = Color8(80, 255, 170)
				l.omni_range = 2.0
				l.light_energy = 0.8
				m.add_child(l)
		"volc":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.03
			cm.bottom_radius = 0.13
			cm.height = 0.16
			cm.radial_segments = 8
			m.mesh = cm
			var vm := StandardMaterial3D.new()
			vm.albedo_color = Color8(120, 92, 60)
			m.material_override = vm
			var l := OmniLight3D.new()
			l.light_color = Color8(255, 120, 40)
			l.omni_range = 2.0
			l.light_energy = 0.8
			m.add_child(l)
		"slip":
			var q := QuadMesh.new()
			q.size = Vector2(0.2, 0.12)
			m.mesh = q
			m.material_override = slip_mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	m.global_position = at
	shots.append({"n": m, "v": v, "kind": kind, "t": 0.0, "up": up, "dmg": float(wd.dmg), "bounces": 0, "chains": 0, "hit": [], "spin": Vector3(randf_range(6, 12), randf_range(-3, 3), 0)})

func _zombie_at(p: Vector3, r: float, skip: Array):
	for z in game.zombies:
		if not z.alive or z in skip:
			continue
		var c: Vector3 = z.global_position
		var sc: float = maxf(z.bscale, 1.0)
		var top: float = c.y + (0.7 if z.crawler else 1.9 * sc)
		if p.y < c.y - 0.2 or p.y > top:
			continue
		if Vector2(p.x - c.x, p.z - c.z).length() < r + 0.32 * sc:
			return z
	return null

func _next_target(from: Vector3, skip: Array, rng := 11.0):
	var best = null
	var bd := rng
	var space := get_world_3d().direct_space_state
	for z in game.zombies:
		if not z.alive or z in skip:
			continue
		var c: Vector3 = z.global_position + Vector3(0, 0.5 if z.crawler else 1.1, 0)
		var d := c.distance_to(from)
		if d < bd and space.intersect_ray(PhysicsRayQueryParameters3D.create(from, c, 1)).is_empty():
			bd = d
			best = z
	return best

func _process(dt: float) -> void:
	if game == null:
		return
	wah_cd -= dt
	_step_foam(dt)
	var space := get_world_3d().direct_space_state
	var i := shots.size() - 1
	while i >= 0:
		var s = shots[i]
		s.t += dt
		var m: MeshInstance3D = s.n
		var g := 11.0 if s.kind == "book" or s.kind == "volc" else (5.0 if s.kind == "dodge" else 0.0)
		s.v.y -= g * dt
		var from := m.global_position
		var to: Vector3 = from + s.v * dt
		m.rotate_object_local(Vector3.RIGHT, s.spin.x * dt)
		m.rotate_object_local(Vector3.UP, s.spin.y * dt)
		var dead := false
		# swept: check the whole step for zombies so fast shots can't tunnel through
		var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1 | 16))
		var end: Vector3 = to if r.is_empty() else r.position
		var steps := maxi(1, ceili(from.distance_to(end) / 0.2))
		var z = null
		var zp := end
		for k in range(1, steps + 1):
			zp = from.lerp(end, float(k) / steps)
			z = _zombie_at(zp, 0.18, s.hit)
			if z != null:
				break
		if z != null:
			dead = _hit_zombie(s, z, zp)
		elif not r.is_empty():
			dead = _hit_world(s, r)
		else:
			m.global_position = to
		if s.t > 6.0 or (s.kind == "slip" and s.t > 1.5):
			dead = true
		if dead:
			if s.n != null and is_instance_valid(s.n):
				s.n.queue_free()
			shots.remove_at(i)
		i -= 1

## returns true when the projectile is spent
func _hit_zombie(s: Dictionary, z, at: Vector3) -> bool:
	var m: MeshInstance3D = s.n
	var dir: Vector3 = s.v.normalized()
	match s.kind:
		"book":
			var hd: bool = at.y > z.global_position.y + 1.5 * maxf(z.bscale, 1.0) and not z.crawler
			var res: Dictionary = z.damage(s.dmg, "head" if hd else "body", dir, 9.0, false, at)
			if z.alive and z.kind != "boss":
				z.stagger = 1.6
				z.velocity += Vector3(dir.x, 0, dir.z).normalized() * 9.0 + Vector3(0, 2.5, 0)
			_score(res)
			game.audio.play("bookslam", at, 4, randf_range(0.9, 1.1))
			game.fx.spray(at, -dir, Color8(236, 230, 214), 6, 3, 0.5)
			game.player.shake = maxf(game.player.shake, 0.06)
			# bounce off them
			s.hit.append(z)
			s.v = Vector3(-s.v.x * 0.3, 4.0, -s.v.z * 0.3)
			s.bounces += 1
			return s.bounces > 2
		"dodge":
			var res: Dictionary = z.damage(s.dmg, "body", dir, 6.0, false, at)
			if z.alive and z.kind != "boss":
				z.stagger = 0.8
				z.velocity += Vector3(dir.x, 0, dir.z).normalized() * 6.0
			_score(res)
			game.audio.play("bounce", at, 4, randf_range(0.9, 1.15))
			s.hit.append(z)
			s.chains += 1
			if s.chains > (5 if s.up else 3):
				return true
			var nt = _next_target(at, s.hit)
			if nt == null:
				s.v = Vector3(-s.v.x, 3.0, -s.v.z) * 0.5
				return false
			var c: Vector3 = nt.global_position + Vector3(0, 0.5 if nt.crawler else 1.2, 0)
			s.v = (c - at).normalized() * 24.0
			m.global_position = at
			# Doublemint: the ball splits in two
			if s.up and shots.size() < 24:
				var nt2 = _next_target(at, s.hit + [nt])
				if nt2 != null:
					var c2: Vector3 = nt2.global_position + Vector3(0, 1.2, 0)
					_spawn("dodge", at, (c2 - at).normalized() * 24.0, {"dmg": s.dmg}, true)
					var ns = shots[shots.size() - 1]
					ns.hit = s.hit.duplicate()
					ns.chains = s.chains
			return false
		"slip":
			_detention(z, s.up, at)
			return true
		"volc":
			z.damage(s.dmg, "body", dir, 4.0, false, at)
			erupt(z.global_position, s.dmg, s.up)
			return true
	return true

func _hit_world(s: Dictionary, r: Dictionary) -> bool:
	var m: MeshInstance3D = s.n
	var n: Vector3 = r.normal
	var at: Vector3 = r.position + n * 0.12
	if r.collider and r.collider.has_method("get") and r.collider is RigidBody3D:
		game.physics.wake(r.collider)
		r.collider.apply_central_impulse(s.v.normalized() * 3.0)
	match s.kind:
		"book":
			s.bounces += 1
			game.audio.play("bookslam", at, -2, randf_range(1.0, 1.3))
			if s.bounces > 2 or s.v.length() < 4.0:
				# it just lies there now
				m.global_position = at
				game.physics.gib(m, s.v * 0.2, false)
				s.n = null
				return true
			s.v = s.v.bounce(n) * 0.45
			m.global_position = at
			return false
		"dodge":
			s.bounces += 1
			game.audio.play("bounce", at, -2, randf_range(0.95, 1.2))
			if s.bounces > 6:
				return true
			s.v = s.v.bounce(n) * 0.8
			m.global_position = at
			# bank shots: off the wall into the next zombie
			var nt = _next_target(at, s.hit, 9.0)
			if nt != null:
				s.v = ((nt.global_position + Vector3(0, 1.2, 0)) - at).normalized() * maxf(s.v.length(), 16.0)
			return false
		"slip":
			game.fx.puff(at, Color8(240, 240, 236), false, 0.05, 0.3, 0.4, 0.2, 0.05, 0.5)
			return true
		"volc":
			erupt(r.position, s.dmg, s.up)
			return true
	return true

# ---------------------------------------------------------------- Volcano Launcher foam
var foams: Array = []      # {pos, r, t, tick, dmg, up, n (node), mat}
var foam_mat: StandardMaterial3D

## a baking-soda eruption: a fizzing foam puddle that slows and eats away at zombies. Puddles that touch merge.
func erupt(at: Vector3, dmg: float, up: bool) -> void:
	var y: float = game._floor_y(at + Vector3(0, 0.3, 0))
	var p := Vector3(at.x, y, at.z)
	game.audio.play("erupt", p, 4, randf_range(0.9, 1.1))
	for k in 6:
		game.fx.puff(p + Vector3(randf_range(-0.3, 0.3), 0.2, randf_range(-0.3, 0.3)), Color8(240, 236, 220) if k % 2 else Color8(255, 150, 70), false, 0.15, randf_range(0.6, 1.1), 0.7, randf_range(1.0, 2.2), 0.3, 0.8)
	game.fx.spray(p + Vector3(0, 0.2, 0), Vector3.UP, Color8(255, 120, 40), 12, 5, 0.6)
	var r0 := 2.1 if up else 1.6
	for f in foams:
		if Vector2(f.pos.x - p.x, f.pos.z - p.z).length() < f.r + r0 * 0.8 and absf(f.pos.y - p.y) < 1.0:
			# merge into the puddle it touches: it grows and lasts longer
			f.r = minf(f.r + 0.45, 4.2)
			f.t = maxf(f.t, 6.5 if not up else 9.0)
			f.dmg = maxf(f.dmg, dmg)
			f.up = f.up or up
			f.n.scale = Vector3(f.r, 1, f.r)
			return
	if foam_mat == null:
		foam_mat = StandardMaterial3D.new()
		foam_mat.albedo_color = Color(0.94, 0.93, 0.86, 0.92)
		foam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		foam_mat.roughness = 1.0
	var n := Node3D.new()
	game.world.add_child(n)
	n.global_position = p + Vector3(0, 0.03, 0)
	for k in 5:
		var b := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = randf_range(0.35, 0.55)
		sm.height = sm.radius * 0.5
		sm.radial_segments = 10
		sm.rings = 4
		b.mesh = sm
		b.material_override = foam_mat
		var a := randf() * TAU
		var rr := 0.0 if k == 0 else randf_range(0.3, 0.6)
		b.position = Vector3(cos(a) * rr, 0.02, sin(a) * rr)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(b)
	n.scale = Vector3(r0, 1, r0)
	foams.append({"pos": p, "r": r0, "t": 6.5 if not up else 9.0, "tick": 0.0, "dmg": dmg, "up": up, "n": n})

func _step_foam(dt: float) -> void:
	var i := foams.size() - 1
	while i >= 0:
		var f = foams[i]
		f.t -= dt
		f.tick -= dt
		var k: float = clampf(f.t / 1.2, 0.0, 1.0)
		f.n.scale = Vector3(f.r * (0.6 + 0.4 * k), k, f.r * (0.6 + 0.4 * k))
		if randf() < dt * 8.0:
			var a := randf() * TAU
			var rr: float = randf() * f.r * 0.8
			game.fx.puff(f.pos + Vector3(cos(a) * rr, 0.15, sin(a) * rr), Color8(255, 140, 60) if f.up and randf() < 0.5 else Color8(245, 242, 230), f.up, 0.08, 0.3, 0.6, 0.6, 0.05, 0.7)
		if f.tick <= 0:
			f.tick = 0.4
			for z in game.zombies:
				if not z.alive:
					continue
				var d: Vector3 = z.global_position - f.pos
				if absf(d.y) > 1.2 or Vector2(d.x, d.z).length() > f.r:
					continue
				z.slow_t = maxf(z.slow_t, 0.6)
				var res: Dictionary = z.damage(f.dmg * (0.4 if f.up else 0.25) * (0.4 if z.kind == "boss" else 1.0), "body", Vector3.UP, 1.0, false, z.global_position + Vector3(0, 0.4, 0))
				if res.get("kill", false):
					game.hud.hit(true)
			if randf() < 0.3:
				game.audio.play("fizz", f.pos, -10, randf_range(1.2, 1.6))
		if f.t <= 0:
			f.n.queue_free()
			foams.remove_at(i)
		i -= 1

func _score(res: Dictionary) -> void:
	game.hud.hit(res.get("kill", false))
	if not res.get("kill", false):
		game.add_points(10)

## the Detention Slip: chalk dust, and the zombie is sent to the far end of the school
func _detention(z, up: bool, at: Vector3) -> void:
	var c: Vector3 = z.global_position + Vector3(0, 1.0, 0)
	for k in 5:
		game.fx.puff(c + Vector3(randf_range(-0.3, 0.3), randf_range(-0.6, 0.8), randf_range(-0.3, 0.3)), Color8(240, 240, 236), false, 0.2, randf_range(1.0, 1.6), 0.9, 0.4, 0.3, 0.8)
	game.audio.play("poof", c, 4)
	if z.kind == "boss":
		game.hud.callout_small("BOSSES DON'T DO DETENTION")
		z.stagger = 0.5
		return
	if up:
		# SUSPENSION: gone for good, counts as a kill
		z.alive = false
		z.collision_layer = 0
		game.on_zombie_killed(z, false, false)
		game.add_points(50)
		game.hud.callout_small("SUSPENDED!")
		z.queue_free()
		return
	# send them to the spawn point furthest from you
	var best: Vector3 = z.global_position
	var bd := -1.0
	for s in game.world.data.spawns:
		if game.open_areas.has(s.area):
			var p := Vector3(s.pos[0], s.pos[1], s.pos[2])
			var d: float = p.distance_to(game.player.global_position)
			if d > bd:
				bd = d
				best = p
	z.global_position = best
	z.velocity = Vector3.ZERO
	z.emerge = 2.5
	z.stagger = 1.0
	game.add_points(50)
	game.hud.callout_small("DETENTION! +50")

## the Trombone: a blast of brass that staggers and shoves everything in front of you
func _cone(wd: Dictionary, origin: Vector3, dir: Vector3, muzzle: Vector3, up: bool) -> void:
	var rng := 10.0 if up else 7.5
	var half := deg_to_rad(40.0 if up else 32.0)
	var space := get_world_3d().direct_space_state
	var kills := 0
	var hits := 0
	for z in game.zombies.duplicate():
		if not z.alive:
			continue
		var c: Vector3 = z.global_position + Vector3(0, 0.5 if z.crawler else 1.1, 0)
		var to := c - origin
		var d := to.length()
		if d > rng or dir.angle_to(to / maxf(d, 0.01)) > half:
			continue
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, c, 1)).is_empty():
			continue
		var k := 1.0 - 0.5 * d / rng
		var res: Dictionary = z.damage(float(wd.dmg) * k, "body", to.normalized(), 7.0, false, c)
		hits += 1
		if res.get("kill", false):
			kills += 1
		elif z.kind != "boss":
			z.stagger = 1.1
			z.velocity += Vector3(to.x, 0, to.z).normalized() * 11.0 * k
	# the sound you can see: brass rings rolling out of the bell
	for i in 7:
		var p := muzzle + dir * (0.6 + i * rng / 7.0)
		game.fx.puff(p, Color8(240, 200, 90), true, 0.2 + i * 0.12, 0.6 + i * 0.3, 0.35, 0.0, 0.15 + i * 0.12, 0.35)
	game.player.shake = maxf(game.player.shake, 0.08)
	if hits > 0:
		game.hud.hit(kills > 0)
	# the sad trombone is a reward for a massacre, not every kill
	if kills >= 3 and wah_cd <= 0:
		wah_cd = 12.0
		game.audio.play("wahwah", null, -2)
		if kills >= 3:
			game.callout("SAD TROMBONE", "+%d" % (kills * 25))
			game.add_points(kills * 25)
