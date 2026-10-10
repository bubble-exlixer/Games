extends Node3D
## The second floor rework: smashed doorways between the upstairs rooms (the exporter cut the holes),
## a broken hole in the gym balcony with a rubble ramp up from the bleachers, and the power breaker.

const SWITCH_POS := Vector3(21.7, 5.3, -38.0)
const SWITCH_SPOT := Vector3(20.6, 4.0, -38.0)

var game
var world
var concrete: StandardMaterial3D
var wood: StandardMaterial3D
var lever: Node3D
var lamp: OmniLight3D
var lamp_mat: StandardMaterial3D

func setup(g) -> void:
	game = g
	world = g.world
	concrete = _mat(Color8(120, 116, 106))
	wood = _mat(Color8(120, 80, 44))
	_doorway(-16.0, -35.0)
	_doorway(0.0, -38.5)
	_balcony_hole()
	_breaker()
	world.rebake()

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m

func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	parent.add_child(m)
	m.position = pos
	m.rotation = rot
	return m

## a doorway knocked through a wall along z: ragged jambs, a header, rubble both sides
func _doorway(x: float, zc: float) -> void:
	var g := Node3D.new()
	add_child(g)
	var z0 := zc - 1.1
	var z1 := zc + 1.1
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(x) * 100 + absf(zc))
	# reveal: cover the wall's thickness on the three sides of the hole, with broken lumps
	for z in [z0, z1]:
		_box(g, Vector3(0.52, 2.7, 0.08), concrete, Vector3(x, 5.05, z + (0.04 if z == z0 else -0.04)))
		for k in 4:
			_box(g, Vector3(0.56, rng.randf_range(0.2, 0.5), rng.randf_range(0.1, 0.25)), concrete, Vector3(x, rng.randf_range(4.2, 6.2), z + (0.08 if z == z0 else -0.08)), Vector3(0, 0, rng.randf_range(-0.3, 0.3)))
	_box(g, Vector3(0.52, 0.1, 2.2), concrete, Vector3(x, 6.42, zc))
	for k in 5:
		_box(g, Vector3(0.56, rng.randf_range(0.1, 0.3), rng.randf_range(0.3, 0.7)), concrete, Vector3(x, 6.35, rng.randf_range(z0 + 0.3, z1 - 0.3)), Vector3(rng.randf_range(-0.3, 0.3), 0, 0))
	# rubble and bricks scattered on both floors
	for side in [-1.0, 1.0]:
		for k in 9:
			var s := rng.randf_range(0.08, 0.3)
			_box(g, Vector3(s, s * 0.6, s * rng.randf_range(0.8, 1.6)), concrete if k % 3 else _mat(Color8(150, 70, 50)),
				Vector3(x + side * rng.randf_range(0.4, 1.8), 4.0 + s * 0.3, zc + rng.randf_range(-1.4, 1.4)), Vector3(0, rng.randf() * 3, 0))
	game.fx.spray(Vector3(x, 4.1, zc), Vector3.UP, Color8(120, 116, 106), 1, 0.1, 0.1)

## the balcony floor gave way over the bleachers: splintered boards round the hole and a rubble ramp
func _balcony_hole() -> void:
	var g := Node3D.new()
	add_child(g)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	# splintered boards jutting into the hole
	for k in 10:
		var along_x := k < 6
		var len := rng.randf_range(0.3, 0.8)
		var pos: Vector3
		if along_x:
			pos = Vector3(rng.randf_range(-51.8, -48.2), 3.95, -20.45 + len / 2 - 0.05 if k % 2 else -17.75 - len / 2 + 0.05)
			_box(g, Vector3(0.18, 0.05, len), wood, pos, Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.2, 0.2)))
		else:
			pos = Vector3(-52.0 + len / 2 - 0.05 if k % 2 else -48.0 - len / 2 + 0.05, 3.95, rng.randf_range(-20.2, -18.0))
			_box(g, Vector3(len, 0.05, 0.18), wood, pos, Vector3(0, 0, rng.randf_range(-0.3, 0.3)))
	# the ramp: from the top bleacher (1.8 m) up through the hole to the balcony (4.0 m)
	var a := Vector3(-48.1, 1.35, -19.1)
	var b := Vector3(-52.1, 4.0, -19.1)
	var mid := (a + b) / 2.0
	var dir := (b - a).normalized()
	var length := a.distance_to(b)
	var up := Vector3(-dir.y, dir.x, 0) if dir.x > 0 else Vector3(dir.y, -dir.x, 0)    # the ramp's upward normal
	var basis := Basis(Vector3(0, 0, 1), atan2(dir.y, dir.x))
	var thick := 1.2
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(length + 0.4, thick, 2.4)
	cs.shape = sh
	body.add_child(cs)
	world.nav.add_child(body)
	body.global_transform = Transform3D(basis, mid - up * thick / 2.0)
	var vis := _box(g, Vector3(length + 0.4, thick, 2.4), concrete, Vector3.ZERO)
	vis.global_transform = body.global_transform
	# a lumpy pile on top so it reads as rubble, not a ramp
	for k in 26:
		var t := rng.randf()
		var s := rng.randf_range(0.15, 0.45)
		var p := a.lerp(b, t) + Vector3(0, s * 0.25, rng.randf_range(-1.1, 1.1))
		_box(g, Vector3(s, s * 0.5, s * rng.randf_range(0.8, 1.5)), concrete if k % 4 else wood, p, Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * 3, rng.randf_range(-0.4, 0.4)))
	# a heap underneath on the bleachers
	for k in 14:
		var s := rng.randf_range(0.2, 0.5)
		_box(g, Vector3(s, s * 0.6, s), concrete if k % 3 else wood, Vector3(rng.randf_range(-47.8, -45.0), 1.4 + s * 0.2, rng.randf_range(-19.1, -18.4)), Vector3(0, rng.randf() * 3, 0))

## the breaker panel in the boiler room: one big lever
func _breaker() -> void:
	var g := Node3D.new()
	add_child(g)
	g.position = SWITCH_POS
	var panel := _mat(Color8(70, 76, 70))
	panel.metallic = 0.5
	_box(g, Vector3(0.18, 1.3, 0.9), panel, Vector3.ZERO)
	_box(g, Vector3(0.05, 0.9, 0.6), _mat(Color8(40, 42, 40)), Vector3(-0.1, 0.1, 0))
	var stripes := _mat(Color8(200, 160, 40))
	_box(g, Vector3(0.04, 0.12, 0.9), stripes, Vector3(-0.08, -0.6, 0))
	lever = Node3D.new()
	lever.position = Vector3(-0.15, 0.1, 0.0)
	g.add_child(lever)
	_box(lever, Vector3(0.06, 0.55, 0.06), _mat(Color8(150, 150, 150)), Vector3(-0.05, 0.25, 0))
	_box(lever, Vector3(0.1, 0.1, 0.24), _mat(Color8(170, 30, 30)), Vector3(-0.05, 0.52, 0))
	lever.rotation.z = -0.9         # down = off
	lamp_mat = StandardMaterial3D.new()
	lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_mat.albedo_color = Color(1, 0.15, 0.1)
	var bulb := _box(g, Vector3(0.06, 0.08, 0.08), lamp_mat, Vector3(-0.1, 0.55, 0.3))
	bulb.name = "Bulb"
	lamp = OmniLight3D.new()
	lamp.light_color = Color(1, 0.2, 0.1)
	lamp.omni_range = 3.5
	lamp.light_energy = 1.2
	lamp.position = Vector3(-0.4, 0.55, 0.3)
	g.add_child(lamp)
	var sign := Label3D.new()
	sign.text = "MAIN POWER"
	sign.font = load("res://assets/fonts/BlackOpsOne-Regular.ttf")
	sign.font_size = 48
	sign.pixel_size = 0.004
	sign.modulate = Color8(220, 200, 150)
	sign.position = Vector3(-0.1, 0.9, 0)
	sign.rotation.y = -PI / 2
	g.add_child(sign)

func prompt() -> String:
	if world.powered:
		return ""
	var d: Vector3 = game.player.global_position - SWITCH_SPOT
	if Vector2(d.x, d.z).length() > 1.8 or absf(d.y) > 1.5:
		return ""
	return "Press {use} to turn on the power"

func throw_switch() -> void:
	var tw := create_tween()
	tw.tween_property(lever, "rotation:z", 0.9, 0.25).set_trans(Tween.TRANS_BACK)
	lamp_mat.albedo_color = Color(0.2, 1, 0.3)
	lamp.light_color = Color(0.3, 1, 0.4)
	game.audio.play("strike", SWITCH_POS, 0, 0.7)
	game.audio.play("buzzer", SWITCH_POS, -4)

func _process(_dt: float) -> void:
	if lamp and not world.powered:
		lamp.light_energy = 1.2 if fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.5 else 0.2
