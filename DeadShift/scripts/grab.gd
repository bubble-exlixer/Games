extends Node
## Grab and throw: pick up a loose prop (chair, trash can, trophy, tray, fire extinguisher...) with the use
## button, carry it in front of you, and hurl it with fire. Thrown props knock zombies down.

const REACH := 2.6
const MAX_MASS := 16.0
const THROW_SPEED := 17.0

var game
var held: RigidBody3D = null
var held_layer := 0
var held_mask := 0
var held_ext = null            # the extinguisher record when we're carrying one
var hold_t := 0.0
var flying: Array = []         # {b, t, hit: []}

func setup(g) -> void:
	game = g

## what the crosshair is on, if it's something we can lift
func _target():
	var P = game.player
	var o: Vector3 = P.cam.global_position
	var f: Vector3 = -P.cam.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(o, o + f * REACH, 1 | 16 | 32)
	var r: Dictionary = P.get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return null
	var c = r.collider
	if c is RigidBody3D and c in game.physics.props and not c.get_meta("ragdoll", false) and not c.has_meta("temp") and c.mass <= MAX_MASS:
		return c
	if c is StaticBody3D and c.has_meta("ext") and not c.get_meta("ext").live:
		return c
	return null

func prompt() -> String:
	if held != null or game.player.slots.is_empty():
		return ""
	return "Press {use} to pick it up" if _target() != null else ""

func pick_up() -> void:
	var t = _target()
	if t == null:
		return
	held_ext = null
	if t is StaticBody3D:
		# a wall-mounted extinguisher comes off its bracket
		var ex: Dictionary = t.get_meta("ext")
		var b: RigidBody3D = game.physics._rigid("metal", 4.0, t.global_position)
		for c in t.get_children():
			if c is MeshInstance3D:
				c.reparent(b)
		game.physics._shape_box(b, Vector3(0.16, 0.5, 0.16))
		t.queue_free()
		ex.rb = b
		held_ext = ex
		t = b
	held = t
	game.physics.wake(held)
	held_layer = held.collision_layer
	held_mask = held.collision_mask
	held.collision_layer = 0
	held.collision_mask = 0
	held.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	held.freeze = true
	held.set_meta("rest", false)
	hold_t = 0.0
	game.audio.play("swap", null, -2, 0.8)

func _release() -> RigidBody3D:
	var b := held
	held = null
	if not is_instance_valid(b):
		return null
	b.collision_layer = held_layer
	b.collision_mask = held_mask
	b.freeze = false
	b.sleeping = false
	return b

func drop() -> void:
	var b := _release()
	if b:
		b.linear_velocity = game.player.velocity * 0.5

func throw() -> void:
	var P = game.player
	var b := _release()
	if b == null:
		return
	var f: Vector3 = -P.cam.global_transform.basis.z
	var speed: float = THROW_SPEED * clampf(4.0 / maxf(b.mass, 1.0), 0.75, 1.2)
	b.linear_velocity = f * speed + Vector3(0, 2.2, 0) + P.velocity * 0.5
	b.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-4, 4), randf_range(-8, 8))
	flying.append({"b": b, "t": 1.6, "hit": []})
	if held_ext != null:
		# a thrown extinguisher goes off mid-air and sprays a slowing cloud as it tumbles
		held_ext.live = true
		held_ext.t = 3.2
		game.audio.play("strike", b.global_position, 0, 0.6)
		held_ext = null
	game.audio.play("whoosh", null, 0, 0.75)
	P.kick = 0.6
	P.shake = maxf(P.shake, 0.06)
	game.rumble(0.2, 0.3, 0.08)

func _physics_process(dt: float) -> void:
	if game == null:
		return
	var P = game.player
	if held != null:
		if not is_instance_valid(held) or P.dead or game.state == "over":
			held = null
		else:
			hold_t += dt
			var basis: Basis = P.cam.global_transform.basis
			var at: Vector3 = P.cam.global_position - basis.z * 1.25 - basis.y * 0.35 + basis.x * 0.15
			at.y += sin(hold_t * 3.0) * 0.02 + sin(P.bob * 2.0) * 0.02
			var want := Transform3D(Basis(Vector3.UP, P.yaw + 0.4) * Basis(Vector3.RIGHT, 0.15), at)
			held.global_transform = held.global_transform.interpolate_with(want, minf(1.0, dt * 18.0))
	# thrown props bowl zombies over
	var i := flying.size() - 1
	while i >= 0:
		var fl = flying[i]
		fl.t -= dt
		var b: RigidBody3D = fl.b
		if fl.t <= 0 or not is_instance_valid(b):
			flying.remove_at(i)
			i -= 1
			continue
		var v: Vector3 = b.linear_velocity
		if v.length() > 4.0:
			for z in game.zombies:
				if not z.alive or z in fl.hit:
					continue
				var d: Vector3 = b.global_position - z.global_position
				var tall: float = (0.8 if z.crawler else 2.0) * maxf(z.bscale, 1.0)
				if d.y < -0.3 or d.y > tall or Vector2(d.x, d.z).length() > 0.5 + 0.3 * z.bscale:
					continue
				fl.hit.append(z)
				var dir: Vector3 = v.normalized()
				var dmg: float = (30.0 + v.length() * 2.5 * clampf(b.mass, 1.0, 8.0)) * (0.35 if z.kind == "boss" else 1.0)
				var hd: bool = d.y > tall * 0.8
				var res: Dictionary = z.damage(dmg, "head" if hd else "body", dir, 5.0, false, b.global_position)
				if z.alive and z.kind != "boss":
					z.stagger = 1.5
					z.flinch = 1.0
					z.velocity += Vector3(dir.x, 0, dir.z).normalized() * 7.0
				game.audio.play("thud", b.global_position, 4, randf_range(0.8, 1.0))
				game.audio.play({"metal": "clang", "can": "tink", "glass": "glass"}.get(b.get_meta("kind", "wood"), "wood"), b.global_position, 0)
				game.fx.blood_hit(b.global_position, dir, 1, hd)
				game.hud.hit(res.get("kill", false))
				game.hitstop(0.04)
				if not res.get("kill", false):
					game.add_points(10)
				b.linear_velocity = -dir * 2.0 + Vector3(0, 2.5, 0)
				break
		i -= 1
