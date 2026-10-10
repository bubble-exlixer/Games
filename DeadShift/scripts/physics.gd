extends Node3D
## Real physics everywhere: ragdoll corpses, loose props (chairs, trash cans, soda cans), breakable glass,
## lockers that bang open, a vending machine that spills cans, fire extinguishers that rocket around,
## swinging pendant lamps, ceiling tiles that drop in explosions, a bookshelf you can push across a doorway.

const WORLD := 1
const ZOMBIE_BODY := 2
const SHOOT := 16          # things bullets hit but nothing walks into
const DEBRIS := 32         # loose rigid bodies

var game
var world
var detail := 1.0          # settings: 0.5 low, 1 normal (caps)
var ragdolls: Array = []   # {bodies: Array, t: float}
var props: Array = []      # RigidBody3D (chairs, cans, bins, shards, tiles, gibs)
var lamps: Array = []      # {pivot, cord, len, a: Vector2, v: Vector2, light}
var lockers: Array = []
var extinguishers: Array = []
var clouds: Array = []     # {pos, t}
var shelf: Dictionary = {}
var vending: Dictionary = {}
var blood_mat: StandardMaterial3D
var mats := {}
var snd_t := {}

func setup(g) -> void:
	game = g
	world = g.world
	blood_mat = StandardMaterial3D.new()
	blood_mat.albedo_texture = g.fx.splat_tex[0]
	blood_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blood_mat.uv1_triplanar = true
	blood_mat.uv1_world_triplanar = true
	blood_mat.uv1_scale = Vector3(1.6, 1.6, 1.6)
	blood_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	blood_mat.render_priority = 1
	_chairs()
	_bins()
	_glass()
	_lockers()
	_vending()
	_extinguishers()
	_pendants()
	_bookshelf()
	world.rebake()

func _m(c: Color, metal := 0.0, rough := 0.9) -> StandardMaterial3D:
	var key := c.to_html() + str(metal)
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	mats[key] = m
	return m

func _mesh_box(parent: Node3D, size: Vector3, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

func _shape_box(body: CollisionObject3D, size: Vector3, pos := Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = pos
	body.add_child(cs)

func _floor_y(p: Vector3, from_up := 1.5) -> float:
	var r: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(0, from_up, 0), p - Vector3(0, 3, 0), WORLD))
	return r.position.y if not r.is_empty() else p.y

## a loose rigid prop; kind picks its impact sound
func _rigid(kind: String, mass: float, pos: Vector3, rot := Vector3.ZERO) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.collision_layer = DEBRIS
	b.collision_mask = WORLD | DEBRIS
	b.mass = mass
	b.linear_damp = 0.15
	b.angular_damp = 0.8
	b.contact_monitor = true
	b.max_contacts_reported = 2
	b.set_meta("kind", kind)
	b.body_entered.connect(_impact.bind(b))
	add_child(b)
	b.global_position = pos
	b.rotation = rot
	props.append(b)
	return b

func _impact(_other, b: RigidBody3D) -> void:
	if not is_instance_valid(b):
		return
	var sp := b.linear_velocity.length()
	if sp < 1.4:
		return
	var now := Time.get_ticks_msec()
	if now - int(snd_t.get(b.get_instance_id(), 0)) < 120:
		return
	snd_t[b.get_instance_id()] = now
	var kind: String = b.get_meta("kind", "wood")
	var vol := clampf(-22.0 + sp * 2.2, -22.0, -2.0)
	match kind:
		"wood":
			game.audio.play("wood", b.global_position, vol, randf_range(0.9, 1.2))
		"metal":
			game.audio.play("clang", b.global_position, vol - 4, randf_range(1.1, 1.5))
		"can":
			game.audio.play("tink", b.global_position, vol - 2, randf_range(0.8, 1.2))
		"glass":
			game.audio.play("tink", b.global_position, vol - 8, randf_range(1.5, 2.0))
		"tile":
			game.audio.play("chip", b.global_position, vol, randf_range(0.8, 1.1))
		"flesh":
			game.audio.play("splat", b.global_position, vol - 4, randf_range(0.8, 1.1))
			if sp > 3 and randf() < 0.5:
				game.fx.splat(b.global_position, randf_range(0.3, 0.6))
		_:
			game.audio.play("thud", b.global_position, vol, randf_range(0.9, 1.1))

## a pure rotation for a physics body (mirrored or scaled bases upset the solver)
static func _rot(b: Basis) -> Basis:
	var o := b.orthonormalized()
	if o.determinant() < 0:
		o.x = -o.x
	return o

func _cap(list: Array, n: int) -> void:
	while list.size() > n:
		var o = list.pop_front()
		if o is Node and is_instance_valid(o):
			o.queue_free()

# ---------------------------------------------------------------- loose props
func _chair(pos: Vector3, ry: float, col: Color) -> void:
	var b := _rigid("wood", 4.0, pos + Vector3(0, 0.5, 0), Vector3(0, ry, 0))
	var seat := _m(col)
	var leg := _m(Color8(60, 60, 64), 0.6, 0.5)
	_mesh_box(b, Vector3(0.42, 0.04, 0.42), seat, Vector3(0, 0, 0))
	_mesh_box(b, Vector3(0.42, 0.42, 0.04), seat, Vector3(0, 0.24, 0.19))
	for x in [-0.18, 0.18]:
		for z in [-0.18, 0.18]:
			_mesh_box(b, Vector3(0.03, 0.46, 0.03), leg, Vector3(x, -0.25, z))
	_shape_box(b, Vector3(0.42, 0.5, 0.42), Vector3(0, -0.22, 0))
	_shape_box(b, Vector3(0.42, 0.42, 0.05), Vector3(0, 0.24, 0.19))
	b.set_meta("small", true)
	b.set_meta("rest", true)
	b.freeze = true           # sits perfectly still until something hits it

func _chairs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for x in [22.5, 25.1, 27.7, 30.3]:
		for z in [-2.0, 0.4, 2.8]:
			if rng.randf() < 0.85:
				_chair(Vector3(x + rng.randf_range(-0.1, 0.1), 0, z + 0.62), rng.randf_range(-0.3, 0.3), Color8(150, 120, 80))
	for t in [[0, -2], [9, -2], [0, 4], [3, 10], [9, 10]]:
		for k in 1:
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var x: float = t[0] + rng.randf_range(-1.5, 1.5)
			var z: float = t[1] + side * 0.85
			_chair(Vector3(x, 0, z), (0.0 if side > 0 else PI) + rng.randf_range(-0.5, 0.5), [Color8(170, 60, 50), Color8(60, 90, 140), Color8(200, 160, 60)][rng.randi() % 3])

func _bins() -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.26
	cm.bottom_radius = 0.22
	cm.height = 0.72
	cm.radial_segments = 10
	for p in [Vector3(-12.6, 0, -5.8), Vector3(12.6, 0, 13.6), Vector3(-12.6, 0, 13.6), Vector3(-24, 0, -6.1), Vector3(26, 0, -8.6), Vector3(-34, 0, 4.2), Vector3(-8, 4.0, -28.9)]:
		var b := _rigid("metal", 3.0, p + Vector3(0, 0.37, 0))
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = _m(Color8(70, 90, 70), 0.4, 0.6)
		b.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 0.25
		sh.height = 0.72
		cs.shape = sh
		b.add_child(cs)
		b.set_meta("small", true)
		b.set_meta("rest", true)
		b.freeze = true

## props that rest frozen (chairs, bins, trophies) come alive when touched
func wake(b) -> void:
	if b is RigidBody3D and b.get_meta("rest", false) and b.freeze:
		b.freeze = false
		b.sleeping = false

## soda can (from the vending machine) or any small debris
func spawn_can(pos: Vector3, vel: Vector3) -> void:
	var b := _rigid("can", 0.35, pos, Vector3(randf() * 3, randf() * 3, randf() * 3))
	var cm := CylinderMesh.new()
	cm.top_radius = 0.033
	cm.bottom_radius = 0.033
	cm.height = 0.12
	cm.radial_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = _m([Color8(190, 30, 30), Color8(40, 90, 190), Color8(230, 200, 60), Color8(60, 160, 70)][randi() % 4], 0.5, 0.4)
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.035
	sh.height = 0.12
	cs.shape = sh
	b.add_child(cs)
	b.linear_velocity = vel
	b.angular_velocity = Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10))
	b.set_meta("small", true)
	b.set_meta("temp", 40.0)

## takes over a gore mesh and makes it a real physics object (heads, arms, legs)
func gib(n: Node3D, vel: Vector3, bleed := true) -> RigidBody3D:
	var xf := n.global_transform
	var b := _rigid("flesh" if bleed else "wood", 1.5, xf.origin)
	b.global_transform = Transform3D(_rot(xf.basis), xf.origin)
	if n.get_parent():
		n.get_parent().remove_child(n)
	b.add_child(n)
	n.global_transform = xf
	if n is GeometryInstance3D:
		n.material_overlay = null
	var aabb := AABB(Vector3.ZERO, Vector3.ONE * 0.1)
	if n is MeshInstance3D and n.mesh:
		aabb = (b.global_transform.affine_inverse() * n.global_transform) * n.mesh.get_aabb()
	_shape_box(b, (aabb.size * 0.85).max(Vector3.ONE * 0.06), aabb.get_center())
	b.linear_velocity = vel
	b.angular_velocity = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
	b.set_meta("temp", 12.0)
	b.set_meta("bleed", 1.5 if bleed else 0.0)
	_cap_props()
	return b

func _cap_props() -> void:
	var temps := props.filter(func(p): return is_instance_valid(p) and p.has_meta("temp"))
	var cap := int(90 * detail)
	if temps.size() > cap:
		for k in temps.size() - cap:
			props.erase(temps[k])
			temps[k].queue_free()

# ---------------------------------------------------------------- ragdolls
const RAG_PARTS := ["core", "spine", "head", "armL1", "armL2", "armR1", "armR2", "legL1", "legL2", "legR1", "legR2"]

func ragdoll(z, dir: Vector3, power: float, head: bool, blast: bool) -> void:
	var bodies := {}
	var parent_of := {}
	for j in z.sample.joints:
		parent_of[j.n] = j.parent
	z.vis.force_update_transform()
	for jn in RAG_PARTS:
		if not z.joints.has(jn):
			continue
		var jnode: Node3D = z.joints[jn]
		var meshes: Array = []
		for c in jnode.get_children():
			if c is MeshInstance3D and c.visible:
				meshes.append(c)
		if jn == "core" and z.joints.has("root"):
			for c in z.joints["root"].get_children():
				if c is MeshInstance3D and c.visible:
					meshes.append(c)
		if meshes.is_empty():
			continue
		var xf: Transform3D = jnode.global_transform
		var b := RigidBody3D.new()
		b.collision_layer = DEBRIS
		b.collision_mask = WORLD | DEBRIS      # bodies pile up on each other instead of melting together
		var big: bool = jn in ["core", "spine"]
		b.mass = (8.0 if big else (4.0 if jn == "head" else 2.0)) * z.bscale
		b.linear_damp = 0.4
		b.angular_damp = 2.0
		b.set_meta("kind", "flesh")
		b.set_meta("ragdoll", true)
		add_child(b)
		b.global_transform = Transform3D(_rot(xf.basis), xf.origin)
		var aabb: AABB
		var first := true
		for m in meshes:
			var mx: Transform3D = m.global_transform
			m.get_parent().remove_child(m)
			b.add_child(m)
			m.global_transform = mx
			m.material_overlay = game.char_mat if z.charred else null
			var a: AABB = (b.global_transform.affine_inverse() * mx) * m.mesh.get_aabb()
			aabb = a if first else aabb.merge(a)
			first = false
		_shape_box(b, (aabb.size * 0.9).max(Vector3.ONE * 0.08), aabb.get_center())
		bodies[jn] = b
	if bodies.is_empty():
		return
	# the parts of one body never collide with each other (only the joints hold them together)
	var bl: Array = bodies.values()
	for i in bl.size():
		for k in range(i + 1, bl.size()):
			bl[i].add_collision_exception_with(bl[k])
	# joints: each part hangs off the nearest ancestor that made it into the ragdoll
	for jn in bodies:
		var p = parent_of.get(jn)
		while p != null and not bodies.has(p):
			p = parent_of.get(p)
		if jn.begins_with("leg") and jn.ends_with("1") and bodies.has("core"):
			p = "core"
		if p == null or not bodies.has(p):
			continue
		var cj := ConeTwistJoint3D.new()
		add_child(cj)
		cj.global_position = z.joints[jn].global_position
		cj.node_a = bodies[p].get_path()
		cj.node_b = bodies[jn].get_path()
		var limb_end: bool = jn.ends_with("2")
		cj.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(30.0 if limb_end else 50.0))
		cj.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(15.0 if limb_end else 30.0))
		bodies[jn].set_meta("joint", cj)
	var hdir := Vector3(dir.x, 0, dir.z)
	if hdir.length() < 0.1:
		hdir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	hdir = (hdir.normalized() + Vector3(randf_range(-0.35, 0.35), 0, randf_range(-0.35, 0.35))).normalized()
	var push := hdir * clampf(power, 2.0, 12.0) * (1.6 if blast else 0.6)
	var base_v: Vector3 = z.velocity * 0.5
	var tip_axis := hdir.cross(Vector3.UP)          # topple away from the shot
	for jn in bodies:
		var b: RigidBody3D = bodies[jn]
		b.can_sleep = false
		var high: bool = jn in ["spine", "head", "armL1", "armR1", "armL2", "armR2"]
		b.linear_velocity = base_v + push * randf_range(0.7, 1.1) + Vector3(0, (4.0 if blast else 0.6), 0) + (hdir * 2.2 if high else -hdir * 0.4)
		b.angular_velocity = -tip_axis * randf_range(2.0, 3.5) + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * (3.0 if blast else 1.0)
	get_tree().create_timer(1.5).timeout.connect(func():
		for b in bodies.values():
			if is_instance_valid(b):
				b.can_sleep = true)
	if head and bodies.has("head"):
		bodies["head"].linear_velocity += Vector3(0, 2.5, 0) + push * 0.8
	ragdolls.append({"bodies": bodies.values(), "t": 0.0})
	while ragdolls.size() > int(12 * detail):
		_free_ragdoll(ragdolls.pop_front())

## a home-run swing: send the newest body flying
func launch_last(v: Vector3) -> void:
	if ragdolls.is_empty():
		return
	for b in ragdolls.back().bodies:
		if is_instance_valid(b):
			b.linear_velocity += v * randf_range(0.85, 1.1)
			b.angular_velocity += Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))

## Staple Cannon kills: the body gets stapled to the wall behind it
func staple_pin(at: Vector3, dir: Vector3) -> void:
	if ragdolls.is_empty():
		return
	var r: Dictionary = ragdolls.back()
	var best: RigidBody3D = null
	var bd := 99.0
	for b in r.bodies:
		if is_instance_valid(b) and b.global_position.distance_to(at) < bd:
			bd = b.global_position.distance_to(at)
			best = b
	if best == null:
		return
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at, at + dir * 2.5, WORLD))
	if hit.is_empty() or absf(hit.normal.y) > 0.5:
		return
	var wall: Vector3 = hit.position
	for b in r.bodies:
		if is_instance_valid(b):
			b.global_position += (wall + hit.normal * 0.22) - best.global_position
	var anchor := StaticBody3D.new()
	anchor.collision_layer = 0
	anchor.collision_mask = 0
	add_child(anchor)
	anchor.global_position = wall
	var pj := PinJoint3D.new()
	add_child(pj)
	pj.global_position = wall + hit.normal * 0.12
	pj.node_a = best.get_path()
	pj.node_b = anchor.get_path()
	best.set_meta("joint2", pj)
	var st := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.18, 0.03, 0.03)
	st.mesh = bm
	st.material_override = _m(Color8(190, 192, 198), 0.9, 0.3)
	add_child(st)
	st.global_position = wall + hit.normal * 0.02
	game.fx.spark(wall, hit.normal)
	game.audio.play("clang", wall, -4, 1.6)
	get_tree().create_timer(10.0).timeout.connect(func():
		if is_instance_valid(st):
			st.queue_free()
		if is_instance_valid(pj):
			pj.queue_free()
		if is_instance_valid(anchor):
			anchor.queue_free())

func _free_ragdoll(r: Dictionary) -> void:
	for b in r.bodies:
		if is_instance_valid(b):
			if b.has_meta("joint") and is_instance_valid(b.get_meta("joint")):
				b.get_meta("joint").queue_free()
			b.queue_free()

## bullets nudge corpses and loose props
func shot(body: Node, at: Vector3, dir: Vector3, power: float) -> void:
	if body is RigidBody3D:
		wake(body)
		if body.get_meta("ragdoll", false):
			# corpses take a gentle nudge per bullet (a machine gun used to juggle them), and never get flung
			body.apply_impulse(dir * minf(power, 6.0) * 0.12 * body.mass, at - body.global_position)
			body.linear_velocity = body.linear_velocity.limit_length(5.0)
			body.angular_velocity = body.angular_velocity.limit_length(8.0)
			game.fx.blood_hit(at, dir, 1, false)
		else:
			body.apply_impulse(dir * power * 0.9 * body.mass * 0.35, at - body.global_position)
	elif body.has_meta("glass"):
		shatter(body.get_meta("glass"), at, dir)
	elif body.has_meta("locker"):
		bang_locker(body.get_meta("locker"), dir)
	elif body.has_meta("lamp"):
		swing_lamp(body.get_meta("lamp"), dir * 2.5)
	elif body.has_meta("ext"):
		launch_extinguisher(body.get_meta("ext"), at, dir)

func blast(at: Vector3, radius: float, force: float) -> void:
	for b in get_children():
		if b is RigidBody3D:
			var d: Vector3 = b.global_position - at
			var l := d.length()
			if l < radius * 1.4:
				wake(b)
				var k := 1.0 - l / (radius * 1.4)
				b.apply_central_impulse((d.normalized() + Vector3(0, 0.6, 0)).normalized() * force * k * b.mass)
				b.angular_velocity += Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6)) * k
	for g in glass_list.duplicate():
		if g.pos.distance_to(at) < radius:
			shatter(g, g.pos, (g.pos - at).normalized())
	for l in lamps:
		var d2: Vector3 = l.pivot.global_position - at
		if d2.length() < radius * 2.5:
			swing_lamp(l, Vector3(d2.x, 0, d2.z).normalized() * 3.0 * (1.0 - d2.length() / (radius * 2.5)))
	for e in extinguishers:
		if not e.live and e.pos.distance_to(at) < radius * 0.8:
			launch_extinguisher(e, e.pos, (e.pos - at).normalized())
	_ceiling_tiles(at, radius)

## melee kick / knife: shove anything loose in front of you
func kick(origin: Vector3, f: Vector3, rng: float) -> void:
	for b in get_children():
		if b is RigidBody3D:
			var d: Vector3 = b.global_position - origin
			if d.length() < rng + 0.4 and Vector3(d.x, 0, d.z).normalized().dot(f) > 0.4:
				wake(b)
				b.apply_central_impulse((f + Vector3(0, 0.4, 0)).normalized() * 6.0 * minf(b.mass, 4.0))
				b.angular_velocity += Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5))

## blood that stays on props
func bloody(at: Vector3, r: float) -> void:
	for b in props:
		if is_instance_valid(b) and b.has_meta("small") and b.global_position.distance_to(at) < r:
			for m in b.get_children():
				if m is MeshInstance3D:
					m.material_overlay = blood_mat

# ---------------------------------------------------------------- glass
var glass_list: Array = []

func _pane(pos: Vector3, size: Vector3, tint := Color(0.7, 0.85, 0.9, 0.28)) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = SHOOT
	body.collision_mask = 0
	add_child(body)
	body.global_position = pos
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.05
	mat.metallic_specular = 1.0
	mi.material_override = mat
	body.add_child(mi)
	_shape_box(body, size)
	var g := {"body": body, "pos": pos, "size": size, "dead": false}
	body.set_meta("glass", g)
	glass_list.append(g)

func _glass() -> void:
	_pane(Vector3(-7.85, 1.55, 4.1), Vector3(7.1, 0.04, 0.55))                   # lunch line sneeze guard
	_pane(Vector3(-19.5, 1.45, -5.31), Vector3(5.0, 1.1, 0.03))                  # trophy case front
	_pane(Vector3(-22.0, 1.45, -5.55), Vector3(0.03, 1.1, 0.5))
	_pane(Vector3(-17.0, 1.45, -5.55), Vector3(0.03, 1.1, 0.5))
	_pane(Vector3(-19.5, 2.0, -5.55), Vector3(5.0, 0.03, 0.5))
	for w in [[4.5, -20.6, 0.5, 0.6], [5.9, -18.7, 0.6, 0.8], [6.1, -20.4, 0.7, 0.5], [4.4, -18.8, 0.4, 0.5]]:
		_pane(Vector3(-59.95, w[0], w[1]), Vector3(0.03, w[3], w[2]))         # gym's broken windows
	# trophies inside the case
	var gold := _m(Color8(210, 170, 60), 0.8, 0.3)
	for k in 7:
		var x := -21.4 + k * 0.62
		var b := _rigid("metal", 1.0, Vector3(x, 1.18, -5.55))
		_mesh_box(b, Vector3(0.12, 0.05, 0.12), _m(Color8(40, 30, 24)), Vector3(0, -0.12, 0))
		_mesh_box(b, Vector3(0.05, 0.14, 0.05), gold, Vector3(0, -0.02, 0))
		_mesh_box(b, Vector3(0.14, 0.1, 0.14), gold, Vector3(0, 0.1, 0))
		_shape_box(b, Vector3(0.12, 0.3, 0.12))
		b.set_meta("small", true)
		b.set_meta("rest", true)
		b.freeze = true

func shatter(g: Dictionary, at: Vector3, dir: Vector3) -> void:
	if g.dead:
		return
	g.dead = true
	glass_list.erase(g)
	var size: Vector3 = g.size
	var n := int(clampf(size.x * size.y * size.z * 0 + (size.x + size.y + size.z) * 5.0, 8, 24) * detail)
	for k in n:
		var p: Vector3 = g.pos + Vector3(randf_range(-0.5, 0.5) * size.x, randf_range(-0.5, 0.5) * size.y, randf_range(-0.5, 0.5) * size.z)
		var b := _rigid("glass", 0.1, p, Vector3(randf() * 3, randf() * 3, randf() * 3))
		var s := randf_range(0.05, 0.16)
		_mesh_box(b, Vector3(s, 0.006, s * randf_range(0.6, 1.4)), g.body.get_child(0).material_override)
		_shape_box(b, Vector3(s, 0.02, s))
		b.linear_velocity = dir * randf_range(1, 4) + Vector3(randf_range(-1, 1), randf_range(0, 2), randf_range(-1, 1))
		b.set_meta("temp", 8.0)
	game.fx.spray(at, dir, Color(0.85, 0.95, 1.0), 12, 4, 0.3, false, 0.0, 2.0, 0.6)
	game.audio.play("glass", at, 0)
	g.body.queue_free()

# ---------------------------------------------------------------- ceiling tiles
func _ceiling_tiles(at: Vector3, radius: float) -> void:
	var r: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.5, 0), at + Vector3(0, 6, 0), WORLD | 8))
	if r.is_empty() or r.normal.y > -0.5:
		return
	var ceil_y: float = r.position.y
	var tile := _m(Color8(214, 208, 190))
	for k in int(randi_range(3, 6) * detail):
		var p := Vector3(at.x + randf_range(-radius * 0.5, radius * 0.5), ceil_y - 0.08, at.z + randf_range(-radius * 0.5, radius * 0.5))
		var b := _rigid("tile", 1.2, p, Vector3(randf_range(-0.3, 0.3), randf() * 3, randf_range(-0.3, 0.3)))
		_mesh_box(b, Vector3(0.6, 0.03, 0.6), tile)
		_shape_box(b, Vector3(0.6, 0.04, 0.6))
		b.linear_velocity = Vector3(randf_range(-1, 1), randf_range(-2, 0), randf_range(-1, 1))
		b.set_meta("temp", 20.0)
		game.fx.puff(p, Color8(200, 196, 180), false, 0.2, randf_range(0.8, 1.4), 1.2, -0.3, 0.3, 0.5)

# ---------------------------------------------------------------- lockers
func _lockers() -> void:
	var body_m := _m(Color8(52, 84, 70), 0.4, 0.6)
	var door_m := _m(Color8(58, 96, 80), 0.4, 0.5)
	var dark := _m(Color8(12, 14, 12))
	for k in 12:
		var x := -10.5 + k * 0.5 + 0.25
		var z := -31.5
		var st := StaticBody3D.new()
		st.collision_layer = WORLD
		world.nav.add_child(st)
		st.global_position = Vector3(x, 4.0 + 1.0, z)
		_shape_box(st, Vector3(0.48, 2.0, 0.5))
		_mesh_box(st, Vector3(0.48, 2.0, 0.02), body_m, Vector3(0, 0, -0.24))
		_mesh_box(st, Vector3(0.02, 2.0, 0.5), body_m, Vector3(-0.23, 0, 0))
		_mesh_box(st, Vector3(0.44, 1.96, 0.02), dark, Vector3(0, 0, -0.2))
		_mesh_box(st, Vector3(0.48, 0.02, 0.5), body_m, Vector3(0, 1.0, 0))
		var hinge := Node3D.new()
		st.add_child(hinge)
		hinge.position = Vector3(-0.23, 0, 0.25)
		var door := StaticBody3D.new()
		door.collision_layer = SHOOT
		door.collision_mask = 0
		hinge.add_child(door)
		door.position = Vector3(0.23, 0, 0)
		_mesh_box(door, Vector3(0.46, 1.96, 0.025), door_m)
		for v in 3:
			_mesh_box(door, Vector3(0.3, 0.02, 0.03), dark, Vector3(0, 0.7 + v * 0.06, 0.005))
		_mesh_box(door, Vector3(0.03, 0.08, 0.04), _m(Color8(160, 160, 160), 0.8, 0.3), Vector3(0.17, 0, 0.02))
		_shape_box(door, Vector3(0.46, 1.96, 0.05))
		var l := {"hinge": hinge, "a": 0.0, "v": 0.0, "pos": st.global_position + Vector3(0, 0, 0.3), "loot": randf() < 0.3}
		door.set_meta("locker", l)
		lockers.append(l)

func bang_locker(l: Dictionary, dir: Vector3) -> void:
	l.v -= randf_range(9, 14)
	game.audio.play("metalDoor", l.pos, -6, randf_range(1.2, 1.5))
	if l.loot:
		l.loot = false
		if randf() < 0.5:
			game.add_points(50)
			game.hud.callout_small("+50 LOCKER CASH")
			game.audio.play("pick", l.pos)
		else:
			game.drop_ammo(l.pos + Vector3(0, -0.9, 0.4))

# ---------------------------------------------------------------- vending machine
func _vending() -> void:
	var st := StaticBody3D.new()
	st.collision_layer = WORLD
	world.nav.add_child(st)
	st.global_position = Vector3(10.0, 0.95, 14.15)
	_shape_box(st, Vector3(1.0, 1.9, 0.8))
	_mesh_box(st, Vector3(1.0, 1.9, 0.8), _m(Color8(170, 30, 30), 0.3, 0.5))
	var face := StandardMaterial3D.new()
	face.albedo_color = Color8(250, 240, 210)
	face.emission_enabled = true
	face.emission = Color8(255, 240, 200)
	face.emission_energy_multiplier = 0.6
	_mesh_box(st, Vector3(0.62, 1.2, 0.02), face, Vector3(-0.1, 0.25, -0.41))
	for r in 5:
		for c in 4:
			_mesh_box(st, Vector3(0.1, 0.16, 0.03), _m([Color8(190, 30, 30), Color8(40, 90, 190), Color8(230, 200, 60), Color8(60, 160, 70)][(r + c) % 4]), Vector3(-0.34 + c * 0.16, 0.7 - r * 0.24, -0.42))
	_mesh_box(st, Vector3(0.5, 0.18, 0.04), _m(Color8(20, 20, 20)), Vector3(-0.1, -0.68, -0.41))
	var glow := OmniLight3D.new()
	glow.light_color = Color8(255, 220, 190)
	glow.omni_range = 3.0
	glow.light_energy = 0.8
	glow.position = Vector3(0, 0.3, -0.9)
	st.add_child(glow)
	st.set_meta("vending", true)
	vending = {"body": st, "left": 30, "cd": 0.0}

func hit_vending(at: Vector3) -> void:
	if vending.left <= 0 or vending.cd > 0:
		game.audio.play("clang", at, -6, 0.8)
		return
	vending.cd = 0.12
	var n := randi_range(1, 3)
	for k in n:
		vending.left -= 1
		spawn_can(Vector3(9.9 + randf_range(-0.15, 0.15), 0.3, 13.65), Vector3(randf_range(-1, 1), randf_range(1, 2.5), randf_range(-3.5, -1.5)))
	game.audio.play("clang", at, -2, 0.7)
	game.audio.play("tink", at, -6, 1.4)

# ---------------------------------------------------------------- fire extinguishers
func _extinguishers() -> void:
	var red := _m(Color8(190, 24, 20), 0.3, 0.4)
	for e in [[Vector3(-13.5, 1.1, 9.5), Vector3(1, 0, 0)], [Vector3(13.5, 1.1, -1.0), Vector3(-1, 0, 0)], [Vector3(-22.0, 1.1, -9.0), Vector3(0, 0, 1)],
			[Vector3(20.0, 1.1, -9.0), Vector3(0, 0, 1)], [Vector3(-59.5, 1.1, -8.0), Vector3(1, 0, 0)], [Vector3(-2.0, 5.1, -28.35), Vector3(0, 0, -1)]]:
		var st := StaticBody3D.new()
		st.collision_layer = SHOOT
		add_child(st)
		st.global_position = e[0] + e[1] * 0.1
		var cm := CylinderMesh.new()
		cm.top_radius = 0.075
		cm.bottom_radius = 0.08
		cm.height = 0.45
		cm.radial_segments = 8
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = red
		st.add_child(mi)
		_mesh_box(st, Vector3(0.06, 0.08, 0.06), _m(Color8(30, 30, 30)), Vector3(0, 0.27, 0))
		_mesh_box(st, Vector3(0.03, 0.03, 0.14), _m(Color8(30, 30, 30)), Vector3(0, 0.29, 0.07))
		_shape_box(st, Vector3(0.18, 0.5, 0.18))
		var ex := {"body": st, "pos": st.global_position, "live": false, "t": 0.0, "rb": null}
		st.set_meta("ext", ex)
		extinguishers.append(ex)

func launch_extinguisher(ex: Dictionary, at: Vector3, dir: Vector3) -> void:
	if ex.live:
		return
	ex.live = true
	var st: StaticBody3D = ex.body
	var b := _rigid("metal", 4.0, st.global_position)
	for c in st.get_children():
		if c is MeshInstance3D:
			c.reparent(b)
	_shape_box(b, Vector3(0.16, 0.5, 0.16))
	st.queue_free()
	b.linear_velocity = dir * 3.0 + Vector3(0, 2, 0)
	b.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	ex.rb = b
	ex.t = 3.2
	game.audio.play("whoosh", at, 4, 0.6)
	game.audio.play("strike", at, 0, 0.6)

# ---------------------------------------------------------------- pendant lamps
func _pendants() -> void:
	var shade_m := _m(Color8(60, 66, 60), 0.5, 0.5)
	var cord_m := _m(Color8(20, 20, 20))
	var bulb_m := StandardMaterial3D.new()
	bulb_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bulb_m.albedo_color = Color(1, 0.92, 0.75)
	var spots := [[0, -2, true], [9, 4, false], [-6, 7, true], [-26, -38, false], [-31, -35, false], [-24, -7.25, true], [24, -7.25, true], [-46, -3, false]]
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for s in spots:
		var base_y := 4.0 if s[1] < -30 else 0.0
		var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(s[0], base_y + 2.5, s[1]), Vector3(s[0], base_y + 12, s[1]), WORLD | 8))
		var top: float = r.position.y if not r.is_empty() else base_y + 4.0
		var length := clampf(top - (base_y + 2.7), 0.4, 4.0)
		var pivot := Node3D.new()
		add_child(pivot)
		pivot.global_position = Vector3(s[0], top, s[1])
		var arm := Node3D.new()
		pivot.add_child(arm)
		_mesh_box(arm, Vector3(0.015, length, 0.015), cord_m, Vector3(0, -length / 2, 0))
		var shade := StaticBody3D.new()
		shade.collision_layer = SHOOT
		arm.add_child(shade)
		shade.position = Vector3(0, -length, 0)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.08
		cm.bottom_radius = 0.3
		cm.height = 0.22
		cm.radial_segments = 10
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = shade_m
		shade.add_child(mi)
		_mesh_box(shade, Vector3(0.1, 0.06, 0.1), bulb_m, Vector3(0, -0.1, 0))
		_shape_box(shade, Vector3(0.5, 0.25, 0.5))
		var light := SpotLight3D.new()
		light.light_color = Color8(255, 226, 180)
		light.spot_range = 7.0
		light.spot_angle = 52.0
		light.light_energy = 2.4
		light.shadow_enabled = s[2]
		light.rotation.x = -PI / 2
		light.position = Vector3(0, -0.12, 0)
		shade.add_child(light)
		var l := {"pivot": pivot, "arm": arm, "len": length, "a": Vector2(randf_range(-0.05, 0.05), randf_range(-0.05, 0.05)), "v": Vector2.ZERO, "light": light, "base": 2.4}
		shade.set_meta("lamp", l)
		lamps.append(l)

func swing_lamp(l: Dictionary, push: Vector3) -> void:
	l.v += Vector2(push.z, -push.x) / maxf(l.len, 0.5)

# ---------------------------------------------------------------- the bookshelf
const SHELF_HOME := Vector3(-16.52, 4.0, -37.6)
const SHELF_BLOCK := Vector3(-16.52, 4.0, -35.0)

func _bookshelf() -> void:
	var st := StaticBody3D.new()
	st.collision_layer = WORLD
	world.nav.add_child(st)
	st.global_position = SHELF_HOME + Vector3(0, 1.1, 0)
	var wood := _m(Color8(110, 74, 40))
	_shape_box(st, Vector3(0.45, 2.2, 2.4))
	_mesh_box(st, Vector3(0.45, 2.2, 0.06), wood, Vector3(0, 0, -1.17))
	_mesh_box(st, Vector3(0.45, 2.2, 0.06), wood, Vector3(0, 0, 1.17))
	_mesh_box(st, Vector3(0.04, 2.2, 2.4), wood, Vector3(0.2, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for r in 5:
		_mesh_box(st, Vector3(0.45, 0.04, 2.4), wood, Vector3(0, -1.08 + r * 0.53, 0))
		var z := -1.1
		while z < 1.05:
			var w := rng.randf_range(0.04, 0.09)
			var h := rng.randf_range(0.28, 0.42)
			_mesh_box(st, Vector3(0.3, h, w), _m([Color8(140, 40, 40), Color8(40, 70, 120), Color8(60, 100, 60), Color8(180, 150, 90), Color8(70, 50, 90)][rng.randi() % 5]), Vector3(-0.02, -1.06 + r * 0.53 + h / 2, z + w / 2))
			z += w + 0.005
	shelf = {"body": st, "state": "home", "t": 0.0}

func shelf_prompt() -> String:
	if shelf.is_empty() or shelf.state == "moving" or shelf.state == "broken":
		return ""
	var d: Vector3 = game.player.global_position - (shelf.body.global_position - Vector3(0, 1.1, 0))
	var near := Vector2(maxf(absf(d.x) - 0.25, 0.0), maxf(absf(d.z) - 1.2, 0.0))   # distance to the shelf's footprint
	if near.length() > 1.5 or absf(d.y) > 1.5:
		return ""
	return "Press {use} to push the bookshelf" + (" across the doorway" if shelf.state == "home" else " back")

func push_shelf() -> void:
	var to: Vector3 = SHELF_BLOCK if shelf.state == "home" else SHELF_HOME
	var blocking: bool = shelf.state == "home"
	shelf.state = "moving"
	game.audio.play("drag", shelf.body.global_position, 0, 0.8)
	var tw := create_tween()
	tw.tween_property(shelf.body, "global_position", to + Vector3(0, 1.1, 0), 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func():
		shelf.state = "blocking" if blocking else "home"
		shelf.t = 25.0
		game.audio.play("thud", shelf.body.global_position, 0, 0.7)
		world.rebake())

func _break_shelf() -> void:
	shelf.state = "broken"
	shelf.t = 45.0
	var st: StaticBody3D = shelf.body
	var p := st.global_position
	game.audio.play("wood", p, 4, 0.7)
	game.audio.play("crunch", p, 0, 0.8)
	for k in int(14 * detail):
		var b := _rigid("wood", 1.0, p + Vector3(randf_range(-0.2, 0.2), randf_range(-1, 1), randf_range(-1.1, 1.1)), Vector3(randf() * 3, randf() * 3, randf() * 3))
		_mesh_box(b, Vector3(0.4, 0.04, randf_range(0.3, 0.9)), _m(Color8(110, 74, 40)))
		_shape_box(b, Vector3(0.4, 0.05, 0.5))
		b.linear_velocity = Vector3(randf_range(-3, -0.5), randf_range(0, 3), randf_range(-2, 2))
		b.set_meta("temp", 15.0)
	st.visible = false
	st.collision_layer = 0
	world.rebake()

# ---------------------------------------------------------------- per frame
func _physics_process(dt: float) -> void:
	# temp props time out; bleeding gibs leave trails
	for b in props.duplicate():
		if not is_instance_valid(b):
			props.erase(b)
			continue
		if b.has_meta("temp"):
			var t: float = b.get_meta("temp") - dt
			b.set_meta("temp", t)
			if t < 1.0:
				b.freeze = true
				b.global_position.y -= dt * 0.4
			if t <= 0:
				props.erase(b)
				b.queue_free()
				continue
		if b.get_meta("bleed", 0.0) > 0:
			var bl: float = b.get_meta("bleed") - dt
			b.set_meta("bleed", bl)
			if b.linear_velocity.length() > 1.5 and randf() < 0.5:
				game.fx.spray(b.global_position, Vector3.UP, Color8(106, 8, 8), 1, 0.5, 0.9, true)
		if b.global_position.y < -20:
			props.erase(b)
			b.queue_free()
	# zombies stumble over clutter, and flying junk hurts them
	for z in game.zombies:
		if not z.alive or z.kind == "boss":
			continue
		var zp: Vector3 = z.global_position
		var zv: Vector3 = z.velocity
		for b in props:
			if not is_instance_valid(b) or not b.has_meta("small"):
				continue
			var d: Vector3 = b.global_position - zp
			if absf(d.y) > 1.2 or Vector2(d.x, d.z).length() > 0.55:
				continue
			var bv: Vector3 = b.linear_velocity
			if bv.length() > 5.0:
				z.damage(12.0 + bv.length() * 2.0, "body", bv.normalized(), 3.0, false, b.global_position)
				z.stagger = maxf(z.stagger, 0.5)
				b.linear_velocity *= 0.3
			elif Vector2(zv.x, zv.z).length() > 0.8:
				wake(b)
				b.apply_central_impulse(Vector3(zv.x, 0.6, zv.z).normalized() * 1.2 * minf(b.mass, 3.0))
				if randf() < 0.05 and not z.crawler:
					z.stagger = maxf(z.stagger, 0.35)
					z.flinch = 1.0
	# ragdolls settle, then sink away
	for r in ragdolls.duplicate():
		r.t += dt
		if r.t > 9.0:
			for b in r.bodies:
				if is_instance_valid(b):
					b.freeze = true
					b.global_position.y -= dt * 0.3
		if r.t > 11.0:
			_free_ragdoll(r)
			ragdolls.erase(r)

func _process(dt: float) -> void:
	# pendulum lamps
	for l in lamps:
		var w2 := 9.8 / maxf(l.len, 0.4)
		l.v -= l.a * w2 * dt
		l.v *= 1.0 - dt * 0.35
		l.a += l.v * dt
		l.a = l.a.limit_length(1.1)
		l.arm.rotation = Vector3(l.a.x, 0, l.a.y)
		l.light.light_energy = l.base * (1.0 if world.powered else 0.35) * (0.85 + 0.15 * randf() if l.v.length() > 1.0 else 1.0)
	# lockers swing on their hinges
	for l in lockers:
		if absf(l.v) < 0.01:
			continue
		l.v *= 1.0 - minf(1.0, dt * 2.5)
		l.a += l.v * dt
		if l.a < -2.2 or l.a > 0.0:
			l.a = clampf(l.a, -2.2, 0.0)
			if absf(l.v) > 3:
				game.audio.play("clang", l.pos, -14, 1.3)
			l.v *= -0.35
		l.hinge.rotation.y = l.a
	# extinguishers on the loose
	for e in extinguishers:
		if e.live and e.t > 0 and is_instance_valid(e.rb):
			e.t -= dt
			var b: RigidBody3D = e.rb
			var axis := b.global_transform.basis.y
			b.apply_central_force(-axis * 70.0)
			b.apply_torque(Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3)))
			var nozzle := b.global_position + axis * 0.3
			if randf() < 0.8:
				game.fx.puff(nozzle, Color8(235, 235, 230), false, 0.15, randf_range(0.9, 1.6), randf_range(1.0, 1.6), 0.1, 0.1, 0.6)
			clouds.append({"pos": nozzle, "t": 4.0})
			if e.t <= 0:
				game.audio.play("thud", b.global_position, -2)
	var i := clouds.size() - 1
	while i >= 0:
		clouds[i].t -= dt
		if clouds[i].t <= 0:
			clouds.remove_at(i)
		i -= 1
	if not clouds.is_empty():
		for z in game.zombies:
			if not z.alive:
				continue
			for c in clouds:
				if z.global_position.distance_to(c.pos) < 2.2:
					z.slow_t = 1.0
					break
	if not vending.is_empty():
		vending.cd -= dt
	# the bookshelf: holds the doorway for a while, then the horde smashes it
	if not shelf.is_empty():
		if shelf.state == "blocking":
			shelf.t -= dt
			if shelf.t <= 0:
				_break_shelf()
		elif shelf.state == "broken":
			shelf.t -= dt
			if shelf.t <= 0:
				shelf.state = "home"
				shelf.body.visible = true
				shelf.body.collision_layer = WORLD
				shelf.body.global_position = SHELF_HOME + Vector3(0, 1.1, 0)
				world.rebake()
