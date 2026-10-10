extends Node
## Short in-engine cutscenes: the intro fly-in, boss entrances and the power coming back on.
## A shot moves a camera from one place to another while looking at a point (or along a path);
## the game freezes underneath, the HUD letterboxes, and any key skips.

var game
var cam: Camera3D
var playing := false
var skip := false
var _frozen: Array = []

func setup(g) -> void:
	game = g
	cam = Camera3D.new()
	cam.fov = 64
	cam.near = 0.05
	cam.far = 120
	g.world.add_child(cam)

func request_skip() -> void:
	if playing:
		skip = true

static func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)

static func _catmull(pts: Array, t: float) -> Vector3:
	var n := pts.size() - 1
	var f := clampf(t, 0, 1) * n
	var i := mini(int(f), n - 1)
	var u := f - i
	var p0: Vector3 = pts[maxi(i - 1, 0)]
	var p1: Vector3 = pts[i]
	var p2: Vector3 = pts[i + 1]
	var p3: Vector3 = pts[mini(i + 2, n)]
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u)

func _begin(keep = null) -> void:
	playing = true
	skip = false
	Engine.time_scale = 1.0
	game.cut_prev_state = game.state
	game.state = "cutscene"
	game.player.frozen = true
	game.player.vm.visible = false
	game.player.knife.visible = false
	game.player.boot.visible = false
	_frozen.clear()
	for z in game.zombies:
		if z != keep and is_instance_valid(z):
			z.process_mode = Node.PROCESS_MODE_DISABLED
			_frozen.append(z)
	cam.current = true
	game.hud.letterbox(true)

func _end() -> void:
	for z in _frozen:
		if is_instance_valid(z):
			z.process_mode = Node.PROCESS_MODE_INHERIT
	_frozen.clear()
	game.player.cam.current = true
	game.player.frozen = false
	game.hud.letterbox(false)
	game.hud.cut_title("", "")
	game.state = game.cut_prev_state
	playing = false

## shots: [{from, to, look (Vector3) or look_from/look_to, path (Array), dur, fov, events: [[t, Callable]]}]
func play(shots: Array, keep = null, run_skipped := true) -> void:
	_begin(keep)
	for sh in shots:
		var dur: float = sh.get("dur", 2.0)
		var events: Array = sh.get("events", []).duplicate()
		var t := 0.0
		cam.fov = sh.get("fov", 64.0)
		while t <= dur:
			var k := _smooth(clampf(t / dur, 0, 1))
			var pos: Vector3
			if sh.has("path"):
				pos = _catmull(sh.path, k)
			else:
				pos = (sh.from as Vector3).lerp(sh.to, k)
			var look: Vector3
			if sh.has("look"):
				look = sh.look
			elif sh.has("look_from"):
				look = (sh.look_from as Vector3).lerp(sh.look_to, k)
			else:
				look = _catmull(sh.path, minf(1.0, k + 0.05)) if k < 0.95 else pos + sh.get("end_dir", Vector3.FORWARD)
			cam.global_position = pos
			if pos.distance_to(look) > 0.01:
				cam.look_at(look, Vector3.UP)
			while not events.is_empty() and events[0][0] <= t:
				events.pop_front()[1].call()
			if skip:
				break
			await get_tree().process_frame
			t += get_process_delta_time()
		# events not reached yet still have to happen (lights, banners) when skipped
		if not skip or run_skipped:
			for e in events:
				e[1].call()
		if skip:
			if not run_skipped:
				break
			for rest in shots.slice(shots.find(sh) + 1):
				for e in rest.get("events", []):
					e[1].call()
			break
	_end()

# ---------------------------------------------------------------- the three scenes
func intro() -> void:
	var p = game.player
	var f: Vector3 = -p.global_transform.basis.z
	var eye: Vector3 = p.global_position + Vector3(0, 1.6, 0)
	var path := [Vector3(-8, 15, 50), Vector3(4, 10, 46), Vector3(11, 5.5, 40), Vector3(15, 2.6, 35.8), Vector3(15.8, 1.8, 34.4), eye]
	game.audio.play("thunder", null, -4)
	await play([{"path": path, "dur": 6.5, "fov": 70.0, "end_dir": f, "events": [
		[0.4, func(): game.hud.cut_title("WESTFIELD HIGH", "THE NIGHT THE LAST BELL NEVER RANG")],
		[4.6, func(): game.hud.cut_title("", "")],
		[5.2, func(): game.audio.play("z_deep_moan", p.global_position + Vector3(-12, 1.5, -10), -2, 0.8)]]}])
	game.hud.banner("", game.hud.controls_hint(), 5.0)

func boss(z) -> void:
	if playing:
		return
	var sc: float = z.bscale
	var fwd: Vector3 = -z.global_transform.basis.z
	var head: Vector3 = z.global_position + Vector3(0, 1.75 * sc, 0)
	var a: Vector3 = z.global_position + fwd * 5.0 * sc + Vector3(0, 1.0 * sc, 0) + z.global_transform.basis.x * 1.2
	var b: Vector3 = z.global_position + fwd * 3.0 * sc + Vector3(0, 1.3 * sc, 0) + z.global_transform.basis.x * 0.5
	# make sure the camera isn't inside a wall: pull it in along the line of sight
	var space: PhysicsDirectSpaceState3D = game.world.get_world_3d().direct_space_state
	for which in [0, 1]:
		var pt: Vector3 = a if which == 0 else b
		var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(head, pt, 1))
		if not r.is_empty():
			pt = head.lerp(r.position, 0.85)
		if which == 0:
			a = pt
		else:
			b = pt
	z.emerge = 3.6
	var name: String = game.BOSSES[z.bt].name
	var sub: String = game.BOSSES[z.bt].sub
	await play([{"from": a, "to": b, "look": head, "dur": 3.4, "fov": 58.0, "events": [
		[0.2, func(): game.hud.cut_title(name, sub)],
		[0.9, func():
			game.audio.play("z_deep_moan", head, 8, 0.5)
			game.player.shake = 0.3]]}], z)

func power() -> void:
	if playing:
		return
	var sw: Vector3 = game.level.SWITCH_POS
	await play([
		{"from": sw + Vector3(-1.6, 0.2, 1.2), "to": sw + Vector3(-1.1, 0.0, 0.7), "look": sw, "dur": 1.3, "events": [
			[0.15, func(): game.level.throw_switch()],
			[0.8, func():
				game.world.power_on(sw, 0.025)
				game.audio.play("thud", null, 0, 0.5)]]},
		{"from": Vector3(-30, 5.6, -30), "to": Vector3(-20, 5.6, -30), "look_from": Vector3(10, 5, -30), "look_to": Vector3(15, 5, -30), "dur": 1.6},
		{"from": Vector3(0, 3.2, 13), "to": Vector3(0, 2.8, 10), "look": Vector3(0, 1, -6), "dur": 1.6},
		{"from": Vector3(-34, 4.5, 4), "to": Vector3(-36, 4.0, 2), "look": Vector3(-50, 1.5, -10), "dur": 1.8, "events": [
			[0.2, func(): game.hud.cut_title("POWER ON", "THE LIGHTS ARE BACK")]]}])
	game.hud.banner("POWER ON", "", 1.5)

# ---------------------------------------------------------------- how it started (plays once at launch)
var actors: Array = []
var props: Array = []

func _actor(pos: Vector3, ry: float, look := "student") -> Node3D:
	var z = preload("res://scripts/zombie.gd").new()
	game.zroot.add_child(z)
	z.setup(game, "walker", pos, 1)
	z.process_mode = Node.PROCESS_MODE_DISABLED
	z.collision_layer = 0
	z.global_position = pos
	z.rotation.y = ry
	z.emerge = 0
	if z.hat != null and is_instance_valid(z.hat):
		var h: MeshInstance3D = z.hat
		z.meshes = z.meshes.filter(func(e): return e.n != h)
		h.queue_free()
		z.hat = null
		z.prop_blade = null
	_humanize(z, actors.size())
	for b in z.boxes:
		b.collision_layer = 0
	actors.append(z)
	return z

func _hm(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m

## still human: clean shirts, jeans, skin, hair, eyes and a mouth; the zombie look is kept for later
const SHIRTS := [Color8(70, 110, 190), Color8(200, 60, 60), Color8(240, 240, 235), Color8(60, 140, 90), Color8(230, 180, 50), Color8(130, 80, 160)]
const SKINS := [Color8(236, 192, 160), Color8(198, 140, 100), Color8(150, 100, 70), Color8(245, 210, 180), Color8(110, 72, 50)]
const HAIRS := [Color8(40, 28, 20), Color8(120, 80, 40), Color8(220, 190, 110), Color8(20, 18, 18), Color8(160, 60, 30)]
func _humanize(z, i: int) -> void:
	var skin := _hm(SKINS[(i * 3 + 1) % SKINS.size()])
	var shirt := _hm(SHIRTS[i % SHIRTS.size()])
	var jeans := _hm(Color8(50, 70, 110))
	var hair := _hm(HAIRS[(i * 2) % HAIRS.size()])
	var human: Array = []
	for e in z.meshes:
		if not is_instance_valid(e.n):
			continue
		if e.n.material_override == game.eye_mat:
			e.n.visible = false
			continue
		var j: String = e.joint
		var m: Material = skin
		if j in ["spine", "core", "armL1", "armR1"]:
			m = shirt
		elif j.begins_with("leg") or j == "root" or j == "hips":
			m = jeans
		e.n.set_meta("zmat", e.n.material_override)
		e.n.material_override = m
		e.n.material_overlay = null
		human.append(e.n)
	# a face and a haircut
	var hd: Node3D = z.joints["head"]
	var parts: Array = []
	var add := func(size: Vector3, mat: Material, pos: Vector3) -> void:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = size
		mi.mesh = b
		mi.material_override = mat
		mi.position = pos
		hd.add_child(mi)
		parts.append(mi)
	var white := _hm(Color8(245, 245, 240))
	var dark := _hm(Color8(25, 20, 18))
	for x in [-0.065, 0.065]:
		add.call(Vector3(0.055, 0.032, 0.01), white, Vector3(x, 0.2, 0.176))
		add.call(Vector3(0.022, 0.026, 0.01), dark, Vector3(x, 0.2, 0.182))
		add.call(Vector3(0.06, 0.012, 0.012), hair, Vector3(x, 0.235, 0.178))
	add.call(Vector3(0.09, 0.018, 0.01), _hm(Color8(130, 50, 50)), Vector3(0, 0.1, 0.178))
	add.call(Vector3(0.39, 0.09, 0.39), hair, Vector3(0, 0.31, -0.01))
	add.call(Vector3(0.39, 0.22, 0.07), hair, Vector3(0, 0.21, -0.17))
	if i % 2 == 0:
		add.call(Vector3(0.06, 0.18, 0.3), hair, Vector3(-0.19, 0.22, -0.04))
		add.call(Vector3(0.06, 0.18, 0.3), hair, Vector3(0.19, 0.22, -0.04))
	z.set_meta("human", human)
	z.set_meta("face", parts)

func _look(z, human: bool) -> void:
	for n in z.get_meta("human", []):
		if is_instance_valid(n):
			if human:
				continue
			n.material_override = n.get_meta("zmat")
	for e in z.meshes:
		if is_instance_valid(e.n) and e.n.material_override == game.eye_mat:
			e.n.visible = not human
	var face: Array = z.get_meta("face", [])
	for k in face.size():
		# keep the hair, lose the human eyes and mouth
		if is_instance_valid(face[k]) and k < face.size() - (4 if face.size() > 9 else 2):
			face[k].visible = human

func _humanize_again(z) -> void:
	var skin_like: Array = z.get_meta("human", [])
	for n in skin_like:
		if is_instance_valid(n) and n.has_meta("hmat"):
			n.material_override = n.get_meta("hmat")
	for e in z.meshes:
		if is_instance_valid(e.n) and e.n.material_override == game.eye_mat:
			e.n.visible = false
	for p in z.get_meta("face", []):
		if is_instance_valid(p):
			p.visible = true

## the bite: a gross flicker between the two looks, then the eyes light up and they groan
func _turn(z) -> void:
	for n in z.get_meta("human", []):
		if is_instance_valid(n) and not n.has_meta("hmat"):
			n.set_meta("hmat", n.material_override)
	var tw := create_tween()
	for k in 7:
		tw.tween_callback(func(): _look(z, false))
		tw.tween_interval(0.05 + k * 0.012)
		if k < 6:
			tw.tween_callback(func(): _humanize_again(z))
			tw.tween_interval(0.07 - k * 0.008)
	tw.tween_callback(func():
		_look(z, false)
		var hp: Vector3 = z.joints["head"].global_position
		game.fx.puff(hp + Vector3(0, 0.15, 0.1), Color8(120, 220, 90), false, 0.05, 0.4, 0.7, 0.3, 0.1, 0.7)
		game.fx.spray(hp, Vector3.UP, Color8(110, 10, 10), 6, 1.5, 0.6, true)
		game.audio.play(["z_deep_moan", "z_hoarse_moan", "z_wet_moan"][randi() % 3], hp, 4, randf_range(0.85, 1.1)))

func _prop_cyl(r: float, h: float, col: Color, pos: Vector3, glow := false) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 10
	m.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	if glow:
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 1.5
	m.material_override = mat
	game.world.add_child(m)
	m.global_position = pos
	props.append(m)
	return m

func _cleanup() -> void:
	for a in actors:
		if is_instance_valid(a):
			a.queue_free()
	for p in props:
		if is_instance_valid(p):
			p.queue_free()
	actors.clear()
	props.clear()

func infection() -> void:
	var w = game.world
	var fx = game.fx
	var au = game.audio
	var hud = game.hud
	# the chem lab upstairs
	var table := Vector3(-7.4, 4.86, -36.0)
	var kyle = _actor(Vector3(-7.4, 4.0, -35.1), 0.0)
	var green := _prop_cyl(0.06, 0.18, Color8(120, 255, 90), table + Vector3(0.25, 0.09, 0.25), true)
	var pink := _prop_cyl(0.06, 0.18, Color8(255, 90, 220), table + Vector3(-0.15, 0.09, 0.25), true)
	var lablight := OmniLight3D.new()
	lablight.light_color = Color8(150, 255, 120)
	lablight.omni_range = 5
	lablight.light_energy = 0.0
	w.add_child(lablight)
	lablight.global_position = table + Vector3(0, 0.6, 0.4)
	props.append(lablight)
	# the lunch line
	var pot := _prop_cyl(0.32, 0.34, Color8(60, 60, 64), Vector3(-8.0, 1.12, 4.1))
	var lbl := Label3D.new()
	lbl.text = "MYSTERY\nMEAT"
	lbl.font = load("res://assets/fonts/BlackOpsOne-Regular.ttf")
	lbl.font_size = 40
	lbl.pixel_size = 0.004
	lbl.modulate = Color8(230, 220, 200)
	lbl.position = Vector3(0, 0.05, 0.33)
	pot.add_child(lbl)
	var potlight := OmniLight3D.new()
	potlight.light_color = Color8(150, 255, 120)
	potlight.omni_range = 4
	potlight.light_energy = 0.0
	pot.add_child(potlight)
	potlight.position = Vector3(0, 0.5, 0.3)
	var line: Array = []
	for i in 4:
		line.append(_actor(Vector3(-11.0 + i * 1.3, 0.0, 5.1), 0.0))
	# the PA speaker
	var spk := MeshInstance3D.new()
	var sbm := BoxMesh.new()
	sbm.size = Vector3(0.15, 0.4, 0.55)
	spk.mesh = sbm
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color8(200, 196, 180)
	spk.material_override = smat
	w.add_child(spk)
	spk.global_position = Vector3(-13.6, 3.3, 0.0)
	props.append(spk)
	var gas_from := Vector3(-12.5, 2.6, 8.0)
	var gas_to := Vector3(-8.0, 1.4, 4.1)
	var gas_puffs := func(k: float):
		for j in 2:
			fx.puff(gas_from.lerp(gas_to, k) + Vector3(randf_range(-0.3, 0.3), randf_range(-0.2, 0.2), randf_range(-0.3, 0.3)), Color8(120, 220, 90), false, 0.3, randf_range(0.8, 1.3), 1.4, 0.0, 0.2, 0.55)
	var shots: Array = [
		{"from": Vector3(-8, 15, 52), "to": Vector3(6, 8, 42), "look_from": Vector3(0, 4, 15), "look_to": Vector3(0, 3, 14), "dur": 4.2, "fov": 60.0, "events": [
			[0.3, func(): hud.cut_title("", "WESTFIELD HIGH.  SCIENCE FAIR DAY.  7:58 AM.")],
			[0.4, func(): au.play("bell", null, -6)]]},
		{"from": Vector3(-5.9, 5.75, -34.4), "to": Vector3(-6.3, 5.55, -34.8), "look": table + Vector3(0, 0.2, 0), "dur": 6.0, "fov": 55.0, "events": [
			[0.2, func(): hud.cut_title("", "KYLE:  \"what happens if you mix the green one with the pink one?\"")],
			[1.8, func(): create_tween().tween_property(kyle.joints["armR1"], "rotation:x", -1.3, 0.5)],
			[2.4, func():
				create_tween().tween_property(green, "global_position", pink.global_position + Vector3(0, 0.22, 0), 0.4)
				create_tween().tween_property(green, "rotation:z", 2.0, 0.4)],
			[2.9, func():
				au.play("fizz", table, 4)
				create_tween().tween_property(lablight, "light_energy", 4.0, 1.5)],
			[3.1, func():
				for i in 6:
					fx.puff(table + Vector3(-0.1, 0.3 + i * 0.15, 0.25), Color8(130, 240, 90), false, 0.1, randf_range(0.6, 1.4), 1.8, 0.6, 0.15, 0.8)],
			[3.6, func(): hud.cut_title("", "KYLE:  \"...oh.\"")],
			[4.2, func():
				for i in 12:
					fx.puff(table + Vector3(randf_range(-0.8, 0.8), 0.4, randf_range(-0.8, 0.8)), Color8(120, 220, 80), false, 0.4, randf_range(1.8, 2.8), 2.2, 0.4, 0.5, 0.85)
				au.play("bloat", table, 2)
				game.player.shake = 0.2]]},
		{"from": Vector3(-4.8, 2.4, 7.6), "to": Vector3(-5.2, 2.1, 6.9), "look_from": Vector3(-11, 2.2, 7.0), "look_to": Vector3(-8, 1.2, 4.1), "dur": 5.0, "fov": 60.0, "events": [
			[0.2, func(): hud.cut_title("", "The fumes went looking for lunch.")],
			[0.3, func(): gas_puffs.call(0.0)], [0.6, func(): gas_puffs.call(0.15)], [0.9, func(): gas_puffs.call(0.3)], [1.2, func(): gas_puffs.call(0.45)],
			[1.5, func(): gas_puffs.call(0.6)], [1.8, func(): gas_puffs.call(0.75)], [2.1, func(): gas_puffs.call(0.9)], [2.4, func(): gas_puffs.call(1.0)],
			[2.8, func():
				au.play("gurgle", pot.global_position, 4)
				create_tween().tween_property(potlight, "light_energy", 3.0, 0.8)
				for i in 8:
					fx.spray(pot.global_position + Vector3(0, 0.2, 0), Vector3.UP, Color8(140, 255, 100), 3, 2.5, 0.6)],
			[3.4, func(): hud.cut_title("", "It found the mystery meat.")]]},
		{"from": Vector3(-11.4, 3.0, 1.6), "to": Vector3(-11.9, 3.15, 0.9), "look": Vector3(-13.6, 3.3, 0.0), "dur": 5.2, "fov": 55.0, "events": [
			[0.2, func(): au.play("paChime", spk.global_position, 2)],
			[1.1, func():
				au.play("paVoice", spk.global_position, 4)
				hud.cut_title("", "PRINCIPAL (PA):  \"Good morning, Wildcats! Today's lunch...\"")],
			[3.4, func(): hud.cut_title("", "\"...is the special.\"")]]},
		{"from": Vector3(-4.8, 1.8, 7.4), "to": Vector3(-5.1, 1.7, 7.0), "look": Vector3(-9.0, 1.3, 4.8), "dur": 8.5, "fov": 58.0, "events": [
			[0.2, func(): hud.cut_title("", "")],
			[0.6, func():
				for i in line.size():
					var a = line[i]
					var tw := create_tween()
					tw.tween_interval(i * 0.35)
					tw.tween_property(a.joints["spine"], "rotation:x", 0.55, 0.25)
					tw.tween_callback(func():
						au.play("chomp", a.global_position + Vector3(0, 1.4, 0), 2, randf_range(0.9, 1.2))
						_turn(a))
					tw.tween_property(a.joints["spine"], "rotation:x", 0.0, 0.3)],
			[3.0, func(): hud.cut_title("", "...")],
			[4.4, func():
				for a in line:
					a.joints["head"].rotation = Vector3(-0.3, 0, randf_range(-0.4, 0.4))
				au.play("z_deep_moan", line[1].global_position + Vector3(0, 1.6, 0), 6, 0.8)
				au.play("z_hoarse_moan", line[2].global_position + Vector3(0, 1.6, 0), 6, 1.0)
				game.player.shake = 0.15],
			[5.1, func():
				for a in line:
					var tw := create_tween()
					tw.tween_property(a, "rotation:y", deg_to_rad(randf_range(130, 160)), 0.6)
					create_tween().tween_property(a.joints["armL1"], "rotation:x", -1.4, 0.6)
					create_tween().tween_property(a.joints["armR1"], "rotation:x", -1.5, 0.6)],
			[5.6, func(): hud.cut_title("", "It was not special.")]]},
		{"from": Vector3(-5.4, 1.7, 6.8), "to": Vector3(-5.2, 1.65, 6.6), "look": Vector3(-9.0, 1.5, 5.0), "dur": 2.6, "fov": 50.0, "events": [
			[0.15, func():
				hud.cut_title("DEAD SHIFT", "WESTFIELD HIGH")
				au.play("boom", null, -4, 0.7)
				au.play("thunder", null, -6)
				game.player.shake = 0.35]]},
	]
	await play(shots, null, false)
	hud.cut_title("", "")
	_cleanup()
