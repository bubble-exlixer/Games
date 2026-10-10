extends Node3D
## Set dressing the web game drew in code (so it never came across in the map export):
## posters and flyers, the gym's pep rally (banners, pennants, streamers, balloons, confetti, court lines),
## the welcome sign, and new clutter: lunch trays and milk, a menu board, papers in the halls.

const BALLOON_LAYER := 16
const PCOLS := 8
const PROWS := 4

var game
var rng := RandomNumberGenerator.new()
var posters: Array = []     # [x, y, z, face, idx, w, h, tilt]
var balloons: Array = []    # {body, mesh, base: Vector3, ph: float, float: bool, col: Color}

func setup(g) -> void:
	game = g
	rng.seed = 1999
	_place_posters()
	_build_quads(posters, "res://assets/textures/posters.png", PCOLS, PROWS)
	var ban: Array = []
	for b in [[-46, 6.3, 5.73, "-z", 0, 9, 2.25], [-59.73, 6.6, -4, "+x", 1, 10, 2.5], [-32.27, 6.6, -14.5, "-x", 2, 8, 2], [-32.27, 2.0, -7.25, "-x", 3, 4.2, 3.6]]:
		ban.append(b + [rng.randf_range(-0.02, 0.02)])
	_build_quads(ban, "res://assets/textures/banners.png", 1, 4)
	_court()
	_pennants()
	_balloons()
	_confetti()
	_welcome()
	_cafeteria()
	_papers.call_deferred()

# ---------------------------------------------------------------- posters (the web game's placements)
func _poster(x: float, y: float, z: float, face: String, idx := -1, w := 0.62, h := 1.24) -> void:
	if idx < 0:
		idx = rng.randi() % 32
	posters.append([x, y, z, face, idx, w, h, rng.randf_range(-0.06, 0.06)])

func _along(axis: String, fixed: float, face: String, a0: float, a1: float, y: float, step: float, skip := []) -> void:
	var a := a0
	while a <= a1:
		var ok := true
		for s in skip:
			if a > s[0] - 0.5 and a < s[1] + 0.5:
				ok = false
		if ok and rng.randf() >= 0.18:
			var yy := y + rng.randf_range(-0.15, 0.15)
			var sc := rng.randf_range(0.8, 1.15)
			if axis == "x":
				_poster(a, yy, fixed, face, -1, 0.62 * sc, 1.24 * sc)
			else:
				_poster(fixed, yy, a, face, -1, 0.62 * sc, 1.24 * sc)
		a += step * rng.randf_range(0.8, 1.25)

func _place_posters() -> void:
	# hallways (above the lockers), cafeteria, vestibule, classrooms, stairwell, kitchen
	_along("x", -9.23, "+z", -30, -15.5, 2.9, 1.7); _along("x", -5.27, "-z", -23, -15.5, 2.9, 1.7); _along("x", -5.27, "-z", -30.5, -24.5, 2.9, 1.7)
	_along("x", -9.23, "+z", 15, 35, 2.9, 1.6, [[25, 27.5]]); _along("x", -5.27, "-z", 15, 35, 2.9, 1.6, [[25, 27.5]])
	_along("z", -13.73, "+x", -4.6, 2.5, 2.3, 1.4); _along("z", 13.73, "-x", -4.5, 14, 2.3, 1.5, [[-8.75, -5.75]])
	_along("x", 14.73, "-z", 2.8, 13.2, 2.3, 1.5); _along("x", -15.73, "+z", 6.6, 9, 2.3, 1.2); _along("x", -15.73, "+z", -1.4, 2.4, 2.3, 1.2)
	_along("z", -3.23, "+x", 15.8, 22, 2.1, 1.4); _along("z", 3.23, "-x", 15.8, 22, 2.1, 1.4)
	_along("x", -4.73, "+z", 21, 33, 2.4, 1.3, [[25, 27.5]]); _along("z", 20.27, "+x", 3.8, 7, 2.3, 1.3); _along("x", 7.73, "-z", 21, 33, 2.4, 1.3, [[26, 29]])
	_along("x", -26.73, "+z", 21, 39, 2.2, 1.0, [[26, 28], [30.6, 32.6], [37.6, 39.6]]); _along("z", 20.27, "+x", -26, -10.5, 2.9, 1.1); _along("z", 39.73, "-x", -24, -10.5, 2.4, 1.1, [[-19, -16]])
	_along("z", 11.73, "-x", -27, -17, 1.9, 1.6); _along("z", 0.27, "+x", -27, -24.5, 5.8, 1.4)
	_poster(-4.27, 2.2, 6.5, "-x", 15, 0.9, 1.6); _poster(-4.27, 2.2, 12, "-x", 10); _poster(-9.23, 2.0, 11.95, "+x", 12, 0.42, 0.84)
	_poster(20.27, 2.0, 1.5, "+x", 24, 1.4, 1.8); _poster(20.27, 2.1, -2.2, "+x", 25, 1.2, 1.5)
	# gym and upstairs
	_along("x", -31.73, "+z", -34.5, 20.5, 6.2, 1.9, [[-33.5, -31.5], [-20, -18], [-13, -11], [-4, -2], [3, 5], [15.5, 17.5]]); _along("x", -28.27, "-z", -30.5, 21, 6.6, 2.2, [[6, 9]])
	_along("z", -35.73, "+x", -43, -33, 6, 1.6); _along("z", -0.27, "-x", -43, -33, 6, 1.4, [[-36, -34]]); _poster(-15.73, 6.1, -38, "+x", 3, 0.9, 1.6)
	# a few more flyers in the cafeteria
	_poster(-13.7, 1.9, 5.5, "+x", 15, 0.8, 1.4); _poster(-13.7, 1.8, 1.0, "+x", 5); _poster(13.7, 1.9, 1.0, "-x", 0)

func _face_vecs(face: String) -> Array:
	match face:
		"+x":
			return [Vector3(1, 0, 0), Vector3(0, 0, -1)]
		"-x":
			return [Vector3(-1, 0, 0), Vector3(0, 0, 1)]
		"+z":
			return [Vector3(0, 0, 1), Vector3(1, 0, 0)]
	return [Vector3(0, 0, -1), Vector3(-1, 0, 0)]

func _build_quads(list: Array, tex_path: String, cols: int, rows: int) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q in list:
		var idx: int = q[4]
		var c := idx % cols
		var r := idx / cols
		var u0 := float(c) / cols
		var u1 := float(c + 1) / cols
		var v0 := float(r) / rows
		var v1 := float(r + 1) / rows
		var fv := _face_vecs(q[3])
		var n: Vector3 = fv[0]
		var right: Vector3 = fv[1]
		var tilt: float = q[7]
		var ct := cos(tilt)
		var stl := sin(tilt)
		var w: float = q[5]
		var h: float = q[6]
		var pos := Vector3(q[0], q[1], q[2]) + n * 0.02
		var corner := func(sx: float, sy: float) -> Vector3:
			var dx := sx * w / 2.0
			var dy := sy * h / 2.0
			return pos + right * (dx * ct - dy * stl) + Vector3(0, dx * stl + dy * ct, 0)
		var A: Vector3 = corner.call(-1, -1)
		var B: Vector3 = corner.call(1, -1)
		var C: Vector3 = corner.call(1, 1)
		var D: Vector3 = corner.call(-1, 1)
		for pt in [[A, Vector2(u0, v1)], [C, Vector2(u1, v0)], [B, Vector2(u1, v1)], [A, Vector2(u0, v1)], [D, Vector2(u0, v0)], [C, Vector2(u1, v0)]]:
			st.set_normal(n)
			st.set_uv(pt[1])
			st.add_vertex(pt[0])
	var m := MeshInstance3D.new()
	m.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(tex_path)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.roughness = 0.9
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)

func _flat(tex_path: String, size: Vector2, pos: Vector3, rot: Vector3, alpha := false) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	m.mesh = q
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(tex_path)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	if alpha:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.6
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	m.position = pos
	m.rotation = rot
	return m

# ---------------------------------------------------------------- the gym's pep rally
func _court() -> void:
	_flat("res://assets/textures/court.png", Vector2(26, 16), Vector3(-46, 0.02, -3), Vector3(-PI / 2, 0, 0), true)

func _pennants() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var red := Color(0.62, 0.1, 0.12)
	var white := Color(0.92, 0.88, 0.8)
	var gold := Color(0.85, 0.7, 0.25)
	var tri := func(a: Vector3, b: Vector3, c: Vector3, cl: Color) -> void:
		for p in [a, b, c]:
			st.set_color(cl)
			st.set_normal(Vector3(0, 0, 1))
			st.add_vertex(p)
	for z in [-17.0, -11.0, -5.0, 1.0]:
		var n := 20
		var x0 := -59.5
		var x1 := -32.5
		for i in n:
			var k0 := float(i) / n
			var k1 := (i + 0.8) / n
			var xa := x0 + (x1 - x0) * k0
			var xb := x0 + (x1 - x0) * k1
			var ya := 7.6 - sin(k0 * PI) * 1.1
			var yb := 7.6 - sin(k1 * PI) * 1.1
			tri.call(Vector3(xa, ya, z), Vector3(xb, yb, z), Vector3((xa + xb) / 2, (ya + yb) / 2 - 0.45, z), red if i % 2 else white)
			if i % 3 == 1:
				var sx := (xa + xb) / 2
				var sy := (ya + yb) / 2
				var ln := rng.randf_range(0.8, 1.8)
				var cl := gold if i % 2 else red
				var j := rng.randf_range(-0.1, 0.1)
				tri.call(Vector3(sx - 0.05, sy, z + 0.02), Vector3(sx + 0.05, sy, z + 0.02), Vector3(sx + 0.05 + j, sy - ln, z + 0.02), cl)
				tri.call(Vector3(sx - 0.05, sy, z + 0.02), Vector3(sx + 0.05 + j, sy - ln, z + 0.02), Vector3(sx - 0.05, sy - ln, z + 0.02), cl)
	var m := MeshInstance3D.new()
	m.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.material_override = mat
	add_child(m)

func _balloons() -> void:
	var spots: Array = []
	for c in [[-56.5, -16.5, 7], [-35.5, -16.5, 7], [-48.5, 4.6, 5], [-43.5, 4.6, 5], [-33.2, -10.4, 4], [-33.2, -3.8, 4]]:
		for i in c[2]:
			spots.append([c[0] + rng.randf_range(-0.6, 0.6), rng.randf_range(1.4, 2.6), c[1] + rng.randf_range(-0.4, 0.4), true])
	for i in 12:
		spots.append([rng.randf_range(-58, -34), 0.07, rng.randf_range(-15, 4), false])
	var sm := SphereMesh.new()
	sm.radius = 0.24
	sm.height = 0.48
	sm.radial_segments = 8
	sm.rings = 6
	var cols := [Color8(176, 28, 34), Color8(236, 228, 208), Color8(200, 160, 48)]
	var mats := {}
	for c in cols:
		var mt := StandardMaterial3D.new()
		mt.albedo_color = c
		mt.roughness = 0.25
		mt.metallic_specular = 0.8
		mats[c] = mt
	var string_mat := StandardMaterial3D.new()
	string_mat.albedo_color = Color(0.85, 0.85, 0.8)
	for s in spots:
		var col: Color = cols[rng.randi() % 3]
		var m := MeshInstance3D.new()
		m.mesh = sm
		m.material_override = mats[col]
		add_child(m)
		var base := Vector3(s[0], s[1], s[2])
		m.position = base
		if not s[3]:
			m.scale = Vector3(1, 0.25 * 1.15, 1)        # popped, flat on the floor
			continue
		m.scale = Vector3(1, 1.15, 1)
		var str := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.01, base.y - 0.25, 0.01)
		str.mesh = bm
		str.material_override = string_mat
		str.position = Vector3(0, -0.25 - (base.y - 0.25) / 2.0, 0)
		str.scale = Vector3(1, 1 / 1.15, 1)
		m.add_child(str)
		var body := StaticBody3D.new()
		body.collision_layer = BALLOON_LAYER
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = 0.26
		cs.shape = sp
		body.add_child(cs)
		body.scale = Vector3(1, 1 / 1.15, 1)      # Jolt wants uniformly scaled bodies
		m.add_child(body)
		var b := {"mesh": m, "base": base, "ph": rng.randf() * TAU, "col": col, "dead": false}
		body.set_meta("balloon", b)
		balloons.append(b)

## shot balloons pop in a puff of confetti
func pop(b: Dictionary) -> void:
	if b.dead:
		return
	b.dead = true
	var p: Vector3 = b.mesh.global_position
	b.mesh.queue_free()
	for c in [b.col, Color8(200, 30, 36), Color8(236, 228, 208), Color8(216, 176, 48), Color8(42, 74, 154)]:
		game.fx.spray(p, Vector3.UP, c, 5, 3.5, 0.5, false, 0.0, 2.5, 1.6)
	game.audio.play("paintPop", p, -2, 1.4)
	game.add_points(5)

func _confetti() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = mat
	mm.mesh = q
	mm.instance_count = 900
	var cols := [Color8(200, 30, 36), Color8(236, 228, 208), Color8(216, 176, 48), Color8(42, 74, 154)]
	for i in 900:
		var b := Basis(Vector3.RIGHT, -PI / 2).rotated(Vector3.UP, rng.randf() * TAU)
		mm.set_instance_transform(i, Transform3D(b, Vector3(rng.randf_range(-59, -33), 0.025, rng.randf_range(-16, 5.5))))
		mm.set_instance_color(i, cols[rng.randi() % 4])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _welcome() -> void:
	_flat("res://assets/textures/welcome.png", Vector2(6, 0.75), Vector3(0, 3.9, 15.25), Vector3(0, PI, 0))

# ---------------------------------------------------------------- new clutter
func _box(size: Vector3, col: Color, pos: Vector3, ry := 0.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	var mt := StandardMaterial3D.new()
	mt.albedo_color = col
	mt.roughness = 0.8
	m.material_override = mt
	add_child(m)
	m.position = pos
	m.rotation.y = ry
	return m

func _cafeteria() -> void:
	# lunch trays, milk cartons and the odd apple on the standing tables
	for t in [[0, -2], [9, -2], [0, 4], [3, 10], [9, 10]]:
		for k in rng.randi_range(2, 4):
			var x: float = t[0] + rng.randf_range(-1.6, 1.6)
			var z: float = t[1] + rng.randf_range(-0.3, 0.3)
			var ry := rng.randf_range(-0.4, 0.4)
			_box(Vector3(0.42, 0.025, 0.3), [Color8(154, 140, 110), Color8(110, 130, 150), Color8(170, 110, 90)][rng.randi() % 3], Vector3(x, 0.775, z), ry)
			if rng.randf() < 0.7:
				var c := _box(Vector3(0.07, 0.11, 0.07), Color8(236, 232, 220), Vector3(x + rng.randf_range(-0.12, 0.12), 0.85, z + rng.randf_range(-0.08, 0.08)), rng.randf() * 3)
				_box(Vector3(0.072, 0.03, 0.072), Color8(40, 80, 160), Vector3(0, 0.03, 0), 0).reparent(c, false)
			if rng.randf() < 0.4:
				_box(Vector3(0.16, 0.02, 0.12), Color8(200, 150, 60), Vector3(x + 0.05, 0.8, z), ry)   # a slice of pizza
	# a knocked-over carton and a puddle of milk on the floor
	_box(Vector3(0.11, 0.07, 0.07), Color8(236, 232, 220), Vector3(4.5, 0.04, 1.2), 0.6)
	var puddle := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.55
	cm.bottom_radius = 0.55
	cm.height = 0.005
	puddle.mesh = cm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.93, 0.92, 0.88, 0.85)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.roughness = 0.1
	puddle.material_override = pm
	puddle.position = Vector3(4.9, 0.015, 1.4)
	puddle.scale = Vector3(1.3, 1, 0.8)
	add_child(puddle)
	# the menu board by the lunch line
	_flat("res://assets/textures/menu.png", Vector2(1.6, 1.2), Vector3(-13.7, 2.5, -2.5), Vector3(0, PI / 2, 0))

func _papers() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	# loose worksheets kicked all over the halls, classrooms and cafeteria
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(0.24, 0.3)
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode cull_disabled;
uniform sampler2D tex : filter_nearest, source_color;
varying float v;
void vertex(){ v = INSTANCE_CUSTOM.r; }
void fragment(){ vec4 c = texture(tex, vec2((UV.x + floor(v * 4.0)) / 4.0, UV.y)); if (c.a < 0.5) discard; ALBEDO = c.rgb; ROUGHNESS = 0.9; }"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tex", load("res://assets/textures/paper.png"))
	q.material = mat
	mm.mesh = q
	var areas := [[-12, 12, -6, 13, 60], [-30, -15.5, -9, -5.5, 30], [15, 35, -9, -5.5, 30], [21, 33, -4, 5, 30], [-58, -34, -15, 4, 30]]
	var count := 0
	for a in areas:
		count += a[4]
	mm.instance_count = count
	var space := get_world_3d().direct_space_state
	var i := 0
	for a in areas:
		for k in a[4]:
			var p := Vector3(rng.randf_range(a[0], a[1]), 0.0, rng.randf_range(a[2], a[3]))
			var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.2, 0), p - Vector3(0, 0.5, 0), 1))
			if r.is_empty() or r.normal.y < 0.9 or r.position.y > 0.3:
				mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), p))
				i += 1
				continue
			p.y = r.position.y + 0.02 + rng.randf() * 0.004
			var b := Basis(Vector3.RIGHT, -PI / 2 + rng.randf_range(-0.08, 0.08)).rotated(Vector3.UP, rng.randf() * TAU)
			mm.set_instance_transform(i, Transform3D(b, p))
			mm.set_instance_custom_data(i, Color(rng.randf(), 0, 0, 0))
			i += 1
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _process(dt: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for b in balloons:
		if not b.dead:
			b.mesh.position = b.base + Vector3(sin(t * 0.7 + b.ph) * 0.04, sin(t * 1.1 + b.ph) * 0.06, cos(t * 0.6 + b.ph) * 0.04)
