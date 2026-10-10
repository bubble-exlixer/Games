extends Node
## Beefier bosses: new moves, a second phase at half health, and taunts that pop up while you fight.

var game
const TAUNTS := {
	"coach": {
		"idle": ["I'VE SEEN BETTER CARDIO FROM THE CORPSES.", "YOU THROW LIKE YOU'RE ON THE CHESS TEAM.", "TEN LAPS FOR EVERY MISS. YOU OWE ME FOUR THOUSAND.",
			"MY KNEES ARE SHOT AND I'M STILL FASTER THAN YOU.", "THIS IS WHY YOU WEREN'T PICKED FOR DODGEBALL."],
		"hit": "WALK IT OFF.", "special": "FULL-COURT PRESS!", "half": "HALFTIME! I'M NOT EVEN WINDED!", "near": "TELL MY TEAM... TO RUN THE PLAY...",
	},
	"principal": {
		"idle": ["THIS IS GOING ON YOUR PERMANENT RECORD. WHICH IS NOW VERY SHORT.", "I'VE CALLED YOUR PARENTS. THEY SAID 'WHO?'", "THE VENDING MACHINE IS FOR EMERGENCIES ONLY.",
			"IS THAT GUM? ARE YOU CHEWING GUM IN MY APOCALYPSE?", "I WAS NAMED PRINCIPAL OF THE YEAR. TWICE. ONCE ALIVE."],
		"special": "POP QUIZ! NOBODY LEAVES UNTIL SOMEBODY DIES.", "half": "I'M NOT MAD. I'M JUST DISAPPOINTED. AND HUNGRY.", "near": "WHO... APPROVED... THIS FIELD TRIP...",
	},
	"chem": {
		"idle": ["TODAY'S LAB: WHAT HAPPENS WHEN YOU ARGUE WITH A PH OF ONE.", "GOGGLES ON! OH WAIT, YOU WON'T NEED EYES.", "I DIDN'T GET TENURE FOR NOTHING.",
			"IT'S NOT A MUTATION, IT'S PEER REVIEW.", "KYLE. THIS IS ALL KYLE'S FAULT."],
		"hit": "THAT WILL BE ON THE FINAL.", "half": "INCREASING THE TEMPERATURE. FOR SCIENCE.", "near": "MY ONLY REGRET... IS GRADING ON A CURVE...",
	},
	"lunch": {
		"idle": ["I'VE BEEN SERVING THIS MEAT SINCE 1987. IT'S NOT DONE WITH YOU.", "YOU WANT A SIDE OF GRAVY? EVERYBODY GETS GRAVY.", "NO TRAY? NO SERVICE.",
			"I KNOW WHAT'S IN THE MYSTERY MEAT. NOW YOU WILL TOO.", "THE FOOD PYRAMID WAS A LIE, SWEETIE."],
		"hit": "BUS YOUR OWN TABLE.", "half": "THAT'S IT. KITCHEN'S CLOSED. YOU'RE ON THE MENU.", "near": "TELL THEM... TUESDAY IS... TACO DAY...",
	},
}
const PHASE2 := {"coach": "OVERTIME", "principal": "ZERO TOLERANCE", "chem": "EXOTHERMIC", "lunch": "KITCHEN'S CLOSED"}

var bag: Array = []
var taunt_t := 6.0
var taunt_box: Control
var t_name: Label
var t_line: Label
var t_tween: Tween
var clouds: Array = []      # chem gas grenades
var rings: Array = []       # lunch lady shockwaves

func setup(g) -> void:
	game = g
	var hud = game.hud
	taunt_box = Control.new()
	taunt_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	taunt_box.anchor_left = 0.5
	taunt_box.anchor_right = 0.5
	taunt_box.offset_left = -420
	taunt_box.offset_right = 420
	taunt_box.offset_top = 76
	taunt_box.offset_bottom = 170
	taunt_box.pivot_offset = Vector2(420, 20)
	taunt_box.modulate.a = 0
	hud.root.add_child(taunt_box)
	t_name = hud._label(taunt_box, hud.display, 20, hud.BLOOD, Vector2(0, 0), Vector2(840, 24))
	t_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t_line = hud._label(taunt_box, hud.display, 28, hud.GOLD, Vector2(0, 24), Vector2(840, 70))
	t_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

## a boss just arrived
func start(z) -> void:
	bag = []
	taunt_t = randf_range(7.0, 10.0)
	z.phase = 1
	z.near_said = false

func say(z, line: String) -> void:
	if line == "" or game.hud == null:
		return
	t_name.text = game.BOSSES[z.bt].name
	t_line.text = '"' + line + '"'
	if t_tween:
		t_tween.kill()
	taunt_box.modulate.a = 1.0
	taunt_box.scale = Vector2(1.45, 1.45)
	taunt_box.rotation = deg_to_rad(randf_range(-4, 4))
	t_tween = taunt_box.create_tween().set_ignore_time_scale(true)
	t_tween.set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t_tween.tween_property(taunt_box, "scale", Vector2.ONE, 0.3)
	t_tween.tween_property(taunt_box, "rotation", deg_to_rad(randf_range(-1.5, 1.5)), 0.3)
	t_tween.set_parallel(false)
	t_tween.tween_interval(clampf(line.length() * 0.06, 2.4, 4.2))
	t_tween.tween_property(taunt_box, "modulate:a", 0.0, 0.45)
	game.audio.play("sting", null, -12, randf_range(0.9, 1.1))
	game.audio.play("z_deep_grunt", z.global_position + Vector3(0, 2.5, 0), 2, 0.55)
	taunt_t = maxf(taunt_t, randf_range(8.0, 15.0))

## one-off lines ("hit", "special", "half", "near")
func event(z, kind: String) -> void:
	if z == null or not is_instance_valid(z) or not z.alive:
		return
	var tb: Dictionary = TAUNTS.get(z.bt, {})
	if not tb.has(kind):
		return
	if kind == "hit" and z.get_meta("hit_said_t", -99.0) > Time.get_ticks_msec() / 1000.0 - 10.0:
		return
	if kind == "hit":
		z.set_meta("hit_said_t", Time.get_ticks_msec() / 1000.0)
	say(z, tb[kind])

func _idle_line(z) -> String:
	if bag.is_empty():
		bag = TAUNTS[z.bt].idle.duplicate()
		bag.shuffle()
	return bag.pop_back()

## called from the boss's brain every frame; returns true when a move is in progress
func brain(z, dt: float, p, dist: float, see: bool) -> void:
	# taunts
	if game.state == "play" and not game.cutscene.playing:
		taunt_t -= dt
		if taunt_t <= 0:
			taunt_t = randf_range(8.0, 15.0)
			say(z, _idle_line(z))
	# phase 2 at half health
	if z.phase == 1 and z.hp < z.max_hp * 0.5:
		z.phase = 2
		_phase2(z)
	if not z.near_said and z.hp < z.max_hp * 0.15:
		z.near_said = true
		event(z, "near")
	z.move_t -= dt * (1.6 if z.phase == 2 else 1.0)
	z.move2_t -= dt * (1.6 if z.phase == 2 else 1.0)
	match z.bt:
		"coach":
			# charge: a short wind-up, then a straight-line sprint that flattens you
			if z.move_t <= 0 and dist > 4.5 and dist < 22 and see and z.charge_t <= 0 and z.hold_t <= 0:
				z.move_t = randf_range(6.0, 8.0)
				z.hold_t = 0.65
				z.charge_pending = true
				z.lunge = 1.0
				game.audio.play("z_deep_moan", z.global_position + Vector3(0, 2.5, 0), 6, 0.7)
				event(z, "special")
			# whistle stun
			if z.move2_t <= 0 and dist < 16 and see and z.charge_t <= 0:
				z.move2_t = randf_range(10.0, 13.0)
				_coach_whistle(z, p)
		"principal":
			# paddle: a big swat that sends you flying
			if z.move2_t <= 0 and dist < 3.4:
				z.move2_t = randf_range(4.5, 6.0)
				z.lunge = 1.0
				game.audio.play("whoosh", z.global_position + Vector3(0, 2, 0), 2, 0.6)
				game.get_tree().create_timer(0.28).timeout.connect(func():
					if is_instance_valid(z) and z.alive and not p.dead and z.global_position.distance_to(p.global_position) < 4.0:
						var away: Vector3 = p.global_position - z.global_position
						away.y = 0
						p.velocity += away.normalized() * 22.0 + Vector3(0, 5, 0)
						game.last_attacker = z
						p.hurt(z.dmg * 0.7)
						p.shake = maxf(p.shake, 0.35)
						game.audio.play("thock", p.global_position, 4, 0.7)
						game.hud.callout_small("SWAT!"))
		"chem":
			# gas grenade: a lingering cloud
			if z.move_t <= 0 and dist > 3 and dist < 22 and see:
				z.move_t = randf_range(7.0, 9.0)
				z.lunge = 1.0
				game.throw_flask(z, false, true)
		"lunch":
			# mystery-meat ground pound: jump over the shockwave
			if z.move_t <= 0 and dist < 7.0 and z.hold_t <= 0:
				z.move_t = randf_range(5.0, 7.0)
				z.hold_t = 0.55
				z.pound_pending = true
				z.lunge = 1.0
				game.audio.play("z_deep_grunt", z.global_position + Vector3(0, 2.5, 0), 6, 0.5)

func _phase2(z) -> void:
	event(z, "half")
	game.hud.callout(PHASE2[z.bt], "PHASE 2")
	game.audio.play("sting", null, -4, 0.75)
	game.player.shake = maxf(game.player.shake, 0.25)
	game.fx.flash_light(z.global_position + Vector3(0, 2, 0), Color(1, 0.3, 0.2), 5.0, 10.0, 0.5)
	match z.bt:
		"coach":
			z.speed *= 1.35
		"lunch":
			z.enraged = true
			z.always_enraged = true
			for i in 4:
				if game.zombies.size() >= 28:
					break
				var m = game.ZombieScript.new()
				game.zroot.add_child(m)
				var a := randf() * TAU
				m.setup(game, "walker", z.global_position + Vector3(cos(a) * 2.2, 0.3, sin(a) * 2.2), game.wave)
				if m.hat == null:
					m._hat("hairnet")
				m.emerge = 0.5
				game.zombies.append(m)
				game.spawned_this_wave += 1
			game.hud.callout_small("CAFETERIA STAFF!")

## the Coach's whistle: a stunning blast and the horde comes running
func _coach_whistle(z, p) -> void:
	var at: Vector3 = z.joints["head"].global_position
	game.audio.play("whistle", at, 8, 0.85)
	game.fx.puff(at, Color8(240, 240, 230), false, 0.1, 0.5, 0.5, 0.4, 0.03, 0.6)
	z.lunge = 1.0
	if p.global_position.distance_to(z.global_position) < 16:
		p.stun_t = 1.4 if z.phase == 1 else 1.9
		p.shake = maxf(p.shake, 0.3)
		game.hud.jolt(1.2)
		game.hud.callout_small("WHISTLE STUN!")
	for o in game.zombies:
		if o != z and o.alive and o.global_position.distance_to(z.global_position) < 22:
			o.rush_t = 4.0

## the charge hit a wall or the player, or a ground pound landed
func pound(z) -> void:
	var c: Vector3 = z.global_position
	game.audio.play("pound", c, 6)
	game.player.shake = maxf(game.player.shake, 0.4)
	game.fx.splat(c + Vector3(0, 0.1, 0), 2.5)
	for i in 10:
		var a := TAU * i / 10.0
		game.fx.puff(c + Vector3(cos(a) * 1.2, 0.2, sin(a) * 1.2), Color8(150, 110, 70), false, 0.3, 1.2, 0.6, 0.3, 0.2, 0.7)
	var m := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	tm.rings = 24
	tm.ring_segments = 4
	m.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.55, 0.36, 0.2, 0.85)
	m.material_override = mat
	game.world.add_child(m)
	m.global_position = c + Vector3(0, 0.15, 0)
	m.scale = Vector3(1, 0.4, 1)
	rings.append({"n": m, "mat": mat, "r": 1.0, "c": c, "hit": false, "dmg": z.dmg * (0.75 if z.phase == 1 else 0.95)})

func gas_cloud(at: Vector3) -> void:
	clouds.append({"pos": at, "t": 9.0, "pt": 0.0, "ht": 0.5})
	game.audio.play("fizz", at, 2, 1.2)

func _process(dt: float) -> void:
	if game == null:
		return
	var P = game.player
	var i := rings.size() - 1
	while i >= 0:
		var r = rings[i]
		r.r += dt * 9.0
		r.n.scale = Vector3(r.r, 0.4, r.r)
		r.mat.albedo_color.a = clampf(1.0 - r.r / 9.0, 0, 0.85)
		var d: Vector3 = P.global_position - r.c
		var hd := Vector2(d.x, d.z).length()
		if not r.hit and absf(hd - r.r) < 0.7 and d.y < 0.6 and P.is_on_floor() and not P.dead:
			r.hit = true
			game.last_attacker = game.boss
			P.hurt(r.dmg)
			P.velocity += Vector3(d.x, 0, d.z).normalized() * 10.0 + Vector3(0, 5, 0)
			if game.boss != null and is_instance_valid(game.boss):
				event(game.boss, "hit")
		if r.r > 9.0:
			r.n.queue_free()
			rings.remove_at(i)
		i -= 1
	i = clouds.size() - 1
	while i >= 0:
		var c = clouds[i]
		c.t -= dt
		c.pt -= dt
		c.ht -= dt
		if c.pt <= 0:
			c.pt = 0.12
			var a := randf() * TAU
			var rr := randf() * 2.4
			game.fx.puff(c.pos + Vector3(cos(a) * rr, randf_range(0.2, 1.3), sin(a) * rr), Color8(150, 200, 70) if randf() < 0.5 else Color8(90, 140, 40), false, 0.5, randf_range(1.4, 2.4), randf_range(1.2, 2.0), randf_range(0.1, 0.4), 0.3, 0.5 * minf(1.0, c.t / 2.0))
		var pd: Vector3 = P.global_position - c.pos
		if not P.dead and c.ht <= 0 and c.t > 0.5 and Vector2(pd.x, pd.z).length() < 3.0 and absf(pd.y) < 2.0:
			c.ht = 0.5
			game.last_attacker = game.boss
			P.hurt(5, true)
			game.audio.play("cough", null, -6)
		if c.t <= 0:
			clouds.remove_at(i)
		i -= 1
