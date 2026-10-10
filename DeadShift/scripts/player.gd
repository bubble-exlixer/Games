extends CharacterBody3D
## First-person player: the web game's movement numbers, gun pose, recoil, sway, ADS, flashlight.

const WORLD := 1
const ZOMBIE_BODY := 2
const HITBOX := 4
const GRAVITY := 22.0
const EYE := 1.6

var game                       # game.gd
var cam: Camera3D
var vm: Node3D                 # viewmodel root (child of camera)
var gun_node: Node3D
var flash_node: MeshInstance3D
var muzzle_light: OmniLight3D
var torch: SpotLight3D
var carry: OmniLight3D
var torch_on := true
var torch_flick := 0.0
var torch_wait := 6.0

var yaw := 0.0
var pitch := 0.0
var hp := 100.0
var max_hp := 100.0
var hurt_t := 99.0
var dead := false

var slots: Array = [{"id": "pistol", "mag": 12, "res": -1, "up": false}]
var cur := 0
var weapons: Dictionary
var fire_t := 0.0
var reload_t := 0.0
var swap_t := 0.0
var melee_t := 0.0
var kick := 0.0
var shake := 0.0
var fov_kick := 0.0
var bloom := 0.0
var ads := 0.0
var sprint := 0.0
var bob := 0.0
var sw := Vector2.ZERO
var look_delta := Vector2.ZERO
var step_phase := 0
var trigger := false
var trigger_was := false
var heart_t := 0.0
var throw_anim := 0.0
var sprint_latch := false
var frozen := false          # during cutscenes
var slow_t := 0.0            # wading through gravy
var stun_t := 0.0            # the Coach's whistle
var free_t := 0.0            # Free Period: infinite ammo
var sens_k := 1.0
var pad_k := 1.0
var assist_k := 1.0          # aim assist strength (0 off .. 1.4 strong), controller only
var pad_dead := 0.15
var _ast = null              # current assist target
var _ast_dir := Vector3.ZERO # its direction last frame (for rotational stickiness)
var _snap_t := 0.0
var _ads_was := false
var invert := false
var base_fov := 72.0
var melee_anim := 0.0
var melee_kind := "knife"
var knife: Node3D
var boot: Node3D
var roll := 0.0
var land_dip := 0.0
var was_floor := true
var fall_v := 0.0
const CASING := {"pistol": "shot", "dmr": "shot", "smg": "shot", "lmg": "shot", "bayonet": "shot", "ak": "shot", "shotgun": "pump", "revolver": "reload", "sawed": "reload"}
var bot := false                     # automated test player
var bot_input := {"move": Vector2.ZERO, "fire": false, "ads": false, "look": Vector2.ZERO}

func setup(g, start: Array) -> void:
	game = g
	weapons = g.world.data.weapons
	collision_layer = 0
	collision_mask = WORLD | ZOMBIE_BODY
	floor_max_angle = deg_to_rad(52)
	floor_snap_length = 0.45
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)
	cam = Camera3D.new()
	cam.fov = 72
	cam.near = 0.05
	cam.far = 120
	cam.position.y = EYE
	add_child(cam)
	vm = Node3D.new()
	cam.add_child(vm)
	torch = SpotLight3D.new()
	torch.light_color = Color8(255, 230, 196)
	torch.spot_range = 26.0
	torch.spot_angle = 30.0
	torch.spot_angle_attenuation = 0.7
	torch.spot_attenuation = 1.1
	torch.light_energy = 2.2
	torch.shadow_enabled = true
	torch.light_cull_mask = 1          # don't light our own gun (it sits right in front of the lamp)
	torch.position = Vector3(0.18, -0.14, 0.05)
	cam.add_child(torch)
	torch.rotation = Vector3(0.0, 0.023, 0.0)   # points almost straight ahead, like the web game's torch
	carry = OmniLight3D.new()
	carry.light_color = Color8(255, 220, 180)
	carry.omni_range = 4.0
	carry.light_energy = 0.45
	carry.light_cull_mask = 1
	cam.add_child(carry)
	muzzle_light = OmniLight3D.new()
	muzzle_light.light_color = Color(1, 0.7, 0.4)
	muzzle_light.omni_range = 7.0
	muzzle_light.light_energy = 0.0
	cam.add_child(muzzle_light)
	knife = _limb([[Vector3(0.025, 0.035, 0.26), Color8(94, 96, 100), Vector3(0, 0, -0.13), 0.0], [Vector3(0.032, 0.042, 0.12), Color8(26, 26, 24), Vector3(0, 0, 0.06), 0.0],
		[Vector3(0.12, 0.1, 0.14), Color8(138, 106, 82), Vector3(0, -0.03, 0.1), 0.0], [Vector3(0.15, 0.15, 0.45), Color8(52, 59, 42), Vector3(0.04, -0.1, 0.38), 0.2]])
	boot = _limb([[Vector3(0.17, 0.13, 0.34), Color8(26, 23, 20), Vector3(0, 0, -0.1), 0.0], [Vector3(0.16, 0.45, 0.16), Color8(44, 46, 38), Vector3(0, 0.25, 0.05), 0.0]])
	global_position = Vector3(start[0], start[1] + 0.1, start[2])
	yaw = start[3]
	build_gun()

# ---------------------------------------------------------------- guns
const Guns := preload("res://scripts/guns.gd")
var _upw := {}
var pap_t := 0.0             # gun is inside the Pack-a-Punch machine

## the weapon numbers for a slot: Pack-a-Punched guns hit 2.2x as hard, hold more, pierce one more
func wdata(slot: Dictionary) -> Dictionary:
	var base: Dictionary = weapons[slot.id]
	if not slot.get("up", false):
		return base
	if not _upw.has(slot.id):
		var u := base.duplicate(true)
		u.name = base.get("up_name", base.name + " II")
		u.dmg = base.dmg * 2.2
		u.mag = int(base.get("up_mag", base.mag))
		u.spread = base.spread * 0.7
		u.reload = base.reload * 0.85
		u.pierce = int(base.pierce) + 1
		u.up = true
		_upw[slot.id] = u
	return _upw[slot.id]

func w() -> Dictionary:
	return wdata(slots[cur])

func build_gun() -> void:
	if gun_node:
		gun_node.queue_free()
	var id: String = slots[cur].id
	gun_node = Guns.make(id, true, game.world)
	if slots[cur].get("up", false):
		Guns.upgrade_skin(gun_node)
	for m in gun_node.find_children("*", "MeshInstance3D", true, false):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.layers = 2
	vm.add_child(gun_node)
	# muzzle flash
	flash_node = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(0.75, 0.5, 1.0, 1) if slots[cur].get("up", false) else Color(1, 0.8, 0.45, 1)
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 0.9, 1))
	gr.set_color(1, Color(1, 0.5, 0.1, 0))
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	fm.albedo_texture = gt
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = fm
	flash_node.mesh = q
	flash_node.visible = false
	var f: Array = w().flash
	flash_node.position = Vector3(f[0], f[1], f[2])
	gun_node.add_child(flash_node)
	swap_t = 0.35
	reload_t = 0.0
	swing_t = -1.0
	bat_pos = BAT_REST[0] + Vector3(0, -0.3, 0)
	bat_rot = BAT_REST[1]

func set_start_gun(id: String) -> void:
	if id == "pistol" or not weapons.has(id):
		return
	var res := 36
	for wb in game.world.data.wallbuys:
		if wb.id == id:
			res = int(wb.reserve)
	slots = [{"id": id, "mag": weapons[id].mag, "res": res, "up": false}]
	cur = 0
	build_gun()

func give(id: String, reserve: int) -> void:
	var wd: Dictionary = weapons[id]
	for i in slots.size():
		if slots[i].id == id:
			var up: bool = slots[i].get("up", false)
			slots[i].mag = wdata(slots[i]).mag
			slots[i].res = int(wd.get("up_reserve", reserve)) if up and reserve >= 0 else reserve
			cur = i
			build_gun()
			return
	if slots.size() < 2:
		slots.append({"id": id, "mag": wd.mag, "res": reserve, "up": false})
		cur = 1
	else:
		slots[cur] = {"id": id, "mag": wd.mag, "res": reserve, "up": false}
	build_gun()

func owns(id: String) -> int:
	for i in slots.size():
		if slots[i].id == id:
			return i
	return -1

func swap() -> void:
	if slots.size() < 2 or dead or pap_t > 0:
		return
	if game.grab and game.grab.held != null:
		game.grab.drop()
	cur = 1 - cur
	build_gun()
	game.audio.play("swap", null, -3)

func reload() -> void:
	var s = slots[cur]
	var wd := w()
	if reload_t > 0 or s.mag >= wd.mag or s.res == 0 or dead:
		return
	reload_t = wd.reload
	game.audio.play(wd.reload_snd, null, -2)

func _finish_reload() -> void:
	var s = slots[cur]
	var need: int = w().mag - s.mag
	if CASING.get(s.id, "") == "reload":
		for i in need:
			_eject(s.id == "sawed")
	if s.res < 0:
		s.mag += need
	else:
		var take := mini(need, s.res)
		s.mag += take
		s.res -= take

func _eject(shell: bool) -> void:
	var b := cam.global_transform.basis
	var p := cam.global_transform * Vector3(0.3, -0.1, -0.6)
	game.fx.eject(p, b.x, b.y, shell, velocity)

func on_mouse(rel: Vector2) -> void:
	look_delta += rel

# ---------------------------------------------------------------- shooting
func _spread_dir(spread: float) -> Vector3:
	var b := cam.global_transform.basis
	var ang := spread * sqrt(randf())
	var th := randf() * TAU
	return (-b.z + b.x * cos(th) * ang + b.y * sin(th) * ang).normalized()

func shoot() -> void:
	var s = slots[cur]
	var wd := w()
	if wd.get("melee", false):
		_swing()
		return
	fire_t = wd.rate
	if free_t <= 0.0:
		s.mag -= 1
	var moving := Vector2(velocity.x, velocity.z).length() > 0.5
	var spread: float = (wd.spread + bloom) * (0.4 if ads > 0.5 else 1.0) * (1.35 if moving else 1.0)
	var origin := cam.global_position
	var muzzle := flash_node.global_position
	var space := get_world_3d().direct_space_state
	var any_hit := false
	var any_kill := false
	if wd.has("proj") or wd.get("cone", false):
		game.wonder.fire(wd, origin, _spread_dir(0.0), muzzle)
	elif wd.get("flame", false):
		var d := _spread_dir(0.0)
		any_hit = game.flame(origin, d, wd)
		for i in 3:
			game.fx.burst(muzzle, d, 1, Color(1, randf_range(0.4, 0.7), 0.15), 12.0, 0.12, 0.45, true)
	else:
		var mag_to = _magnet_point()
		for i in int(wd.pellets):
			var d := _spread_dir(spread)
			if mag_to != null and wd.pellets == 1:
				# bullet magnetism: bend a near miss up to ~2 degrees onto the target
				var want: Vector3 = (mag_to - origin).normalized()
				var ang := d.angle_to(want)
				if ang < deg_to_rad(3.5) * assist_k and ang > 0.0001:
					d = d.slerp(want, minf(1.0, deg_to_rad(2.2) * assist_k / ang))
			var res: Dictionary = game.shoot_ray(origin, d, wd)
			any_hit = any_hit or res.hit
			any_kill = any_kill or res.kill
			if wd.get("bolt", false) or randf() < (0.35 if wd.pellets > 1 else 0.7):
				game.fx.tracer(muzzle, res.end, Color(0.85, 0.88, 0.95) if wd.get("staple", false) else (Color(0.8, 0.6, 1.0) if wd.get("up", false) else Color(1, 0.86, 0.6)))
	if any_hit:
		game.hud.hit(any_kill)
		game.audio.play("killmark" if any_kill else "hitmark", null, -4)
	kick = wd.kick
	shake = maxf(shake, 0.06 * wd.kick)
	game.rumble(0.15 + 0.12 * wd.kick, 0.05 + 0.1 * wd.kick * (1.5 if wd.pellets > 1 else 1.0), 0.08 + 0.03 * wd.kick)
	var ct: String = CASING.get(s.id, "")
	if ct == "shot":
		_eject(false)
	elif ct == "pump":
		get_tree().create_timer(0.3).timeout.connect(func(): _eject(true))
	if wd.pellets > 1 or wd.kick >= 1.5:
		game.fx.puff(muzzle, Color(0.6, 0.58, 0.55), false, 0.06, randf_range(0.35, 0.6), 0.5, 0.4, 0.03, 0.4)
	flash_node.scale = Vector3.ONE * randf_range(0.8, 1.5) * (1.6 if wd.pellets > 1 else 1.0)
	if wd.has("fov"):
		fov_kick = wd.fov
	elif s.id == "shotgun":
		fov_kick = 7
	bloom = minf(bloom + wd.bloom, wd.bloomMax)
	flash_node.visible = true
	flash_node.rotation.z = randf() * 3.0
	muzzle_light.position = cam.to_local(muzzle)
	muzzle_light.light_energy = 3.0 + wd.kick * 1.5
	game.audio.play(wd.shot_snd, null, -1, 0.82 if wd.get("up", false) else 1.0)
	if wd.get("up", false) and randf() < 0.5:
		game.audio.play("crackle", null, -14, 1.6)
	if s.id == "shotgun":
		get_tree().create_timer(0.26).timeout.connect(func(): game.audio.play("pump", null, -3))
	if s.mag == ceili(wd.mag * 0.25) and wd.mag >= 6:
		game.audio.play("lowAmmo", null, -8)
	if s.mag == 0 and s.res != 0:
		reload()

## first-person knife (and a boot when you're sprinting), built like the web game's
func _limb(parts: Array) -> Node3D:
	var n := Node3D.new()
	n.rotation_order = EULER_ORDER_XYZ
	for p in parts:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = p[0]
		m.mesh = b
		var mat := StandardMaterial3D.new()
		mat.albedo_color = p[1]
		mat.roughness = 0.6
		m.material_override = mat
		m.position = p[2]
		m.rotation.x = p[3]
		m.layers = 2
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(m)
	n.visible = false
	cam.add_child(n)
	return n

# ---------------------------------------------------------------- aim assist (controller only)
func _assist_on() -> bool:
	return not bot and game.pad and assist_k > 0.0 and not dead

## where on a zombie we pull toward: just under the crown of the head, or the body of a crawler
func _aim_point(z) -> Vector3:
	if z.crawler or not z.joints.has("head"):
		return z.global_position + Vector3(0, 0.35, 0)
	var h: Node3D = z.joints["head"]
	return h.global_transform * Vector3(0, 0.22, 0.02)

## nearest live zombie inside a cone of the crosshair that we can actually see
func _find_target(cone: float, rng := 40.0):
	var o := cam.global_position
	var f := -cam.global_transform.basis.z
	var best = null
	var best_s := 1e9
	var space := get_world_3d().direct_space_state
	for z in game.zombies:
		if not is_instance_valid(z) or not z.alive:
			continue
		var p := _aim_point(z)
		var to := p - o
		var dist := to.length()
		if dist > rng or dist < 0.5:
			continue
		var ang := f.angle_to(to / dist)
		# the cone narrows in angle with distance a little less than the target shrinks, so far targets still get help
		var lim := cone * clampf(6.0 / dist, 0.45, 1.6)
		if ang > lim:
			continue
		var score := ang / lim + dist * 0.004
		if score >= best_s:
			continue
		var q := PhysicsRayQueryParameters3D.create(o, p, 1)
		if not space.intersect_ray(q).is_empty():
			continue
		best = z
		best_s = score
	return best

func _magnet_point():
	if not _assist_on():
		return null
	var z = _find_target(deg_to_rad(4.0))
	return _aim_point(z) if z != null else null

## slowdown + rotational stickiness + the ADS snap. sd = the raw stick look this frame.
func _assist(dt: float, sd: Vector2) -> Vector2:
	if not _assist_on():
		_ast = null
		_ads_was = ads > 0.5
		return sd
	var k := assist_k
	var o := cam.global_position
	var z = _find_target(deg_to_rad(7.0 + 3.0 * ads))
	var out := sd
	if z != null:
		var dir := (_aim_point(z) - o).normalized()
		# slowdown: the crosshair gets "heavier" over a target
		var near := 1.0 - clampf((-cam.global_transform.basis.z).angle_to(dir) / deg_to_rad(7.0), 0.0, 1.0)
		out *= 1.0 - (0.4 + 0.15 * ads) * minf(k, 1.0) * near
		# rotational: follow the target's angular motion while we're steering
		if z == _ast and _ast_dir != Vector3.ZERO and (sd.length() > 0.0005 or velocity.length() > 0.5):
			var y0 := atan2(-_ast_dir.x, -_ast_dir.z)
			var y1 := atan2(-dir.x, -dir.z)
			var p0 := asin(clampf(_ast_dir.y, -1, 1))
			var p1 := asin(clampf(dir.y, -1, 1))
			var dy := wrapf(y1 - y0, -PI, PI)
			out.x -= dy * 0.55 * minf(k, 1.2)
			out.y -= (p1 - p0) * 0.55 * minf(k, 1.2)
		_ast_dir = dir
	else:
		_ast_dir = Vector3.ZERO
	_ast = z
	# ADS snap: pressing aim with a zombie near the crosshair pulls onto its head
	var aiming := Input.is_action_pressed("ads")
	if aiming and not _ads_was:
		var sz = _find_target(deg_to_rad(10.0 + 5.0 * k))
		if sz != null:
			_ast = sz
			_snap_t = 0.14
	_ads_was = aiming
	if _snap_t > 0.0 and _ast != null and is_instance_valid(_ast) and _ast.alive:
		_snap_t -= dt
		var dir := (_aim_point(_ast) - o).normalized()
		var ty := atan2(-dir.x, -dir.z)
		var tp := asin(clampf(dir.y, -1, 1))
		var a := minf(1.0, dt / maxf(_snap_t + dt, 0.001)) * minf(k, 1.0)
		out.x -= wrapf(ty - (yaw - out.x), -PI, PI) * a
		out.y -= (tp - (pitch - out.y)) * a
	return out

func melee() -> void:
	if melee_t > 0 or dead:
		return
	if w().get("melee", false) and sprint < 0.4:
		if fire_t <= 0 and swap_t <= 0:
			_swing()
		return
	var kick := sprint > 0.4
	melee_t = 0.8 if kick else 0.5
	melee_anim = 1.0
	melee_kind = "kick" if kick else ("bayo" if slots[cur].id == "bayonet" else "knife")
	fire_t = maxf(fire_t, 0.35)
	game.audio.play("whoosh", null, -3, 0.8 if kick else 1.15)
	var kind := melee_kind
	get_tree().create_timer(0.14 if kick else 0.09).timeout.connect(func():
		if not dead:
			game.melee(cam.global_position, -cam.global_transform.basis.z, kind))

# ---------------------------------------------------------------- the bat
# A three-hit combo: forehand sweep, backhand sweep, overhead slam. Each swing has an anticipation,
# a fast strike with a smear, a hit frame with hitstop, and a follow-through; it lunges you at a nearby zombie.
var swing_t := -1.0
var swing_n := 0
var swing_dur := 0.42
var swing_hit := 0.15
var swing_done := false
var swing_end_ms := 0
var bat_pos := Vector3(0.32, -0.42, -0.5)
var bat_rot := Vector3(0.15, 0.0, -0.35)
var lunge_t := 0.0
var lunge_v := Vector3.ZERO
var bat_blood := 0.0
var tip_prev = null
var base_prev = null
const BAT_REST := [Vector3(0.32, -0.42, -0.5), Vector3(0.15, 0.0, -0.35)]
# per swing: windup, strike, follow-through as [pos, rot]
const BAT_KEYS := [
	[[Vector3(0.5, -0.25, -0.25), Vector3(-1.15, -1.75, 0.0)], [Vector3(0.15, -0.3, -0.45), Vector3(-1.45, 0.75, 0.0)], [Vector3(-0.35, -0.35, -0.3), Vector3(-1.3, 1.9, 0.0)]],
	[[Vector3(-0.35, -0.28, -0.28), Vector3(-1.2, 1.85, 0.0)], [Vector3(-0.1, -0.3, -0.45), Vector3(-1.45, -0.75, 0.0)], [Vector3(0.42, -0.36, -0.3), Vector3(-1.3, -1.8, 0.0)]],
	[[Vector3(0.15, -0.02, -0.22), Vector3(1.25, 0.1, -0.1)], [Vector3(0.05, -0.15, -0.35), Vector3(-2.0, 0.0, 0.0)], [Vector3(0.05, -0.4, -0.3), Vector3(-2.5, 0.0, 0.0)]],
]

func _swing() -> void:
	if swing_t >= 0.0 and swing_t < swing_dur * 0.75:
		return
	var chain: bool = Time.get_ticks_msec() - swing_end_ms < 450 or swing_t >= 0.0
	swing_n = (swing_n + 1) % 3 if chain else 0
	swing_dur = 0.62 if swing_n == 2 else 0.4
	swing_hit = 0.25 if swing_n == 2 else 0.14
	fire_t = swing_dur * (1.15 if swing_n == 2 else 0.78)      # the slam leaves you open for a moment
	swing_t = 0.0
	swing_done = false
	tip_prev = null
	game.audio.play("batSwing", null, -2, (0.78 if swing_n == 2 else randf_range(0.95, 1.1)))
	roll += (-0.025 if swing_n == 0 else (0.025 if swing_n == 1 else 0.0))
	# lunge: close the gap to a zombie just out of reach
	var f := -global_transform.basis.z
	f.y = 0
	f = f.normalized()
	var best := 99.0
	for z in game.zombies:
		if not z.alive:
			continue
		var d3: Vector3 = z.global_position - global_position
		var d := Vector2(d3.x, d3.z).length()
		if d < best and d < 3.6 and absf(d3.y) < 1.5 and Vector3(d3.x, 0, d3.z).normalized().dot(f) > 0.6:
			best = d
	if swing_n == 0 and best < 3.8 and best > 2.0:      # only the opening swing of a combo lunges
		# a short burst forward that ends just inside swinging range
		lunge_t = 0.12
		lunge_v = f * clampf((best - 1.9) / 0.12, 4.0, 13.0)

func _bat_target(t: float) -> Array:
	if t < 0.0:
		var sp := sprint * 0.12
		return [BAT_REST[0] + Vector3(0, -sp, 0), BAT_REST[1] + Vector3(-sp, 0, 0)]
	var k: Array = BAT_KEYS[swing_n]
	var w_at := swing_hit * 0.55
	var f_at := swing_hit + (swing_dur - swing_hit) * 0.35
	var a: Array
	var b: Array
	var u: float
	if t < w_at:
		a = [bat_pos, bat_rot]
		b = k[0]
		u = t / w_at
		u = 1.0 - (1.0 - u) * (1.0 - u)            # ease out into the windup
	elif t < swing_hit:
		a = k[0]
		b = k[1]
		u = (t - w_at) / (swing_hit - w_at)
		u = u * u                                    # accelerate into the hit
	elif t < f_at:
		a = k[1]
		b = k[2]
		u = (t - swing_hit) / (f_at - swing_hit)
		u = 1.0 - (1.0 - u) * (1.0 - u)
	else:
		a = k[2]
		b = BAT_REST
		u = clampf((t - f_at) / (swing_dur - f_at), 0, 1)
		u = u * u * (3.0 - 2.0 * u)
	return [(a[0] as Vector3).lerp(b[0], u), (a[1] as Vector3).lerp(b[1], u)]

func _bat_tick(dt: float) -> void:
	if swing_t >= 0.0:
		swing_t += dt
		if not swing_done and swing_t >= swing_hit:
			swing_done = true
			game.bat_hit(cam.global_position, -cam.global_transform.basis.z, swing_n)
		if swing_t >= swing_dur:
			swing_t = -1.0
			swing_end_ms = Time.get_ticks_msec()
	var tg := _bat_target(swing_t)
	var sharp := 40.0 if swing_t >= 0.0 else 14.0
	bat_pos = bat_pos.lerp(tg[0], minf(1.0, dt * sharp))
	bat_rot = bat_rot.lerp(tg[1], minf(1.0, dt * sharp))
	# the smear: a fading ribbon traced by the barrel through the strike
	if gun_node and swing_t >= swing_hit * 0.5 and swing_t <= swing_hit + 0.07:
		var tip: Vector3 = gun_node.global_transform * Vector3(0, 0.95, 0)
		var base: Vector3 = gun_node.global_transform * Vector3(0, 0.55, 0)
		if tip_prev != null:
			game.fx.ribbon(base_prev, tip_prev, tip, base, Color(1.0, 0.85, 0.75, 0.3) if not slots[cur].get("up", false) else Color(0.75, 0.55, 1.0, 0.5), 0.16)
		tip_prev = tip
		base_prev = base
	else:
		tip_prev = null
	if gun_node and gun_node.has_meta("bat_mat"):
		var m: StandardMaterial3D = gun_node.get_meta("bat_mat")
		m.albedo_color = Color8(214, 178, 124).lerp(Color8(110, 14, 12), bat_blood * 0.75)

var invuln := false
func hurt(dmg: float, acid := false) -> void:
	if dead or invuln:
		return
	hp -= dmg
	hurt_t = 0.0
	shake = maxf(shake, 0.14 + dmg / 120.0)
	roll = (0.05 + dmg / 300.0) * (1.0 if randf() < 0.5 else -1.0)
	game.hud.hurt_flash(dmg, acid)
	game.rumble(0.4, 0.6, 0.2)
	game.hud.jolt(0.25 + dmg / 30.0)
	game.audio.play("hurt", null, -2)
	if hp <= 0:
		hp = 0
		dead = true
		game.player_died()

# ---------------------------------------------------------------- per frame
func _physics_process(dt: float) -> void:
	if frozen:
		velocity = Vector3.ZERO
		look_delta = Vector2.ZERO
		return
	if dead:
		velocity.x = move_toward(velocity.x, 0, dt * 20)
		velocity.z = move_toward(velocity.z, 0, dt * 20)
		velocity.y -= GRAVITY * dt
		move_and_slide()
		return
	var inp := Vector2.ZERO
	var want_sprint := false
	var want_ads := false
	if bot:
		inp = bot_input.move
		want_ads = bot_input.ads
		trigger = bot_input.fire
	else:
		inp = Input.get_vector("left", "right", "fwd", "back", 0.2)
		if Input.is_action_just_pressed("sprint_pad"):
			sprint_latch = true
		want_sprint = Input.is_action_pressed("sprint") or (sprint_latch and inp.y < -0.3)
		if inp.length() < 0.2:
			sprint_latch = false
		want_ads = Input.is_action_pressed("ads")
		trigger = Input.is_action_pressed("fire")
	ads = move_toward(ads, 1.0 if want_ads else 0.0, dt * 6)
	var moving := inp.length() > 0.1
	sprint = move_toward(sprint, 1.0 if (want_sprint and moving and inp.y < 0 and ads < 0.2 and not trigger) else 0.0, dt * 5)
	slow_t = maxf(0.0, slow_t - dt)
	stun_t = maxf(0.0, stun_t - dt)
	var speed: float = (7.0 + sprint * 4.2) * (1.0 - 0.35 * ads) * (0.55 if slow_t > 0 else 1.0) * (0.4 if stun_t > 0 else 1.0)
	var dir := Vector3(cos(yaw) * inp.x + sin(yaw) * inp.y, 0, -sin(yaw) * inp.x + cos(yaw) * inp.y)
	var tv := dir * speed
	var acc := 14.0 if is_on_floor() else 4.0
	velocity.x = move_toward(velocity.x, tv.x, acc * speed * dt)
	velocity.z = move_toward(velocity.z, tv.z, acc * speed * dt)
	if lunge_t > 0.0:
		lunge_t -= dt
		velocity.x = lunge_v.x
		velocity.z = lunge_v.z
	if is_on_floor():
		if not bot and Input.is_action_just_pressed("jump"):
			velocity.y = 7.2
	velocity.y -= GRAVITY * dt
	var hv := Vector3(velocity.x, 0, velocity.z)
	if not is_on_floor():
		fall_v = minf(fall_v, velocity.y)
	move_and_slide()
	if is_on_floor() and not was_floor and fall_v < -6.0:
		land_dip = clampf(-fall_v / 14.0, 0.2, 1.0)
		shake = maxf(shake, 0.05 * land_dip)
		game.audio.play("land", null, -6)
	if is_on_floor():
		fall_v = 0.0
	was_floor = is_on_floor()
	# step up curbs and low ledges (the web game steps 0.45 m)
	if is_on_floor() and is_on_wall() and hv.length() > 0.5:
		var up := Vector3(0, 0.46, 0)
		var fwd := hv.normalized() * 0.12
		if not test_move(global_transform, up) and not test_move(global_transform.translated(up), fwd):
			global_position += up + fwd
	if global_position.y < -20:
		global_position = Vector3(game.world.data.start[0], 1, game.world.data.start[2])
	if moving and is_on_floor():
		bob += dt * hv.length() * 1.3
		var ph := int(floor(bob / PI))
		if ph != step_phase:
			step_phase = ph
			game.audio.play("pstep", null, -9 if sprint < 0.5 else -6)

func _process(dt: float) -> void:
	if frozen:
		look_delta = Vector2.ZERO
		return
	# look
	var sens := 0.0022 * sens_k / sqrt(1.0 + (w().ads_zoom - 1.0) * ads)
	var d := look_delta * sens
	# controller: right stick with a little acceleration curve
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	var sd := Vector2.ZERO
	if stick.length() > pad_dead:
		var mag := minf(1.0, (stick.length() - pad_dead) / (0.95 - pad_dead))
		# response curve: gentle near the centre for fine aim, fast at full tilt
		sd = stick.normalized() * (0.35 * mag + 0.65 * mag * mag * mag) * 3.6 * pad_k * dt / sqrt(1.0 + (w().ads_zoom - 1.0) * ads)
	d += _assist(dt, sd)
	if invert:
		d.y = -d.y
	if bot:
		d = bot_input.look
	look_delta = Vector2.ZERO
	if stun_t > 0:
		var k := minf(stun_t, 1.0)
		d += Vector2(sin(Time.get_ticks_msec() / 90.0), cos(Time.get_ticks_msec() / 130.0)) * 0.012 * k
	free_t = maxf(0.0, free_t - dt)
	yaw -= d.x
	pitch = clampf(pitch - d.y, -1.45, 1.45)
	sw.x += (clampf(-d.x * 2.2, -0.08, 0.08) - sw.x) * minf(1.0, dt * 9)
	sw.y += (clampf(d.y * 2.2, -0.06, 0.06) - sw.y) * minf(1.0, dt * 9)
	rotation.y = yaw
	# timers
	fire_t -= dt
	melee_t -= dt
	swap_t = maxf(0.0, swap_t - dt)
	hurt_t += dt
	if reload_t > 0:
		reload_t -= dt
		if reload_t <= 0:
			reload_t = 0
			_finish_reload()
	kick = maxf(0.0, kick - dt * 6)
	shake = maxf(0.0, shake - dt * 0.3)
	fov_kick = maxf(0.0, fov_kick - dt * 35)
	throw_anim = maxf(0.0, throw_anim - dt * 1.6)
	roll = move_toward(roll, 0.0, dt * 0.4)
	land_dip = maxf(0.0, land_dip - dt * 4.0)
	var melee_dip := 0.0
	var bayo_thrust := 0.0
	if melee_anim > 0:
		melee_anim = maxf(0.0, melee_anim - dt * (2.4 if melee_kind == "kick" else 3.2))
		var mk := 1.0 - melee_anim
		var s2 := sin(mk * PI)
		knife.visible = melee_kind == "knife"
		boot.visible = melee_kind == "kick"
		if melee_kind == "knife":
			knife.position = Vector3(0.45 - mk * 0.8, -0.28 + s2 * 0.12, -0.45 - s2 * 0.15)
			knife.rotation = Vector3(-0.2, 0.9 - mk * 1.6, -0.5 + mk * 0.9)
		elif melee_kind == "kick":
			boot.position = Vector3(0.05, -0.75 + s2 * 0.3, -0.2 - s2 * 0.55)
			boot.rotation = Vector3(-1.2 + s2 * 0.4, 0, 0)
		else:
			bayo_thrust = s2
		melee_dip = 0.0 if melee_kind == "bayo" else s2 * 0.28
	else:
		knife.visible = false
		boot.visible = false
	bloom = maxf(0.0, bloom - dt * 0.08)
	if not dead and hurt_t > 4.0 and hp < max_hp:
		hp = minf(max_hp, hp + dt * 5.0)
	heart_t -= dt
	if not dead and hp < 30 and heart_t <= 0:
		heart_t = 0.85
		game.audio.play("heart", null, -3)
	# fire
	var wd := w()
	var s = slots[cur]
	pap_t = maxf(0.0, pap_t - dt)
	var carrying: bool = game.grab != null and game.grab.held != null
	if carrying:
		if not dead and trigger and not trigger_was:
			game.grab.throw()
			fire_t = 0.35
			swap_t = 0.35
	elif not dead and trigger and fire_t <= 0 and reload_t <= 0 and swap_t <= 0 and pap_t <= 0:
		if s.mag > 0:
			if wd.auto or not trigger_was:
				shoot()
		elif not trigger_was:
			game.audio.play("click", null, -4)
			reload()
	trigger_was = trigger
	if not dead and s.mag == 0 and s.res != 0 and reload_t <= 0 and fire_t <= 0:
		reload()
	# camera: shake, kick, bob, FOV
	var ad := ads
	var sh := shake * 0.5
	var moving := Vector2(velocity.x, velocity.z).length() > 0.5
	cam.position = Vector3(randf_range(-0.5, 0.5) * sh, EYE + (sin(bob * 2) * 0.045 * (1 - 0.7 * ad) if moving else 0.0) + randf_range(-0.5, 0.5) * sh - sin(land_dip * PI) * 0.12, 0)
	cam.rotation = Vector3(pitch + kick * 0.035 * (1 - 0.5 * ad) + randf_range(-0.5, 0.5) * sh * 0.06, randf_range(-0.5, 0.5) * sh * 0.06, roll)
	cam.fov = (base_fov + sprint * 9.0 + fov_kick) / (1.0 + (wd.ads_zoom - 1.0) * ad)
	# viewmodel pose (web game numbers)
	var bob_a := (1.0 + sprint * 1.6) if moving else 0.0
	var rl := sin((1.0 - reload_t / wd.reload) * PI) if reload_t > 0 else 0.0
	var swp := swap_t / 0.35
	var gx := 0.27 + cos(bob) * 0.014 * bob_a - sprint * 0.06 + sw.x
	var gy := -0.27 - absf(sin(bob)) * 0.018 * bob_a - sprint * 0.1 + sw.y
	var gz := -0.52
	gx += (wd.ads_x + sw.x * 0.25 - gx) * ad
	gy += (wd.ads_y + sw.y * 0.25 - gy) * ad
	gz += (-0.42 - gz) * ad
	var th := sin(throw_anim * PI) if throw_anim > 0 else 0.0
	gy -= rl * 0.2 + swp * 0.35 + th * 0.4 + land_dip * 0.06 + melee_dip
	gz -= bayo_thrust * 0.35
	gz += kick * 0.09 * (1 - 0.5 * ad)
	if wd.get("melee", false):
		_bat_tick(dt)
		vm.position = bat_pos + Vector3(cos(bob) * 0.014 * bob_a + sw.x * 0.6, -absf(sin(bob)) * 0.02 * bob_a - swp * 0.35 - land_dip * 0.06 + sw.y * 0.6, 0)
		vm.rotation = bat_rot + Vector3(sw.y * 0.8, sw.x * 0.8, 0)
		vm.visible = not dead and pap_t <= 0 and not carrying
	else:
		vm.position = Vector3(gx, gy, gz)
		vm.rotation = Vector3(kick * 0.22 * (1 - 0.6 * ad) - rl * 0.7 - sprint * 0.35 + sw.y * 1.5 * (1 - ad), (sprint * 0.55 + sw.x * 1.4) * (1 - ad), rl * 0.4 + sprint * 0.35 + sw.x * 0.8 * (1 - ad))
		var scoped: bool = slots[cur].id == "dmr" and ad > 0.85
		vm.visible = not scoped and not dead and pap_t <= 0 and not carrying
	if flash_node and kick < wd.kick * 0.65:
		flash_node.visible = false
	muzzle_light.light_energy = maxf(0.0, muzzle_light.light_energy - dt * 40)
	# flashlight with the occasional flicker
	torch_flick -= dt
	torch_wait -= dt
	if torch_wait <= 0 and randf() < dt * 0.06:
		torch_flick = 0.3
		torch_wait = 6
	var k := (0.15 if randf() < 0.5 else 1.0) if torch_flick > 0 else 1.0
	if hp < 30:
		k *= 0.8 + randf() * 0.2
	torch.light_energy += ((2.2 * k if torch_on and not dead else 0.0) - torch.light_energy) * minf(1.0, dt * 20)

func hud_state() -> Dictionary:
	var wd := w()
	var s = slots[cur]
	var other := ""
	if slots.size() > 1:
		other = wdata(slots[1 - cur]).name
	var hint := ""
	if reload_t > 0:
		hint = "RELOADING"
	elif s.mag == 0 and s.res == 0:
		hint = "NO AMMO"
	elif s.mag <= ceili(wd.mag * 0.25) and s.res != 0 and not wd.get("melee", false):
		hint = "PRESS {reload} TO RELOAD"
	return {"hp": hp, "max_hp": max_hp, "gun": wd.name, "other": other, "mag": s.mag, "res": s.res,
		"low_ammo": s.mag <= ceili(wd.mag * 0.25), "hint": hint, "spread": (wd.spread + bloom) * (1 - ads * 0.7),
		"melee": wd.get("melee", false), "show_cross": ads < 0.6 and not dead, "scoped": slots[cur].id == "dmr" and ads > 0.85}
