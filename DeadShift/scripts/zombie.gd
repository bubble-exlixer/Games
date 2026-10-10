extends CharacterBody3D
## One zombie: the web game's real model, its pose code, its AI, and its gore.

const WORLD := 1
const ZOMBIE_BODY := 2
const HITBOX := 4
const GRAVITY := 22.0
const REACH := 1.2
const VTYPE := {"walker": ["deep", "hoarse"], "runner": ["wheeze"], "armored": ["deep"], "bloater": ["wet"], "spitter": ["wet"], "boss": ["deep"], "monitor": ["wheeze"]}
const BOSS_SCALE := {"coach": 1.8, "principal": 1.55, "chem": 1.5, "lunch": 1.75}
const KITCHEN := Vector3(-8, 0, 2.5)

var game
var kind := "walker"
var sample: Dictionary
var hp := 100.0
var max_hp := 100.0
var speed := 2.5
var dmg := 14.0
var helmet_hp := 0.0
var vest_hp := 0.0
var alive := true
var crawler := false
var lost := {}

var vis: Node3D
var joints := {}
var rest := {}
var meshes: Array = []        # {n: MeshInstance3D, joint: String, head: bool, armor: bool}
var boxes: Array = []         # Area3D hitboxes
var agent: NavigationAgent3D
var shape: CollisionShape3D

# animation (same names as the web game)
var cyc := 0.0
var t := 0.0
var lean := 0.2
var sway := 0.08
var tilt := 0.0
var arm_style := "reach"
var lunge := 0.0
var flinch := 0.0
var fzone := "body"
var fside := 1.0
var emerge := 1.3
var spit_anim := 0.0
var stagger := 0.0
var flash_t := 0.0
# ai
var cd := 0.0
var spit_cd := 3.0
var repath := 0.0
var stuck := 0
var check_t := 0.0
var last_pos := Vector3.ZERO
var voice_t := 2.0
var vtype := "deep"
var pitch := 1.0
var moving := false
var nav_force := 0.0          # seconds left of "follow the navmesh, not your nose"
var side_t := 0.0             # sidestep out of a snag
var side_dir := Vector3.ZERO
var los_t := 0.0
var los_ok := false
var prog_t := 0.0
var prog_pos := Vector3.ZERO
var drip_t := 0.0
# bosses
var bt := ""                  # coach | principal | chem
var bscale := 1.0
var reach := REACH
var rush_t := 0.0
var ab_t := 4.0
var th_t := 2.5
var throw_n := 0
var sdir := 1.0
var sdir_t := 0.0
var flask_node: MeshInstance3D
var step_ph := 0
var whistle_cd := 2.0
var tray_t := 4.5
var enraged := false
var slow_t := 0.0
var phase := 1
var near_said := false
var move_t := 4.0
var move2_t := 6.0
var hold_t := 0.0
var charge_t := 0.0
var charge_pending := false
var pound_pending := false
var charge_dir := Vector3.ZERO
var always_enraged := false
# death
var ct := 0.0
# silly hats
var hat: MeshInstance3D
# power-ups and traps
var freeze_t := 0.0           # Snow Day: frozen solid
var flee_t := 0.0             # Fire Drill: walking away from the player
var tint_mat = null           # overlay that replaces the skin overlay (ice, char)
var charred := false          # fried by the shock gate: the ragdoll stays black
var zap_t := 0.0              # shock gate cooldown per zombie
var prop_blade: Node3D

func setup(g, k: String, pos: Vector3, wave: int, boss_type := "") -> void:
	game = g
	kind = k
	bt = boss_type
	var list: Array = game.samples_by_kind.get(kind, game.samples_by_kind["walker"])
	var si: int = list[randi() % list.size()]
	var want_look := ""
	if kind == "boss":
		want_look = {"coach": "janitor", "lunch": "lunch"}.get(bt, "teacher")
	elif kind == "monitor":
		want_look = "student"
	if want_look != "":
		for i in game.world.data.zombie_samples.size():
			if game.world.data.zombie_samples[i].look == want_look:
				si = i
				break
	sample = game.world.data.zombie_samples[si]
	_stats(wave)
	collision_layer = ZOMBIE_BODY
	collision_mask = WORLD
	floor_max_angle = deg_to_rad(52)
	floor_snap_length = 0.5
	shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.7
	shape.shape = cap
	shape.position.y = 0.85
	add_child(shape)
	vis = Node3D.new()
	vis.rotation.y = PI          # the web model faces +Z, Godot's forward is -Z
	add_child(vis)
	for j in sample.joints:
		var n := Node3D.new()
		n.name = j.n
		n.rotation_order = EULER_ORDER_XYZ
		n.position = Vector3(j.pos[0], j.pos[1], j.pos[2])
		rest[j.n] = n.position
		if j.parent == null:
			vis.add_child(n)
		else:
			joints[j.parent].add_child(n)
		joints[j.n] = n
	var inst: Node3D = game.zombie_scene(si).instantiate()
	var by_name := {}
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		by_name[String(m.name)] = m
	for p in sample.parts:
		var m: MeshInstance3D = by_name.get(p.node)
		if m == null:
			continue
		var xf := m.transform
		m.owner = null
		m.get_parent().remove_child(m)
		joints[p.joint].add_child(m)
		m.transform = xf
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		meshes.append({"n": m, "joint": p.joint, "head": p.head, "armor": p.armor})
	inst.queue_free()
	# glowing eyes
	for x in [-0.065, 0.065]:
		var e := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.04, 0.025, 0.02)
		e.mesh = b
		e.material_override = game.eye_mat
		e.position = Vector3(x, 0.2, 0.172)
		joints["head"].add_child(e)
		meshes.append({"n": e, "joint": "head", "head": true, "armor": false})
	if kind == "boss":
		_dress_boss()
	elif kind == "monitor":
		_dress_monitor()
	elif kind in ["walker", "runner", "spitter", "bloater"] and randf() < 0.22:
		_hat(["grad", "helmet", "beanie", "dunce", "hairnet"][randi() % 5])
	_hitboxes()
	if game.skin != "normal":
		_overlay(false)
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.4
	agent.target_desired_distance = 0.6
	agent.radius = 0.4
	agent.height = 1.8
	agent.path_max_distance = 3.0
	add_child(agent)
	global_position = pos
	rotation.y = randf() * TAU
	if kind != "boss":
		lean = sample.lean if sample.has("lean") else randf_range(0.1, 0.4)
	sway = sample.sway if sample.has("sway") else 0.08
	if kind == "boss":
		arm_style = "reach" if bt == "coach" else "one"
	elif kind == "runner":
		arm_style = "run"
	elif kind == "bloater":
		arm_style = "dangle"
	elif kind == "monitor":
		arm_style = "one"
	else:
		arm_style = ["reach", "reach", "one", "dangle"][randi() % 4]
	tilt = randf_range(-0.35, 0.35)
	cyc = randf() * 6.0
	t = randf() * 10.0
	var vt: Array = VTYPE.get(kind, VTYPE.walker)
	vtype = vt[randi() % vt.size()]
	pitch = randf_range(1.3, 1.5) if kind == "monitor" else randf_range(0.85, 1.15)
	voice_t = randf_range(0.5, 4.0)
	spit_cd = randf_range(2.0, 4.0)
	last_pos = pos
	game.fx.burst(pos + Vector3(0, 0.1, 0), Vector3.UP, 8, Color(0.29, 0.27, 0.25), 3.0, 0.08, 0.9)

## the web game's school bosses: re-skinned and scaled up, with their props
func _mat_tex(path: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 1.0
	return m

func _acc(joint: String, size: Vector3, col: Color, pos: Vector3, head := true, glow := false) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	if glow:
		mat.emission_enabled = true
		mat.emission = col * 0.6
	m.material_override = mat
	m.position = pos
	joints[joint].add_child(m)
	meshes.append({"n": m, "joint": joint, "head": head, "armor": false})
	return m

func _dress_boss() -> void:
	bscale = BOSS_SCALE.get(bt, 1.8)
	vis.scale = Vector3.ONE * bscale
	reach = 2.2 if bt == "coach" else 1.2 * bscale
	var shirt := _mat_tex("res://assets/textures/boss_%s_shirt.png" % bt)
	var pants := _mat_tex("res://assets/textures/boss_%s_pants.png" % bt)
	for e in meshes:
		if e.head:
			continue
		if e.joint in ["spine", "core", "armL1", "armR1"]:
			e.n.material_override = shirt
		elif e.joint.begins_with("leg"):
			e.n.material_override = pants
		if bt == "coach" and e.joint.begins_with("arm"):
			e.n.scale = Vector3(1.3, 1, 1.3)
	match bt:
		"coach":
			_acc("head", Vector3(0.36, 0.1, 0.36), Color8(154, 20, 24), Vector3(0, 0.29, -0.01))
			_acc("head", Vector3(0.3, 0.03, 0.14), Color8(154, 20, 24), Vector3(0, 0.25, 0.19))
			_acc("spine", Vector3(0.05, 0.04, 0.06), Color8(200, 176, 64), Vector3(0, 0.4, 0.2), false)
		"principal":
			_acc("head", Vector3(0.27, 0.05, 0.03), Color8(14, 14, 14), Vector3(0, 0.21, 0.175))
			var pd := _acc("armR2", Vector3(0.1, 0.55, 0.03), Color8(120, 80, 44), Vector3(0, -0.62, 0.06), false)
			pd.rotation.x = 0.3
		"lunch":
			_acc("head", Vector3(0.42, 0.16, 0.4), Color8(230, 226, 214), Vector3(0, 0.27, -0.02))   # hairnet
			_acc("armR2", Vector3(0.04, 0.5, 0.04), Color8(170, 170, 176), Vector3(0, -0.5, 0.05), false)   # ladle
			_acc("armR2", Vector3(0.16, 0.08, 0.16), Color8(170, 170, 176), Vector3(0, -0.76, 0.08), false)
		"chem":
			_acc("head", Vector3(0.25, 0.07, 0.04), Color8(74, 208, 96), Vector3(0, 0.215, 0.178), true, true)
			_acc("head", Vector3(0.4, 0.14, 0.38), Color8(184, 180, 172), Vector3(0, 0.3, -0.03))
			flask_node = MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.05
			cm.bottom_radius = 0.08
			cm.height = 0.2
			cm.radial_segments = 6
			flask_node.mesh = cm
			var fm := StandardMaterial3D.new()
			fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fm.albedo_color = Color8(122, 255, 90)
			flask_node.material_override = fm
			flask_node.position = Vector3(0, -0.5, 0.04)
			joints["armR2"].add_child(flask_node)
	var cap: CapsuleShape3D = shape.shape
	cap.radius = 0.32 * minf(bscale, 1.6)
	cap.height = 1.7 * bscale
	shape.position.y = 0.85 * bscale
	lean = 0.3 if bt == "coach" else (0.06 if bt == "principal" else (0.22 if bt == "lunch" else 0.15))

## school-themed hats. They pop off with a "ploink" when you shoot them in the head.
func _hm(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m

func _hpart(p: Node3D, size: Vector3, c: Color, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = _hm(c)
	m.position = pos
	p.add_child(m)
	return m

func _hat(style: String) -> void:
	hat = MeshInstance3D.new()
	var b := BoxMesh.new()
	match style:
		"grad":       # graduation mortarboard with a gold tassel
			b.size = Vector3(0.32, 0.09, 0.32)
			hat.material_override = _hm(Color8(22, 22, 26))
			hat.position = Vector3(0, 0.29, 0)
			var board := _hpart(hat, Vector3(0.5, 0.025, 0.5), Color8(22, 22, 26), Vector3(0, 0.055, 0))
			board.rotation.y = PI / 4
			_hpart(hat, Vector3(0.03, 0.03, 0.03), Color8(230, 190, 60), Vector3(0, 0.08, 0))
			_hpart(hat, Vector3(0.02, 0.16, 0.02), Color8(230, 190, 60), Vector3(0.22, -0.02, 0.1))
		"helmet":     # football helmet, team red with a white stripe and a face mask
			b.size = Vector3(0.42, 0.24, 0.44)
			var team: Color = [Color8(150, 24, 30), Color8(28, 52, 130), Color8(220, 160, 30)][randi() % 3]
			hat.material_override = _hm(team)
			hat.position = Vector3(0, 0.26, -0.01)
			_hpart(hat, Vector3(0.06, 0.245, 0.45), Color8(235, 235, 235), Vector3(0, 0.002, 0))
			_hpart(hat, Vector3(0.06, 0.26, 0.3), team, Vector3(-0.21, -0.12, -0.04))
			_hpart(hat, Vector3(0.06, 0.26, 0.3), team, Vector3(0.21, -0.12, -0.04))
			for y in [-0.14, -0.22]:
				_hpart(hat, Vector3(0.36, 0.025, 0.025), Color8(170, 170, 175), Vector3(0, y, 0.24))
			_hpart(hat, Vector3(0.025, 0.12, 0.025), Color8(170, 170, 175), Vector3(0, -0.18, 0.24))
		"beanie":     # propeller beanie: four coloured panels and a spinning prop
			b.size = Vector3(0.36, 0.1, 0.36)
			hat.material_override = _hm(Color8(220, 40, 40))
			hat.position = Vector3(0, 0.28, 0)
			_hpart(hat, Vector3(0.18, 0.102, 0.18), Color8(40, 90, 220), Vector3(0.09, 0, 0.09))
			_hpart(hat, Vector3(0.18, 0.102, 0.18), Color8(240, 210, 40), Vector3(-0.09, 0, -0.09))
			_hpart(hat, Vector3(0.025, 0.08, 0.025), Color8(60, 60, 60), Vector3(0, 0.09, 0))
			prop_blade = Node3D.new()
			prop_blade.position = Vector3(0, 0.13, 0)
			hat.add_child(prop_blade)
			_hpart(prop_blade, Vector3(0.36, 0.012, 0.05), Color8(60, 200, 80), Vector3.ZERO)
			_hpart(prop_blade, Vector3(0.05, 0.012, 0.36), Color8(240, 120, 30), Vector3.ZERO)
		"dunce":      # a tall paper dunce cap
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = 0.17
			cm.height = 0.55
			cm.radial_segments = 8
			hat.mesh = cm
			hat.material_override = _hm(Color8(236, 230, 210))
			hat.position = Vector3(0, 0.5, 0)
			hat.rotation.z = randf_range(-0.2, 0.2)
			var band := MeshInstance3D.new()
			var bc := CylinderMesh.new()
			bc.top_radius = 0.15
			bc.bottom_radius = 0.17
			bc.height = 0.05
			bc.radial_segments = 8
			band.mesh = bc
			band.material_override = _hm(Color8(40, 40, 40))
			band.position = Vector3(0, -0.24, 0)
			hat.add_child(band)
		_:            # lunch-lady hairnet
			b.size = Vector3(0.41, 0.15, 0.4)
			var nm := _hm(Color8(236, 232, 220))
			nm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			nm.albedo_color.a = 0.75
			hat.material_override = nm
			hat.position = Vector3(0, 0.27, -0.02)
	if hat.mesh == null:
		hat.mesh = b
	joints["head"].add_child(hat)
	meshes.append({"n": hat, "joint": "head", "head": true, "armor": false})

## Snow Day
func freeze(dur: float) -> void:
	if not alive:
		return
	freeze_t = dur
	tint_mat = game.ice_mat
	_overlay(false)

func fire_drill(dur: float) -> void:
	if not alive or kind == "boss":
		return
	flee_t = dur
	sdir = -1.0 if randf() < 0.5 else 1.0

## a headshot sends the hat flying
func _pop_hat(dir: Vector3) -> void:
	if hat == null or not is_instance_valid(hat):
		hat = null
		return
	var h := hat
	hat = null
	prop_blade = null
	meshes = meshes.filter(func(e): return e.n != h)
	var at: Vector3 = h.global_position
	game.physics.gib(h, Vector3(dir.x * 2.5, 0, dir.z * 2.5) + Vector3(randf_range(-1.5, 1.5), randf_range(7, 9.5), randf_range(-1.5, 1.5)), false)
	game.audio.play("ploink", at, 2, randf_range(0.9, 1.15))
	game.fx.burst(at, Vector3.UP, 6, Color(1, 1, 1), 3.0, 0.05, 0.4)

## the Hall Monitor Kid: small, quick, sash and whistle. He calls the whole horde on you.
func _dress_monitor() -> void:
	vis.scale = Vector3.ONE * 0.82
	var sash := _acc("spine", Vector3(0.09, 0.8, 0.4), Color8(240, 140, 30), Vector3(0, 0.3, 0), false)
	sash.rotation.z = 0.65
	_acc("spine", Vector3(0.12, 0.05, 0.05), Color8(240, 230, 120), Vector3(0.1, 0.42, 0.19), false)  # badge
	_acc("head", Vector3(0.05, 0.035, 0.08), Color8(200, 200, 205), Vector3(0, 0.12, 0.2))            # whistle
	_acc("head", Vector3(0.38, 0.08, 0.38), Color8(240, 140, 30), Vector3(0, 0.28, 0))                  # cap
	_acc("head", Vector3(0.3, 0.03, 0.14), Color8(240, 140, 30), Vector3(0, 0.25, 0.2))
	arm_style = "one"
	pitch = randf_range(1.3, 1.5)

func _blow_whistle(p) -> void:
	whistle_cd = randf_range(8.0, 11.0)
	spit_anim = 0.8
	stagger = 0.8
	var hp_at: Vector3 = joints["head"].global_position
	game.audio.play("whistle", hp_at, 6, randf_range(0.95, 1.05))
	game.fx.puff(hp_at + Vector3(0, 0.1, 0), Color8(240, 240, 230), false, 0.05, 0.25, 0.4, 0.4, 0.02, 0.6)
	var n := 0
	for o in game.zombies:
		if o != self and o.alive and o.global_position.distance_to(global_position) < 24:
			o.rush_t = 5.0
			o.nav_force = 0.0
			o.repath = 0.0
			n += 1
	if n > 0:
		game.hud.callout_small("HALL MONITOR!")

func _stats(w: int) -> void:
	var walk: float = minf(2.2 + w * 0.16, 5.2) * randf_range(0.85, 1.15)
	hp = 40 + w * 9
	speed = walk
	dmg = 20 + w * 0.8
	match kind:
		"runner":
			hp = 20 + w * 4
			speed = minf(5.2 + w * 0.12, 7.6) * randf_range(0.85, 1.15)
			dmg = 12 + w * 0.5
		"bloater":
			hp = (40 + w * 9) * 1.5
			speed = walk * 0.55
			dmg = 26 + w
		"armored":
			hp = (40 + w * 9) * 1.15
			helmet_hp = 60 + w * 10
			vest_hp = 90 + w * 12
		"spitter":
			hp = (40 + w * 9) * 0.9
			speed = walk * 0.85
			dmg = 14 + w * 0.5
		"monitor":
			hp = 25 + w * 5
			speed = minf(4.6 + w * 0.1, 6.5) * randf_range(0.9, 1.1)
			dmg = 10 + w * 0.4
		"boss":
			match bt:
				"lunch":
					hp = 1600 + w * 130
					speed = minf(1.8 + w * 0.03, 2.6)
					dmg = 34
				"principal":
					hp = 900 + w * 80
					speed = minf(1.9 + w * 0.03, 2.6)
					dmg = 30
				"chem":
					hp = 1000 + w * 90
					speed = minf(2.5 + w * 0.04, 3.3)
					dmg = 22
				_:
					hp = 1400 + w * 120
					speed = minf(1.7 + w * 0.04, 3.0)
					dmg = 40
	if kind == "boss":
		hp *= 1.2
	max_hp = hp

func _box(joint: String, pos: Vector3, size: Vector3, zone: String) -> void:
	var a := Area3D.new()
	a.collision_layer = HITBOX
	a.collision_mask = 0
	a.monitoring = false
	a.monitorable = false
	a.set_meta("zombie", self)
	a.set_meta("zone", zone)
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	a.add_child(cs)
	a.position = pos
	joints[joint].add_child(a)
	boxes.append(a)

func _hitboxes() -> void:
	var fat := 1.5 if kind == "bloater" else 1.0
	_box("head", Vector3(0, 0.18, 0.02), Vector3(0.36, 0.42, 0.38) * (1.15 if kind == "armored" else 1.0), "head")
	_box("spine", Vector3(0, 0.3, 0), Vector3(0.5 * fat, 0.64, 0.34 * fat), "body")
	_box("core", Vector3(0, 0, 0), Vector3(0.42 * fat, 0.26, 0.3 * fat), "body")
	for s in ["L", "R"]:
		_box("arm%s1" % s, Vector3(0, -0.17, 0), Vector3(0.16, 0.38, 0.16), "arm" + s)
		_box("arm%s2" % s, Vector3(0, -0.24, 0), Vector3(0.15, 0.5, 0.15), "arm" + s)
		_box("leg%s1" % s, Vector3(0, -0.22, 0), Vector3(0.21, 0.46, 0.21), "leg")
		_box("leg%s2" % s, Vector3(0, -0.25, 0), Vector3(0.18, 0.52, 0.18), "leg")

# ---------------------------------------------------------------- damage
func damage(amount: float, zone: String, dir: Vector3, power: float, blast := false, at = null) -> Dictionary:
	if not alive:
		return {"kill": false, "head": false}
	var head := zone == "head"
	if kind == "armored":
		if head and helmet_hp > 0 and not blast:
			helmet_hp -= amount * 2.2
			flinch = 1.0
			fzone = "head"
			var hp_at: Vector3 = at if at != null else joints["head"].global_position
			game.fx.spray(hp_at, -dir, Color8(255, 208, 112), 6, 5, 0.35, false, 0.03)
			game.audio.play("clang", hp_at, -2)
			if helmet_hp <= 0:
				_drop(func(e): return e.armor and e.joint == "head", Vector3.UP, 5.0)
				game.audio.play("armorBreak", global_position + Vector3(0, 1.7, 0))
			return {"kill": false, "head": false, "armor": true}
		if not head and vest_hp > 0 and zone == "body" and not blast:
			vest_hp -= amount
			var vp: Vector3 = at if at != null else global_position + Vector3(0, 1.2, 0)
			game.fx.spray(vp, -dir, Color8(255, 208, 112), 4, 4, 0.35, false, 0.03)
			game.audio.play("clang", vp, -4, 0.85)
			if vest_hp <= 0:
				_drop(func(e): return e.armor and e.joint != "head", dir, 4.0)
				game.audio.play("armorBreak", vp)
			amount *= 0.25
		if blast:
			amount *= 0.6
	if head and not blast:
		amount *= 2.2
		if hat != null:
			_pop_hat(dir)
	if kind == "boss" and blast:
		amount *= 0.5
	hp -= amount
	flash_t = 0.08
	var kb := (1.4 if blast else (0.8 if power > 5 else 0.35)) * (0.15 if kind == "boss" else 1.0)
	velocity += Vector3(dir.x, 0, dir.z).normalized() * kb * 6.0
	stagger = (0.5 if blast else (0.35 if power > 5 else 0.18)) * (0.0 if kind == "boss" else 1.0)
	flinch = 1.0
	fside = -1.0 if randf() < 0.5 else 1.0
	fzone = "head" if head else ("leg" if zone == "leg" else "body")
	if fzone == "leg" and not blast and not crawler and kind != "boss":
		stagger = maxf(stagger, 0.45)
	if hp <= 0:
		_kill(head, dir, power, blast)
		return {"kill": true, "head": head}
	if kind == "boss":
		return {"kill": false, "head": head}
	if (zone == "armL" or zone == "armR") and not lost.has(zone) and randf() < 0.35:
		_sever(zone, dir)
	if not crawler and kind != "bloater" and hp < max_hp * 0.6 and randf() < (0.6 if blast else (0.25 if kind == "runner" else 0.4)) * (1.0 if power >= 5 or blast else 0.5):
		_make_crawler(dir)
	return {"kill": false, "head": head}

func _drop(pred: Callable, dir: Vector3, power: float) -> void:
	var keep: Array = []
	for e in meshes:
		if pred.call(e):
			if is_instance_valid(e.n):
				game.physics.gib(e.n, dir * power * randf_range(0.5, 1.2) + Vector3(randf_range(-2, 2), randf_range(3, 6), randf_range(-2, 2)), not e.armor)
		else:
			keep.append(e)
	meshes = keep

func _remove_boxes(pred: Callable) -> void:
	var keep: Array = []
	for b in boxes:
		if pred.call(b):
			b.queue_free()
		else:
			keep.append(b)
	boxes = keep

func _sever(zone: String, dir: Vector3) -> void:
	lost[zone] = true
	var s := zone.substr(3, 1)
	var sp: Vector3 = joints["arm%s1" % s].global_position
	_drop(func(e): return e.joint == "arm%s1" % s or e.joint == "arm%s2" % s, dir, 4.0)
	_remove_boxes(func(b): return b.get_meta("zone") == zone)
	game.fx.blood(sp, Vector3.UP, true)
	game.audio.play("crunch", sp)

func _make_crawler(dir: Vector3) -> void:
	crawler = true
	_drop(func(e): return e.joint.begins_with("leg"), dir, 3.0)
	_remove_boxes(func(b): return b.get_meta("zone") == "leg")
	var hip := global_position + Vector3(0, 0.8, 0)
	game.fx.blood(hip, Vector3.UP, true)
	game.fx.splat(global_position, 1.4)
	game.audio.play("crunch", hip)
	speed = randf_range(0.8, 1.25)
	dmg = 12 + game.wave * 0.5
	stagger = 0.6
	var cap: CapsuleShape3D = shape.shape
	cap.height = 0.7
	cap.radius = 0.3
	shape.position.y = 0.35

func _kill(head: bool, dir: Vector3, power: float, blast: bool) -> void:
	alive = false
	collision_layer = 0
	_remove_boxes(func(_b): return true)
	for e in meshes:
		if is_instance_valid(e.n) and e.n.get_parent() == joints["head"] and e.n.mesh is BoxMesh:
			e.n.visible = false            # eyes go dark
	var c := global_position + Vector3(0, 0.4 if crawler else (1.8 if head else 1.2), 0)
	game.on_zombie_killed(self, head, blast)
	game.fx.splat(global_position + Vector3(0, 0.2, 0), randf_range(1.8, 2.9))
	for i in 3:
		game.fx.splat(global_position + Vector3(randf_range(-1.4, 1.4), 0.2, randf_range(-1.4, 1.4)), randf_range(0.3, 0.7))
	var full := blast or power >= 7 or kind == "bloater" or kind == "boss"
	if kind == "boss":
		game.boss_down(self)
	if kind == "bloater":
		game.bloater_burst(global_position + Vector3(0, 1.1, 0))
	if kind == "spitter":
		game.acid_puddle(global_position)
	if full:
		_drop(func(_e): return true, dir, power * 1.3)
		game.fx.blood(c, dir, true)
		game.fx.blood(c, Vector3.UP, true)
		game.fx.gib_bits(c, dir)
		game.audio.play("crunch", c)
		queue_free()
		return
	if head:
		_drop(func(e): return e.head or e.joint == "head", Vector3.UP, power)
		game.fx.blood(c, Vector3.UP, true)
		game.fx.gib_bits(c, Vector3.UP)
		game.audio.play("head", c)
	else:
		game.fx.spray(c, dir, Color8(122, 10, 10), 22, 5, 1.1, true)
		game.fx.spray(c, Vector3.UP, Color8(74, 5, 5), 6, 2, 1.8, true)
		game.fx.wall_splat(c, dir, randf_range(0.9, 1.6))
	game.physics.bloody(global_position, 1.5)
	# real ragdoll: the body tumbles, folds over desks and gets thrown by blasts
	game.physics.ragdoll(self, dir, power, head, blast)
	queue_free()
	return

# ---------------------------------------------------------------- per frame
func _physics_process(dt: float) -> void:
	if not alive:
		_corpse(dt)
		return
	t += dt
	cd -= dt
	if prop_blade != null and is_instance_valid(prop_blade):
		prop_blade.rotation.y += dt * (18.0 + velocity.length() * 4.0)
	spit_cd -= dt
	whistle_cd -= dt
	stagger -= dt
	flinch = maxf(0.0, flinch - dt * 5)
	lunge = maxf(0.0, lunge - dt * 4)
	spit_anim = maxf(0.0, spit_anim - dt)
	if flash_t > 0:
		flash_t -= dt
		_overlay(flash_t > 0)
	# wounded zombies drip
	if hp < max_hp * 0.7 and emerge <= 0 and randf() < dt * (9.0 if hp < max_hp * 0.35 else 4.0):
		game.fx.spray(global_position + Vector3(randf_range(-0.18, 0.18), 0.35 if crawler else randf_range(0.7, 1.3), randf_range(-0.18, 0.18)), Vector3.UP, Color8(106, 8, 8), 1, 0.3, 0.8, true, 0.03, 0.2)
	var p = game.player
	var want := Vector3.ZERO
	zap_t = maxf(0.0, zap_t - dt)
	# Snow Day: frozen solid (still shootable)
	if freeze_t > 0.0:
		freeze_t -= dt
		if freeze_t <= 0.0:
			tint_mat = null
			_overlay(false)
			game.fx.burst(global_position + Vector3(0, 1.2, 0), Vector3.UP, 6, Color(0.8, 0.9, 1.0), 2.5, 0.05, 0.5)
		velocity.x = 0
		velocity.z = 0
		velocity.y -= GRAVITY * dt
		move_and_slide()
		return
	flee_t = maxf(0.0, flee_t - dt)
	if emerge > 0:
		emerge -= dt
	elif p and not p.dead and flee_t > 0.0:
		# Fire Drill: single file, away from the student
		var away: Vector3 = global_position - p.global_position
		away.y = 0
		want = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
		if is_on_wall():
			var n := get_wall_normal()
			n.y = 0
			want = (want + n.normalized().cross(Vector3.UP) * sdir).normalized()
	elif p and not p.dead and kind == "boss" and (hold_t > 0.0 or charge_t > 0.0):
		# boss moves: a wind-up, then the Coach's charge or the Lunch Lady's ground pound
		var to2: Vector3 = p.global_position - global_position
		if hold_t > 0.0:
			hold_t -= dt
			_face(to2)
			lunge = maxf(lunge, 0.8)
			if hold_t <= 0.0:
				if charge_pending:
					charge_pending = false
					charge_t = 1.25
					charge_dir = Vector3(to2.x, 0, to2.z).normalized()
				if pound_pending:
					pound_pending = false
					game.bosses.pound(self)
		else:
			charge_t -= dt
			want = charge_dir
			rush_t = maxf(rush_t, 0.1)
			if randf() < dt * 20:
				game.fx.puff(global_position + Vector3(0, 0.2, 0), Color8(120, 110, 95), false, 0.2, 0.7, 0.5, 0.2, 0.2, 0.6)
			if Vector2(to2.x, to2.z).length() < reach + 0.4 and absf(to2.y) < 2.0:
				charge_t = 0.0
				p.velocity += charge_dir * 20.0 + Vector3(0, 6, 0)
				p.hurt(dmg * 1.1)
				game.bosses.event(self, "hit")
				game.audio.play("kickHit", p.global_position, 6, 0.6)
			elif is_on_wall() and charge_t < 1.1:
				charge_t = 0.0
				stagger = 1.2
				game.audio.play("slam", global_position + Vector3(0, 1.5, 0), 4, 0.7)
				p.shake = maxf(p.shake, 0.3)
				game.hud.callout_small("COACH HIT THE WALL")
	elif p and not p.dead:
		var to: Vector3 = p.global_position - global_position
		var dist := Vector2(to.x, to.z).length()
		var dy := absf(to.y)
		var rch := reach * (0.9 if crawler else 1.0)
		var bmode := _boss_brain(dt, p, dist) if kind == "boss" and game.state == "play" else 0
		if dist < rch and dy < 1.2 * maxf(bscale, 1.0):
			_face(to)
			if cd <= 0:
				cd = 1.1 if crawler else 0.9
				lunge = 1.0
				get_tree().create_timer(0.22).timeout.connect(func():
					if alive and is_instance_valid(p) and global_position.distance_to(p.global_position) < rch + 0.5:
						if kind == "boss":
							var away: Vector3 = p.global_position - global_position
							away.y = 0
							p.velocity += away.normalized() * 14.0 + Vector3(0, 2, 0)
							game.bosses.event(self, "hit")
						p.hurt(dmg))
		elif bmode == 1:
			_face(to)
			want = -Vector3(to.x, 0, to.z).normalized()
		elif bmode == 2:
			_face(to)
			want = Vector3(to.x, 0, to.z).normalized().cross(Vector3.UP) * sdir
		elif kind == "monitor" and dist < 20 and whistle_cd <= 0 and _los(p):
			_face(to)
			_blow_whistle(p)
		elif kind == "spitter" and not crawler and dist < 21 and dist > 4.5 and spit_cd <= 0 and _los(p):
			spit_cd = randf_range(3.5, 5.0)
			spit_anim = 0.6
			_face(to)
			get_tree().create_timer(0.55).timeout.connect(func():
				if alive and is_instance_valid(p):
					game.spit(joints["head"].global_position, p))
		elif kind == "spitter" and not crawler and dist < 11 and _los(p):
			_face(to)
			want = global_transform.basis.x * sin(t * 0.8 + pitch * 10.0) * 0.5
		else:
			want = _nav_dir(p, dist, dy)
	rush_t = maxf(0.0, rush_t - dt)
	slow_t = maxf(0.0, slow_t - dt)
	var spd := speed * (0.25 if stagger > 0 else 1.0) * (1.75 if rush_t > 0 else 1.0) * (2.2 if charge_t > 0 else 1.0) * (0.35 if slow_t > 0 else 1.0) * (1.5 if enraged else 1.0)
	# elbow room so the horde doesn't melt into one body (also while standing and swinging)
	var steer := want
	var push := Vector3.ZERO
	var room := 0.8 * maxf(bscale, 1.0)
	for o in game.zombies:
		if o == self or not o.alive or o.freeze_t > 0:
			continue
		var d: Vector3 = global_position - o.global_position
		if absf(d.y) > 1.5:
			continue
		d.y = 0
		var l := d.length()
		var r2: float = room + 0.8 * (maxf(o.bscale, 1.0) - 1.0)
		if l < r2:
			push += (d / l if l > 0.001 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()) * (r2 - l) / r2
	if push.length() > 0.01:
		want = (want + push * 2.2).limit_length(1.0)
	velocity.x = move_toward(velocity.x, want.x * spd, 20.0 * dt)
	velocity.z = move_toward(velocity.z, want.z * spd, 20.0 * dt)
	velocity.y -= GRAVITY * dt
	var hv := Vector3(velocity.x, 0, velocity.z)
	move_and_slide()
	if is_on_floor() and is_on_wall() and hv.length() > 0.3:
		var up := Vector3(0, 0.5, 0)
		var fwd := hv.normalized() * 0.12
		if not test_move(global_transform, up) and not test_move(global_transform.translated(up), fwd):
			global_position += up + fwd
	moving = Vector2(velocity.x, velocity.z).length() > 0.3
	if want.length() > 0.1:
		if steer.length() > 0.1:
			_face(steer)
		cyc += dt * speed * (3.2 if crawler else (2.4 if moving else 0.8)) / maxf(bscale * 0.8, 1.0)
		if kind == "boss":
			var ph := int(floor(cyc / PI))
			if ph != step_ph and moving:
				step_ph = ph
				var pdist: float = global_position.distance_to(p.global_position) if p else 99.0
				game.audio.play("thud", global_position, 0, 0.6)
				p.shake = maxf(p.shake, 0.12 * clampf(1.0 - pdist / 16.0, 0, 1))
	# snagged on a wall: follow the navmesh for a while, and sidestep along the wall if that's not enough
	nav_force = maxf(0.0, nav_force - dt)
	side_t = maxf(0.0, side_t - dt)
	if is_on_wall() and want.length() > 0.1 and stagger <= 0:
		nav_force = 2.0
		var n := get_wall_normal()
		n.y = 0
		if n.length() > 0.1 and want.normalized().dot(-n.normalized()) > 0.85 and side_t <= 0 and Vector2(velocity.x, velocity.z).length() < speed * 0.3:
			var side := n.normalized().cross(Vector3.UP)
			side_dir = side if randf() < 0.5 else -side
			side_t = 0.6
	prog_t += dt
	if prog_t > 0.5:
		prog_t = 0
		if want.length() > 0.1 and stagger <= 0 and global_position.distance_to(prog_pos) < 0.2 * speed:
			nav_force = 2.0
			if side_t <= 0:
				var a := randf() * TAU
				side_dir = Vector3(cos(a), 0, sin(a))
				side_t = 0.5
		prog_pos = global_position
	# really stuck: come back somewhere sensible
	check_t += dt
	if check_t > 1.0:
		check_t = 0
		if want.length() > 0.1 and global_position.distance_to(last_pos) < 0.3:
			stuck += 1
			if stuck >= 5:
				stuck = 0
				game.respawn_near(self)
		else:
			stuck = 0
		last_pos = global_position
	if global_position.y < -10:
		game.respawn_near(self)
	# voice
	voice_t -= dt
	if voice_t <= 0:
		voice_t = randf_range(2.5, 7.0)
		if p and global_position.distance_to(p.global_position) < 35:
			var r := randf()
			var nm := "z_%s_%s" % [vtype, "moan" if r < 0.5 else ("grunt" if r < 0.8 else "stutter")]
			if kind == "spitter" and r < 0.3:
				nm = "z_hiss"
			elif kind == "runner" and r < 0.25:
				nm = "z_shriek"
			game.audio.play(nm, global_position + Vector3(0, 1.6, 0), -2, pitch)
	_pose(dt)

## the Principal and the Chemistry Teacher keep their distance and fight with tricks; the Coach just charges
func _boss_brain(dt: float, p, dist: float) -> int:
	sdir_t -= dt
	if sdir_t <= 0:
		sdir_t = randf_range(1.6, 3.0)
		sdir = -1.0 if randf() < 0.5 else 1.0
	var see := _los(p)
	game.bosses.brain(self, dt, p, dist, see)
	if bt == "coach":
		return 0
	if bt == "lunch":
		var near_kitchen := global_position.distance_to(KITCHEN) < 9.0
		if near_kitchen and not enraged:
			enraged = true
			game.hud.banner("", "SHE'S PROTECTING THE KITCHEN", 1.8)
			game.audio.play("z_deep_moan", global_position + Vector3(0, 2.5, 0), 6, 0.45)
		elif not near_kitchen and not always_enraged:
			enraged = false
		var rate := 2.0 if enraged else 1.0
		th_t -= dt * rate
		tray_t -= dt * rate
		if th_t <= 0 and dist > 3 and dist < 22 and see:
			th_t = randf_range(2.2, 3.2)
			lunge = 1.0
			game.lob_gravy(self)
		if tray_t <= 0 and dist > 2.5 and dist < 18 and see:
			tray_t = randf_range(4.0, 5.5)
			lunge = 1.0
			game.throw_tray(self)
		return 2 if see and dist > 6 and dist < 12 and not enraged else 0
	if bt == "chem":
		th_t -= dt
		if th_t <= 0.45 and th_t + dt > 0.45 and flask_node:
			flask_node.material_override.albedo_color = Color8(255, 90, 224) if throw_n % 3 == 2 else Color8(122, 255, 90)
		if th_t <= 0 and dist > 2.5 and dist < 26 and see:
			th_t = randf_range(1.7, 2.6)
			throw_n += 1
			lunge = 1.0
			game.throw_flask(self, throw_n % 3 == 0)
			if phase == 2:
				get_tree().create_timer(0.3).timeout.connect(func():
					if alive:
						game.throw_flask(self, false, false, true))
			if flask_node:
				flask_node.visible = false
				get_tree().create_timer(0.7).timeout.connect(func():
					if is_instance_valid(flask_node):
						flask_node.visible = true
						flask_node.material_override.albedo_color = Color8(122, 255, 90))
		elif th_t <= 0:
			th_t = 0.3
		if not see:
			return 0
		return 1 if dist < 8 else (2 if dist < 13 else 0)
	ab_t -= dt
	if ab_t <= 0:
		ab_t = randf_range(7.5, 10.5)
		game.principal_ability(self)
	if not see:
		return 0
	return 1 if dist < 5.5 else (2 if dist < 10 else 0)

func _face(d: Vector3) -> void:
	if Vector2(d.x, d.z).length() < 0.01:
		return
	var target := atan2(-d.x, -d.z)
	rotation.y = lerp_angle(rotation.y, target, 0.25)

func _los(p) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.4, 0), p.global_position + Vector3(0, 1.4, 0), WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

## a body-wide line of sight: rays from both shoulders and the knees, so a clear view over a desk
## doesn't send the zombie grinding into it
func _clear_path(p) -> bool:
	var space := get_world_3d().direct_space_state
	var a := global_position
	var b: Vector3 = p.global_position
	var side := (b - a)
	side.y = 0
	side = side.normalized().cross(Vector3.UP) * 0.3
	for o in [Vector3(0, 0.45, 0) + side, Vector3(0, 0.45, 0) - side, Vector3(0, 1.3, 0)]:
		var q := PhysicsRayQueryParameters3D.create(a + o, b + o, WORLD)
		if not space.intersect_ray(q).is_empty():
			return false
	return true

func _nav_dir(p, dist: float, dy: float) -> Vector3:
	var dt := get_physics_process_delta_time()
	var to: Vector3 = p.global_position - global_position
	if side_t > 0:
		return side_dir
	los_t -= dt
	if los_t <= 0:
		los_t = 0.2
		los_ok = dist < 25 and dy < 1.0 and _clear_path(p)
	if los_ok and (nav_force <= 0 or dist < 2.5):
		return Vector3(to.x, 0, to.z).normalized()
	repath -= dt
	if repath <= 0:
		repath = 0.3
		agent.target_position = p.global_position
	if agent.is_navigation_finished():
		return Vector3(to.x, 0, to.z).normalized()
	var nxt := agent.get_next_path_position()
	var d := nxt - global_position
	d.y = 0
	if d.length() < 0.05:
		return Vector3(to.x, 0, to.z).normalized()
	return d.normalized()

func _overlay(on: bool) -> void:
	var rest = tint_mat if tint_mat != null else game.skin_overlay()
	for e in meshes:
		if is_instance_valid(e.n):
			if e.n.mesh is BoxMesh and e.joint == "head" and e.n.material_override == game.eye_mat:
				continue
			e.n.material_overlay = game.hit_mat if on else rest

# the web game's animEnemy
func _pose(dt: float) -> void:
	var P := {}
	for k in joints:
		P[k] = Vector3.ZERO
	var py := 0.0
	var c := cyc
	var s := sin(c)
	var em := 0.0
	if crawler:
		var a := 0.45 if moving else 0.1
		P.armL1 = Vector3(PI - 0.35 + s * a, 0, 0.15)
		P.armR1 = Vector3(PI - 0.35 - s * a, 0, -0.15)
		P.armL2 = Vector3(-0.5 - maxf(0, s) * 0.6, 0, 0)
		P.armR2 = Vector3(-0.5 - maxf(0, -s) * 0.6, 0, 0)
		P.core = Vector3(PI / 2 - 0.12, 0, s * 0.08)
		py = 0.24 - 0.95 + absf(s) * 0.03
		P.head = Vector3(-1.15 + sin(t * 1.7) * 0.1 - flinch * 0.9, 0, tilt)
	else:
		var fast := kind == "runner"
		var amp := (0.85 if fast else 0.5) if moving else 0.04
		P.legL1 = Vector3(s * amp, 0, 0)
		P.legR1 = Vector3(-s * amp, 0, 0)
		P.legL2 = Vector3(maxf(0, -cos(c)) * amp * 1.4, 0, 0)
		P.legR2 = Vector3(maxf(0, cos(c)) * amp * 1.4, 0, 0)
		py = absf(cos(c)) * 0.04 * (1.0 if moving else 0.0)
		P.core = Vector3(0, s * 0.12, sin(c * 0.5) * sway)
		P.spine = Vector3(lean + lunge * 0.35, 0, 0)
		var L := lunge * 0.6
		if arm_style == "run":
			P.armL1 = Vector3(-s * 1.0, 0, 0)
			P.armR1 = Vector3(s * 1.0, 0, 0)
			P.armL2 = Vector3(-1.1, 0, 0)
			P.armR2 = Vector3(-1.1, 0, 0)
		else:
			var rl := arm_style == "reach" or arm_style == "one"
			var rr := arm_style == "reach" or lunge > 0.1
			P.armL1 = Vector3(-1.35 + sin(t * 4) * 0.15 - L if rl else -s * 0.35 * amp + 0.1, 0, 0.0 if rl else -0.08)
			P.armR1 = Vector3(-1.45 + cos(t * 3.3) * 0.15 - L if rr else s * 0.35 * amp + 0.1, 0, 0.0 if rr else 0.08)
			P.armL2 = Vector3(-0.2 if rl else -0.35, 0, 0)
			P.armR2 = Vector3(-0.2 if rr else -0.3, 0, 0)
		P.head = Vector3(sin(t * 1.3) * 0.06 - 0.1, 0, tilt + sin(t * 0.9) * 0.05)
		if spit_anim > 0:
			P.head.x += sin((0.6 - spit_anim) / 0.6 * PI) * 0.8
		if emerge > 0:
			var k := 1.0 - clampf(emerge / 1.3, 0, 1)
			em = -(1.0 - k) * (1.0 - k) * 2.0
			P.armL1 = Vector3(-2.8 + sin(t * 7) * 0.25, 0, 0)
			P.armR1 = Vector3(-2.7 + cos(t * 6) * 0.25, 0, 0)
			P.armL2 = Vector3(-0.3, 0, 0)
			P.armR2 = Vector3(-0.3, 0, 0)
		if flinch > 0:
			if fzone == "head":
				P.head.x -= flinch * 0.9
			elif fzone == "body":
				P.spine.x -= flinch * 0.5
				P.core.y += flinch * 0.35 * fside
			else:
				P.core.z += flinch * 0.25 * fside
				py -= flinch * 0.12
				P.spine.x += flinch * 0.3
	for k in joints:
		joints[k].rotation = P[k]
	joints.core.position = rest.core + Vector3(0, py, 0)
	joints.root.position = Vector3(0, em, 0)

func _corpse(dt: float) -> void:
	ct += dt
	if not crawler:
		var k := clampf(ct / 0.6, 0, 1)
		var kk := k * k
		joints.root.rotation = Vector3(-kk * 1.5, 0, 0)
		joints.root.position = Vector3(0, kk * 0.13, 0)
		joints.legL1.rotation = Vector3.ZERO
		joints.legR1.rotation = Vector3.ZERO
		joints.legL2.rotation = Vector3(0.4 * (1 - kk), 0, 0)
		joints.legR2.rotation = Vector3(0.4 * (1 - kk), 0, 0)
		joints.armL1.rotation = Vector3(-2.6 * kk - 0.3, 0, 0.4 * kk)
		joints.armR1.rotation = Vector3(-2.3 * kk - 0.2, 0, -0.5 * kk)
		joints.spine.rotation = Vector3.ZERO
		joints.core.rotation = Vector3.ZERO
		joints.core.position = rest.core - Vector3(0, kk * 0.1, 0)
		joints.head.rotation = Vector3(-0.4 * kk, 0, 0)
	velocity.x = move_toward(velocity.x, 0, dt * 10)
	velocity.z = move_toward(velocity.z, 0, dt * 10)
	if ct > 9:
		vis.position.y -= dt * 0.3
	else:
		velocity.y -= GRAVITY * dt
		move_and_slide()
	if ct > 11:
		queue_free()
