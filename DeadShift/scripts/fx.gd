extends Node3D
## The web game's juice: instanced blood spray with streaks, puffs, bouncing gibs and casings,
## floor/wall splats, scorch marks, tracers and explosions.

const CAP := 1400
const MAX_DECALS := 170
const UP := Vector3.UP
const BLOOD := Color8(122, 10, 10)
const BLOOD_DK := Color8(74, 5, 5)
const BLOOD_LT := Color8(140, 14, 14)

var parts: Array = []        # {p, v, s, c, life, blood, str, fl}
var puffs: Array = []        # {n, mat, life, max, s0, s1, vy, op}
var gibs: Array = []         # {n, v, spin, life, still, bleed, trail, rest}
var casings: Array = []
var decals: Array = []
var mm: MultiMesh
var cube := BoxMesh.new()
var mats := {}
var dmats := {}
var splat_tex: Array = []
var hole_tex: ImageTexture
var scorch_tex: Texture2D
var bile_tex: ImageTexture
var brass: StandardMaterial3D
var shellm: StandardMaterial3D
var splat_budget := 3
var game

func _ready() -> void:
	cube.size = Vector3.ONE
	for i in 3:
		splat_tex.append(_make_splat(Color(0.48, 0.03, 0.04, 0.95), 9 + i * 3))
	hole_tex = _make_splat(Color(0.05, 0.045, 0.04), 1)
	bile_tex = _make_splat(Color(0.35, 0.45, 0.1, 0.85), 9)
	scorch_tex = load("res://assets/textures/scorch.png")
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bm := BoxMesh.new()
	bm.size = Vector3(0.08, 0.08, 0.08)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.vertex_color_use_as_albedo = true
	bm.material = pm
	mm.mesh = bm
	mm.instance_count = CAP
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-500, -100, -500), Vector3(1000, 300, 1000))
	add_child(mmi)
	brass = StandardMaterial3D.new()
	brass.albedo_color = Color8(201, 160, 64)
	brass.metallic = 0.6
	brass.roughness = 0.4
	shellm = StandardMaterial3D.new()
	shellm.albedo_color = Color8(154, 26, 20)

func _make_splat(col: Color, blobs: int) -> ImageTexture:
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for b in blobs:
		var cx := 24.0 + (randf_range(-13, 13) if b > 0 else 0.0)
		var cy := 24.0 + (randf_range(-13, 13) if b > 0 else 0.0)
		var r := randf_range(2, 8) if b > 0 else 11.0
		for y in 48:
			for x in 48:
				var d := Vector2(x - cx, y - cy).length()
				if d < r:
					var a := clampf((r - d) / 2.0, 0, 1) * col.a
					var c := img.get_pixel(x, y)
					var k := randf_range(0.75, 1.1)
					img.set_pixel(x, y, Color(col.r * k, col.g, col.b, maxf(c.a, a)))
	return ImageTexture.create_from_image(img)

func _mat(col: Color, glow := false) -> StandardMaterial3D:
	var key := col.to_html() + str(glow)
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.roughness = 1.0
	mats[key] = m
	return m

func _floor_at(p: Vector3, up := 0.3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, up, 0), p + Vector3(0, -30, 0), 1)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	return r.position.y if not r.is_empty() else p.y - 30.0

# ---------------------------------------------------------------- particles (the web game's spray)
func spray(p: Vector3, dir: Vector3, col: Color, n: int, spd: float, size := 1.0, blood := false, streak := 0.0, jit := 1.5, life := 1.0) -> void:
	if n <= 0:
		return
	if parts.size() + n > CAP:
		parts = parts.slice(parts.size() + n - CAP)
	var fl := _floor_at(p)
	for i in n:
		parts.append({"p": p, "v": Vector3(dir.x * spd * randf_range(0.3, 1) + randf_range(-jit, jit), dir.y * spd * randf_range(0.3, 1) + randf_range(0.5, 3), dir.z * spd * randf_range(0.3, 1) + randf_range(-jit, jit)),
			"s": size * randf_range(0.6, 1.5), "c": col, "life": randf_range(0.5, 1.1) * life, "blood": blood, "str": (streak if streak > 0 else 0.045) if blood else streak, "fl": fl})

## compatibility with the old API
func burst(pos: Vector3, dir: Vector3, n: int, col: Color, speed: float, size: float, life: float, _glow := false) -> void:
	spray(pos, dir, col, n, speed, size / 0.08, false, 0.0, speed * 0.25, life)

## a juicy bullet impact on flesh: entry splash back at you, a fast exit spurt, heavy drops, fine mist
func blood_hit(pt: Vector3, dir: Vector3, pellets: int, head: bool) -> void:
	var k := 0.45 if pellets > 1 else 1.0
	spray(pt, dir, BLOOD, roundi(12 * k), 6, 1.1, true)
	spray(pt, dir, Color8(86, 6, 6), roundi(7 * k), 11, 0.75, true, 0.07, 0.8, 0.8)
	var bd := -dir
	bd.y += 0.3
	spray(pt, bd, BLOOD_LT, roundi(5 * k), 3.5, 0.7, true)
	spray(pt, UP, Color8(58, 4, 4), maxi(1, roundi(3 * k)), 1.5, 1.9, true, 0.02, 1, 1.3)
	if randf() < (0.35 if pellets > 1 else 0.8):
		puff(pt, Color8(160, 48, 48) if head else Color8(106, 10, 10), false, 0.05, randf_range(0.5, 0.75) if head else randf_range(0.3, 0.5), randf_range(0.25, 0.4), 0.15, 0.04, 0.55)
	if randf() < 0.5 * k:
		wall_splat(pt, dir, randf_range(0.5, 1.0))

func blood(pos: Vector3, dir: Vector3, big := false) -> void:
	if big:
		spray(pos, dir, BLOOD, 40, 6, 1.4, true)
		spray(pos, dir, BLOOD_DK, 18, 3, 2.2, true, 0.02)
		spray(pos, UP, Color8(140, 14, 14), 20, 7, 0.9, true, 0.06, 2.5)
		puff(pos, Color8(106, 10, 10), false, 0.1, randf_range(0.9, 1.3), 0.5, 0.2, 0.1, 0.6)
		splat(pos, randf_range(1.2, 2.0))
		wall_splat(pos, dir, randf_range(0.9, 1.6))
	else:
		blood_hit(pos, dir, 1, false)

func gib_bits(pos: Vector3, dir: Vector3) -> void:
	spray(pos, dir, Color8(160, 128, 115), 10, 6, 1.0, false, 0.0, 2.0, 0.9)
	spray(pos, UP, BLOOD, 44, 6, 1.3, true, 0.06, 2.0)
	spray(pos, UP, BLOOD_DK, 10, 3, 2, true)

func spark(pos: Vector3, normal: Vector3) -> void:
	spray(pos, normal, Color(1.0, 0.82, 0.45), 6, 6, 0.4, false, 0.0, 1.5, 0.35)
	spray(pos, normal, Color(0.42, 0.4, 0.36), 4, 2.4, 0.9, false, 0.0, 1.0, 0.6)
	puff(pos + normal * 0.05, Color(0.55, 0.52, 0.48), false, 0.05, randf_range(0.25, 0.4), 0.45, 0.25, 0.02, 0.45)

func splash(pos: Vector3, col: Color, n := 14) -> void:
	spray(pos, UP, col, n, 5.5, 1.0, false, 0.0, 2.5, 0.8)

func puff(pos: Vector3, col: Color, add: bool, s0: float, s1: float, life: float, vy: float, spread: float, op := 1.0) -> void:
	if puffs.size() > 110:
		var o = puffs.pop_front()
		o.n.queue_free()
	var m := MeshInstance3D.new()
	m.mesh = cube
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(col, op)
	if add:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.no_depth_test = false
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	m.global_position = pos + Vector3(randf_range(-spread, spread), randf_range(-spread * 0.4, spread), randf_range(-spread, spread))
	m.rotation = Vector3(randf() * 3, randf() * 3, randf() * 3)
	m.scale = Vector3.ONE * s0
	puffs.append({"n": m, "mat": mat, "life": life, "max": life, "s0": s0, "s1": s1, "vy": vy, "op": op})

# ---------------------------------------------------------------- decals
func _dmat(tex: Texture2D) -> StandardMaterial3D:
	if dmats.has(tex):
		return dmats[tex]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 0.35
	dmats[tex] = m
	return m

## a flat splat on whatever floor is under pos
func splat(pos: Vector3, size := -1.0, tex: Texture2D = null) -> void:
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.3, 0), pos + Vector3(0, -4, 0), 1)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty() or r.normal.y < 0.6:
		return
	_decal(r.position, r.normal, tex if tex else splat_tex[randi() % splat_tex.size()], size if size > 0 else randf_range(0.35, 0.8))

## blood thrown onto the wall behind what was hit
func wall_splat(pos: Vector3, dir: Vector3, size: float) -> void:
	var d := Vector3(dir.x, dir.y * 0.5 - 0.1, dir.z).normalized()
	var q := PhysicsRayQueryParameters3D.create(pos, pos + d * 3.0, 1)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return
	_decal(r.position, r.normal, splat_tex[randi() % splat_tex.size()], size * (1.0 - r.position.distance_to(pos) / 4.0))

func scorch(pos: Vector3, size: float) -> void:
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.5, 0), pos + Vector3(0, -4, 0), 1)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		_decal(r.position, r.normal, scorch_tex, size)

func bile_splat(pos: Vector3, size: float) -> void:
	splat(pos, size, bile_tex)

func hole(pos: Vector3, normal: Vector3) -> void:
	_decal(pos, normal, hole_tex, 0.07)

func _decal(pos: Vector3, normal: Vector3, tex: Texture2D, size: float) -> void:
	var q := MeshInstance3D.new()
	var pm := QuadMesh.new()
	pm.size = Vector2(size, size)
	pm.material = _dmat(tex)
	q.mesh = pm
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(q)
	var z := normal.normalized()
	var x := z.cross(Vector3.UP if absf(z.y) < 0.9 else Vector3.RIGHT).normalized()
	var y := z.cross(x)
	q.global_transform = Transform3D(Basis(x, y, z).rotated(z, randf() * TAU), pos + z * (0.012 + (decals.size() % 40) * 0.0004))
	decals.append(q)
	if decals.size() > MAX_DECALS:
		decals.pop_front().queue_free()

# ---------------------------------------------------------------- tracers, lights, explosions
func tracer(a: Vector3, b: Vector3, col := Color(1, 0.86, 0.6)) -> void:
	var len := a.distance_to(b)
	if len < 0.5:
		return
	var m := MeshInstance3D.new()
	m.mesh = cube
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(col, 0.9)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	m.global_position = (a + b) / 2.0
	m.look_at(b, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)
	m.scale = Vector3(0.025, 0.025, len)
	var tw := m.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.07)
	tw.tween_callback(m.queue_free)

## a fading quad between two edges (the bat's swing smear)
func ribbon(a0: Vector3, a1: Vector3, b1: Vector3, b0: Vector3, col: Color, life := 0.12) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in [a0, a1, b1, a0, b1, b0]:
		im.surface_add_vertex(p)
	im.surface_end()
	var m := MeshInstance3D.new()
	m.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.albedo_color = col
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.layers = 2
	add_child(m)
	var tw := m.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, life)
	tw.tween_callback(m.queue_free)

## a jagged electric arc (a chain of short tracers)
func arc(a: Vector3, b: Vector3, col := Color(0.6, 0.8, 1.0), jag := 0.35, life := 0.12, thick := 0.05) -> void:
	var n := clampi(int(a.distance_to(b) / 0.6), 3, 14)
	var prev := a
	for i in range(1, n + 1):
		var k := float(i) / n
		var p := a.lerp(b, k)
		if i < n:
			p += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * jag
		var m := MeshInstance3D.new()
		m.mesh = cube
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(col, 1.0)
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		var l := prev.distance_to(p)
		if l > 0.01:
			m.global_position = (prev + p) / 2.0
			m.look_at(p, Vector3.UP if absf((p - prev).normalized().y) < 0.99 else Vector3.RIGHT)
			m.scale = Vector3(thick, thick, l)
		var tw := m.create_tween()
		tw.tween_property(mat, "albedo_color:a", 0.0, life)
		tw.tween_callback(m.queue_free)
		prev = p

func flash_light(pos: Vector3, col := Color(1, 0.75, 0.45), energy := 3.0, rng := 6.0, t := 0.06) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, t).set_ease(Tween.EASE_IN)
	tw.tween_callback(l.queue_free)

func boom(pos: Vector3, radius: float, bile := false) -> void:
	if bile:
		flash_light(pos + Vector3(0, 1, 0), Color(0.6, 0.75, 0.25), 4.0, radius * 2.5, 0.4)
		for i in 8:
			puff(pos, Color8(138, 154, 58) if i % 2 else Color8(94, 110, 36), false, 0.5, randf_range(1.8, 3), randf_range(0.8, 1.6), randf_range(0.3, 1), 1, 0.8)
		spray(pos, UP, Color8(122, 138, 48), 30, 8, 1.2)
		spray(pos, UP, Color8(90, 16, 16), 16, 6, 1.1, true)
		bile_splat(pos, randf_range(3, 4))
		return
	flash_light(pos + Vector3(0, 1, 0), Color(1, 0.55, 0.2), 9.0, radius * 3.2, 0.45)
	for i in 7:
		puff(pos, Color8(255, 224, 138) if i < 3 else Color8(255, 122, 32), true, 0.6, randf_range(2.2, 3.4), randf_range(0.35, 0.55), randf_range(1, 3), 0.8)
	for i in 6:
		puff(pos, Color8(26, 23, 20), false, 0.5, randf_range(2, 3.2), randf_range(1.2, 2), randf_range(1.5, 2.5), 1, 0.85)
	spray(pos, UP, Color(1, 0.75, 0.38), 22, 10, 0.8, false, 0.05)
	spray(pos, UP, Color(0.25, 0.22, 0.2), 14, 7, 1.3, false, 0.0, 3.0)
	scorch(pos, randf_range(3, 4))

## gore pieces that fly off: takes over a mesh node and throws it
func throw_piece(n: Node3D, vel: Vector3, life := 9.0, bleed := true) -> void:
	var xf := n.global_transform
	if n.get_parent():
		n.get_parent().remove_child(n)
	add_child(n)
	n.global_transform = xf
	if n is GeometryInstance3D:
		n.material_overlay = null
	if gibs.size() > 90:
		var o = gibs.pop_front()
		if is_instance_valid(o.n):
			o.n.queue_free()
	gibs.append({"n": n, "v": vel, "spin": Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9)), "life": life, "still": false, "bleed": bleed, "trail": 0.0, "rest": 0.06})

## brass flying out of the gun's ejection port
func eject(pos: Vector3, right: Vector3, up: Vector3, shell: bool, pvel: Vector3) -> void:
	if casings.size() > 40:
		var o = casings.pop_front()
		if is_instance_valid(o.n):
			o.n.queue_free()
	var m := MeshInstance3D.new()
	m.mesh = cube
	m.material_override = shellm if shell else brass
	m.scale = Vector3(0.04, 0.04, 0.09) if shell else Vector3(0.018, 0.018, 0.045)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	m.global_position = pos
	m.rotation = Vector3(randf() * 3, randf() * 3, randf() * 3)
	var v := right * randf_range(1.8, 2.6) + up * randf_range(1.5, 2.4) + pvel * 0.8
	casings.append({"n": m, "v": v, "life": 4.0, "bounces": 0, "shell": shell, "still": false})

func _process(dt: float) -> void:
	splat_budget = 3
	var space := get_world_3d().direct_space_state
	# particles
	var n := 0
	var keep: Array = []
	for p in parts:
		p.life -= dt
		if p.life <= 0:
			continue
		p.v.y -= 16.0 * dt
		p.p += p.v * dt
		var rest: float = p.fl + 0.04
		if p.p.y < rest and p.p.y > rest - 1.5:
			p.p.y = rest
			if p.blood and p.v.y < -2 and splat_budget > 0 and randf() < 0.3:
				splat_budget -= 1
				_decal(p.p - Vector3(0, 0.03, 0), UP, splat_tex[randi() % splat_tex.size()], randf_range(0.25, 0.6))
			p.v = Vector3(p.v.x * 0.4, p.v.y * -0.2, p.v.z * 0.4)
		keep.append(p)
		var s: float = p.s
		var b := Basis.from_scale(Vector3(s, s, s))
		if p.str > 0:
			var sp: float = p.v.length()
			if sp > 0.5:
				var d: Vector3 = p.v / sp
				var x := d.cross(Vector3.RIGHT if absf(d.x) < 0.9 else Vector3.FORWARD).normalized()
				var z := x.cross(d)
				b = Basis(x * s * 0.8, d * s * (1.0 + minf(sp, 14.0) * p.str), z * s * 0.8)
		mm.set_instance_transform(n, Transform3D(b, p.p))
		mm.set_instance_color(n, p.c)
		n += 1
	parts = keep
	mm.visible_instance_count = n
	# puffs
	var i := puffs.size() - 1
	while i >= 0:
		var f = puffs[i]
		f.life -= dt
		if f.life <= 0:
			f.n.queue_free()
			puffs.remove_at(i)
		else:
			var t := clampf(1.0 - f.life / f.max, 0, 1)
			f.n.scale = Vector3.ONE * (f.s0 + (f.s1 - f.s0) * sqrt(t))
			f.n.position.y += f.vy * dt
			f.n.rotate_y(dt)
			f.mat.albedo_color.a = f.op * (1.0 - t)
		i -= 1
	# gibs: bounce on the real floor, bleed while flying, leave a splat where they land
	i = gibs.size() - 1
	while i >= 0:
		var g = gibs[i]
		g.life -= dt
		if g.life <= 0 or not is_instance_valid(g.n):
			if is_instance_valid(g.n):
				g.n.queue_free()
			gibs.remove_at(i)
			i -= 1
			continue
		var m: Node3D = g.n
		if not g.still:
			g.v.y -= 18.0 * dt
			var from := m.global_position
			var to: Vector3 = from + g.v * dt
			var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to + g.v.normalized() * 0.08, 1))
			if not r.is_empty() and r.normal.y < 0.6:
				g.v = g.v.bounce(r.normal) * 0.45
				to = from
			m.global_position = to
			m.rotate_x(g.spin.x * dt)
			m.rotate_z(g.spin.z * dt)
			g.trail -= dt
			if g.bleed and g.trail <= 0 and g.v.y > -12:
				g.trail = 0.06
				spray(to, UP, Color8(106, 8, 8), 1, 0.5, 0.9, true)
			if g.v.y < 0:
				var fr := space.intersect_ray(PhysicsRayQueryParameters3D.create(to + Vector3(0, 0.3, 0), to - Vector3(0, 0.4, 0), 1))
				if not fr.is_empty() and to.y < fr.position.y + g.rest:
					m.global_position.y = fr.position.y + g.rest
					if g.bleed and g.v.y < -3:
						_decal(fr.position, fr.normal, splat_tex[randi() % splat_tex.size()], randf_range(0.4, 0.8))
					g.v = Vector3(g.v.x * 0.45, g.v.y * -0.25, g.v.z * 0.45)
					g.spin *= 0.4
					if absf(g.v.y) < 0.8:
						g.still = true
		if g.life < 1:
			m.global_position.y -= dt * 0.4
		i -= 1
	# casings
	i = casings.size() - 1
	while i >= 0:
		var c = casings[i]
		c.life -= dt
		if c.life <= 0:
			c.n.queue_free()
			casings.remove_at(i)
			i -= 1
			continue
		if not c.still:
			c.v.y -= 14.0 * dt
			var np: Vector3 = c.n.global_position + c.v * dt
			c.n.rotate_x(dt * 12)
			c.n.rotate_y(dt * 9)
			if c.v.y < 0:
				var fr := space.intersect_ray(PhysicsRayQueryParameters3D.create(np + Vector3(0, 0.25, 0), np - Vector3(0, 0.1, 0), 1))
				if not fr.is_empty() and np.y < fr.position.y + 0.015:
					np.y = fr.position.y + 0.015
					if c.bounces < 2 and c.v.y < -1:
						c.bounces += 1
						if game:
							game.audio.play("casing", np, -10, 1.3 if not c.shell else 0.8)
					c.v = Vector3(c.v.x * 0.5, c.v.y * -0.35, c.v.z * 0.5)
					if absf(c.v.y) < 0.6:
						c.still = true
						c.n.rotation = Vector3(PI / 2, randf() * TAU, 0)
			c.n.global_position = np
		i -= 1
