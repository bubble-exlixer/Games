extends Node3D
## Builds Westfield High: the real textured map, collision, navigation, lights, fog, rain and light shafts.

signal nav_ready

const WORLD_LAYER := 1
const ROOF_LAYER := 8
var data: Dictionary
var nav: NavigationRegion3D
var doors := {}            # id -> {"node": Node3D, "barriers": [StaticBody3D], "open": bool, "def": Dictionary}
var env: Environment
var fog_target := Vector2(6, 34)
var rain: GPUParticles3D
var fires: Array = []
var lamps: Array = []
var baking := false
var bake_again := false
var nav_baked_once := false
var powered := false        # the school's power: off until someone flips the breaker upstairs
var lamps_sorted := false

func _ready() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/map.json"))
	nav = NavigationRegion3D.new()
	nav.name = "Nav"
	add_child(nav)
	_build_environment()
	_build_map()
	_build_collision()
	_build_lights()
	_build_shafts()
	_build_fires()
	_build_rain()
	_setup_nav()

# ---------------------------------------------------------------- look
func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color8(11, 13, 18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color8(122, 134, 160)
	env.ambient_light_energy = 0.62
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color8(11, 13, 18)
	env.fog_depth_begin = 6.0
	env.fog_depth_end = 34.0
	env.fog_density = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _crisp(n: Node) -> void:
	# PS2 look: nearest-neighbour textures, vertex-ish lambert shading
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		for i in mi.mesh.get_surface_count():
			var mat = mi.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
				mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
				mat.roughness = 1.0
				mat.metallic = 0.0
	for c in n.get_children():
		_crisp(c)

func _build_map() -> void:
	var scene: PackedScene = load("res://assets/models/map.glb")
	var map: Node3D = scene.instantiate()
	map.name = "Map"
	add_child(map)
	_crisp(map)
	# group door meshes so a door can drop them when bought
	var by_name := {}
	for n in map.find_children("door_*", "", true, false):
		by_name[String(n.name)] = n
	var droot := Node3D.new()
	droot.name = "Doors"
	add_child(droot)
	for d in data.doors:
		var g := Node3D.new()
		g.name = d.id
		droot.add_child(g)
		for nm in d.nodes:
			if by_name.has(nm):
				var mesh: Node3D = by_name[nm]
				var xf := mesh.global_transform
				mesh.owner = null
				mesh.get_parent().remove_child(mesh)
				g.add_child(mesh)
				mesh.global_transform = xf
		var bars := []
		for b in d.barriers:
			bars.append(_box_body(Vector3(b.pos[0], b.pos[1], b.pos[2]), Vector3(b.size[0], b.size[1], b.size[2]), Basis(), nav))
		doors[d.id] = {"node": g, "barriers": bars, "open": false, "def": d}

# ---------------------------------------------------------------- collision
func _box_body(pos: Vector3, size: Vector3, basis: Basis, parent: Node, layer: int = WORLD_LAYER) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = layer
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(max(size.x, 0.02), max(size.y, 0.02), max(size.z, 0.02))
	cs.shape = sh
	b.add_child(cs)
	parent.add_child(b)
	b.global_transform = Transform3D(basis, pos)
	return b

func _build_collision() -> void:
	for c in data.collision:
		_box_body(Vector3(c.pos[0], c.pos[1], c.pos[2]), Vector3(c.size[0], c.size[1], c.size[2]), Basis(), nav)
	for f in data.floors:
		var r: Array = f.rot
		var basis := Basis(Vector3(r[0], r[3], r[6]), Vector3(r[1], r[4], r[7]), Vector3(r[2], r[5], r[8]))
		_box_body(Vector3(f.pos[0], f.pos[1], f.pos[2]), Vector3(f.size[0], f.size[1], f.size[2]), basis, nav)
	# ceilings: only used to tell indoors from outdoors (rain, fog); nothing collides with them
	for f in data.ceilings:
		var r: Array = f.rot
		var basis := Basis(Vector3(r[0], r[3], r[6]), Vector3(r[1], r[4], r[7]), Vector3(r[2], r[5], r[8]))
		_box_body(Vector3(f.pos[0], f.pos[1], f.pos[2]), Vector3(f.size[0], f.size[1], f.size[2]), basis, self, ROOF_LAYER)
	# safety ground under the whole school
	_box_body(Vector3(-7, -0.6, -1), Vector3(130, 1, 100), Basis(), nav)
	# smooth ramps over both staircases (the steps stay too)
	for rp in data.ramps:
		var zb: float = rp.z_bottom
		var zt: float = rp.z_top
		var h: float = rp.rise
		var run := zt - zb
		var L := sqrt(run * run + h * h)
		var fwd := Vector3(0, h / L, run / L)
		var up := Vector3(0, abs(run) / L, -signf(run) * h / L)
		var back := -fwd
		var right := up.cross(back)
		var ext := 0.3
		var mid := Vector3((rp.x0 + rp.x1) / 2.0, h / 2.0, (zb + zt) / 2.0) - fwd * ext / 2.0 - up * 0.15
		_box_body(mid, Vector3(abs(rp.x1 - rp.x0), 0.3, L + ext), Basis(right, up, back), nav)

# ---------------------------------------------------------------- lights, shafts, fire, rain
func _build_lights() -> void:
	for l in data.lights:
		var o := OmniLight3D.new()
		o.light_color = Color8(int(l.color[0]), int(l.color[1]), int(l.color[2]))
		o.light_energy = clampf(l.energy * 2.4 + 0.5, 0.5, 4.0)
		o.omni_range = clampf(l.range * 1.25, 4.0, 20.0)
		o.omni_attenuation = 1.2
		o.shadow_enabled = false
		add_child(o)
		o.global_position = Vector3(l.pos[0], l.pos[1], l.pos[2])
		lamps.append({"light": o, "base": o.light_energy, "t": randf() * 10.0, "flicker": randf() < 0.18, "on": false, "dead": randf() < 0.3,
			"street_c": l.pos[1] > 5.5 and l.color[0] > 240 and l.color[2] < 120, "street": false, "boost": 1.0, "range": o.omni_range})

func _build_shafts() -> void:
	for s in data.shafts:
		var a := Vector3(s.a[0], s.a[1], s.a[2])
		var b := Vector3(s.b[0], s.b[1], s.b[2])
		var h := a.distance_to(b)
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.08
		cyl.bottom_radius = s.r
		cyl.height = h
		cyl.cap_top = false
		cyl.cap_bottom = false
		cyl.radial_segments = 14
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.no_depth_test = false
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		var col := Color8(int(s.color[0]), int(s.color[1]), int(s.color[2]))
		col.a = s.op * 1.1
		mat.albedo_color = col
		var gt := GradientTexture2D.new()
		var gr := Gradient.new()
		gr.set_color(0, Color(1, 1, 1, 1))
		gr.set_color(1, Color(1, 1, 1, 0))
		gt.gradient = gr
		gt.fill_from = Vector2(0, 0)
		gt.fill_to = Vector2(0, 1)
		gt.width = 4
		gt.height = 64
		mat.albedo_texture = gt
		mat.disable_fog = false
		cyl.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var dir := (b - a).normalized()
		var basis := Basis()
		var y := -dir
		var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		var z := x.cross(y).normalized()
		basis = Basis(x, y, z)
		mi.global_transform = Transform3D(basis, (a + b) / 2.0)

func _build_fires() -> void:
	for f in data.fires:
		var p := Vector3(f[0], f[1], f[2])
		var light := OmniLight3D.new()
		light.light_color = Color8(255, 140, 50)
		light.light_energy = 2.0
		light.omni_range = 8.0
		add_child(light)
		light.global_position = p + Vector3(0, 0.6, 0)
		var parts := GPUParticles3D.new()
		parts.amount = 40
		parts.lifetime = 0.9
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3.UP
		pm.spread = 18.0
		pm.initial_velocity_min = 1.0
		pm.initial_velocity_max = 2.4
		pm.gravity = Vector3(0, 0.6, 0)
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.35 * f[3]
		pm.scale_min = 0.6
		pm.scale_max = 1.2
		var grad := Gradient.new()
		grad.set_color(0, Color(1.0, 0.75, 0.3, 1))
		grad.set_color(1, Color(0.6, 0.1, 0.02, 0))
		var gt := GradientTexture1D.new()
		gt.gradient = grad
		pm.color_ramp = gt
		parts.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(0.35, 0.35)
		var qm := StandardMaterial3D.new()
		qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		qm.vertex_color_use_as_albedo = true
		qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		q.material = qm
		parts.draw_pass_1 = q
		add_child(parts)
		parts.global_position = p
		fires.append({"light": light, "t": randf() * 10.0})

func _build_rain() -> void:
	rain = GPUParticles3D.new()
	rain.amount = 2600          # downpour; the weather scales it with amount_ratio
	rain.lifetime = 0.8
	rain.visibility_aabb = AABB(Vector3(-20, -14, -20), Vector3(40, 28, 40))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(14, 0.5, 14)
	pm.direction = Vector3(0.05, -1, 0)
	pm.spread = 3.0
	pm.initial_velocity_min = 22.0
	pm.initial_velocity_max = 26.0
	pm.gravity = Vector3.ZERO
	rain.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.45)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.albedo_color = Color(0.7, 0.75, 0.85, 0.35)
	q.material = qm
	rain_mat = qm
	rain.draw_pass_1 = q
	add_child(rain)

# weather: 0.3 drizzle, 1.0 steady, 1.8 downpour (game.gd drifts it between states)
var rain_k := 1.0
var rain_mat: StandardMaterial3D
var under_roof := false

func update_look(dt: float, cam: Camera3D) -> void:
	# rain follows the camera; stops under a roof
	var p := cam.global_position
	rain.global_position = p + Vector3(0, 10, 0) - cam.global_transform.basis.z * 5.0
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p, p + Vector3(0, 25, 0), WORLD_LAYER | ROOF_LAYER)
	var roof := space.intersect_ray(q)
	rain.emitting = roof.is_empty()
	under_roof = not roof.is_empty()
	rain.amount_ratio = clampf(rain_k / 1.8, 0.08, 1.0)
	rain_mat.albedo_color.a = 0.22 + 0.12 * clampf(rain_k, 0.0, 1.8)
	var far := 30.0 - 4.5 * maxf(0.0, rain_k - 1.0)
	var want := Vector2(4 - maxf(0.0, rain_k - 1.0), far) if roof.is_empty() else Vector2(6, 30)
	fog_target = fog_target.lerp(want, minf(1.0, dt * 2.0))
	env.fog_depth_begin = fog_target.x
	env.fog_depth_end = fog_target.y
	for f in fires:
		f.t += dt
		f.light.light_energy = 1.8 + sin(f.t * 13.0) * 0.25 + sin(f.t * 31.0) * 0.2
	if not lamps_sorted and nav_baked_once:
		# street lamps and anything outdoors don't need the school's power
		lamps_sorted = true
		for l in lamps:
			var lp: Vector3 = l.light.global_position
			var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(lp + Vector3(0, 0.3, 0), lp + Vector3(0, 25, 0), WORLD_LAYER | ROOF_LAYER))
			if r.is_empty():
				l.on = true
				l.dead = false
				if l.street_c:
					l.street = true
					_street_glow(l)
	for l in lamps:
		l.t += dt
		if l.street:
			# parking lot street lamps: lit from the start, much brighter once the school has power
			l.light.light_energy = l.base * l.boost
			l.light.omni_range = l.range * (1.0 + (l.boost - 1.0) * 0.45)
			if l.has("glow"):
				l.glow.modulate = Color(1, 0.75, 0.45, clampf(0.35 + (l.boost - 1.0) * 0.5, 0.0, 1.0))
				l.glow.pixel_size = 0.012 * (1.0 + (l.boost - 1.0) * 0.6)
				l.pool.light_energy = maxf(0.0, l.boost - 1.0) * 4.0
				l.cone_mat.albedo_color.a = 0.025 + maxf(0.0, l.boost - 1.0) * 0.05
				l.patch_mat.albedo_color.a = 0.08 + maxf(0.0, l.boost - 1.0) * 0.32
		elif l.on:
			l.light.light_energy = l.base * ((0.25 if fmod(l.t * 7.3, 5.0) < 0.35 else 1.0) if l.flicker else 1.0)
		else:
			# no power: emergency glow, some dead, the rest stuttering
			var k := 0.0 if l.dead else 0.32
			if not l.dead and fmod(l.t * (3.1 + fmod(l.base * 7.0, 2.0)), 4.0) < 0.5:
				k *= 0.2 if randf() < 0.6 else 1.6
			l.light.light_energy = l.base * k

# ---------------------------------------------------------------- navigation
func _setup_nav() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = WORLD_LAYER
	nm.agent_radius = 0.4
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 50.0
	nm.cell_size = 0.2
	nm.cell_height = 0.1
	nm.region_min_size = 4.0
	nav.navigation_mesh = nm
	nav.bake_finished.connect(_on_baked)
	rebake()

func rebake() -> void:
	if baking:
		bake_again = true
		return
	baking = true
	nav.bake_navigation_mesh(true)

func _on_baked() -> void:
	baking = false
	nav_baked_once = true
	nav_ready.emit()
	if bake_again:
		bake_again = false
		rebake()

## a soft glow sprite on a street lamp's head, so you can see the lamp itself get brighter
var _glow_tex: Texture2D
func _street_glow(l: Dictionary) -> void:
	if _glow_tex == null:
		var gt := GradientTexture2D.new()
		var gr := Gradient.new()
		gr.set_color(0, Color(1, 1, 1, 1))
		gr.set_color(1, Color(1, 1, 1, 0))
		gt.gradient = gr
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 64
		gt.height = 64
		_glow_tex = gt
	var s := Sprite3D.new()
	s.texture = _glow_tex
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.transparent = true
	s.pixel_size = 0.004
	s.modulate = Color(1, 0.75, 0.45, 0.35)
	s.render_priority = 1
	add_child(s)
	s.global_position = l.light.global_position
	l["glow"] = s
	# a pool of light on the asphalt that only comes alive once the power's on
	var sp := SpotLight3D.new()
	sp.light_color = Color8(255, 176, 96)
	sp.spot_range = 12.0
	sp.spot_angle = 52.0
	sp.spot_attenuation = 0.6
	sp.light_energy = 0.0
	add_child(sp)
	sp.global_position = l.light.global_position - Vector3(0, 0.2, 0)
	sp.rotation = Vector3(-PI / 2, 0, 0)
	l["pool"] = sp
	# the light itself, drawn: a hazy cone in the rain and a bright patch on the asphalt (these show even
	# where the renderer has run out of lights for a big piece of ground)
	var top: Vector3 = l.light.global_position
	var r: Dictionary = get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(top, top - Vector3(0, 12, 0), WORLD_LAYER))
	var floor_y: float = r.position.y if not r.is_empty() else 0.0
	var h: float = top.y - floor_y - 0.25
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.25
	cm.bottom_radius = 3.4
	cm.height = h
	cm.radial_segments = 16
	cm.cap_top = false
	cm.cap_bottom = false
	cone.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cmat.albedo_color = Color(1.0, 0.62, 0.3, 0.0)
	cone.material_override = cmat
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cone)
	cone.global_position = Vector3(top.x, floor_y + 0.25 + h / 2.0, top.z)
	var patch := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(7.5, 7.5)
	patch.mesh = qm
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pmat.albedo_texture = _glow_tex
	pmat.albedo_color = Color(1.0, 0.65, 0.35, 0.0)
	patch.material_override = pmat
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(patch)
	patch.global_position = Vector3(top.x, floor_y + 0.04, top.z)
	patch.rotation = Vector3(-PI / 2, 0, 0)
	l["cone_mat"] = cmat
	l["patch_mat"] = pmat

## the street lamps surge brighter one after another, with a buzz and a stutter (sodium lamps warming up)
func street_surge(delay := 0.0) -> void:
	var st: Array = lamps.filter(func(l): return l.street)
	for i in st.size():
		var l = st[i]
		get_tree().create_timer(delay + i * 0.35, true, false, true).timeout.connect(func():
			if audio_cb.is_valid():
				audio_cb.call(l.light.global_position)
			var tw := create_tween()
			var setb := func(v: float): l.boost = v
			var prev := 1.0
			for k in [0.3, 1.6, 0.5, 2.1, 1.4, 2.4]:
				tw.tween_method(setb, prev, k, 0.07)
				prev = k
			tw.tween_method(setb, prev, 2.3, 0.4))

var audio_cb := Callable()

## lamps come back on one by one, nearest the breaker first (or all at once)
func power_on(from: Vector3, stagger := 0.0) -> void:
	powered = true
	street_surge(0.4 if stagger > 0 else 0.0)
	var order := lamps.duplicate()
	order.sort_custom(func(a, b): return a.light.global_position.distance_to(from) < b.light.global_position.distance_to(from))
	for i in order.size():
		var l = order[i]
		if stagger <= 0:
			l.on = true
			continue
		get_tree().create_timer(i * stagger, true, false, true).timeout.connect(func():
			l.on = true
			l.light.light_energy = l.base * 1.6)
	var tw := create_tween()
	tw.tween_property(env, "ambient_light_energy", 0.75, maxf(0.5, stagger * order.size() * 0.5))

func open_door(id: String) -> void:
	var d = doors.get(id)
	if d == null or d.open:
		return
	d.open = true
	for b in d.barriers:
		b.queue_free()
	var tw := create_tween().set_parallel(true)
	for m in d.node.get_children():
		if m is Node3D:
			tw.tween_property(m, "position", m.position + Vector3(randf_range(-0.4, 0.4), -2.0, randf_range(-0.4, 0.4)), 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tw.tween_property(m, "rotation", m.rotation + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.9, 0.9)), 0.8)
	tw.chain().tween_callback(d.node.queue_free)
	await get_tree().physics_frame
	rebake()
