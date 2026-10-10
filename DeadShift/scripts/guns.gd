extends RefCounted
## Gun models: the exported web guns (with or without the viewmodel hand + sleeve), the new Staple Cannon
## (built here), and the Pack-a-Punch skin.

static var _up_mat: StandardMaterial3D
static var _mats := {}

static func _m(c: Color, metal := 0.0, rough := 0.7) -> StandardMaterial3D:
	var k := c.to_html() + str(metal)
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.metallic = metal
		m.roughness = rough
		_mats[k] = m
	return _mats[k]

static func _box(p: Node3D, size: Vector3, mat: Material, pos: Vector3, rx := 0.0, hand := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation.x = rx
	if hand:
		mi.set_meta("hand", true)
	p.add_child(mi)
	return mi

## a modified office stapler with a drum magazine and a strip of duct tape
static func _staple(arms: bool) -> Node3D:
	var g := Node3D.new()
	var black := _m(Color8(30, 30, 34), 0.3, 0.5)
	var chrome := _m(Color8(170, 172, 178), 0.8, 0.3)
	var red := _m(Color8(150, 30, 30), 0.2, 0.6)
	var tape := _m(Color8(150, 150, 140), 0.0, 0.9)
	_box(g, Vector3(0.07, 0.05, 0.42), black, Vector3(0, 0, -0.2))           # base
	_box(g, Vector3(0.075, 0.045, 0.4), red, Vector3(0, 0.05, -0.2), -0.05)  # top arm
	_box(g, Vector3(0.05, 0.02, 0.1), chrome, Vector3(0, 0.03, -0.42))       # jaw
	_box(g, Vector3(0.06, 0.1, 0.06), black, Vector3(0, -0.08, -0.02), 0.25) # grip
	_box(g, Vector3(0.09, 0.09, 0.09), chrome, Vector3(0, -0.02, -0.15))      # drum mag
	_box(g, Vector3(0.08, 0.03, 0.1), tape, Vector3(0, 0.0, -0.1))
	_box(g, Vector3(0.02, 0.02, 0.18), chrome, Vector3(0, 0.08, -0.08))       # spring rail
	if arms:
		_box(g, Vector3(0.12, 0.1, 0.14), _m(Color8(138, 106, 82)), Vector3(0, -0.1, 0.04), 0.0, true)
		_box(g, Vector3(0.16, 0.16, 0.5), _m(Color8(52, 59, 42)), Vector3(0.04, -0.24, 0.38), 0.35, true)
	return g

static func _arms(g: Node3D) -> void:
	_box(g, Vector3(0.12, 0.1, 0.14), _m(Color8(138, 106, 82)), Vector3(0, -0.1, 0.04), 0.0, true)
	_box(g, Vector3(0.16, 0.16, 0.5), _m(Color8(52, 59, 42)), Vector3(0.04, -0.24, 0.38), 0.35, true)

static func _cyl(p: Node3D, r0: float, r1: float, h: float, mat: Material, pos: Vector3, rot := Vector3.ZERO, seg := 10) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r0
	c.bottom_radius = r1
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	p.add_child(mi)
	return mi

## Textbook Launcher: a leaf blower tube with a hopper of hardcovers
static func _book(arms: bool) -> Node3D:
	var g := Node3D.new()
	var orange := _m(Color8(220, 110, 30), 0.1, 0.6)
	var black := _m(Color8(30, 30, 34), 0.2, 0.6)
	_cyl(g, 0.085, 0.07, 0.55, orange, Vector3(0, 0.02, -0.28), Vector3(PI / 2, 0, 0))
	_cyl(g, 0.095, 0.095, 0.05, black, Vector3(0, 0.02, -0.56), Vector3(PI / 2, 0, 0))
	_box(g, Vector3(0.06, 0.12, 0.07), black, Vector3(0, -0.08, -0.02), 0.25)
	_box(g, Vector3(0.12, 0.14, 0.18), black, Vector3(0, 0.0, 0.05))
	# a hopper with a stack of books on top
	for i in 3:
		var col: Color = [Color8(150, 30, 30), Color8(30, 70, 150), Color8(40, 110, 50)][i]
		_box(g, Vector3(0.16, 0.035, 0.2), _m(col), Vector3(0, 0.11 + i * 0.037, -0.16), 0.0)
		_box(g, Vector3(0.15, 0.03, 0.005), _m(Color8(235, 230, 215)), Vector3(0, 0.11 + i * 0.037, -0.059))
	if arms:
		_arms(g)
	return g

## Dodgeball Cannon: a ball pitching machine bolted to a T-shirt cannon
static func _dodge(arms: bool) -> Node3D:
	var g := Node3D.new()
	var red := _m(Color8(190, 40, 40), 0.0, 0.5)
	var grey := _m(Color8(150, 150, 156), 0.6, 0.4)
	var black := _m(Color8(30, 30, 34), 0.2, 0.6)
	_cyl(g, 0.075, 0.075, 0.6, grey, Vector3(0, 0.03, -0.3), Vector3(PI / 2, 0, 0))
	_cyl(g, 0.085, 0.085, 0.04, red, Vector3(0, 0.03, -0.6), Vector3(PI / 2, 0, 0))
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.11
	sm.height = 0.22
	sm.radial_segments = 10
	sm.rings = 6
	ball.mesh = sm
	ball.material_override = red
	ball.position = Vector3(0, 0.15, -0.12)
	g.add_child(ball)
	_box(g, Vector3(0.06, 0.12, 0.07), black, Vector3(0, -0.08, -0.02), 0.25)
	_box(g, Vector3(0.1, 0.08, 0.16), black, Vector3(0, -0.02, 0.06))
	_box(g, Vector3(0.02, 0.05, 0.3), _m(Color8(230, 200, 40)), Vector3(0.08, 0.03, -0.3))
	if arms:
		_arms(g)
	return g

## Trombone: bell forward, slide underneath
static func _bone(arms: bool) -> Node3D:
	var g := Node3D.new()
	var brass := _m(Color8(236, 196, 80), 0.35, 0.35)
	_cyl(g, 0.012, 0.012, 0.6, brass, Vector3(0, 0.05, -0.2), Vector3(PI / 2, 0, 0), 6)
	_cyl(g, 0.012, 0.012, 0.7, brass, Vector3(0, -0.05, -0.3), Vector3(PI / 2, 0, 0), 6)
	_cyl(g, 0.012, 0.012, 0.7, brass, Vector3(0, -0.11, -0.3), Vector3(PI / 2, 0, 0), 6)
	_box(g, Vector3(0.025, 0.08, 0.025), brass, Vector3(0, -0.08, -0.65))
	_cyl(g, 0.11, 0.02, 0.22, brass, Vector3(0, 0.05, -0.6), Vector3(PI / 2, 0, 0), 12)
	_cyl(g, 0.02, 0.02, 0.18, brass, Vector3(0, 0.0, 0.12), Vector3(0, 0, 0), 6)
	_box(g, Vector3(0.03, 0.12, 0.03), brass, Vector3(0, 0.0, 0.18))
	if arms:
		_arms(g)
	return g

## Detention Slip: a pad of pink slips and a red pen
static func _slip(arms: bool) -> Node3D:
	var g := Node3D.new()
	_box(g, Vector3(0.16, 0.04, 0.22), _m(Color8(240, 150, 190)), Vector3(0, 0.0, -0.14))
	_box(g, Vector3(0.16, 0.005, 0.22), _m(Color8(250, 230, 240)), Vector3(0, 0.023, -0.14))
	for i in 4:
		_box(g, Vector3(0.1 - i * 0.015, 0.003, 0.008), _m(Color8(60, 60, 140)), Vector3(-0.02, 0.027, -0.21 + i * 0.03))
	_box(g, Vector3(0.14, 0.02, 0.02), _m(Color8(150, 30, 30)), Vector3(0.0, 0.04, -0.06))
	_box(g, Vector3(0.012, 0.007, 0.05), _m(Color8(140, 140, 150), 0.6), Vector3(0.0, 0.03, -0.25))
	if arms:
		_arms(g)
	return g

## the Wildcats baseball bat: ash wood, black grip tape, a dented barrel. Built along +Y from the knob,
## so the viewmodel can swing it around the grip. Its wood material is kept on the root (it gets bloody).
static func _bat(arms: bool) -> Node3D:
	var g := Node3D.new()
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color8(214, 178, 124)
	wood.roughness = 0.55
	g.set_meta("bat_mat", wood)
	var tape := _m(Color8(24, 24, 26), 0.0, 0.9)
	_cyl(g, 0.032, 0.032, 0.025, tape, Vector3(0, 0.0, 0))              # knob
	_cyl(g, 0.019, 0.019, 0.26, tape, Vector3(0, 0.14, 0))              # taped handle
	_cyl(g, 0.03, 0.02, 0.26, wood, Vector3(0, 0.39, 0))                # taper
	_cyl(g, 0.045, 0.031, 0.22, wood, Vector3(0, 0.63, 0))
	_cyl(g, 0.047, 0.045, 0.2, wood, Vector3(0, 0.84, 0))               # barrel
	_cyl(g, 0.04, 0.047, 0.03, wood, Vector3(0, 0.955, 0))              # end cap
	var stripe := _cyl(g, 0.046, 0.046, 0.025, _m(Color8(150, 24, 30)), Vector3(0, 0.55, 0))
	stripe.scale = Vector3(1.01, 1, 1.01)
	if arms:
		var skin := _m(Color8(138, 106, 82))
		_box(g, Vector3(0.085, 0.09, 0.09), skin, Vector3(0, 0.07, 0.0), 0.0, true)
		_box(g, Vector3(0.085, 0.09, 0.09), skin, Vector3(0, 0.18, 0.0), 0.0, true)
	return g

## Volcano Launcher: a garden pump sprayer with a papier-mache science-fair volcano taped on top
static func _volc(arms: bool) -> Node3D:
	var g := Node3D.new()
	var tank := _m(Color8(232, 232, 226), 0.1, 0.5)
	var blue := _m(Color8(40, 90, 190), 0.2, 0.5)
	var black := _m(Color8(30, 30, 34), 0.2, 0.6)
	var rock := _m(Color8(120, 92, 60), 0.0, 0.95)
	var lava := StandardMaterial3D.new()
	lava.albedo_color = Color8(255, 110, 30)
	lava.emission_enabled = true
	lava.emission = Color8(255, 90, 20)
	lava.emission_energy_multiplier = 1.4
	_cyl(g, 0.07, 0.07, 0.3, tank, Vector3(0, -0.02, -0.12), Vector3(PI / 2, 0, 0))       # pump tank
	_cyl(g, 0.072, 0.072, 0.03, blue, Vector3(0, -0.02, -0.27), Vector3(PI / 2, 0, 0))
	_cyl(g, 0.016, 0.012, 0.3, black, Vector3(0, 0.0, -0.42), Vector3(PI / 2, 0, 0))     # nozzle wand
	_cyl(g, 0.03, 0.02, 0.05, blue, Vector3(0, 0.0, -0.58), Vector3(PI / 2, 0, 0))
	_box(g, Vector3(0.05, 0.12, 0.06), black, Vector3(0, -0.11, -0.02), 0.25)                 # grip
	_cyl(g, 0.02, 0.11, 0.17, rock, Vector3(0, 0.12, -0.13))                                   # the volcano
	_cyl(g, 0.025, 0.025, 0.02, lava, Vector3(0, 0.205, -0.13))
	var drip := _cyl(g, 0.012, 0.02, 0.09, lava, Vector3(0.03, 0.16, -0.12))
	drip.rotation.z = 0.5
	_box(g, Vector3(0.15, 0.025, 0.06), _m(Color8(160, 160, 150), 0.0, 0.9), Vector3(0, 0.06, -0.13))   # duct tape
	if arms:
		_arms(g)
	return g

## arms: keep the viewmodel hand + sleeve (they're the last two pieces of every exported gun)
static func make(id: String, arms: bool, world = null) -> Node3D:
	match id:
		"staple":
			return _staple(arms)
		"book":
			return _book(arms)
		"dodge":
			return _dodge(arms)
		"bone":
			return _bone(arms)
		"slip":
			return _slip(arms)
		"bat":
			return _bat(arms)
		"volc":
			return _volc(arms)
	var g: Node3D = load("res://assets/models/guns/%s.glb" % id).instantiate()
	if world:
		world._crisp(g)
	var ms := g.find_children("*", "MeshInstance3D", true, false)
	ms.sort_custom(func(a, b): return int(String(a.name).get_slice("_", 1)) < int(String(b.name).get_slice("_", 1)))
	for j in range(maxi(0, ms.size() - 2), ms.size()):
		ms[j].set_meta("hand", true)
		if not arms:
			ms[j].visible = false
	return g

## Pack-a-Punch: violet circuitry over everything but the hands
static func upgrade_skin(g: Node3D) -> void:
	if _up_mat == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color8(26, 16, 40))
		var rng := RandomNumberGenerator.new()
		rng.seed = 9
		for i in 9:
			var x := rng.randi_range(0, 31)
			var y := rng.randi_range(0, 31)
			for k in 4:
				var horiz := rng.randf() < 0.5
				var n := rng.randi_range(3, 8)
				for s in n:
					img.set_pixel(clampi(x, 0, 31), clampi(y, 0, 31), Color8(138, 80, 255))
					if horiz:
						x += 1
					else:
						y += 1
		for i in 10:
			img.set_pixel(rng.randi_range(0, 31), rng.randi_range(0, 31), Color8(64, 224, 255))
		var tex := ImageTexture.create_from_image(img)
		_up_mat = StandardMaterial3D.new()
		_up_mat.albedo_texture = tex
		_up_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_up_mat.uv1_triplanar = true
		_up_mat.uv1_scale = Vector3(6, 6, 6)
		_up_mat.emission_enabled = true
		_up_mat.emission_texture = tex
		_up_mat.emission = Color(1, 1, 1)
		_up_mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		_up_mat.emission_energy_multiplier = 1.2
		_up_mat.metallic = 0.6
		_up_mat.roughness = 0.35
	for m in g.find_children("*", "MeshInstance3D", true, false):
		if not m.has_meta("hand"):
			m.material_override = _up_mat
