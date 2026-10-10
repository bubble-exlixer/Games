extends Node
## Westfield High's rules: rounds, points, doors, wall-buys, the mystery box, grenades, barrels,
## pickups, combos and all the little punches that make a kill feel good.

const ZombieScript := preload("res://scripts/zombie.gd")
const MAX_ALIVE := 24          # early waves; late waves grow the horde (see horde_cap)
const BOX_COST := 950
const MAX_NADES := 4
const COMBO_WIN := 2.6
const TRACK_NAME := {"sNight": "NIGHT SCHOOL", "sLofi": "HALL PASS", "sRock": "DETENTION", "sHeavy": "LAST BELL", "sBoss": "MAIN EVENT", "sPrin": "THE PRINCIPAL", "sChem": "LAB SAFETY"}
# the web game's school props (local school coordinates)
const BARRELS := [[24, 36], [41.5, 31.5], [-40, 19], [-8, 40], [-5, 11], [-34, -19.5]]

var world
var pad := false              # last input came from a controller (prompts + aim assist)
var menu_hint_cb := Callable()
var silly                     # power-ups, PA, shock gate, boss taunts (silly.gd)
var wonder                    # projectile novelty weapons (wonder.gd)
var bosses                    # boss moves, phase 2, taunts (bosses.gd)
var escape                    # buy the bus (escape.gd)
var run_t := 0.0              # time played this run
var player
var hud
var fx
var audio
var zroot: Node3D

var samples_by_kind := {}
var zscenes := {}
var eye_mat: StandardMaterial3D
var hit_mat: StandardMaterial3D

var points := 500
var kills := 0
var wave := 0
var to_spawn := 0
var spawn_t := 0.0
var inter_t := 3.0
var state := "inter"     # inter | play | over | stage
var open_areas := {"yard": true}
var zombies: Array = []
var corpses: Array = []
var spits: Array = []
var puddles: Array = []
var bolt_t := 12.0
var interact_target: Dictionary = {}
var respawns := 0

# bosses (the web game's school rotation)
const BOSSES := {
	"coach": {"name": "THE COACH", "sub": "BLOW THE WHISTLE", "track": "sBoss"},
	"principal": {"name": "THE PRINCIPAL", "sub": "REPORT TO THE OFFICE", "track": "sPrin"},
	"chem": {"name": "THE CHEMISTRY TEACHER", "sub": "SAFETY GOGGLES ON", "track": "sChem"},
	"lunch": {"name": "THE LUNCH LADY", "sub": "SECONDS, ANYONE?", "track": "sBoss"},
}
# doorways the Principal can slam shut: local x, z, width, wall runs along x?, door that must be open ("" = always)
const DOORWAYS := [[0, 23, 4.2, true, "sFront"], [0, 15, 4.1, true, ""], [-14, -7.25, 3.1, false, "sWest"], [14, -7.25, 3.1, false, "sEast"],
	[4.5, -16, 3.1, true, "sStairs"], [26.25, -9.5, 2.6, true, "sArt"], [26.25, -5, 2.6, true, "sClass"], [27.5, 8, 3.1, true, "sWindow"],
	[-32, -7.25, 4.6, false, ""], [-46, 6, 4.1, true, "sGymOut"]]
var boss = null
var boss_spawned := false
var last_boss := ""
var spawned_this_wave := 0
var shutters: Array = []
var flasks: Array = []
var poison: Dictionary = {}
var hammy
var shop
var dressing
var physics
var level
var cutscene
var cut_prev_state := "inter"
var settings
var skin := "normal"

# juice
var hitstop_until := 0
var combo_n := 0
var combo_t := 0.0
var mk_n := 0
var mk_t := 0.0
var x2_t := 0.0

# grenades, barrels, pickups
var grenades := 2
var nade_t := 0.0
var nades: Array = []
var nade_mesh: Mesh
var nade_mat: StandardMaterial3D
var barrels: Array = []
var chain_q: Array = []
var barrel_mat: StandardMaterial3D
var pickups: Array = []

# the mystery box (the web game's state machine)
var box_spot := 0
var box_uses := 0
var box_move_at := 5
var box_state := "idle"   # idle rolling offer closing omen leave away arrive
var box_t := 0.0
var box_cycle := 0.0
var box_note := 0
var box_weapon := ""
var box_cur := ""
var box_omen := false
var box_node: Node3D
var box_lid: Node3D
var box_glow: StandardMaterial3D
var box_beam: StandardMaterial3D
var box_disp: Node3D
var box_light: OmniLight3D
var box_body: StaticBody3D
var box_models := {}
var box_hand: Node3D

func setup(w, p, h, f, a, zr: Node3D) -> void:
	world = w
	player = p
	hud = h
	h.game = self
	fx = f
	audio = a
	zroot = zr
	fx.game = self
	for i in world.data.zombie_samples.size():
		var k: String = world.data.zombie_samples[i].kind
		if not samples_by_kind.has(k):
			samples_by_kind[k] = []
		samples_by_kind[k].append(i)
	eye_mat = StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.albedo_color = Color(0.94, 0.89, 0.63)
	hit_mat = StandardMaterial3D.new()
	hit_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hit_mat.albedo_color = Color(1.0, 0.85, 0.8, 0.6)
	hit_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_make_tints()
	_build_box()
	_box_place(0)
	_build_barrels()
	dressing = preload("res://scripts/dressing.gd").new()
	world.add_child(dressing)
	dressing.setup(self)
	physics = preload("res://scripts/physics.gd").new()
	world.add_child(physics)
	physics.setup(self)
	level = preload("res://scripts/level_mods.gd").new()
	world.add_child(level)
	level.setup(self)
	cutscene = preload("res://scripts/cutscene.gd").new()
	add_child(cutscene)
	cutscene.setup(self)
	shop = preload("res://scripts/shop.gd").new()
	world.add_child(shop)
	shop.setup(self)
	hammy = preload("res://scripts/hammy.gd").new()
	world.add_child(hammy)
	hammy.setup(self)
	bosses = preload("res://scripts/bosses.gd").new()
	add_child(bosses)
	bosses.setup(self)
	silly = preload("res://scripts/silly.gd").new()
	world.add_child(silly)
	silly.setup(self)
	wonder = preload("res://scripts/wonder.gd").new()
	world.add_child(wonder)
	wonder.setup(self)
	escape = preload("res://scripts/escape.gd").new()
	world.add_child(escape)
	escape.setup(self)
	var nm := CylinderMesh.new()
	nm.top_radius = 0.055
	nm.bottom_radius = 0.065
	nm.height = 0.13
	nm.radial_segments = 8
	nade_mesh = nm
	nade_mat = StandardMaterial3D.new()
	nade_mat.albedo_color = Color8(62, 70, 40)
	audio.on_track = func(n): hud.now_playing(TRACK_NAME.get(n, n))

var _skin_mats := {}
## alternate zombie looks (unlocks): a multiply tint over every zombie
var ice_mat: StandardMaterial3D
var char_mat: StandardMaterial3D
func _make_tints() -> void:
	ice_mat = StandardMaterial3D.new()
	ice_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ice_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ice_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ice_mat.albedo_color = Color(0.25, 0.45, 0.75, 0.9)
	char_mat = StandardMaterial3D.new()
	char_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	char_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	char_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	char_mat.albedo_color = Color(0.18, 0.15, 0.13)

func skin_overlay():
	if skin == "normal":
		return null
	if not _skin_mats.has(skin):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.72, 0.95, 0.55) if skin == "rotten" else Color(0.7, 0.66, 0.74)
		_skin_mats[skin] = m
	if skin == "glow":
		eye_mat.albedo_color = Color(1.0, 0.1, 0.05)
	return _skin_mats[skin]

func zombie_scene(i: int) -> PackedScene:
	if not zscenes.has(i):
		zscenes[i] = load("res://assets/models/zombies/z%02d.glb" % i)
	return zscenes[i]

# ---------------------------------------------------------------- juice
## freeze-frame: the world nearly stops for a few hundredths of a second
func hitstop(t: float) -> void:
	hitstop_until = maxi(hitstop_until, Time.get_ticks_msec() + int(t * 1000))
	Engine.time_scale = 0.03

func add_points(n: int, pop := true) -> void:
	if x2_t > 0:
		n *= 2
	points += n
	if pop:
		hud.points_pop(n)

func callout(name: String, sub := "") -> void:
	hud.callout(name, sub)

func _combo_kill() -> void:
	if state != "play":
		return
	combo_n += 1
	combo_t = COMBO_WIN
	if combo_n >= 2:
		hud.combo(combo_n, 1.0)
		if combo_n % 5 == 0:
			audio.play("comboUp", null, -2, 1.0 + combo_n * 0.01)

func _combo_tick(dt: float) -> void:
	if mk_n > 0:
		mk_t -= dt
		if mk_t <= 0:
			if mk_n >= 2:
				var nm: String = "DOUBLE KILL" if mk_n == 2 else ("TRIPLE KILL" if mk_n == 3 else ("MULTI KILL" if mk_n == 4 else "MASSACRE"))
				var bonus := 50 * mk_n * (mk_n - 1)
				add_points(bonus, false)
				callout(nm, "+%d" % (bonus * (2 if x2_t > 0 else 1)))
				audio.play("killmark", null, 0, 0.8 + mk_n * 0.08)
			mk_n = 0
	if combo_n == 0:
		return
	combo_t -= dt
	hud.combo(combo_n, clampf(combo_t / COMBO_WIN, 0, 1))
	if combo_t <= 0:
		var n := combo_n
		combo_n = 0
		if n >= 2:
			var bonus := mini(2500, 10 * n * (n - 1))
			add_points(bonus, false)
			hud.combo_end(bonus * (2 if x2_t > 0 else 1))
			audio.play("comboUp", null, -4, 0.8)
		else:
			hud.combo(0, 0)

# ---------------------------------------------------------------- shooting (called by the player)
func _ray(from: Vector3, to: Vector3, exclude: Array) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4 | 16 | 32, exclude)
	q.collide_with_areas = true
	q.collide_with_bodies = true
	return world.get_world_3d().direct_space_state.intersect_ray(q)

func shoot_ray(origin: Vector3, dir: Vector3, wd: Dictionary) -> Dictionary:
	var rng: float = wd.get("range", 120.0)
	var pierce: int = int(wd.pierce)
	var exclude: Array = [player.get_rid()]
	var from := origin
	var end := origin + dir * rng
	var hit := false
	var kill := false
	var nkill := 0
	var hit_z := {}
	for i in 10:
		var r := _ray(from, origin + dir * rng, exclude)
		if r.is_empty():
			break
		var col = r.collider
		if col is Area3D and col.has_meta("zombie"):
			var z = col.get_meta("zombie")
			exclude.append(col.get_rid())
			if hit_z.has(z):
				from = r.position
				continue
			hit_z[z] = true
			var res: Dictionary = z.damage(wd.dmg, col.get_meta("zone"), dir, wd.power, false, r.position)
			hit = true
			kill = kill or res.kill
			if res.kill:
				nkill += 1
				if wd.get("staple", false):
					physics.staple_pin(r.position, dir)
			elif not res.get("armor", false):
				add_points(10)
			if wd.get("staple", false) and not res.kill:
				z.slow_t = maxf(z.slow_t, 0.6)
			if not res.get("armor", false):
				fx.blood_hit(r.position, dir, int(wd.pellets), res.head)
				physics.bloody(r.position, 0.9)
				audio.play("head" if res.head else "hit", r.position, -4)
			if wd.get("bolt", false):
				explode(r.position, wd.blast_r, 0.8)
				end = r.position
				break
			pierce -= 1
			# a zombie's other hitboxes don't count twice
			for b in z.boxes:
				if is_instance_valid(b):
					exclude.append(b.get_rid())
			if pierce <= 0:
				end = r.position
				break
			from = r.position
		elif col.has_meta("balloon"):
			dressing.pop(col.get_meta("balloon"))
			exclude.append(col.get_rid())
			from = r.position
			continue
		elif col.has_meta("glass"):
			physics.shot(col, r.position, dir, wd.power)
			exclude.append(col.get_rid())
			from = r.position
			continue
		elif col is RigidBody3D or col.has_meta("locker") or col.has_meta("lamp") or col.has_meta("ext"):
			physics.shot(col, r.position, dir, wd.power)
			if not col.get_meta("ragdoll", false):
				fx.spark(r.position, r.normal)
			end = r.position
			break
		elif col.has_meta("vending"):
			physics.hit_vending(r.position)
			fx.spark(r.position, r.normal)
			end = r.position
			break
		else:
			end = r.position
			if col.has_meta("barrel"):
				damage_barrel(col.get_meta("barrel"), wd.dmg, r.position, dir)
				fx.spark(r.position, r.normal)
			else:
				fx.spark(r.position, r.normal)
				fx.hole(r.position, r.normal)
				if randf() < 0.15:
					audio.play("ric", r.position, -10, randf_range(0.9, 1.2))
			if wd.get("bolt", false):
				explode(r.position, wd.blast_r, 0.8)
			break
	if nkill >= 2 and int(wd.pellets) == 1:
		add_points(50 * nkill, false)
		callout("COLLATERAL", "+%d" % (50 * nkill * (2 if x2_t > 0 else 1)))
	return {"end": end, "hit": hit, "kill": kill}

func flame(origin: Vector3, dir: Vector3, wd: Dictionary) -> bool:
	var any := false
	for z in zombies.duplicate():
		if not z.alive:
			continue
		var to: Vector3 = z.global_position + Vector3(0, 1.1, 0) - origin
		if to.length() < wd.range and to.normalized().dot(dir) > 0.9:
			var q := PhysicsRayQueryParameters3D.create(origin, origin + to, 1)
			if world.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				var res: Dictionary = z.damage(wd.dmg, "body", dir, 1.0, false)
				any = true
				if not res.kill and randf() < 0.3:
					add_points(10)
	for b in barrels:
		if b.dead:
			continue
		var tb: Vector3 = b.pos + Vector3(0, 0.6, 0) - origin
		if tb.length() < wd.range and tb.normalized().dot(dir) > 0.9:
			damage_barrel(b, wd.dmg * 0.5, b.pos + Vector3(0, 0.6, 0), dir)
	return any

## the shared explosion: grenades, barrels, crossbow bolts
func explode(at: Vector3, radius: float, power: float, bile := false) -> void:
	fx.boom(at, radius, bile)
	audio.play("bloat" if bile else "boom", at, 2.0)
	var pd: float = (player.global_position + Vector3(0, 1, 0)).distance_to(at)
	if pd < 30:
		hitstop(0.07)
	physics.blast(at, radius, 7.0 if not bile else 3.0)
	player.shake = maxf(player.shake, 0.55 * clampf(1.0 - pd / 22.0, 0, 1))
	rumble(0.8 * clampf(1.0 - pd / 25.0, 0, 1), 1.0 * clampf(1.0 - pd / 25.0, 0, 1), 0.35)
	hud.jolt(0.6 * clampf(1.0 - pd / 18.0, 0, 1))
	var n := 0
	for z in zombies.duplicate():
		if not z.alive:
			continue
		var dz: Vector3 = z.global_position + Vector3(0, 0.6, 0) - at
		var d := Vector3(dz.x, dz.y * 0.8, dz.z).length()
		if d >= radius:
			continue
		var dir := Vector3(dz.x, 0, dz.z).normalized() + Vector3(0, 0.35, 0)
		var res: Dictionary = z.damage((30.0 + 170.0 * (1.0 - d / radius)) * power, "body", dir.normalized(), 9.0, true)
		if res.kill:
			n += 1
		else:
			add_points(10)
	for b in barrels:
		if b.dead or b.queued:
			continue
		var d: float = (b.pos + Vector3(0, 0.6, 0)).distance_to(at)
		if d < radius:
			b.queued = true
			chain_q.append({"b": b, "t": randf_range(0.12, 0.3)})
	if pd < radius and state == "play" and not player.dead:
		var away: Vector3 = (player.global_position - at)
		away.y = 0
		player.velocity += away.normalized() * 10.0 + Vector3(0, 3, 0)
		player.hurt(roundf(8 + 50 * (1.0 - pd / radius)) * (0.5 if bile else 1.0))
	if n >= 3:
		callout("BOOM", "%d KILLS" % n)

## the web game's melee: a knife stab, a bayonet thrust (two in a line) or a sprinting boot that shoves a crowd
func melee(origin: Vector3, dir: Vector3, kind := "knife") -> void:
	var f := Vector3(dir.x, 0, dir.z).normalized()
	var rng: float = 2.3 if kind == "kick" else (2.8 if kind == "bayo" else 2.0)
	physics.kick(player.global_position + Vector3(0, 0.8, 0), f, rng)
	var hits: Array = []
	for z in zombies:
		if not z.alive or z.emerge > 0:
			continue
		var d3: Vector3 = z.global_position - player.global_position
		var d := Vector2(d3.x, d3.z).length()
		if d > rng + 0.3 * z.bscale or absf(d3.y) > 1.5:
			continue
		if Vector3(d3.x, 0, d3.z).normalized().dot(f) < 0.5:
			continue
		hits.append([d, z])
	for b in barrels:
		if not b.dead and b.pos.distance_to(player.global_position) < rng:
			damage_barrel(b, 20, b.pos + Vector3(0, 0.6, 0), f)
	if hits.is_empty():
		return
	hits.sort_custom(func(a, b): return a[0] < b[0])
	var hdir := (f + Vector3(0, 0.1, 0)).normalized()
	var any_kill := false
	if kind == "kick":
		for h in hits.slice(0, 4):
			var z = h[1]
			var pt: Vector3 = z.global_position + Vector3(0, 1.1, 0)
			var res: Dictionary = z.damage(20, "body", hdir, 4.0, false, pt)
			any_kill = any_kill or res.kill
			if z.alive and z.kind != "boss":
				z.velocity += f * 9.0 + Vector3(0, 2, 0)
				z.stagger = 1.0
			for o in zombies:
				if o != z and o.alive and o.global_position.distance_to(z.global_position) < 1.6:
					o.stagger = maxf(o.stagger, 0.6)
		audio.play("kickHit", hits[0][1].global_position + Vector3(0, 1, 0))
		player.shake = maxf(player.shake, 0.12)
	else:
		for h in hits.slice(0, 2 if kind == "bayo" else 1):
			var z = h[1]
			var pt: Vector3 = z.global_position + Vector3(0, (0.4 if z.crawler else 1.3) * z.bscale, 0)
			var res: Dictionary = z.damage(320.0 if kind == "bayo" else 150.0, "body", hdir, 4.0, false, pt)
			any_kill = any_kill or res.kill
			fx.spray(pt, hdir, Color8(122, 10, 10), 20 if kind == "bayo" else 14, 4, 1.0, true)
			fx.blood_hit(pt, hdir, 1, false)
			audio.play("stab", pt)
			if not res.kill:
				add_points(10)
	hud.hit(any_kill)
	hitstop(0.05)
	player.shake = maxf(player.shake, 0.1)

## the bat connects. n: 0 forehand sweep, 1 backhand sweep, 2 overhead slam (the combo finisher)
var homerun_t := 0
func bat_hit(origin: Vector3, look: Vector3, n: int) -> int:
	var wd: Dictionary = player.w()
	var up: bool = wd.get("up", false)
	var f := Vector3(look.x, 0, look.z).normalized()
	var right := f.cross(Vector3.UP)
	var side := -right if n == 0 else right
	var rng := 2.9 if n == 2 else 2.6
	physics.kick(player.global_position + Vector3(0, 0.8, 0), f, rng)
	for b in barrels:
		if not b.dead and b.pos.distance_to(player.global_position) < rng:
			damage_barrel(b, 30, b.pos + Vector3(0, 0.6, 0), f)
	var hits: Array = []
	for z in zombies:
		if not z.alive or z.emerge > 0:
			continue
		var d3: Vector3 = z.global_position - player.global_position
		var d := Vector2(d3.x, d3.z).length()
		if d > rng + 0.35 * z.bscale or absf(d3.y) > 1.6:
			continue
		if d > 0.6 and Vector3(d3.x, 0, d3.z).normalized().dot(f) < (0.5 if n == 2 else 0.2):
			continue
		hits.append([d, z])
	if hits.is_empty():
		# whiff, or a solid thunk if there's a wall or table in the way
		var r: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + look * 2.2, 1 | 16 | 32))
		if not r.is_empty():
			audio.play("batWall", r.position, 0, randf_range(0.9, 1.1))
			fx.spark(r.position, r.normal)
			fx.puff(r.position, Color8(140, 130, 115), false, 0.05, 0.3, 0.4, 0.2, 0.05, 0.6)
			physics.shot(r.collider, r.position, look, 8.0)
			if r.collider and r.collider.has_meta("balloon"):
				dressing.pop(r.collider.get_meta("balloon"))
			hitstop(0.03)
			player.shake = maxf(player.shake, 0.08)
			rumble(0.3, 0.4, 0.08)
		return 0
	hits.sort_custom(func(a, b): return a[0] < b[0])
	var any_kill := false
	var kills_now := 0
	var mults := [1.0, 0.7, 0.5, 0.5]
	var count := 0
	for h in hits.slice(0, 4 if n == 2 else 3):
		var z = h[1]
		var pt: Vector3 = z.global_position + Vector3(0, (0.45 if z.crawler else 1.45) * z.bscale, 0)
		var kdir: Vector3 = ((f * 0.8 + Vector3(0, -0.35, 0)) if n == 2 else (f * 0.55 + side * 0.85 + Vector3(0, 0.25, 0))).normalized()
		var dmg: float = float(wd.dmg) * mults[count] * (1.8 if n == 2 else 1.0)
		var res: Dictionary = z.damage(dmg, "head" if n == 2 and not z.crawler else "body", kdir, 6.5, false, pt)
		count += 1
		fx.spray(pt, kdir, Color8(122, 10, 10), 18, 5, 1.0, true)
		fx.blood_hit(pt, kdir, 1, n == 2)
		if res.kill:
			any_kill = true
			kills_now += 1
			physics.launch_last((Vector3(kdir.x, 0, kdir.z).normalized() * (10.0 if n != 2 else 4.0)) + Vector3(0, 4.5 if n != 2 else 1.5, 0))
			fx.wall_splat(pt, kdir, randf_range(1.0, 1.6))
		else:
			add_points(10)
			if z.kind != "boss":
				z.stagger = 1.4 if n == 2 else 0.9
				z.flinch = 1.0
				z.velocity += Vector3(kdir.x, 0, kdir.z).normalized() * (5.0 if n == 2 else 9.0)
			# the crowd behind them stumbles too
			for o in zombies:
				if o != z and o.alive and o.kind != "boss" and o.global_position.distance_to(z.global_position) < 1.3:
					o.stagger = maxf(o.stagger, 0.5)
		# Grand Slam: the bat's charge jumps to one more zombie
		if up:
			var best = null
			var bd := 5.0
			for o in zombies:
				if o != z and o.alive and o.global_position.distance_to(z.global_position) < bd:
					bd = o.global_position.distance_to(z.global_position)
					best = o
			if best != null:
				var b2: Vector3 = best.global_position + Vector3(0, 1.1, 0)
				fx.arc(pt, b2, Color(0.75, 0.5, 1.0))
				audio.play("zap", b2, -2, 1.2)
				best.damage(dmg * 0.6, "body", (b2 - pt).normalized(), 3.0, false, b2)
	var first: Vector3 = hits[0][1].global_position + Vector3(0, 1.3, 0)
	audio.play("batSlam" if n == 2 else "batHit", first, 4, randf_range(0.93, 1.07))
	if any_kill:
		audio.play("crunch", first, 0)
	# feel: freeze-frame, shake, a camera roll in the swing's direction, a punch of FOV, rumble
	hitstop(0.1 if n == 2 else 0.06 + 0.015 * mini(count, 3))
	player.shake = maxf(player.shake, 0.32 if n == 2 else 0.2)
	player.roll += (0.0 if n == 2 else (0.035 if n == 0 else -0.035))
	player.fov_kick = maxf(player.fov_kick, 4.0 if n == 2 else 2.5)
	player.bat_blood = minf(1.0, player.bat_blood + 0.12 * count)
	hud.hit(any_kill)
	hud.jolt(0.35 if n == 2 else 0.2)
	rumble(0.7, 1.0 if n == 2 else 0.7, 0.18 if n == 2 else 0.12)
	if any_kill and (n == 2 or kills_now >= 2) and Time.get_ticks_msec() > homerun_t:
		homerun_t = Time.get_ticks_msec() + 5000
		hud.callout_small("HOME RUN!")
		audio.play("homerun", null, -6)
	return count

func on_zombie_killed(z, head: bool, blast := false) -> void:
	kills += 1
	var bonus := 0
	match z.kind:
		"runner":
			bonus = 50
		"bloater":
			bonus = 50
		"armored":
			bonus = 100
		"spitter":
			bonus = 50
		"monitor":
			bonus = 100
	add_points(100 + (50 if head else 0) + bonus)
	zombies.erase(z)
	audio.play("die", z.global_position + Vector3(0, 1.2, 0), -2)
	mk_n += 1
	mk_t = 0.3
	_combo_kill()
	if head and not blast:
		hitstop(0.045)
	player.shake = maxf(player.shake, 0.08)
	hud.jolt(0.12)
	var c: Vector3 = z.global_position
	if silly.maybe_drop(c):
		pass
	elif randf() < 0.025:
		drop_x2(c)
	elif randf() < 0.045:
		drop_health(c)

func add_corpse(z) -> void:
	corpses.append(z)
	if corpses.size() > 14:
		var old = corpses.pop_front()
		if is_instance_valid(old):
			old.queue_free()

# ---------------------------------------------------------------- grenades
func throw_nade() -> void:
	if state != "play" and state != "inter":
		return
	if player.dead or grenades <= 0 or nade_t > 0:
		return
	grenades -= 1
	nade_t = 0.7
	player.throw_anim = 1.0
	var b: Basis = player.cam.global_transform.basis
	var dir := -b.z
	var m := MeshInstance3D.new()
	m.mesh = nade_mesh
	m.material_override = nade_mat
	world.add_child(m)
	var start: Vector3 = player.cam.global_position + dir * 0.5 + b.x * 0.15 - Vector3(0, 0.1, 0)
	var q := PhysicsRayQueryParameters3D.create(player.cam.global_position, start, 1)
	if not world.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		start = player.cam.global_position
	m.global_position = start
	var v: Vector3 = dir * 14.0 + Vector3(0, 3.5, 0) + Vector3(player.velocity.x, 0, player.velocity.z) * 0.4
	nades.append({"n": m, "v": v, "fuse": 2.0, "bt": 0.0, "rest": false, "beep": 0.0})
	audio.play("whoosh", null, -4, 1.2)
	audio.play("lclick", null, -6)

func _step_nades(dt: float) -> void:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var i := nades.size() - 1
	while i >= 0:
		var n = nades[i]
		n.fuse -= dt
		n.bt -= dt
		n.beep -= dt
		var m: Node3D = n.n
		if n.beep <= 0 and n.fuse < 1.2:
			n.beep = 0.18
			audio.play("tink", m.global_position, -12, 2.0)
		if n.fuse <= 0:
			var at: Vector3 = m.global_position + Vector3(0, 0.3, 0)
			m.queue_free()
			nades.remove_at(i)
			explode(at, 6.0, 1.1)
			i -= 1
			continue
		if not n.rest:
			n.v.y -= 20.0 * dt
			var from := m.global_position
			var to: Vector3 = from + n.v * dt
			var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to + n.v.normalized() * 0.1, 1))
			if not r.is_empty():
				if n.bt <= 0 and n.v.length() > 2:
					n.bt = 0.12
					audio.play("tink", r.position, -4)
				if r.normal.y > 0.6:
					to = r.position + r.normal * 0.07
					n.v = Vector3(n.v.x * 0.65, -n.v.y * 0.38, n.v.z * 0.65)
					if absf(n.v.y) < 0.8:
						n.v.y = 0
						if Vector2(n.v.x, n.v.z).length() < 0.3:
							n.rest = true
				else:
					to = r.position + r.normal * 0.1
					n.v = n.v.bounce(r.normal) * 0.4
			else:
				# rolling along the floor
				var fr := space.intersect_ray(PhysicsRayQueryParameters3D.create(to + Vector3(0, 0.1, 0), to - Vector3(0, 0.12, 0), 1))
				if not fr.is_empty() and n.v.y <= 0:
					to.y = fr.position.y + 0.07
					n.v.y = 0
					n.v.x *= 1.0 - dt * 2.5
					n.v.z *= 1.0 - dt * 2.5
					if Vector2(n.v.x, n.v.z).length() < 0.2:
						n.rest = true
			m.global_position = to
			m.rotate_x(n.v.z * dt * 4)
			m.rotate_z(-n.v.x * dt * 4)
		i -= 1

# ---------------------------------------------------------------- explosive barrels
func _build_barrels() -> void:
	barrel_mat = StandardMaterial3D.new()
	barrel_mat.albedo_texture = load("res://assets/textures/barrel.png")
	barrel_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	barrel_mat.roughness = 0.8
	var cm := CylinderMesh.new()
	cm.top_radius = 0.42
	cm.bottom_radius = 0.42
	cm.height = 1.15
	cm.radial_segments = 10
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	var lid := CylinderMesh.new()
	lid.top_radius = 0.4
	lid.bottom_radius = 0.42
	lid.height = 0.04
	lid.radial_segments = 10
	var lid_m := StandardMaterial3D.new()
	lid_m.albedo_color = Color8(90, 26, 18)
	lid_m.metallic = 0.4
	lid_m.roughness = 0.6
	var rim := TorusMesh.new()
	rim.inner_radius = 0.4
	rim.outer_radius = 0.435
	rim.rings = 12
	rim.ring_segments = 4
	var rim_m := StandardMaterial3D.new()
	rim_m.albedo_color = Color8(70, 18, 12)
	rim_m.metallic = 0.5
	var blob := QuadMesh.new()
	blob.size = Vector2(1.5, 1.5)
	var blob_m := StandardMaterial3D.new()
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(0, 0, 0, 0.75))
	gr.set_color(1, Color(0, 0, 0, 0))
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	blob_m.albedo_texture = gt
	blob_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blob_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blob.material = blob_m
	for xz in BARRELS:
		var x: float = xz[0]
		var z: float = xz[1]
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 0.42
		sh.height = 1.15
		cs.shape = sh
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = barrel_mat
		body.add_child(mi)
		for top in [true, false]:
			var l := MeshInstance3D.new()
			l.mesh = lid
			l.material_override = lid_m
			l.position.y = 0.56 if top else -0.56
			body.add_child(l)
			var r := MeshInstance3D.new()
			r.mesh = rim
			r.material_override = rim_m
			r.position.y = 0.57 if top else -0.55
			body.add_child(r)
		for ry in [-0.2, 0.2]:
			var band := MeshInstance3D.new()
			band.mesh = rim
			band.material_override = rim_m
			band.position.y = ry
			body.add_child(band)
		var shadow := MeshInstance3D.new()
		shadow.mesh = blob
		shadow.rotation.x = -PI / 2
		shadow.position.y = -0.565
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(shadow)
		world.nav.add_child(body)
		body.global_position = Vector3(x, 0.575, z)
		body.rotation.y = randf() * TAU
		var b := {"body": body, "pos": Vector3(x, 0, z), "hp": 45.0, "dead": false, "queued": false}
		body.set_meta("barrel", b)
		barrels.append(b)
	_snap_barrels.call_deferred()

## sit every barrel exactly on the ground under it (needs the level's colliders to exist first)
func _snap_barrels() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for b in barrels:
		var p: Vector3 = b.pos
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 1.4, p.z), Vector3(p.x, -3, p.z), 1, [b.body.get_rid()])
		var r := space.intersect_ray(q)
		if not r.is_empty():
			b.pos.y = r.position.y
			b.body.global_position.y = r.position.y + 0.575
	world.rebake()

func damage_barrel(b: Dictionary, dmg: float, at: Vector3, dir: Vector3) -> void:
	if b.dead:
		return
	b.hp -= dmg
	audio.play("clang", at, -6, randf_range(0.7, 0.9))
	if b.hp <= 0:
		explode_barrel(b)

func explode_barrel(b: Dictionary) -> void:
	if b.dead:
		return
	b.dead = true
	var c: Vector3 = b.pos + Vector3(0, 0.6, 0)
	var body: StaticBody3D = b.body
	for i in 7:
		var s := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(randf_range(0.2, 0.4), randf_range(0.3, 0.6), 0.05)
		s.mesh = bm
		s.material_override = barrel_mat
		fx.add_child(s)
		s.global_position = c + Vector3(randf_range(-0.3, 0.3), randf_range(0, 0.5), randf_range(-0.3, 0.3))
		var out: Vector3 = s.global_position - b.pos
		out.y = 0
		physics.gib(s, out.normalized() * randf_range(5, 10) + Vector3(0, randf_range(5, 10), 0), false)
	body.queue_free()
	world.rebake()
	explode(c, 5.5, 1.0)

func _step_chain(dt: float) -> void:
	var i := chain_q.size() - 1
	while i >= 0:
		chain_q[i].t -= dt
		if chain_q[i].t <= 0:
			var b = chain_q[i].b
			chain_q.remove_at(i)
			explode_barrel(b)
		i -= 1

# ---------------------------------------------------------------- pickups
func _floor_y(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p + Vector3(0, -6, 0), 1)
	var r: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(q)
	return r.position.y if not r.is_empty() else p.y

func drop_ammo(at: Vector3) -> void:
	var g := Node3D.new()
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.42, 0.26, 0.24)
	box.mesh = bm
	var mt := StandardMaterial3D.new()
	mt.albedo_color = Color8(74, 80, 48)
	box.material_override = mt
	g.add_child(box)
	var band := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.43, 0.05, 0.25)
	band.mesh = bb
	var bmt := StandardMaterial3D.new()
	bmt.albedo_color = Color8(201, 162, 58)
	band.material_override = bmt
	g.add_child(band)
	world.add_child(g)
	var y := _floor_y(at)
	g.global_position = Vector3(at.x, y + 0.2, at.z)
	pickups.append({"n": g, "type": "ammo", "life": 25.0, "y": y})

func drop_health(at: Vector3) -> void:
	var g := Node3D.new()
	var kit := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.42, 0.24, 0.3)
	kit.mesh = bm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color8(214, 206, 190)
	kit.material_override = wm
	g.add_child(kit)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color8(179, 18, 27)
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for s in [Vector3(0.24, 0.02, 0.07), Vector3(0.07, 0.02, 0.2)]:
		var c := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = s
		c.mesh = cb
		c.material_override = rm
		c.position.y = 0.125
		g.add_child(c)
	world.add_child(g)
	var y := _floor_y(at)
	g.global_position = Vector3(at.x, y + 0.3, at.z)
	pickups.append({"n": g, "type": "health", "life": 15.0, "y": y})

func drop_x2(at: Vector3) -> void:
	for p in pickups:
		if p.type == "x2":
			return
	var g := Node3D.new()
	var l := Label3D.new()
	l.text = "2X"
	l.font = load("res://assets/fonts/BlackOpsOne-Regular.ttf")
	l.font_size = 96
	l.pixel_size = 0.006
	l.modulate = Color8(255, 210, 110)
	l.outline_modulate = Color8(90, 50, 10)
	l.outline_size = 18
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	g.add_child(l)
	var o := OmniLight3D.new()
	o.light_color = Color8(217, 164, 65)
	o.omni_range = 4
	o.light_energy = 1.6
	g.add_child(o)
	world.add_child(g)
	var y := _floor_y(at)
	g.global_position = Vector3(at.x, y + 0.9, at.z)
	pickups.append({"n": g, "type": "x2", "life": 15.0, "y": y})
	audio.play("x2", g.global_position, -4, 1.3)

func _step_pickups(dt: float) -> void:
	var i := pickups.size() - 1
	while i >= 0:
		var p = pickups[i]
		p.life -= dt
		var n: Node3D = p.n
		n.rotate_y(dt * 1.5)
		var d: Vector3 = player.global_position - n.global_position
		var near: bool = Vector2(d.x, d.z).length() < 1.3 and absf(player.global_position.y - p.y) < 1.5 and not player.dead
		if p.type == "x2" or p.type.begins_with("pw_"):
			n.global_position.y = p.y + 0.9 + sin(p.life * 3.0) * 0.1
		else:
			n.global_position.y = p.y + 0.25 + sin(p.life * 3.0) * 0.05
		n.visible = p.life > 4 or int(p.life * 7) % 2 == 0
		var take := false
		if near and p.type == "health" and player.hp < player.max_hp:
			player.hp = minf(player.max_hp, player.hp + 30)
			audio.play("pick")
			hud.callout_small("+30 HEALTH")
			take = true
		elif near and p.type == "ammo":
			var sl = player.slots[player.cur]
			if sl.res >= 0:
				sl.res += int(world.data.weapons[sl.id].mag)
				audio.play("pick")
				hud.callout_small("+AMMO")
				take = true
		elif near and p.type.begins_with("pw_"):
			silly.activate(p.type.substr(3))
			take = true
		elif near and p.type == "x2":
			x2_t = 20.0
			audio.play("x2", null, 0)
			hud.banner("DOUBLE POINTS", "", 1.6)
			take = true
		if take or p.life <= 0:
			n.queue_free()
			pickups.remove_at(i)
		i -= 1

# ---------------------------------------------------------------- spitters and bloaters
func spit(from: Vector3, target) -> void:
	var to: Vector3 = target.global_position + Vector3(0, 0.7, 0) + target.velocity * Vector3(1, 0, 1) * 0.4
	var T := clampf(from.distance_to(to) / 13.0, 0.6, 1.6)
	var g := Vector3(0, -17, 0)
	var v := (to - from) / T - g * 0.5 * T
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.18
	sm.height = 0.36
	m.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.6, 0.9, 0.2)
	m.material_override = mat
	var l := OmniLight3D.new()
	l.light_color = Color(0.6, 1, 0.25)
	l.omni_range = 3
	l.light_energy = 1.5
	m.add_child(l)
	world.add_child(m)
	m.global_position = from
	spits.append({"n": m, "v": v, "t": 0.0})
	audio.play("spit", from)

## the Lunch Lady's ladle of gravy: an arcing glob that leaves a slow, scalding puddle
func lob_gravy(z) -> void:
	var from: Vector3 = z.joints["armR2"].global_position + Vector3(0, 0.3, 0)
	var to: Vector3 = player.global_position + Vector3(0, 0.4, 0) + player.velocity * Vector3(1, 0, 1) * 0.5
	var T := clampf(from.distance_to(to) / 12.0, 0.6, 1.6)
	var g := Vector3(0, -17, 0)
	var v := (to - from) / T - g * 0.5 * T
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.36
	m.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color8(110, 70, 34)
	mat.roughness = 0.2
	m.material_override = mat
	world.add_child(m)
	m.global_position = from
	spits.append({"n": m, "v": v, "t": 0.0, "gravy": true})
	audio.play("slop", from, 2)

## ...and a lunch tray flung like a frisbee
func throw_tray(z) -> void:
	var from: Vector3 = z.global_position + Vector3(0, 1.6 * z.bscale, 0) - z.global_transform.basis.z * 0.6
	var to: Vector3 = player.global_position + Vector3(0, 1.0, 0)
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.45, 0.03, 0.32)
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color8(150, 140, 110)
	m.material_override = mat
	world.add_child(m)
	m.global_position = from
	spits.append({"n": m, "v": (to - from).normalized() * 16.0, "t": 0.0, "tray": true})
	audio.play("whoosh", from, 0, 1.3)

func acid_puddle(at: Vector3, gravy := false) -> void:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.6, 0), at + Vector3(0, -8, 0), 1)
	var r: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.3
	cm.bottom_radius = 1.3
	cm.height = 0.02
	m.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.43, 0.27, 0.12, 0.9) if gravy else Color(0.55, 0.86, 0.16, 0.65)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material_override = mat
	if not gravy:
		var l := OmniLight3D.new()
		l.light_color = Color(0.6, 1, 0.25)
		l.omni_range = 3
		l.light_energy = 1.0
		m.add_child(l)
	world.add_child(m)
	m.global_position = r.position + Vector3(0, 0.02, 0)
	puddles.append({"n": m, "mat": mat, "pos": r.position, "left": 7.0 if gravy else 6.0, "tick": 0.0, "gravy": gravy, "a": mat.albedo_color.a})
	audio.play("sizzle", r.position, -6)

func bloater_burst(at: Vector3) -> void:
	fx.boom(at, 3.2, true)
	audio.play("bloat", at, 2)
	var pd: float = player.global_position.distance_to(at)
	player.shake = maxf(player.shake, 0.3 * clampf(1.0 - pd / 15.0, 0, 1))
	if pd < 3.2:
		player.hurt(15, true)

func _step_projectiles(dt: float) -> void:
	var i := spits.size() - 1
	while i >= 0:
		var s = spits[i]
		s.t += dt
		var np: Vector3 = s.n.global_position + s.v * dt
		s.v += Vector3(0, -17, 0) * dt
		var q := PhysicsRayQueryParameters3D.create(s.n.global_position, np, 1)
		var r: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(q)
		var hit_p: bool = not player.dead and player.global_position.distance_to(np) < 1.0 + (0.6 if np.y > player.global_position.y + 0.5 else 0.0)
		if s.get("tray", false):
			s.v.y += 17 * dt * 0.9         # trays fly nearly flat
			s.n.rotate_y(dt * 18)
		if hit_p or not r.is_empty() or s.t > 4:
			var at: Vector3 = r.position if not r.is_empty() else np
			if s.get("tray", false):
				if hit_p:
					player.hurt(14)
					if boss != null and is_instance_valid(boss):
						bosses.event(boss, "hit")
				audio.play("tray", at, 0)
				fx.spark(at, Vector3.UP)
			elif s.get("gravy", false):
				if hit_p:
					player.hurt(10)
					player.slow_t = 1.5
				acid_puddle(at, true)
				fx.splash(at, Color8(110, 70, 34), 16)
				audio.play("slop", at)
			else:
				if hit_p:
					player.hurt(10, true)
				acid_puddle(at)
				fx.splash(at, Color(0.6, 0.9, 0.2), 16)
				audio.play("splat", at)
			s.n.queue_free()
			spits.remove_at(i)
		else:
			s.n.global_position = np
			if randf() < dt * 30:
				fx.spray(np, Vector3.UP, Color(0.5, 0.75, 0.15), 1, 0.3, 0.8, false, 0.0, 0.3, 0.5)
		i -= 1
	i = puddles.size() - 1
	while i >= 0:
		var p = puddles[i]
		p.left -= dt
		p.tick -= dt
		if p.left < 1:
			p.mat.albedo_color.a = p.get("a", 0.65) * maxf(p.left, 0)
		if p.left <= 0:
			p.n.queue_free()
			puddles.remove_at(i)
		else:
			var d: Vector3 = player.global_position - p.pos
			if Vector2(d.x, d.z).length() < 1.3 and d.y > -0.3 and d.y < 1.7:
				if p.get("gravy", false):
					player.slow_t = maxf(player.slow_t, 0.3)
				if p.tick <= 0:
					p.tick = 0.5
					player.hurt(3 if p.get("gravy", false) else 4, not p.get("gravy", false))
		i -= 1

# ---------------------------------------------------------------- spawning
func _pick_spawn(near: Vector3) -> Vector3:
	var c: Array = []
	for s in world.data.spawns:
		if open_areas.has(s.area):
			var p := Vector3(s.pos[0], s.pos[1], s.pos[2])
			var d := p.distance_to(near)
			if d > 8:
				c.append([d, p])
	if c.is_empty():
		for s in world.data.spawns:
			if open_areas.has(s.area):
				c.append([0, Vector3(s.pos[0], s.pos[1], s.pos[2])])
	c.sort_custom(func(a, b): return a[0] < b[0])
	return c[randi() % mini(5, c.size())][1]

func _pick_kind() -> String:
	var r := randf()
	if wave >= 4 and r < 0.11:
		return "bloater"
	if wave >= 5 and r < 0.23:
		return "armored"
	if wave >= 7 and r < 0.33:
		return "spitter"
	if wave >= 3 and randf() < 0.07:
		return "monitor"
	if wave >= 3 and randf() < minf(0.12 + wave * 0.03, 0.45):
		return "runner"
	return "walker"

func spawn_zombie() -> void:
	var z := ZombieScript.new()
	zroot.add_child(z)
	z.setup(self, _pick_kind(), _pick_spawn(player.global_position), wave)
	zombies.append(z)
	audio.play("vent", z.global_position, -6)

func respawn_near(z) -> void:
	respawns += 1
	var p := _pick_spawn(player.global_position)
	if p.distance_to(player.global_position) > 7:
		z.global_position = p
		z.velocity = Vector3.ZERO
		z.emerge = 1.3

# ---------------------------------------------------------------- interactables
func _near(spot, r := 2.0) -> bool:
	var p: Vector3 = spot if spot is Vector3 else Vector3(spot[0], spot[1], spot[2])
	var d: Vector3 = player.global_position - p
	return Vector2(d.x, d.z).length() < r and absf(d.y) < 1.6

func _find_interact() -> Dictionary:
	for d in world.data.doors:
		var st = world.doors.get(d.id)
		if st == null or st.open:
			continue
		for s in d.spots:
			if _near(s):
				return {"kind": "door", "def": d, "text": "Press {use} to %s  [%d]" % [String(d.label).to_lower(), d.cost]}
	for wb in world.data.wallbuys:
		if _near(wb.spot, 1.8):
			var wd: Dictionary = world.data.weapons[wb.id]
			if player.owns(wb.id) >= 0 and wd.get("melee", false):
				continue
			if player.owns(wb.id) >= 0:
				return {"kind": "ammo", "def": wb, "text": "Press {use} for %s ammo  [%d]" % [wd.name, wb.ammo]}
			return {"kind": "gun", "def": wb, "text": "Press {use} to buy %s  [%d]" % [wd.name, wb.cost]}
	var hp_: String = hammy.pap_prompt()
	if hp_ != "":
		return {"kind": "hampap", "text": hp_}
	var pp: String = shop.pap_prompt()
	if pp != "":
		return {"kind": "pap", "text": pp}
	var pw: String = level.prompt()
	if pw != "":
		return {"kind": "power", "text": pw}
	var bt_: String = escape.prompt()
	if bt_ != "":
		return {"kind": "bus", "text": bt_}
	var gt: String = silly.prompt()
	if gt != "":
		return {"kind": "gate", "text": gt}
	var st: String = physics.shelf_prompt()
	if st != "":
		return {"kind": "shelf", "text": st}
	var ht: String = hammy.prompt()
	if ht != "":
		return {"kind": "hamster", "text": ht}
	if (box_state == "idle" or box_state == "offer") and _near(_box_front(), 1.6):
		if box_state == "offer":
			return {"kind": "box", "text": "Press {use} to take the %s" % world.data.weapons[box_weapon].name}
		return {"kind": "box", "text": "Press {use} for the mystery box  [%d]" % BOX_COST}
	return {}

func interact() -> void:
	if player.dead or interact_target.is_empty():
		return
	var it := interact_target
	match it.kind:
		"door":
			if points < it.def.cost:
				_deny()
				return
			points -= it.def.cost
			hud.points_pop(-int(it.def.cost))
			open_areas[it.def.id] = true
			world.open_door(it.def.id)
			audio.play("buy")
			audio.play("planks" if it.def.id == "sWindow" else ("shutter" if it.def.id in ["sStairs", "sGymOut"] else "metalDoor"), Vector3(it.def.spots[0][0], 1.5, it.def.spots[0][2]))
			hud.banner("", String(it.def.label).replace("OPEN ", "") + " OPENED", 1.4)
			player.shake = maxf(player.shake, 0.15)
		"gun":
			if points < it.def.cost:
				_deny()
				return
			points -= it.def.cost
			hud.points_pop(-int(it.def.cost))
			player.give(it.def.id, int(it.def.reserve))
			audio.play("buy")
			hud.banner(world.data.weapons[it.def.id].name, "", 1.2)
		"ammo":
			var s = player.slots[player.owns(it.def.id)]
			if s.res >= it.def.reserve and s.mag >= world.data.weapons[it.def.id].mag:
				return
			if points < it.def.ammo:
				_deny()
				return
			points -= it.def.ammo
			hud.points_pop(-int(it.def.ammo))
			player.give(it.def.id, int(it.def.reserve))
			audio.play("buy")
		"power":
			if world.powered:
				return
			add_points(500, true)
			if player.bot:
				level.throw_switch()
				world.power_on(level.SWITCH_POS)
			else:
				cutscene.power()
		"shelf":
			physics.push_shelf()
		"pap":
			shop.pap_buy()
		"hampap":
			hammy.pap_buy()
		"gate":
			silly.buy()
		"bus":
			escape.buy()
		"hamster":
			if points < hammy.COST:
				_deny()
				return
			points -= hammy.COST
			hud.points_pop(-hammy.COST)
			audio.play("buy")
			hammy.feed()
		"box":
			if box_state == "offer":
				_box_take()
				return
			if points < BOX_COST:
				_deny()
				return
			points -= BOX_COST
			hud.points_pop(-BOX_COST)
			_box_roll()

func _deny() -> void:
	audio.play("deny")
	hud.banner("", "NOT ENOUGH POINTS", 1.0)
	hud.jolt(0.3)

# ---------------------------------------------------------------- mystery box (the web game's)
## a box mesh with the whole texture on every face, like three.js
func _uvbox(size: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size / 2.0
	var faces := [
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
		[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := n * h
		var uu := u * h
		var vv := v * h
		var pts := [c - uu - vv, c + uu - vv, c + uu + vv, c - uu + vv]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_normal(n)
			st.set_uv(uvs[k])
			st.add_vertex(pts[k])
	return st.commit()

func _part(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, uv := false) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	if uv:
		m.mesh = _uvbox(size)
	else:
		var bm := BoxMesh.new()
		bm.size = size
		m.mesh = bm
	m.material_override = mat
	m.position = pos
	parent.add_child(m)
	return m

func _build_box() -> void:
	box_node = Node3D.new()
	world.add_child(box_node)
	var tex: Texture2D = load("res://assets/textures/box.png")
	var bmat := StandardMaterial3D.new()
	bmat.albedo_texture = tex
	bmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	bmat.roughness = 0.9
	var edge := StandardMaterial3D.new()
	edge.albedo_color = Color8(42, 42, 38)
	edge.metallic = 0.5
	edge.roughness = 0.5
	_part(box_node, Vector3(1.5, 0.52, 0.7), bmat, Vector3(0, 0.26, 0), true)
	for x in [-0.74, 0.74]:
		_part(box_node, Vector3(0.06, 0.56, 0.74), edge, Vector3(x, 0.27, 0))
	for x in [-0.4, 0.4]:
		_part(box_node, Vector3(0.08, 0.53, 0.72), edge, Vector3(x, 0.265, 0))
	box_lid = Node3D.new()
	box_lid.position = Vector3(0, 0.52, -0.35)
	box_node.add_child(box_lid)
	_part(box_lid, Vector3(1.52, 0.12, 0.72), bmat, Vector3(0, 0.06, 0.35), true)
	var latm := StandardMaterial3D.new()
	latm.albedo_color = Color8(138, 122, 64)
	latm.metallic = 0.6
	_part(box_lid, Vector3(0.14, 0.12, 0.04), latm, Vector3(0, 0, 0.72))
	# the glow inside and the beam of light
	var glow := MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = Vector2(1.36, 0.58)
	glow.mesh = gq
	box_glow = StandardMaterial3D.new()
	box_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	box_glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	box_glow.albedo_color = Color(0.74, 0.83, 1.0, 0.0)
	glow.material_override = box_glow
	glow.rotation.x = -PI / 2
	glow.position.y = 0.5
	box_node.add_child(glow)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.55
	cm.bottom_radius = 0.7
	cm.height = 2.2
	cm.radial_segments = 10
	cm.cap_top = false
	cm.cap_bottom = false
	beam.mesh = cm
	box_beam = StandardMaterial3D.new()
	box_beam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box_beam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	box_beam.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	box_beam.cull_mode = BaseMaterial3D.CULL_DISABLED
	box_beam.albedo_color = Color(0.74, 0.83, 1.0, 0.0)
	var bgt := GradientTexture2D.new()
	var bgr := Gradient.new()
	bgr.set_color(0, Color(1, 1, 1, 0))
	bgr.set_color(1, Color(1, 1, 1, 1))
	bgt.gradient = bgr
	bgt.fill_from = Vector2(0, 0)
	bgt.fill_to = Vector2(0, 1)
	box_beam.albedo_texture = bgt
	beam.material_override = box_beam
	beam.position.y = 1.6
	beam.scale.z = 0.5
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	box_node.add_child(beam)
	box_disp = Node3D.new()
	box_disp.position.y = 0.6
	box_node.add_child(box_disp)
	for id in world.data.box_pool:
		if box_models.has(id):
			continue
		var h := Node3D.new()
		var g: Node3D = preload("res://scripts/guns.gd").make(id, false, world)
		g.rotation.y = PI / 2
		g.scale = Vector3.ONE * 1.3
		h.add_child(g)
		h.visible = false
		box_disp.add_child(h)
		box_models[id] = h
	# the omen: a severed hand
	box_hand = Node3D.new()
	var hs := StandardMaterial3D.new()
	hs.albedo_color = Color8(138, 122, 102)
	var stump := StandardMaterial3D.new()
	stump.albedo_color = Color8(90, 12, 12)
	_part(box_hand, Vector3(0.2, 0.06, 0.22), hs, Vector3.ZERO)
	for i in 4:
		var f := _part(box_hand, Vector3(0.04, 0.04, 0.16), hs, Vector3(-0.075 + i * 0.05, -0.03, 0.17))
		f.rotation.x = 0.7 + i * 0.1
	var th := _part(box_hand, Vector3(0.045, 0.045, 0.12), hs, Vector3(-0.12, -0.02, 0.04))
	th.rotation.y = -0.8
	_part(box_hand, Vector3(0.16, 0.08, 0.12), stump, Vector3(0, 0, -0.15))
	box_hand.scale = Vector3.ONE * 1.8
	box_hand.visible = false
	box_disp.add_child(box_hand)
	box_light = OmniLight3D.new()
	box_light.light_color = Color8(188, 212, 255)
	box_light.omni_range = 5.0
	box_light.light_energy = 0.35
	world.add_child(box_light)
	box_body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.54, 0.6, 0.74)
	cs.shape = bs
	cs.position.y = 0.3
	box_body.add_child(cs)
	box_node.add_child(box_body)
	box_move_at = randi_range(4, 8)

func _box_place(i: int) -> void:
	box_spot = i
	var b = world.data.boxes[i]
	box_node.global_position = Vector3(b.pos[0], b.pos[1], b.pos[2])
	box_node.rotation = Vector3(0, b.ry, 0)
	box_node.visible = true
	box_light.global_position = Vector3(b.pos[0] + sin(b.ry) * 0.6, b.pos[1] + 1.4, b.pos[2] + cos(b.ry) * 0.6)

func _box_front() -> Vector3:
	var b = world.data.boxes[box_spot]
	return Vector3(b.pos[0] + sin(b.ry) * 1.0, b.pos[1], b.pos[2] + cos(b.ry) * 1.0)

func _box_pos() -> Vector3:
	return box_node.global_position + Vector3(0, 0.8, 0)

func _box_show(id: String) -> void:
	for k in box_models:
		box_models[k].visible = k == id
	box_hand.visible = id == "hand"
	box_cur = id

func _box_roll() -> void:
	box_uses += 1
	box_state = "rolling"
	box_t = 0.0
	box_cycle = 0.0
	box_note = 0
	box_omen = box_uses >= box_move_at and wave >= 2 and world.data.boxes.size() > 1
	var avail: Array = []
	for id in world.data.box_pool:
		if player.owns(id) < 0:
			avail.append(id)
	if avail.is_empty():
		avail = world.data.box_pool
	box_weapon = "" if box_omen else avail[randi() % avail.size()]
	audio.play("boxOpen", _box_pos())

func _box_take() -> void:
	var id := box_weapon
	if id == "":
		return
	player.give(id, int(world.data.weapons[id].box_reserve))
	audio.play("pick")
	audio.play("buy")
	hud.banner(world.data.weapons[id].name, "FROM THE BOX", 1.4)
	box_state = "closing"
	box_t = 0.0
	_box_show("")

func _box_tick(dt: float) -> void:
	box_t += dt
	var st := box_state
	var b = world.data.boxes[box_spot]
	var sp := Vector3(b.pos[0], b.pos[1], b.pos[2])
	var open := st == "rolling" or st == "offer" or st == "omen"
	box_lid.rotation.x += ((-1.75 if open else 0.0) - box_lid.rotation.x) * minf(1.0, dt * (9.0 if open else 12.0))
	var gl := (0.75 + sin(box_t * 9) * 0.1) if open else (0.06 + sin(Time.get_ticks_msec() / 700.0) * 0.04)
	box_glow.albedo_color.a += (gl - box_glow.albedo_color.a) * minf(1.0, dt * 6)
	box_beam.albedo_color.a += ((0.12 if open else 0.0) - box_beam.albedo_color.a) * minf(1.0, dt * 5)
	box_light.light_energy = 0.0 if st == "away" else ((1.6 + sin(box_t * 11) * 0.3) if open else (0.35 + (randf() * 1.5 if st == "arrive" else 0.0)))
	match st:
		"rolling":
			box_disp.position.y = 0.3 + minf(1.0, box_t / 1.0) * 0.65
			box_cycle -= dt
			if box_cycle <= 0:
				var k := box_t / 3.6
				box_cycle = 0.06 + 0.3 * k * k
				var pool: Array = world.data.box_pool
				var id: String = pool[randi() % pool.size()]
				while id == box_cur and pool.size() > 1:
					id = pool[randi() % pool.size()]
				_box_show(id)
				audio.play("boxNote", _box_pos(), -4, 1.0 + (box_note % 6) * 0.06)
				box_note += 1
			if box_t >= 3.6:
				box_t = 0.0
				if box_omen:
					box_state = "omen"
					_box_show("hand")
					audio.play("boxBye", _box_pos())
					points += BOX_COST
					hud.points_pop(BOX_COST)
					hud.banner("BYE BYE", "%d REFUNDED" % BOX_COST, 1.8)
				else:
					box_state = "offer"
					_box_show(box_weapon)
					audio.play("boxDone", _box_pos())
		"offer":
			box_disp.position.y = 0.95 - minf(1.0, box_t / 7.0) * 0.5
			box_disp.rotation.y = sin(box_t * 2) * 0.08
			if box_t >= 7.0:
				box_state = "closing"
				box_t = 0.0
				_box_show("")
		"closing":
			if box_t > 0.5:
				box_state = "idle"
				box_t = 0.0
				box_disp.rotation.y = 0.0
		"omen":
			box_disp.position.y = 0.95 + sin(box_t * 6) * 0.04
			if box_t > 1.6:
				box_state = "leave"
				box_t = 0.0
				_box_show("")
		"leave":
			var k := box_t / 1.8
			box_node.global_position = sp + Vector3(randf_range(-0.05, 0.05) * (1 - k), k * k * 3.2, randf_range(-0.05, 0.05) * (1 - k))
			box_node.rotation.y = b.ry + k * k * 5
			if randf() < dt * 20:
				fx.spray(sp + Vector3(0, 0.1, 0), Vector3.UP, Color8(90, 84, 72), 2, 3, 0.8)
			if box_t >= 1.8:
				box_state = "away"
				box_t = 0.0
				box_node.visible = false
				box_body.collision_layer = 0
				fx.puff(sp + Vector3(0, 3, 0), Color8(42, 38, 34), false, 0.4, 2, 1, 0.4, 0.5, 0.8)
		"away":
			if box_t >= 5.0:
				var n := box_spot
				while n == box_spot:
					n = randi() % world.data.boxes.size()
				_box_place(n)
				box_state = "arrive"
				box_t = 0.0
				box_node.global_position.y = world.data.boxes[n].pos[1] + 4.0
				box_uses = 0
				box_move_at = randi_range(4, 8)
				hud.banner("THE BOX HAS MOVED", String(world.data.boxes[n].name).to_upper(), 1.8)
		"arrive":
			var k := minf(1.0, box_t / 0.6)
			box_node.global_position.y = sp.y + 4.0 * (1.0 - k * k)
			if k >= 1.0:
				box_state = "idle"
				box_t = 0.0
				box_node.global_position.y = sp.y
				box_body.collision_layer = 1
				audio.play("boxLand", _box_pos())
				fx.spray(sp + Vector3(0, 0.1, 0), Vector3.UP, Color8(90, 84, 72), 18, 4, 1.2)
				var d: float = player.global_position.distance_to(sp)
				player.shake = maxf(player.shake, 0.2 * clampf(1.0 - d / 20.0, 0, 1))

# ---------------------------------------------------------------- rounds
## bigger hordes later on: 24 at once early, up to 44 by wave 15
func horde_cap() -> int:
	return clampi(24 + (wave - 5) * 2, 24, 44) if physics == null or physics.detail >= 1.0 else clampi(20 + (wave - 5), 20, 32)

func rumble(weak: float, strong: float, dur: float) -> void:
	if Input.get_connected_joypads().is_empty():
		return
	Input.start_joy_vibration(0, clampf(weak, 0, 1), clampf(strong, 0, 1), dur)

func start_wave() -> void:
	wave += 1
	if wave > 1:
		grenades = mini(MAX_NADES, grenades + 2)
	for sl in player.slots:
		if world.data.weapons[sl.id].get("wonder", false):
			sl.mag = int(player.wdata(sl).mag)
	to_spawn = 4 + wave * 3
	spawn_t = 0.8
	spawned_this_wave = 0
	boss_spawned = false
	state = "play"
	hud.banner("WAVE %d" % wave, "THEY ARE COMING" if wave == 1 else "", 2.8)
	hud.round_punch()
	audio.play("wave")

func player_died() -> void:
	state = "over"
	Engine.time_scale = 1.0
	audio.play("death")
	audio.set_track("")
	var rec: Dictionary = settings.record(wave, kills, points) if settings else {}
	hud.game_over(wave, kills, points, rec, settings.scores if settings else {})
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(dt: float) -> void:
	if Engine.time_scale < 1.0 and Time.get_ticks_msec() >= hitstop_until:
		Engine.time_scale = 1.0
	if state == "cutscene":
		world.update_look(dt, cutscene.cam)
		hud.update(dt, _hud_state())
		return
	_step_projectiles(dt)
	_step_nades(dt)
	_step_chain(dt)
	_step_pickups(dt)
	_step_shutters(dt)
	_step_flasks(dt)
	if boss != null and is_instance_valid(boss) and boss.alive:
		hud.boss_bar(BOSSES[boss.bt].name, boss.hp / boss.max_hp)
	else:
		hud.boss_bar("", 0.0)
	_box_tick(dt)
	nade_t -= dt
	world.update_look(dt, player.cam)
	if state == "stage" or state == "menu":
		hud.update(dt, _hud_state())
		return
	if x2_t > 0:
		x2_t -= dt
	if state == "play" or state == "inter":
		run_t += dt
	_combo_tick(dt)
	if state == "inter":
		inter_t -= dt
		if inter_t <= 0:
			start_wave()
	elif state == "play":
		spawn_t -= dt
		var alive := 0
		for z in zombies:
			if z.alive:
				alive += 1
		if to_spawn > 0 and spawn_t <= 0 and alive < horde_cap():
			spawn_zombie()
			to_spawn -= 1
			spawned_this_wave += 1
			spawn_t = maxf(0.35, 1.7 - wave * 0.09)
		if wave % 5 == 0 and not boss_spawned and spawned_this_wave >= 3:
			spawn_boss()
		if to_spawn <= 0 and alive == 0:
			state = "inter"
			inter_t = 8.0
			hud.banner("WAVE %d SURVIVED" % wave, "", 3.0)
			audio.play("waveEnd")
			if wave > 0 and wave % 10 == 0:
				silly.pa(wave)
	# music follows the rounds
	if state != "over":
		if boss != null and is_instance_valid(boss) and boss.alive:
			audio.set_track(BOSSES[boss.bt].track)
		else:
			audio.set_track("sNight" if wave <= 3 else ("sRock" if wave <= 7 else "sHeavy"))
		audio.set_calm(state != "play" or zombies.is_empty())
	# lightning outdoors
	bolt_t -= dt
	if bolt_t <= 0:
		bolt_t = randf_range(9, 22)
		_lightning()
	interact_target = _find_interact()
	hud.update(dt, _hud_state())

func _hud_state() -> Dictionary:
	var hs: Dictionary = player.hud_state()
	hs.round = wave
	hs.points = points
	hs.prompt = interact_target.get("text", "") if state != "stage" else ""
	hs.nades = grenades
	hs.x2 = x2_t
	return hs

func _lightning() -> void:
	var env: Environment = world.env
	var base := env.ambient_light_energy
	for i in 2:
		env.ambient_light_energy = base + 2.2
		env.background_color = Color8(60, 66, 90)
		await get_tree().create_timer(0.06 + i * 0.03).timeout
		env.ambient_light_energy = base
		env.background_color = Color8(11, 13, 18)
		await get_tree().create_timer(0.09).timeout
	await get_tree().create_timer(randf_range(0.6, 1.6)).timeout
	audio.play("thunder", null, -2)

# ---------------------------------------------------------------- bosses
func spawn_boss(force := "") -> void:
	boss_spawned = true
	var opts: Array = ["coach", "principal", "chem"].filter(func(k): return k != last_boss)
	var t: String = force if force != "" else ("lunch" if randf() < 0.15 and last_boss != "lunch" else opts[randi() % opts.size()])
	last_boss = t
	var z := ZombieScript.new()
	zroot.add_child(z)
	z.setup(self, "boss", _pick_spawn(player.global_position), wave, t)
	z.pitch = 0.6
	zombies.append(z)
	boss = z
	bosses.start(z)
	if player.bot or state != "play":
		hud.banner(BOSSES[t].name, BOSSES[t].sub, 2.6)
	audio.play("z_deep_moan", z.global_position + Vector3(0, 2.5, 0), 6, 0.55)
	player.shake = maxf(player.shake, 0.2)
	if t == "principal":
		get_tree().create_timer(0.9).timeout.connect(func():
			if is_instance_valid(z) and z.alive and state == "play":
				hall_monitors(z, 2))
	if not player.bot and state == "play":
		cutscene.boss(z)

func boss_down(z) -> void:
	add_points(1000)
	hitstop(0.12)
	player.shake = maxf(player.shake, 0.35)
	if z.bt == "chem":
		poison = {"pos": z.global_position, "t": 8.0, "pt": 0.0, "ht": 0.6}
		for i in 6:
			fx.puff(z.global_position + Vector3(randf_range(-1, 1), 1, randf_range(-1, 1)), Color8(106, 154, 58), false, 0.6, randf_range(2.4, 3.4), randf_range(1.6, 2.4), randf_range(0.2, 0.6), 0.6, 0.7)
		audio.play("bloat", z.global_position, 2)
	# max ammo
	for sl in player.slots:
		var wd: Dictionary = world.data.weapons[sl.id]
		sl.mag = wd.mag
		if sl.res >= 0:
			sl.res = maxi(sl.res, int(wd.mag) * 4 if wd.box_reserve < 0 else int(wd.box_reserve))
	grenades = MAX_NADES
	drop_x2(z.global_position)
	hud.banner(BOSSES[z.bt].name + " IS DOWN", "MAX AMMO  +1000", 2.6)
	audio.play("waveEnd", null, 0, 0.8)
	boss = null

func hall_monitors(z, n: int) -> void:
	for i in n:
		if zombies.size() >= 26:
			break
		var m := ZombieScript.new()
		zroot.add_child(m)
		var a := randf() * TAU
		var pos: Vector3 = z.global_position + Vector3(cos(a) * 1.8, 0.3, sin(a) * 1.8)
		m.setup(self, "walker", pos, wave)
		m.emerge = 0.4
		zombies.append(m)
		spawned_this_wave += 1

func principal_ability(z, second := false) -> void:
	if z.phase == 2 and not second:
		# zero tolerance: two at once
		get_tree().create_timer(0.7).timeout.connect(func():
			if is_instance_valid(z) and z.alive:
				principal_ability(z, true))
	var opts: Array = ["assembly", "detention", "monitors"].filter(func(a): return a != z.get_meta("last_ab", ""))
	var a: String = opts[randi() % opts.size()]
	if a == "detention" and not _detention():
		a = opts.filter(func(x): return x != "detention")[0]
	z.set_meta("last_ab", a)
	audio.play("bell", null, -4, 0.8)
	match a:
		"assembly":
			for o in zombies:
				if o.alive and o != z:
					o.rush_t = 5.0
			hud.banner("ASSEMBLY!", "ALL STUDENTS REPORT", 1.6)
		"monitors":
			hall_monitors(z, 3)
			callout("HALL MONITORS", "")
		_:
			hud.banner("POP QUIZ!", "THE DOORS ARE SHUT", 1.6)
			audio.play("slam", player.global_position + Vector3(0, 2, 3), 2)
			bosses.event(z, "special")

func _detention() -> bool:
	var tex: Texture2D = load("res://assets/textures/shutter.png")
	var n := 0
	for dw in DOORWAYS:
		if dw[4] != "" and not (world.doors.has(dw[4]) and world.doors[dw[4]].open):
			continue
		var c := Vector3(dw[0], 0, dw[1])
		var d: float = Vector2(player.global_position.x - c.x, player.global_position.z - c.z).length()
		if d < 1.8 or d > 16 or absf(player.global_position.y) > 2:
			continue
		if n >= 4:
			break
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var sz := Vector3(dw[2], 3, 0.2) if dw[3] else Vector3(0.2, 3, dw[2])
		bs.size = sz
		cs.shape = bs
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = sz
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.metallic = 0.4
		mat.uv1_scale = Vector3(maxf(1.0, dw[2] / 3.0), 1, 1)
		mi.material_override = mat
		body.add_child(mi)
		world.add_child(body)
		body.global_position = c + Vector3(0, 4.6, 0)
		shutters.append({"b": body, "t": 6.0, "y": 4.6, "c": c})
		audio.play("shutter", c + Vector3(0, 1.5, 0))
		n += 1
	return n > 0

func _step_shutters(dt: float) -> void:
	var i := shutters.size() - 1
	while i >= 0:
		var s = shutters[i]
		s.t -= dt
		var want := 1.5 if s.t > 0 else 4.8
		var was: float = s.y
		s.y += (want - s.y) * minf(1.0, dt * (16.0 if s.t > 0 else 3.0))
		s.b.global_position.y = s.y
		if was > 1.6 and s.y <= 1.6 and s.t > 5:
			fx.spray(s.c + Vector3(0, 0.1, 0), Vector3.UP, Color8(90, 84, 72), 10, 3, 1.0)
			player.shake = maxf(player.shake, 0.08)
		if s.t <= 0 and s.t + dt > 0:
			audio.play("shutter", s.c + Vector3(0, 1.5, 0))
		if s.t <= -1.4:
			s.b.queue_free()
			shutters.remove_at(i)
		i -= 1

## the Chemistry Teacher's flasks: green ones leave acid, every third one is pink and blows up
func throw_flask(z, vol: bool, gas := false, wide := false) -> void:
	var sc: float = z.bscale
	var fwd: Vector3 = -z.global_transform.basis.z
	var from: Vector3 = z.global_position + fwd * 0.45 * sc + Vector3(0, 1.85 * sc, 0)
	var d: float = Vector2(player.global_position.x - from.x, player.global_position.z - from.z).length()
	var T := clampf(d / 11.0, 0.55, 1.5)
	var to: Vector3 = player.global_position + Vector3(player.velocity.x, 0, player.velocity.z) * T * 0.55 + Vector3(0, 0.1, 0)
	if wide:
		to += Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
	var v := Vector3((to.x - from.x) / T, (to.y - from.y + 0.5 * 14.0 * T * T) / T, (to.z - from.z) / T)
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.08
	cm.height = 0.2
	cm.radial_segments = 6
	m.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color8(255, 90, 224) if vol else (Color8(220, 230, 60) if gas else Color8(122, 255, 90))
	m.material_override = mat
	var l := OmniLight3D.new()
	l.light_color = mat.albedo_color
	l.omni_range = 3
	l.light_energy = 1.2
	m.add_child(l)
	world.add_child(m)
	m.global_position = from
	flasks.append({"n": m, "v": v, "t": 0.0, "vol": vol, "gas": gas})
	audio.play("whoosh", from, -2, 0.8)

func _step_flasks(dt: float) -> void:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var i := flasks.size() - 1
	while i >= 0:
		var f = flasks[i]
		f.t += dt
		var m: Node3D = f.n
		var from := m.global_position
		f.v.y -= 14.0 * dt
		var to: Vector3 = from + f.v * dt
		m.rotate_x(dt * 9)
		m.rotate_z(dt * 6)
		if randf() < 0.7:
			fx.spray(to, Vector3.UP, Color8(255, 128, 240) if f.vol else Color8(138, 255, 106), 1, 0.3, 0.4)
		var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
		var d: Vector3 = to - player.global_position
		var on_p: bool = not player.dead and Vector2(d.x, d.z).length() < 0.55 and d.y > 0 and d.y < 1.9
		if not r.is_empty() or on_p or f.t > 4:
			var at: Vector3 = r.position if not r.is_empty() else to
			if on_p and not f.vol:
				player.hurt(8, true)
				if boss != null and is_instance_valid(boss):
					bosses.event(boss, "hit")
			m.queue_free()
			flasks.remove_at(i)
			if f.get("gas", false):
				fx.spray(at, Vector3.UP, Color8(220, 230, 60), 14, 4, 0.5)
				bosses.gas_cloud(at)
				audio.play("glass", at)
			elif f.vol:
				for k in 4:
					fx.puff(at, Color8(255, 96, 224) if k % 2 else Color8(160, 64, 255), true, 0.5, randf_range(1.6, 2.4), randf_range(0.35, 0.5), randf_range(0.6, 1.4), 0.6, 0.7)
				explode(at + Vector3(0, 0.3, 0), 3.6, 0.5)
			else:
				fx.spray(at, Vector3.UP, Color8(138, 255, 106), 18, 4, 0.6)
				fx.spray(at, Vector3.UP, Color8(232, 255, 224), 8, 3, 0.35)
				acid_puddle(at)
				audio.play("glass", at)
		else:
			m.global_position = to
		i -= 1
	if not poison.is_empty():
		poison.t -= dt
		poison.pt -= dt
		poison.ht -= dt
		if poison.pt <= 0:
			poison.pt = 0.1
			var a := randf() * TAU
			var rr := randf() * 2.6
			fx.puff(poison.pos + Vector3(cos(a) * rr, randf_range(0.2, 1.4), sin(a) * rr), Color8(106, 154, 58) if randf() < 0.5 else Color8(58, 90, 32), false, 0.5, randf_range(1.6, 2.6), randf_range(1.4, 2.2), randf_range(0.1, 0.5), 0.35, 0.55 * minf(1.0, poison.t / 2.0))
		var pd: Vector3 = player.global_position - poison.pos
		if not player.dead and poison.ht <= 0 and poison.t > 0.5 and Vector2(pd.x, pd.z).length() < 3.3:
			poison.ht = 0.45
			player.hurt(6, true)
			audio.play("cough", null, -4)
		if poison.t <= 0:
			poison = {}
