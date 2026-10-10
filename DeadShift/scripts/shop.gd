extends Node3D
## New shop pieces: wall-buy displays for the upstairs guns, and the Pack-a-Punch machine in the lab.

const Guns := preload("res://scripts/guns.gd")
const PAP_POS := Vector3(-1.6, 4.0, -43.25)
const PAP_SPOT := Vector3(-1.6, 4.0, -41.8)
const PAP_COST := 5000

var game
var pap_light: OmniLight3D
var pap_slot: StandardMaterial3D
var pap_busy := 0.0
var pap_slot_i := -1
var chalk: ImageTexture

func setup(g) -> void:
	game = g
	_chalk_tex()
	for wb in g.world.data.wallbuys:
		if wb.get("built", false):
			_display(wb)
	_pap_machine()

func _chalk_tex() -> void:
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	for x in 64:
		for y in 32:
			var edge := x < 2 or x > 61 or y < 2 or y > 29
			if edge and rng.randf() < 0.8:
				img.set_pixel(x, y, Color(0.92, 0.9, 0.85, rng.randf_range(0.5, 0.9)))
	chalk = ImageTexture.create_from_image(img)

## a gun on the wall in a chalk outline, its name and price chalked underneath, lit by a small warm lamp
func _display(wb: Dictionary) -> void:
	var face := Vector3(wb.face[0], wb.face[1], wb.face[2])
	var show := Vector3(wb.show[0], wb.show[1], wb.show[2])
	var root := Node3D.new()
	add_child(root)
	root.global_position = show
	root.look_at(show - face, Vector3.UP)        # -Z points into the wall, +Z out of it
	var g := Guns.make(wb.id, false, game.world)
	g.rotation.y = PI / 2
	g.position = Vector3(0, 0, 0.09)
	root.add_child(g)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.5, 0.75)
	q.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_texture = chalk
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	q.material_override = m
	q.position = Vector3(0, 0, 0.03)
	root.add_child(q)
	var l := Label3D.new()
	l.text = "%s\n%d" % [game.world.data.weapons[wb.id].name, wb.cost]
	l.font = load("res://assets/fonts/VT323-Regular.ttf")
	l.font_size = 64
	l.pixel_size = 0.004
	l.modulate = Color(0.92, 0.9, 0.85, 0.9)
	l.position = Vector3(0, -0.6, 0.03)
	root.add_child(l)
	var o := OmniLight3D.new()
	o.light_color = Color8(255, 200, 140)
	o.omni_range = 3.0
	o.light_energy = 1.2
	o.position = Vector3(0, 0.5, 0.6)
	root.add_child(o)

# ---------------------------------------------------------------- Pack-a-Punch
func _pap_machine() -> void:
	var st := StaticBody3D.new()
	game.world.nav.add_child(st)
	st.global_position = PAP_POS + Vector3(0, 1.3, 0)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.8, 2.6, 1.0)
	cs.shape = bs
	st.add_child(cs)
	var body := StandardMaterial3D.new()
	body.albedo_color = Color8(42, 36, 48)
	body.metallic = 0.5
	body.roughness = 0.5
	_box(st, Vector3(1.8, 2.6, 1.0), body, Vector3.ZERO)
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color8(201, 162, 58)
	trim.metallic = 0.7
	_box(st, Vector3(1.84, 0.12, 1.04), trim, Vector3(0, -1.2, 0))
	_box(st, Vector3(1.84, 0.12, 1.04), trim, Vector3(0, 1.24, 0))
	_box(st, Vector3(1.2, 0.5, 0.06), StandardMaterial3D.new(), Vector3(0, 0.15, 0.52)).material_override.albedo_color = Color8(26, 22, 30)
	pap_slot = StandardMaterial3D.new()
	pap_slot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pap_slot.albedo_color = Color8(80, 50, 130)
	_box(st, Vector3(1.0, 0.16, 0.06), pap_slot, Vector3(0, 0.15, 0.53))
	var l := Label3D.new()
	l.text = "UPGRADE"
	l.font = load("res://assets/fonts/BlackOpsOne-Regular.ttf")
	l.font_size = 72
	l.pixel_size = 0.005
	l.modulate = Color8(208, 184, 255)
	l.position = Vector3(0, 0.95, 0.52)
	st.add_child(l)
	var sub := Label3D.new()
	sub.text = "PACK-A-PUNCH  %d" % PAP_COST
	sub.font = load("res://assets/fonts/VT323-Regular.ttf")
	sub.font_size = 48
	sub.pixel_size = 0.004
	sub.modulate = Color8(201, 162, 58)
	sub.position = Vector3(0, 0.62, 0.52)
	st.add_child(sub)
	pap_light = OmniLight3D.new()
	pap_light.light_color = Color8(160, 112, 255)
	pap_light.omni_range = 6.0
	pap_light.light_energy = 0.15
	pap_light.position = Vector3(0, 0.2, 1.0)
	st.add_child(pap_light)

func _box(p: Node3D, size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	p.add_child(mi)
	return mi

func pap_prompt() -> String:
	var p = game.player
	var d: Vector3 = p.global_position - PAP_SPOT
	if Vector2(d.x, d.z).length() > 1.8 or absf(d.y) > 1.5:
		return ""
	if pap_busy > 0:
		return "Upgrading..."
	if not game.world.powered:
		return "The upgrade machine needs power"
	var sl = p.slots[p.cur]
	if sl.get("up", false):
		return "%s is already upgraded" % p.w().name
	return "Press {use} to upgrade the %s  [%d]" % [p.w().name, PAP_COST]

func pap_buy() -> void:
	var p = game.player
	if pap_busy > 0 or not game.world.powered or p.slots[p.cur].get("up", false):
		return
	if game.points < PAP_COST:
		game._deny()
		return
	game.points -= PAP_COST
	game.hud.points_pop(-PAP_COST)
	pap_busy = 3.4
	pap_slot_i = p.cur
	p.pap_t = 3.5
	game.audio.play("papStart", PAP_POS + Vector3(0, 1.3, 0.5), 2)

func _process(dt: float) -> void:
	var powered: bool = game.world.powered
	if pap_busy > 0:
		pap_busy -= dt
		pap_light.light_energy = 2.0 + sin(Time.get_ticks_msec() / 40.0) * 1.2
		pap_slot.albedo_color = Color8(200, 160, 255) if fmod(Time.get_ticks_msec() / 90.0, 2.0) < 1.0 else Color8(110, 70, 220)
		if randf() < dt * 14:
			game.fx.spray(PAP_POS + Vector3(randf_range(-0.6, 0.6), 1.4, 0.6), Vector3(0, 0.5, 1), Color8(190, 140, 255), 3, 3, 0.4, false, 0.0, 1.5, 0.5)
		if pap_busy <= 0:
			var p = game.player
			if pap_slot_i >= 0 and pap_slot_i < p.slots.size():
				var sl = p.slots[pap_slot_i]
				sl.up = true
				var wd: Dictionary = p.wdata(sl)
				sl.mag = wd.mag
				if sl.res >= 0:
					sl.res = int(game.world.data.weapons[sl.id].get("up_reserve", sl.res))
				p.cur = pap_slot_i
				p.build_gun()
				game.hud.banner(wd.name, "WEAPON UPGRADED", 2.2)
				game.audio.play("papDone", PAP_POS + Vector3(0, 1.3, 0.5), 2)
				game.fx.flash_light(PAP_POS + Vector3(0, 1.4, 1.2), Color8(170, 120, 255), 6.0, 8.0, 0.5)
	else:
		pap_light.light_energy = (0.9 + sin(Time.get_ticks_msec() / 600.0) * 0.2) if powered else 0.12
		pap_slot.albedo_color = Color8(160, 112, 255) if powered else Color8(50, 36, 70)
