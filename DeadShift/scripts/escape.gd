extends Node3D
## Buy the bus (30,000): hotwire it, plough through the horde, smash the front gates in slow motion and drive
## off into the night. Ends the run with an ESCAPED screen and saves the score with an escape badge.

const COST := 30000
const DOOR_SPOT := Vector3(36.1, 0.0, 29.7)
const BUS_C := Vector3(33.0, 0.0, 27.0)      # the bus model's pivot (centre of its footprint)
const GATE_X := 50.0
const GATE_Z0 := 24.0
const GATE_Z1 := 30.0
const MAP_ID := "westfield"

var game
var bus: Node3D            # pivot: moving this drives the whole bus
var leaves: Array = []     # gate halves (hinge nodes)
var gate_body: StaticBody3D
var road: Node3D
var driving := false
var bus_v := 0.0
var black: ColorRect
var escaped := false
var taillights: Array = []
var crashed := false
var heads: Array = []
var cabin: OmniLight3D
var can_leave := false

func setup(g) -> void:
	game = g
	bus = Node3D.new()
	add_child(bus)
	bus.global_position = BUS_C
	var inst: Node3D = load("res://assets/models/bus.glb").instantiate()
	game.world._crisp(inst)
	bus.add_child(inst)
	inst.position = -BUS_C
	for x in [-6.8]:
		for z in [-1.0, 1.0]:
			var tl := OmniLight3D.new()
			tl.light_color = Color(1, 0.1, 0.05)
			tl.omni_range = 2.5
			tl.light_energy = 0.0
			bus.add_child(tl)
			tl.position = Vector3(x, 1.0, z)
			taillights.append(tl)
	# headlights and a dim cabin light, switched on when the engine catches
	for z in [-0.9, 0.9]:
		var hl := SpotLight3D.new()
		hl.light_color = Color(1, 0.95, 0.8)
		hl.spot_range = 28
		hl.spot_angle = 28
		hl.light_energy = 0.0
		bus.add_child(hl)
		hl.position = Vector3(7.0, 1.0, z)
		hl.rotation.y = -PI / 2
		hl.rotation.x = -0.06
		heads.append(hl)
	cabin = OmniLight3D.new()
	cabin.light_color = Color(1, 0.85, 0.6)
	cabin.omni_range = 7
	cabin.light_energy = 0.0
	bus.add_child(cabin)
	cabin.position = Vector3(0, 2.0, 0)
	_build_gate()
	black = ColorRect.new()
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black.color = Color(0, 0, 0, 0)
	game.hud.root.add_child(black)

func _m(c: Color, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = 0.6
	return m

func _box(p: Node3D, size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	p.add_child(mi)
	return mi

func _link_tex() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 16:
		img.set_pixel(i, i, Color8(170, 172, 176))
		img.set_pixel(15 - i, i, Color8(170, 172, 176))
	return ImageTexture.create_from_image(img)

## the front gates: two chain-link leaves under a school sign, closing the gap cut in the fence
func _build_gate() -> void:
	var steel := _m(Color8(120, 122, 128), 0.6)
	var link := StandardMaterial3D.new()
	link.albedo_texture = _link_tex()
	link.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	link.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	link.cull_mode = BaseMaterial3D.CULL_DISABLED
	link.uv1_scale = Vector3(9, 8, 1)
	link.metallic = 0.5
	var w := (GATE_Z1 - GATE_Z0) / 2.0
	for side in [0, 1]:
		var hinge := Node3D.new()
		add_child(hinge)
		var hz := GATE_Z0 if side == 0 else GATE_Z1
		hinge.global_position = Vector3(GATE_X, 0, hz)
		var dirz := 1.0 if side == 0 else -1.0
		var leaf := Node3D.new()
		hinge.add_child(leaf)
		_box(leaf, Vector3(0.08, 0.08, w), steel, Vector3(0, 0.15, dirz * w / 2))
		_box(leaf, Vector3(0.08, 0.08, w), steel, Vector3(0, 2.6, dirz * w / 2))
		_box(leaf, Vector3(0.08, 0.08, w), steel, Vector3(0, 1.4, dirz * w / 2))
		_box(leaf, Vector3(0.08, 2.6, 0.08), steel, Vector3(0, 1.35, dirz * (w - 0.05)))
		_box(leaf, Vector3(0.08, 2.6, 0.08), steel, Vector3(0, 1.35, dirz * 0.05))
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(w, 2.45)
		q.mesh = qm
		q.material_override = link
		q.rotation.y = PI / 2
		q.position = Vector3(0, 1.38, dirz * w / 2)
		leaf.add_child(q)
		# padlock and chain in the middle
		if side == 0:
			_box(leaf, Vector3(0.1, 0.14, 0.08), _m(Color8(190, 160, 50), 0.7), Vector3(-0.08, 1.3, dirz * (w - 0.08)))
		leaves.append(hinge)
	# posts and the sign
	for z in [GATE_Z0 - 0.15, GATE_Z1 + 0.15]:
		var post := Node3D.new()
		add_child(post)
		post.global_position = Vector3(GATE_X, 0, z)
		_box(post, Vector3(0.25, 3.8, 0.25), _m(Color8(70, 72, 78), 0.4), Vector3(0, 1.9, 0))
	var sign := Node3D.new()
	add_child(sign)
	sign.global_position = Vector3(GATE_X, 3.75, (GATE_Z0 + GATE_Z1) / 2.0)
	_box(sign, Vector3(0.12, 0.6, GATE_Z1 - GATE_Z0 + 0.6), _m(Color8(110, 20, 26)), Vector3.ZERO)
	for s in [-1.0, 1.0]:
		var l := Label3D.new()
		l.text = "WESTFIELD HIGH"
		l.font = load("res://assets/fonts/BlackOpsOne-Regular.ttf")
		l.font_size = 72
		l.pixel_size = 0.006
		l.modulate = Color8(240, 220, 170)
		l.outline_size = 0
		l.position = Vector3(-s * 0.07, 0, 0)
		l.rotation.y = PI / 2 * -s
		sign.add_child(l)
	gate_body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.3, 3.6, GATE_Z1 - GATE_Z0 + 0.2)
	cs.shape = bs
	gate_body.add_child(cs)
	add_child(gate_body)
	gate_body.global_position = Vector3(GATE_X, 1.8, (GATE_Z0 + GATE_Z1) / 2.0)

func prompt() -> String:
	if escaped:
		return ""
	var d: Vector3 = game.player.global_position - DOOR_SPOT
	if Vector2(d.x, d.z).length() > 2.4 or absf(d.y) > 1.5:
		return ""
	if game.points < COST:
		return "Need 30,000 points to escape"
	return "Press {use} to hotwire the bus and escape  [30,000]"

func buy() -> void:
	if escaped or game.points < COST or game.cutscene.playing:
		if game.points < COST:
			game._deny()
		return
	escaped = true
	var pts: int = game.points
	game.points -= COST
	game.hud.points_pop(-COST)
	game.audio.play("buy")
	_cutscene(pts)

# ---------------------------------------------------------------- the escape
func _road() -> void:
	road = Node3D.new()
	add_child(road)
	var grass := _m(Color8(18, 24, 16))
	_box(road, Vector3(260, 0.05, 220), grass, Vector3(GATE_X + 130.5, -0.04, 27))
	var asphalt := _m(Color8(34, 34, 38))
	_box(road, Vector3(220, 0.04, 9), asphalt, Vector3(GATE_X + 110, -0.005, 27))
	var paint := _m(Color8(220, 190, 60))
	for i in 40:
		_box(road, Vector3(2.0, 0.045, 0.15), paint, Vector3(GATE_X + 3 + i * 5.0, 0.0, 27))
	for i in 5:
		var x := GATE_X + 14 + i * 30.0
		var pole := Node3D.new()
		road.add_child(pole)
		pole.global_position = Vector3(x, 0, 32.5)
		_box(pole, Vector3(0.15, 6, 0.15), _m(Color8(70, 70, 74), 0.5), Vector3(0, 3, 0))
		_box(pole, Vector3(0.4, 0.15, 1.6), _m(Color8(70, 70, 74), 0.5), Vector3(0, 6, -0.7))
		var l := SpotLight3D.new()
		l.light_color = Color8(255, 190, 110)
		l.spot_range = 9
		l.spot_angle = 50
		l.light_energy = 3.0
		pole.add_child(l)
		l.position = Vector3(0, 5.9, -1.3)
		l.rotation.x = -PI / 2

func _spawn_swarm() -> void:
	for i in 16:
		if game.zombies.size() >= 40:
			break
		var a := randf() * TAU
		var r := randf_range(5.0, 12.0)
		var p := BUS_C + Vector3(cos(a) * r, 0.2, sin(a) * r)
		if p.z > 34.0 or p.x > 48.0:
			p = BUS_C + Vector3(-cos(a) * r, 0.2, -absf(sin(a)) * r)
		var z = game.ZombieScript.new()
		game.zroot.add_child(z)
		z.setup(game, ["walker", "runner", "walker"][i % 3], p, maxi(game.wave, 3))
		z.emerge = 0.3
		z.rush_t = 20.0
		game.zombies.append(z)

func _wake_zombies() -> void:
	for z in game.zombies:
		if is_instance_valid(z):
			z.process_mode = Node.PROCESS_MODE_INHERIT

func _cutscene(points_at: int) -> void:
	var cs = game.cutscene
	var P = game.player
	var au = game.audio
	var hud = game.hud
	var t0: float = game.run_t
	P.invuln = true
	_road()
	_spawn_swarm()
	var door := Vector3(36.1, 1.3, 28.4)
	var shots: Array = [
		# 1: climb aboard
		{"from": Vector3(33.8, 1.8, 33.4), "to": Vector3(35.0, 1.65, 31.6), "look": door, "dur": 2.0, "fov": 60.0, "events": [
			[0.05, func():
				_wake_zombies()
				hud.cut_title("", "...the keys are still in it?")],
			[1.2, func():
				au.play("metalDoor", door, 0, 1.3)
				P.global_position = Vector3(36.0, 0.35, 27.2)]]},
		# 2: the engine coughs, then roars (from out front, in the glare)
		{"from": Vector3(45.5, 1.0, 24.6), "to": Vector3(44.6, 1.1, 25.0), "look": Vector3(38.5, 1.6, 27.0), "dur": 3.0, "fov": 60.0, "events": [
			[0.1, func():
				au.play("cough", null, 2)
				hud.cut_title("", "come on... come on...")],
			[0.9, func(): P.shake = 0.1],
			[2.1, func():
				au.play("engine", null, 4)
				hud.cut_title("", "")
				P.shake = 0.3
				for tl in taillights:
					tl.light_energy = 2.0
				for hl in heads:
					hl.light_energy = 6.0
				cabin.light_energy = 1.2
				game.fx.flash_light(BUS_C + Vector3(8, 1.2, 0), Color(1, 0.95, 0.8), 6.0, 14.0, 0.4)]]},
		# 3: the horde swarms the bus
		{"from": Vector3(22.0, 4.6, 35.0), "to": Vector3(24.0, 3.6, 33.5), "look": BUS_C + Vector3(1, 1.0, 0), "dur": 2.6, "fov": 62.0, "events": [
			[0.2, func(): au.play("z_shriek", BUS_C + Vector3(-6, 1.5, 4), 6)],
			[1.0, func(): au.play("z_deep_moan", BUS_C + Vector3(4, 1.5, -6), 6, 0.8)],
			]},
		# 4: ploughing through toward the gates
		{"from": Vector3(30.0, 2.4, 32.5), "to": Vector3(42.5, 2.0, 32.0), "look_from": BUS_C + Vector3(3, 1.2, 0), "look_to": Vector3(50, 1.4, 27), "dur": 2.4, "fov": 64.0, "events": [
			[0.0, func(): driving = true]]},
		# 5: slow motion through the gates (game time; ~2.6 s real)
		{"from": Vector3(56.5, 0.9, 21.0), "to": Vector3(55.5, 0.8, 22.5), "look": Vector3(GATE_X, 1.6, 27.0), "dur": 0.85, "fov": 58.0, "events": [
			[0.0, func(): _slowmo(true)],
			[0.2, func(): _smash()],
			[0.85, func(): _slowmo(false)]]},
		# 6: into the night
		{"from": Vector3(60.0, 1.8, 31.5), "to": Vector3(61.0, 2.2, 31.0), "look_from": Vector3(66, 1.2, 27), "look_to": Vector3(110, 1.0, 27), "dur": 3.4, "fov": 60.0, "events": [
			[0.4, func(): au.play("engine", Vector3(70, 1, 27), 6, 1.15)],
			[2.0, func(): create_tween().tween_property(black, "color:a", 1.0, 1.3)]]},
	]
	await cs.play(shots, game.boss, true)
	_slowmo(false)
	driving = false
	black.color.a = 1.0
	game.state = "over"
	P.invuln = false
	var time: float = t0
	var rec: Dictionary = game.settings.record_escape(game.wave, game.kills, points_at, time, MAP_ID) if game.settings else {}
	await get_tree().create_timer(0.6).timeout
	hud.escaped(game.wave, game.kills, points_at, time, rec)
	await get_tree().create_timer(1.5).timeout
	create_tween().tween_property(black, "color:a", 0.0, 0.8)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	can_leave = true
	await get_tree().create_timer(9.0).timeout
	_to_menu()

func _to_menu() -> void:
	if not is_inside_tree():
		return
	Engine.time_scale = 1.0
	Engine.set_meta("skip_menu", false)
	get_tree().reload_current_scene()

func _slowmo(on: bool) -> void:
	if on:
		Engine.time_scale = 0.3
		game.hitstop_until = Time.get_ticks_msec() + 3500
	else:
		Engine.time_scale = 1.0
		game.hitstop_until = 0

func _smash() -> void:
	var c := Vector3(GATE_X, 1.4, 27.0)
	game.audio.play("crash", c, 8)
	game.audio.play("metalDoor", c, 6, 0.6)
	game.player.shake = 0.5
	game.rumble(1.0, 1.0, 0.6)
	game.fx.flash_light(c, Color(1, 0.8, 0.5), 5.0, 10.0, 0.3)
	for k in 6:
		game.fx.spark(c + Vector3(0, randf_range(-1, 1), randf_range(-2.5, 2.5)), Vector3(1, 0.3, 0))
	crashed = true
	gate_body.queue_free()
	for i in leaves.size():
		var h: Node3D = leaves[i]
		var s := -1.0 if i == 0 else 1.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(h, "global_position", h.global_position + Vector3(9, 2.5, s * 6), 1.2).set_ease(Tween.EASE_OUT)
		tw.tween_property(h, "rotation", Vector3(randf_range(-1, 1), s * 2.2, s * 1.4), 1.2)

func _process(dt: float) -> void:
	if not driving or bus == null:
		return
	bus_v = minf(bus_v + dt * (9.0 if crashed else 3.0), 22.0)
	bus.global_position.x += bus_v * dt
	bus.global_position.y = sin(Time.get_ticks_msec() / 40.0) * 0.02
	var front: float = bus.global_position.x + 6.9
	# anything in the way goes flying
	for z in game.zombies.duplicate():
		if not is_instance_valid(z) or not z.alive:
			continue
		var p: Vector3 = z.global_position
		if p.x > front - 2.0 and p.x < front + 0.6 and absf(p.z - BUS_C.z) < 1.9 and p.y < 2.0:
			var d := Vector3(1.0, 0.7, signf(p.z - BUS_C.z) * 0.6 + randf_range(-0.2, 0.2)).normalized()
			z.damage(99999.0, "body", d, 14.0, false, p + Vector3(0, 1, 0))
			game.audio.play("thud", p, 6, 0.8)
			game.fx.blood(p + Vector3(0, 1.2, 0), d, true)
	if bus.global_position.x > 200:
		driving = false
