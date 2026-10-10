extends Node3D
## The silly stuff: Snow Day / Fire Drill / Free Period power-ups, the principal's PA announcements
## (every 10 rounds) and the Shock Gate trap between the gym and the parking lot.

var game

# ---------------------------------------------------------------- power-ups
const POWERS := {
	"snow": {"text": "SNOW\nDAY", "col": Color8(170, 220, 255), "light": Color8(140, 200, 255)},
	"drill": {"text": "FIRE\nDRILL", "col": Color8(255, 80, 60), "light": Color8(255, 60, 40)},
	"free": {"text": "FREE\nPERIOD", "col": Color8(120, 255, 140), "light": Color8(90, 255, 120)},
}
var snow_t := 0.0
var drill_t := 0.0
var snow_fx: CPUParticles3D
var tint: ColorRect
var caption: Label
var cap_tween: Tween
var alarm_t := 0.0

# ---------------------------------------------------------------- shock gate
const GATE_A := Vector3(-48.0, 0.0, 6.0)     # the gym -> parking lot doorway, west post
const GATE_B := Vector3(-44.0, 0.0, 6.0)     # east post
const LEVER_POS := Vector3(-42.75, 1.35, 5.62)
const LEVER_SPOT := Vector3(-42.75, 0.0, 4.6)
const GATE_COST := 1000
const GATE_TIME := 30.0
const GATE_COOL := 60.0
var gate_t := 0.0          # > 0 while electrified
var gate_cd := 0.0         # cooldown after
var lever: Node3D
var lamp_mat: StandardMaterial3D
var lamp_light: OmniLight3D
var hum: AudioStreamPlayer3D
var arc_t := 0.0
var hurt_t := 0.0

func setup(g) -> void:
	game = g
	_build_lever()
	_band_room()
	tint = ColorRect.new()
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tint.color = Color(0, 0, 0, 0)
	game.hud.root.add_child(tint)
	game.hud.root.move_child(tint, 0)
	caption = game.hud._label(game.hud.root, game.hud.mono, 26, game.hud.AMBER, Vector2.ZERO, Vector2(10, 10))
	caption.anchor_left = 0.12
	caption.anchor_right = 0.88
	caption.anchor_top = 0.84
	caption.anchor_bottom = 0.84
	caption.offset_bottom = 70
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.modulate.a = 0

func _m(c: Color, glow := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	if glow:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 1.5
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

## the upstairs boiler room doubles as band storage now: music stands, a bass drum, a banner
func _band_room() -> void:
	var root := Node3D.new()
	add_child(root)
	var steel := _m(Color8(40, 40, 44))
	steel.metallic = 0.5
	for i in 5:
		var a := lerpf(-0.9, 0.9, i / 4.0)
		var c := Vector3(15.5 + sin(a) * 3.2, 4.0, -36.0 - cos(a) * 3.2)
		var st := Node3D.new()
		root.add_child(st)
		st.global_position = c
		st.rotation.y = a
		_box(st, Vector3(0.03, 1.1, 0.03), steel, Vector3(0, 0.55, 0))
		var desk := _box(st, Vector3(0.5, 0.36, 0.02), steel, Vector3(0, 1.15, 0.05))
		desk.rotation.x = -0.35
		var sheet := _box(st, Vector3(0.42, 0.3, 0.005), _m(Color8(236, 232, 220)), Vector3(0, 1.16, 0.03))
		sheet.rotation.x = -0.35
		for k in 3:
			_box(st, Vector3(0.02, 0.02, 0.4), steel, Vector3(0, 0.01, 0)).rotation.y = k * PI / 3
		# a chair behind each stand
		var ch := Node3D.new()
		root.add_child(ch)
		ch.global_position = c + Vector3(-sin(a), 0, cos(a)) * -0.9 + Vector3(0, 0, 0)
		ch.rotation.y = a
		var seat := _m(Color8(150, 60, 40))
		_box(ch, Vector3(0.42, 0.04, 0.4), seat, Vector3(0, 0.45, 0))
		_box(ch, Vector3(0.42, 0.4, 0.04), seat, Vector3(0, 0.67, -0.2))
		for lx in [-0.18, 0.18]:
			for lz in [-0.17, 0.17]:
				_box(ch, Vector3(0.03, 0.45, 0.03), steel, Vector3(lx, 0.22, lz))
	# bass drum on its side
	var drum := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.42
	cm.bottom_radius = 0.42
	cm.height = 0.38
	cm.radial_segments = 14
	drum.mesh = cm
	drum.material_override = _m(Color8(150, 24, 30))
	root.add_child(drum)
	drum.global_position = Vector3(20.2, 4.44, -33.4)
	drum.rotation = Vector3(0, 0.4, PI / 2)
	var skin := MeshInstance3D.new()
	var sk := CylinderMesh.new()
	sk.top_radius = 0.39
	sk.bottom_radius = 0.39
	sk.height = 0.385
	sk.radial_segments = 14
	skin.mesh = sk
	skin.material_override = _m(Color8(236, 230, 214))
	drum.add_child(skin)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.8, 0.84, 0.5)
	cs.shape = bs
	body.add_child(cs)
	root.add_child(body)
	body.global_position = Vector3(20.2, 4.42, -33.4)
	body.rotation.y = 0.4
	# banner over the trombone
	var l := Label3D.new()
	l.text = "WESTFIELD MARCHING BAND"
	l.font = load("res://assets/fonts/BlackOpsOne-Regular.ttf")
	l.font_size = 64
	l.pixel_size = 0.005
	l.modulate = Color8(240, 210, 90)
	l.outline_size = 10
	l.outline_modulate = Color8(110, 14, 20)
	root.add_child(l)
	l.global_position = Vector3(15.5, 6.55, -43.6)

## 1-in-80ish: a power-up instead of nothing
func maybe_drop(at: Vector3) -> bool:
	if randf() >= 0.013:
		return false
	var opts: Array = POWERS.keys().filter(func(k):
		for p in game.pickups:
			if p.type == "pw_" + k:
				return false
		return true)
	if opts.is_empty():
		return false
	drop(opts[randi() % opts.size()], at)
	return true

func drop(kind: String, at: Vector3) -> void:
	var def: Dictionary = POWERS[kind]
	var g := Node3D.new()
	var l := Label3D.new()
	l.text = def.text
	l.font = load("res://assets/fonts/BlackOpsOne-Regular.ttf")
	l.font_size = 64
	l.pixel_size = 0.006
	l.modulate = def.col
	l.outline_modulate = Color(0.05, 0.05, 0.08)
	l.outline_size = 16
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	g.add_child(l)
	var o := OmniLight3D.new()
	o.light_color = def.light
	o.omni_range = 4
	o.light_energy = 1.6
	g.add_child(o)
	game.world.add_child(g)
	var y: float = game._floor_y(at)
	g.global_position = Vector3(at.x, y + 0.9, at.z)
	game.pickups.append({"n": g, "type": "pw_" + kind, "life": 15.0, "y": y})
	game.audio.play("x2", g.global_position, -4, 1.6)

func activate(kind: String) -> void:
	match kind:
		"snow":
			snow_t = 5.0
			for z in game.zombies:
				if z.alive:
					z.freeze(5.0)
			game.audio.play("snowday", null, 0)
			game.audio.play("iceCreak", null, -4)
			game.hud.banner("SNOW DAY!", "SCHOOL'S CANCELLED", 2.0)
			_snowfall(true)
		"drill":
			drill_t = 6.0
			alarm_t = 0.0
			for z in game.zombies:
				z.fire_drill(6.0)
			game.hud.banner("FIRE DRILL!", "SINGLE FILE, EVERYBODY", 2.0)
		"free":
			game.player.free_t = 10.0
			var sl = game.player.slots[game.player.cur]
			sl.mag = int(game.player.w().mag)
			game.audio.play("freebell", null, 0)
			game.hud.banner("FREE PERIOD!", "INFINITE AMMO", 2.0)

func _snowfall(on: bool) -> void:
	if snow_fx == null:
		snow_fx = CPUParticles3D.new()
		snow_fx.amount = 420
		snow_fx.lifetime = 2.6
		snow_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		snow_fx.emission_box_extents = Vector3(9, 0.5, 9)
		snow_fx.direction = Vector3(0.2, -1, 0)
		snow_fx.spread = 15
		snow_fx.initial_velocity_min = 2.0
		snow_fx.initial_velocity_max = 3.2
		snow_fx.gravity = Vector3(0, -1.0, 0)
		var qm := QuadMesh.new()
		qm.size = Vector2(0.09, 0.09)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.albedo_color = Color(0.95, 0.97, 1.0)
		qm.material = mat
		snow_fx.mesh = qm
		snow_fx.local_coords = false
		game.player.add_child(snow_fx)
		snow_fx.position = Vector3(0, 4.5, 0)
	snow_fx.emitting = on

# ---------------------------------------------------------------- PA (every 10 rounds)
const PA_LINES := [
	"Attention students. Due to the ongoing zombie situation, Friday's pep rally is now... mandatory.",
	"A reminder that running in the halls is still against the rules. Even from them.",
	"The cafeteria would like you to know that today's mystery meat is no longer a mystery. It is Gary.",
	"Will the student who keeps buying doors with zombie money please report to the office.",
	"Detention for everyone who dies. No exceptions. That means you, Kyle.",
	"Yearbook photos have been moved to never. Please stop asking.",
	"The vending machine is out of order. So is society. Have a great day.",
	"Congratulations to our debate team, who have been eaten. A moment of silence. ...That's enough.",
]
func pa(wave: int) -> void:
	var line: String = PA_LINES[(wave / 10 - 1) % PA_LINES.size()]
	game.audio.play("paChime", null, -2)
	await get_tree().create_timer(1.3).timeout
	if game.state == "over":
		return
	game.audio.play("paVoice", null, -6, 0.95)
	show_caption("PRINCIPAL (PA): " + line, 7.0)
	get_tree().create_timer(3.2).timeout.connect(func():
		if game.state != "over" and line.length() > 70:
			game.audio.play("paVoice", null, -6, 0.9))

func show_caption(text: String, dur: float) -> void:
	caption.text = text
	if cap_tween:
		cap_tween.kill()
	caption.modulate.a = 1.0
	cap_tween = caption.create_tween()
	cap_tween.tween_interval(dur)
	cap_tween.tween_property(caption, "modulate:a", 0.0, 0.6)

# ---------------------------------------------------------------- shock gate
func _build_lever() -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = LEVER_POS
	root.rotation.y = 0.0         # faces -Z, into the gym
	var steel := _m(Color8(90, 94, 100))
	steel.metallic = 0.6
	_box(root, Vector3(0.5, 0.75, 0.08), _m(Color8(200, 170, 40)), Vector3(0, 0, 0))
	_box(root, Vector3(0.44, 0.69, 0.02), _m(Color8(30, 30, 34)), Vector3(0, 0, -0.045))
	# hazard stripes
	for i in 4:
		var s := _box(root, Vector3(0.06, 0.5, 0.01), _m(Color8(20, 20, 20)), Vector3(-0.16 + i * 0.11, -0.52, -0.01))
		s.rotation.z = 0.6
	_box(root, Vector3(0.5, 0.2, 0.03), _m(Color8(220, 190, 40)), Vector3(0, -0.52, 0))
	lever = Node3D.new()
	lever.position = Vector3(0, -0.05, -0.08)
	root.add_child(lever)
	_box(lever, Vector3(0.06, 0.46, 0.06), _m(Color8(200, 200, 205)), Vector3(0, 0.23, 0))
	_box(lever, Vector3(0.2, 0.09, 0.09), _m(Color8(230, 30, 30), true), Vector3(0, 0.47, 0))
	_box(lever, Vector3(0.12, 0.12, 0.08), steel, Vector3(0, 0, 0.02))
	lever.rotation.x = 0.5
	lamp_mat = _m(Color8(40, 200, 60), true)
	var lamp := _box(root, Vector3(0.1, 0.1, 0.06), lamp_mat, Vector3(0.16, 0.26, -0.07))
	lamp_light = OmniLight3D.new()
	lamp_light.omni_range = 1.6
	lamp_light.light_energy = 0.8
	lamp.add_child(lamp_light)
	var l := Label3D.new()
	l.text = "SHOCK GATE"
	l.font = load("res://assets/fonts/BlackOpsOne-Regular.ttf")
	l.font_size = 40
	l.pixel_size = 0.004
	l.modulate = Color8(240, 210, 60)
	l.outline_size = 8
	l.position = Vector3(0, 0.52, -0.05)
	l.rotation.y = PI
	root.add_child(l)
	# the posts either side of the doorway
	for p in [GATE_A, GATE_B]:
		var post := Node3D.new()
		add_child(post)
		post.global_position = p + Vector3(0, 0, -0.42)
		_box(post, Vector3(0.12, 2.8, 0.12), steel, Vector3(0, 1.4, 0))
		for k in 4:
			_box(post, Vector3(0.2, 0.06, 0.2), _m(Color8(200, 120, 60)), Vector3(0, 0.5 + k * 0.6, 0))
	hum = AudioStreamPlayer3D.new()
	hum.bus = "SFX"
	hum.stream = game.audio.stream("gatehum")
	hum.unit_size = 6
	hum.volume_db = -60
	add_child(hum)
	hum.global_position = (GATE_A + GATE_B) / 2.0 + Vector3(0, 1.5, 0)

func gate_open() -> bool:
	return game.world.doors.has("sGymOut") and game.world.doors["sGymOut"].open

func prompt() -> String:
	var d: Vector3 = game.player.global_position - LEVER_SPOT
	if Vector2(d.x, d.z).length() > 1.4 or absf(d.y) > 1.5:
		return ""
	if not game.world.powered:
		return "The shock gate needs power"
	if gate_t > 0:
		return "SHOCK GATE ACTIVE"
	if gate_cd > 0:
		return "Shock gate recharging... %d" % ceili(gate_cd)
	return "Press {use} to activate the shock gate  [%d]" % GATE_COST

func buy() -> void:
	if not game.world.powered or gate_t > 0 or gate_cd > 0:
		return
	if game.points < GATE_COST:
		game._deny()
		return
	game.points -= GATE_COST
	game.hud.points_pop(-GATE_COST)
	gate_t = GATE_TIME
	game.audio.play("lever", LEVER_POS, 2)
	game.audio.play("zap", (GATE_A + GATE_B) / 2.0 + Vector3(0, 1.5, 0), 4)
	game.hud.callout_small("SHOCK GATE ON")
	var tw := lever.create_tween()
	tw.tween_property(lever, "rotation:x", -0.6, 0.15)

func _in_gate(p: Vector3, depth := 1.5) -> bool:
	return p.x > GATE_A.x - 0.1 and p.x < GATE_B.x + 0.1 and absf(p.z - GATE_A.z) < depth and p.y < 3.0 and p.y > -0.5

func _gate_tick(dt: float) -> void:
	var powered: bool = game.world.powered
	if gate_t > 0:
		gate_t -= dt
		if gate_t <= 0:
			gate_cd = GATE_COOL
			hum.stop()
			game.audio.play("lever", LEVER_POS, 0, 0.8)
			var tw := lever.create_tween()
			tw.tween_property(lever, "rotation:x", 0.5, 0.3)
		else:
			if not hum.playing:
				hum.volume_db = 0
				hum.play()
			arc_t -= dt
			if arc_t <= 0:
				arc_t = randf_range(0.05, 0.14)
				var y1 := randf_range(0.3, 2.6)
				game.fx.arc(GATE_A + Vector3(0, y1, -0.42), GATE_B + Vector3(0, y1 + randf_range(-0.6, 0.6), -0.42), Color(0.55, 0.75, 1.0), 0.25, 0.1, 0.07)
				game.fx.arc(GATE_A + Vector3(0, randf_range(0.3, 2.6), -0.42), GATE_B + Vector3(0, randf_range(0.3, 2.6), -0.42), Color(0.8, 0.9, 1.0), 0.35, 0.08, 0.045)
				if randf() < 0.3:
					game.fx.flash_light((GATE_A + GATE_B) / 2.0 + Vector3(0, y1, 0), Color(0.5, 0.7, 1.0), 2.0, 6.0, 0.08)
			for z in game.zombies:
				if not z.alive or z.zap_t > 0 or not _in_gate(z.global_position, 2.6 if z.kind == "boss" else 1.5):
					continue
				z.zap_t = 0.4
				var at: Vector3 = z.global_position + Vector3(0, 1.0, 0)
				game.fx.arc(at, GATE_A + Vector3(0, randf_range(0.5, 2.5), -0.42), Color(0.6, 0.8, 1.0))
				game.fx.spark(at, Vector3.UP)
				game.audio.play("zap", at, 2, randf_range(0.9, 1.2))
				if z.kind == "boss":
					z.damage(z.max_hp * 0.07, "body", Vector3.UP, 1.0, false, at)
					z.stagger = 0.4
				else:
					z.charred = true
					z.tint_mat = game.char_mat
					z._overlay(false)
					for k in 3:
						game.fx.puff(at + Vector3(0, k * 0.3, 0), Color8(50, 50, 50), false, 0.2, 0.7, 0.8, 0.6, 0.15, 0.6)
					z.damage(99999.0, "body", Vector3(randf_range(-1, 1), 0.6, randf_range(-1, 1)).normalized(), 6.0, false, at)
			hurt_t -= dt
			var P = game.player
			if not P.dead and hurt_t <= 0 and _in_gate(P.global_position):
				hurt_t = 0.6
				P.hurt(14)
				var push: float = -1.0 if P.global_position.z < GATE_A.z else 1.0
				P.velocity += Vector3(0, 3, push * 7)
				game.fx.arc(P.global_position + Vector3(0, 1, 0), GATE_B + Vector3(0, 1.5, -0.42), Color(0.6, 0.8, 1.0))
				game.audio.play("zap", null, 0)
	elif gate_cd > 0:
		gate_cd -= dt
	var ready := powered and gate_t <= 0 and gate_cd <= 0
	var c: Color = Color8(40, 220, 60) if ready else (Color8(80, 160, 255) if gate_t > 0 else Color8(230, 30, 20))
	if not powered:
		c = Color8(30, 30, 30)
	lamp_mat.albedo_color = c
	lamp_mat.emission = c
	lamp_light.light_color = c
	lamp_light.light_energy = 0.0 if not powered else 0.8

func _process(dt: float) -> void:
	if game == null:
		return
	_gate_tick(dt)
	if snow_t > 0:
		snow_t -= dt
		tint.color = Color(0.75, 0.88, 1.0, 0.12 * minf(1.0, snow_t))
		if snow_t <= 0:
			_snowfall(false)
			tint.color.a = 0
	elif drill_t > 0:
		drill_t -= dt
		alarm_t -= dt
		if alarm_t <= 0:
			alarm_t = 1.95
			game.audio.play("alarm", null, -6)
		tint.color = Color(1.0, 0.1, 0.05, (0.08 + 0.08 * sin(Time.get_ticks_msec() / 120.0)) * minf(1.0, drill_t))
		if drill_t <= 0:
			tint.color.a = 0
