extends Node
## Automated checks for the silly update: --t3=<section>[,<section>...]
## sections: pad, hats, power, gate, hammy, guns, boss, pa, escape, intro

var m          # main.gd
var game
var player
var n := 0

func run(main_node, sections: Array) -> void:
	m = main_node
	game = m.game
	player = m.player
	await get_tree().create_timer(2.0).timeout
	while not game.world.nav_baked_once:
		await get_tree().process_frame
	game.state = "stage"
	player.hp = 1e9
	player.max_hp = 1e9
	for s in sections:
		print("=== ", s)
		await call("_" + s)
	print("=== done")
	get_tree().quit()

func snap(tag: String) -> void:
	await get_tree().process_frame
	n += 1
	get_viewport().get_texture().get_image().save_png("user://t3_%02d_%s.png" % [n, tag])

func wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout

func zombie(kind: String, at: Vector3, wave := 3):
	var z = preload("res://scripts/zombie.gd").new()
	game.zroot.add_child(z)
	z.setup(game, kind, at, wave)
	z.emerge = 0
	game.zombies.append(z)
	return z

func clear() -> void:
	for z in game.zombies.duplicate():
		if is_instance_valid(z):
			z.queue_free()
	game.zombies.clear()

# ---------------------------------------------------------------- device prompts + aim assist
func _pad() -> void:
	var wb: Dictionary = game.world.data.wallbuys[0]
	var sp := Vector3(wb.spot[0], wb.spot[1] + 0.05, wb.spot[2])
	m._look_at(sp, Vector3(wb.show[0], wb.show[1], wb.show[2]) if wb.has("show") else sp + Vector3(0, 1.5, -1))
	game.state = "play"
	game.to_spawn = 0
	game.pad = false
	await wait(0.4)
	print("kb prompt: ", game.interact_target.get("text", ""))
	await snap("prompt_kb")
	game.pad = true
	game.hud.device_changed()
	await wait(0.3)
	await snap("prompt_pad")
	player.slots[0].mag = 2
	await wait(0.2)
	await snap("reload_pad")
	player.slots[0].mag = 12
	# aim assist: a zombie 9 m ahead, 6 degrees off; press ADS and see where the crosshair ends up
	game.state = "stage"
	clear()
	m._look_at(Vector3(0, 0.05, 10), Vector3(0, 1.6, 0))
	await wait(0.2)
	var f: Vector3 = -player.cam.global_transform.basis.z
	var at: Vector3 = player.global_position + f.rotated(Vector3.UP, deg_to_rad(6)) * 9.0
	var z = zombie("walker", Vector3(at.x, 0.05, at.z))
	z.speed = 0.0
	await wait(0.6)
	var aim: Vector3 = player._aim_point(z)
	var before := rad_to_deg((-player.cam.global_transform.basis.z).angle_to((aim - player.cam.global_position).normalized()))
	Input.action_press("ads")
	await wait(0.35)
	aim = player._aim_point(z)
	var after := rad_to_deg((-player.cam.global_transform.basis.z).angle_to((aim - player.cam.global_position).normalized()))
	print("aim assist ADS snap: %.2f deg -> %.2f deg off the head" % [before, after])
	await snap("ads_snap")
	Input.action_release("ads")
	player.assist_k = 0.0
	game.pad = false
	print("assist off target=", player._magnet_point())
	player.assist_k = 1.0
	game.pad = true
	print("magnet point (on) =", player._magnet_point())
	game.pad = false
	game.hud.device_changed()
	clear()

# ---------------------------------------------------------------- hats
func _hats() -> void:
	clear()
	m._look_at(Vector3(0, 0.05, 11), Vector3(0, 1.4, 6))
	var zs := []
	var styles := ["grad", "helmet", "beanie", "dunce", "hairnet"]
	for i in 5:
		var z = zombie("walker", Vector3(-3.2 + i * 1.6, 0.05, 6.5))
		if z.hat != null:
			z.meshes = z.meshes.filter(func(e): return e.n != z.hat)
			z.hat.queue_free()
			z.hat = null
			z.prop_blade = null
		z._hat(styles[i])
		z.speed = 0.0
		z.rotation.y = 0.0
		zs.append(z)
	await wait(0.5)
	for z in zs:
		z.speed = 0.0
	await snap("hats")
	# shoot two in the head: hats fly
	for k in [1, 3]:
		var hz = zs[k]
		var hp: Vector3 = hz.joints["head"].global_position + Vector3(0, 0.15, 0)
		var res: Dictionary = hz.damage(5.0, "head", (hp - player.cam.global_position).normalized(), 3.0, false, hp)
		print("headshot ", styles[k], " hat now=", hz.hat)
	await wait(0.25)
	await snap("hats_pop")
	await wait(1.2)
	await snap("hats_land")
	clear()

# ---------------------------------------------------------------- power-ups
func _power() -> void:
	clear()
	game.state = "play"
	game.to_spawn = 0
	m._look_at(Vector3(0, 0.05, 11), Vector3(0, 1.2, 4))
	game.silly.drop("free", Vector3(0, 0, 7.5))
	await wait(0.6)
	await snap("powerups")
	for p in game.pickups.duplicate():
		if p.type.begins_with("pw_"):
			p.n.queue_free()
			game.pickups.erase(p)
	game.silly.activate("free")
	var mag: int = player.slots[player.cur].mag
	for i in 5:
		player.shoot()
		player.fire_t = 0
	print("free period: mag before ", mag, " after ", player.slots[player.cur].mag)
	player.free_t = 0
	game.state = "stage"

# ---------------------------------------------------------------- shock gate
func _gate() -> void:
	clear()
	game.state = "play"
	game.to_spawn = 0
	game.points = 50000
	if not game.world.doors["sGymOut"].open:
		game.world.open_door("sGymOut")
		game.open_areas["sGymOut"] = true
	m._look_at(game.silly.LEVER_SPOT + Vector3(0, 0.05, 0), game.silly.LEVER_POS)
	await wait(0.4)
	print("gate prompt: ", game.interact_target.get("text", ""))
	await snap("gate_lever")
	game.interact()
	print("gate active=", game.silly.gate_t > 0, " points=", game.points)
	m._look_at(Vector3(-46, 0.05, -1.5), Vector3(-46, 1.2, 6))
	var zs := []
	for i in 4:
		var z = zombie("walker", Vector3(-47.5 + i * 1.0, 0.05, 9.5 + i * 0.4))
		zs.append(z)
	var b = preload("res://scripts/zombie.gd").new()
	game.zroot.add_child(b)
	b.setup(game, "boss", Vector3(-46, 0.05, 12), 5, "coach")
	game.zombies.append(b)
	await wait(0.2)
	await snap("gate_on")
	await wait(4.0)
	var fried := 0
	for z in zs:
		if not is_instance_valid(z) or not z.alive:
			fried += 1
	print("gate fried ", fried, "/", zs.size(), " boss hp ", b.hp if is_instance_valid(b) else -1, "/", b.max_hp if is_instance_valid(b) else -1)
	await snap("gate_fried")
	game.silly.gate_t = 0.01
	await wait(0.2)
	print("cooldown=", game.silly.gate_cd)
	m._look_at(game.silly.LEVER_SPOT + Vector3(0, 0.05, 0), game.silly.LEVER_POS)
	await wait(0.3)
	print("gate prompt after: ", game.interact_target.get("text", ""))
	await snap("gate_cooldown")
	clear()
	game.state = "stage"

# ---------------------------------------------------------------- PaP Hammy
func _hammy() -> void:
	clear()
	game.points = 50000
	var h = game.hammy
	h.fed = 3
	h.free = true
	game.state = "play"
	game.to_spawn = 0
	m._look_at(game.shop.PAP_SPOT + Vector3(0.6, 0.05, 1.2), game.shop.PAP_SPOT + Vector3(0, 0.1, 0.0))
	await wait(0.2)
	for i in 20:
		m._look_at(game.shop.PAP_SPOT + Vector3(0.6, 0.05, 1.2), h.pos)
		await get_tree().process_frame
	game.interact_target = game._find_interact()
	print("hammy prompt: ", game.interact_target.get("text", ""))
	await snap("hammy_prompt")
	game.interact()
	await wait(3.8)
	print("mega=", h.mega)
	game.state = "stage"
	await wait(0.6)
	m._look_at(h.pos + Vector3(0.4, -0.6, 1.4), h.pos + Vector3(0, 0.2, 0))
	await wait(0.3)
	await snap("hammy_mega")
	game.state = "play"
	var z = zombie("walker", h.pos + Vector3(1.5, 0.1, 1.0))
	var z2 = zombie("walker", h.pos + Vector3(2.5, 0.1, 1.5))
	await wait(1.5)
	await snap("hammy_bite")
	clear()
	game.state = "stage"

# ---------------------------------------------------------------- weapons
func _guns() -> void:
	clear()
	game.state = "play"
	game.to_spawn = 0
	# the new wall-buys
	for wb in game.world.data.wallbuys:
		if wb.id in ["bone", "dodge"]:
			var sp := Vector3(wb.spot[0], wb.spot[1] + 0.05, wb.spot[2])
			m._look_at(sp + (sp - Vector3(wb.show[0], sp.y, wb.show[2])).normalized() * 1.2, Vector3(wb.show[0], wb.show[1], wb.show[2]))
			await wait(0.5)
			m._look_at(sp, Vector3(wb.show[0], wb.show[1] - 0.3, wb.show[2]))
			await wait(0.3)
			print(wb.id, " prompt: ", game.interact_target.get("text", ""))
			m._look_at(sp + (sp - Vector3(wb.show[0], sp.y, wb.show[2])).normalized() * 2.0, Vector3(wb.show[0], wb.show[1] - 0.4, wb.show[2]))
			await wait(0.4)
			await snap("wall_" + wb.id)
	# band room wide shot
	m._look_at(Vector3(15.5, 4.05, -33.2), Vector3(15.5, 5.0, -43))
	await wait(0.5)
	await snap("bandroom")
	for id in ["book", "dodge", "bone", "slip"]:
		clear()
		m._look_at(Vector3(0, 0.05, 12), Vector3(0, 1.3, 0))
		player.give(id, 40)
		player.cur = player.owns(id)
		player.build_gun()
		var zs := []
		for i in 5:
			zs.append(zombie("walker", Vector3(-3 + i * 1.5, 0.05, 6.0 - (i % 2) * 1.5)))
		await wait(0.7)
		await snap(id + "_held")
		var killed := 0
		for k in 3:
			var tz = zs[2]
			for z in zs:
				if is_instance_valid(z) and z.alive and z.global_position.distance_to(Vector3(0, 0, 5)) < 12:
					tz = z
					break
			if is_instance_valid(tz):
				m._look_at(Vector3(0, 0.05, 12), tz.global_position + Vector3(0, 1.1, 0))
			await wait(0.1)
			player.fire_t = 0
			player.shoot()
			if k == 0:
				await wait(0.18)
				await snap(id + "_fire")
			await wait(0.8)
		for z in zs:
			if not is_instance_valid(z) or not z.alive or z.global_position.distance_to(Vector3(0, 0, 5)) > 15:
				killed += 1
		print(id, ": shots left in flight ", game.wonder.shots.size())
		print(id, ": zombies down/sent away ", killed, "/5  mag=", player.slots[player.cur].mag)
		await snap(id + "_after")
	# Pack-a-Punched dodgeball splits
	clear()
	player.give("dodge", 40)
	player.slots[player.owns("dodge")].up = true
	player.cur = player.owns("dodge")
	player._upw.clear()
	player.build_gun()
	var zs2 := []
	for i in 8:
		zs2.append(zombie("walker", Vector3(-5 + i * 1.4, 0.05, 5.0 - (i % 3) * 1.2), 10))
	await wait(0.5)
	m._look_at(Vector3(0, 0.05, 12), zs2[3].global_position + Vector3(0, 1.1, 0))
	player.fire_t = 0
	player.shoot()
	await wait(0.25)
	print("doublemint balls in flight: ", game.wonder.shots.size())
	await snap("doublemint")
	await wait(2.0)
	clear()
	game.state = "stage"

# ---------------------------------------------------------------- bosses
func _boss() -> void:
	for bt in ["coach", "principal", "chem", "lunch"]:
		clear()
		game.state = "play"
		game.to_spawn = 0
		game.wave = 5
		m._look_at(Vector3(0, 0.05, 13), Vector3(0, 2, 2))
		var z = preload("res://scripts/zombie.gd").new()
		game.zroot.add_child(z)
		z.setup(game, "boss", Vector3(0, 0.05, 4), 5, bt)
		game.zombies.append(z)
		game.boss = z
		game.bosses.start(z)
		z.emerge = 0
		game.bosses.taunt_t = 0.5
		await wait(1.2)
		await snap(bt + "_taunt")
		z.move_t = 0.0
		z.move2_t = 0.0
		await wait(0.9)
		await snap(bt + "_move")
		z.hp = z.max_hp * 0.45
		await wait(0.6)
		print(bt, " phase=", z.phase, " hp=", int(z.hp), "/", int(z.max_hp), " player hp lost=", int(1e9 - player.hp))
		await snap(bt + "_phase2")
		await wait(2.5)
		await snap(bt + "_p2b")
		player.hp = 1e9
		game.boss = null
	clear()
	game.state = "stage"

func _pa() -> void:
	game.state = "inter"
	game.silly.pa(10)
	await wait(2.0)
	await snap("pa")
	game.state = "stage"

# ---------------------------------------------------------------- escape
func _escape() -> void:
	clear()
	game.state = "play"
	game.to_spawn = 0
	game.points = 12000
	m._look_at(game.escape.DOOR_SPOT + Vector3(0, 0.05, 0.5), Vector3(36.1, 1.3, 28.4))
	await wait(0.4)
	print("bus prompt (poor): ", game.interact_target.get("text", ""))
	game.points = 41000
	await wait(0.3)
	print("bus prompt: ", game.interact_target.get("text", ""))
	await snap("bus_prompt")
	# gate from the yard
	m._look_at(Vector3(42, 0.05, 31), Vector3(50, 1.6, 27))
	await wait(0.4)
	await snap("gate_yard")
	m._look_at(game.escape.DOOR_SPOT + Vector3(0, 0.05, 0.5), Vector3(36.1, 1.3, 28.4))
	await wait(0.3)
	game.interact_target = game._find_interact()
	game.interact()
	var tags := ["board", "engine", "swarm", "plough", "slowmo", "slowmo2", "night"]
	for i in [1.2, 3.6, 6.2, 8.4, 10.0, 12.2, 15.6]:
		pass
	var t := 0.0
	var marks := [1.2, 4.6, 6.8, 8.9, 10.8, 11.6, 14.0]
	var k := 0
	while k < marks.size():
		await get_tree().process_frame
		t += get_process_delta_time() / maxf(Engine.time_scale, 0.001)
		if t >= marks[k]:
			await snap("esc_" + tags[k])
			k += 1
	await wait(6.0)
	await snap("escaped")
	print("scores: ", game.settings.scores)

# ---------------------------------------------------------------- pause (keyboard ESC and controller Start)
func _press(ev: InputEvent) -> void:
	ev.pressed = true
	Input.parse_input_event(ev)
	await wait(0.3)
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await wait(0.4)

func _pause() -> void:
	clear()
	game.state = "play"
	game.to_spawn = 5
	for dev in ["esc", "start"]:
		var ev: InputEvent
		if dev == "esc":
			var k := InputEventKey.new()
			k.keycode = KEY_ESCAPE
			k.physical_keycode = KEY_ESCAPE
			ev = k
		else:
			var j := InputEventJoypadButton.new()
			j.button_index = JOY_BUTTON_START
			ev = j
		await _press(ev)
		print(dev, ": paused=", get_tree().paused, " menu=", m.menu.visible, " page=", m.menu.page)
		await snap("pause_" + dev)
		await _press(ev)
		print(dev, ": after second press paused=", get_tree().paused, " menu=", m.menu.visible)
	game.state = "stage"

# ---------------------------------------------------------------- ragdoll pile: machine-gun a crowd, then see if the bodies settle
func _rag() -> void:
	clear()
	game.state = "stage"
	m._look_at(Vector3(-46, 0.05, 2), Vector3(-46, 1.0, -6))
	player.give("lmg", 300)
	player.cur = player.owns("lmg")
	player.build_gun()
	var zs := []
	for i in 10:
		var z = zombie("walker", Vector3(-47.5 + (i % 4) * 1.0, 0.05, -5.5 - (i / 4) * 0.8), 8)
		z.speed = 0.0
		zs.append(z)
	await wait(0.5)
	game.state = "play"
	game.to_spawn = 0
	var t := 0.0
	var k := 0
	while t < 3.0:
		var tz = null
		for z in zs:
			if is_instance_valid(z) and z.alive:
				tz = z
				break
		var aim: Vector3 = (tz.global_position + Vector3(0, 1.2, 0)) if tz != null else Vector3(-46 + randf_range(-1.5, 1.5), 0.3, -6)
		m._look_at(Vector3(-46, 0.05, 2), aim)
		player.fire_t = 0
		player.slots[player.cur].mag = 100
		player.shoot()
		await wait(0.065)
		t += 0.065
		k += 1
		if k % 12 == 0:
			await snap("rag_fire")
	print("kills=", game.kills, " ragdolls=", game.physics.ragdolls.size(), " props=", game.physics.props.size())
	for r in game.physics.ragdolls:
		for b in r.bodies:
			if is_instance_valid(b):
				print("   body at ", b.global_position, " v=", b.linear_velocity.length())
				break
	for s in 8:
		await wait(0.5)
		var sp := 0.0
		var mx := 0.0
		var nb := 0
		for r in game.physics.ragdolls:
			for b in r.bodies:
				if is_instance_valid(b):
					var v: float = b.linear_velocity.length() + b.angular_velocity.length() * 0.2
					sp += v
					mx = maxf(mx, v)
					nb += 1
		print("t+%.1f bodies=%d mean motion=%.2f max=%.2f" % [(s + 1) * 0.5, nb, sp / maxf(nb, 1), mx])
		if s == 1 or s == 7:
			await snap("rag_settle")
	game.state = "stage"

func _hitscan() -> void:
	clear()
	game.state = "stage"
	m._look_at(Vector3(-46, 0.05, 2), Vector3(-46, 1.0, -6))
	var z = zombie("walker", Vector3(-46, 0.05, -6), 30)
	z.speed = 0.0
	await wait(0.5)
	var wd: Dictionary = game.world.data.weapons["pistol"].duplicate()
	wd.dmg = 0.01
	var hits := 0
	var heads := 0
	for i in 40:
		var o: Vector3 = player.cam.global_position
		var tgt: Vector3 = z.global_position + Vector3(randf_range(-0.15, 0.15), randf_range(0.9, 1.7), 0)
		var r: Dictionary = game.shoot_ray(o, (tgt - o).normalized(), wd)
		if r.hit:
			hits += 1
		await get_tree().physics_frame
	print("hitscan: ", hits, "/40 hits on a standing zombie")
	# and while the shooter is firing a real LMG at it
	player.give("lmg", 300)
	player.cur = player.owns("lmg")
	player.build_gun()
	var hp0: float = z.hp
	for i in 30:
		m._look_at(Vector3(-46, 0.05, 2), z.global_position + Vector3(0, 1.2, 0))
		await get_tree().process_frame
		player.fire_t = 0
		player.shoot()
		await wait(0.09)
	print("lmg 30 shots: hp ", hp0, " -> ", z.hp, " alive=", z.alive)

# ---------------------------------------------------------------- the bat
func _bat() -> void:
	clear()
	game.state = "play"
	game.to_spawn = 0
	game.points = 5000
	for wb in game.world.data.wallbuys:
		if wb.id == "bat":
			m._look_at(Vector3(wb.spot[0], 0.05, wb.spot[2] + 1.0), Vector3(wb.show[0], wb.show[1], wb.show[2]))
			await wait(0.5)
			m._look_at(Vector3(wb.spot[0], 0.05, wb.spot[2]), Vector3(wb.show[0], wb.show[1], wb.show[2]))
			await wait(0.3)
			print("bat prompt: ", game.interact_target.get("text", ""))
			m._look_at(Vector3(wb.spot[0], 0.05, wb.spot[2] + 1.0), Vector3(wb.show[0], wb.show[1], wb.show[2]))
			await wait(0.3)
			await snap("bat_wall")
			game.interact()
	print("slots=", player.slots.map(func(x): return x.id), " cur=", player.slots[player.cur].id)
	await wait(0.6)
	m._look_at(Vector3(-46, 0.05, 2), Vector3(-46, 1.4, -6))
	await wait(0.3)
	await snap("bat_idle")
	var zs := []
	for i in 6:
		var z = zombie("walker", Vector3(-47.5 + (i % 3) * 1.4, 0.05, -1.0 - (i / 3) * 1.3), 4)
		z.speed = 0.0
		zs.append(z)
	await wait(0.4)
	var tags := ["fore", "back", "slam", "fore2", "back2", "slam2"]
	for k in 6:
		player.fire_t = 0
		player.shoot()
		print("swing ", k, " n=", player.swing_n)
		# film the windup, the smear and the hit
		await wait(player.swing_hit * 0.6)
		await snap("bat_%s_a" % tags[k])
		await wait(player.swing_hit * 0.45)
		await snap("bat_%s_b" % tags[k])
		await wait(0.25)
		if k == 2:
			await snap("bat_%s_c" % tags[k])
		await wait(maxf(0.0, player.fire_t))
	var down := 0
	for z in zs:
		if not is_instance_valid(z) or not z.alive:
			down += 1
	print("bat: ", down, "/6 down, kills=", game.kills, " blood=", player.bat_blood)
	await wait(1.0)
	await snap("bat_after")
	clear()
	game.state = "stage"

# ---------------------------------------------------------------- list 4
func _walls4() -> void:
	game.state = "play"
	game.to_spawn = 0
	game.points = 20000
	for id in ["bat", "volc"]:
		for wb in game.world.data.wallbuys:
			if wb.id == id:
				var sp := Vector3(wb.spot[0], wb.spot[1] + 0.05, wb.spot[2])
				var show := Vector3(wb.show[0], wb.show[1], wb.show[2])
				m._look_at(sp, show)
				await wait(0.4)
				print(id, " prompt: ", game.interact_target.get("text", ""))
				m._look_at(sp + (sp - Vector3(show.x, sp.y, show.z)).normalized() * 1.6, show - Vector3(0, 0.25, 0))
				await wait(0.4)
				await snap("wall_" + id)
	print("wall-buy ids: ", game.world.data.wallbuys.map(func(w): return w.id))
	# the retired displays: stage and gym walls should be bare
	m._look_at(Vector3(-7, 0.95, -12.5), Vector3(-7, 2.3, -15.6))
	await wait(0.4)
	await snap("stage_wall")
	m._look_at(Vector3(-56.5, 0.05, -12), Vector3(-59.7, 1.6, -12))
	await wait(0.4)
	await snap("gym_ak_wall")
	game.state = "stage"

func _volc() -> void:
	clear()
	game.state = "play"
	game.to_spawn = 0
	player.give("volc", 36)
	player.cur = player.owns("volc")
	player.build_gun()
	m._look_at(Vector3(-46, 0.05, 2), Vector3(-46, 0.5, -6))
	var zs := []
	for i in 6:
		zs.append(zombie("walker", Vector3(-48 + (i % 3) * 2.0, 0.05, -5.5 - (i / 3) * 1.5), 5))
	await wait(0.5)
	await snap("volc_held")
	for k in 3:
		m._look_at(Vector3(-46, 0.05, 2), Vector3(-47.5 + k * 1.5, 0.3, -6))
		await wait(0.1)
		player.fire_t = 0
		player.shoot()
		await wait(0.9)
	print("foam puddles: ", game.wonder.foams.size(), " radii: ", game.wonder.foams.map(func(f): return snappedf(f.r, 0.01)))
	await snap("volc_foam")
	await wait(3.0)
	var down := 0
	var slowed := 0
	for z in zs:
		if not is_instance_valid(z) or not z.alive:
			down += 1
		elif z.slow_t > 0:
			slowed += 1
	print("volcano: down ", down, "/6, slowed ", slowed)
	await snap("volc_after")
	clear()
	game.state = "stage"

func _mascot() -> void:
	clear()
	game.state = "play"
	game.to_spawn = 0
	game.wave = 8
	m._look_at(Vector3(-46, 0.05, 4), Vector3(-46, 1.5, -6))
	var z = zombie("mascot", Vector3(-46, 0.05, -6), 8)
	await wait(0.2)
	z.speed = 0.0
	z.pounce_cd = 99.0
	await wait(0.5)
	await snap("mascot")
	var hp0: float = z.hp
	z.damage(40.0, "body", Vector3.FORWARD, 2.0)
	print("mascot body hit 40 -> lost ", hp0 - z.hp, " (costume soaks), head on=", z.cat_head != null)
	var hp1: float = z.hp
	z.damage(10.0, "head", Vector3.FORWARD, 2.0, false, z.joints["head"].global_position)
	print("headshot: head on=", z.cat_head != null, " lost ", hp1 - z.hp)
	await wait(0.4)
	await snap("mascot_headoff")
	# pounce
	z.speed = 6.0
	z.pounce_cd = 0.0
	var hp_p: float = player.hp
	player.hp = 100
	player.max_hp = 100
	var start: Vector3 = z.global_position
	await wait(0.3)
	await snap("mascot_pounce")
	await wait(1.0)
	print("pounce: moved ", snappedf(z.global_position.distance_to(start), 0.1), " m, player hp ", player.hp)
	player.hp = 1e9
	player.max_hp = 1e9
	clear()
	game.state = "stage"

func _grab() -> void:
	clear()
	game.state = "play"
	game.to_spawn = 0
	# find a loose chair or bin to pick up
	var target = null
	for b in game.physics.props:
		if is_instance_valid(b) and b is RigidBody3D and not b.get_meta("ragdoll", false) and not b.has_meta("temp") and b.mass <= 16.0 and absf(b.global_position.y) < 1.5:
			target = b
			break
	print("prop to grab: ", target, " mass ", target.mass if target else -1)
	# bring it to the open gym floor so the throw has a clear line
	game.physics.wake(target)
	target.global_position = Vector3(-46, 0.6, 1.0)
	target.linear_velocity = Vector3.ZERO
	await wait(0.6)
	var tp: Vector3 = target.global_position
	m._look_at(tp + Vector3(1.4, -0.4, 0.6), tp)
	await wait(0.3)
	m._look_at(tp + Vector3(1.4, -0.4, 0.6) - Vector3(0, 0, 0), tp)
	await get_tree().physics_frame
	game.interact_target = game._find_interact()
	print("grab prompt: ", game.interact_target.get("text", ""))
	game.interact()
	await wait(0.4)
	print("holding: ", game.grab.held == target)
	await snap("grab_hold")
	var z = zombie("walker", Vector3(-46, 0.05, -5.0), 5)
	z.speed = 0.0
	await wait(0.4)
	m._look_at(player.global_position, z.global_position + Vector3(0, 1.1, 0))
	await wait(0.1)
	var hp0: float = z.hp
	player.trigger = true
	player.trigger_was = false
	game.grab.throw()
	await wait(0.12)
	await snap("grab_throw")
	await wait(0.8)
	print("thrown: zombie hp ", hp0, " -> ", z.hp if is_instance_valid(z) else -1, " alive=", is_instance_valid(z) and z.alive, " stagger=", z.stagger if is_instance_valid(z) else 0)
	await snap("grab_after")
	# extinguisher off the wall
	for e in game.physics.extinguishers:
		if not e.live and is_instance_valid(e.body):
			var ep: Vector3 = e.pos
			m._look_at(ep + Vector3(0, -1.1, 0) + (Vector3(e.pos.x, 0, e.pos.z) - Vector3(e.body.global_position.x, 0, e.body.global_position.z)) + Vector3(0.8, 0, 0.8), ep)
			await get_tree().physics_frame
			print("ext prompt: ", game.grab.prompt())
			break
	clear()
	game.state = "stage"

func _deathcam() -> void:
	clear()
	game.state = "play"
	game.to_spawn = 0
	m._look_at(Vector3(-46, 0.05, 2), Vector3(-46, 1.4, -6))
	var z = zombie("runner", Vector3(-46, 0.05, 0.6), 5)
	z.speed = 0.0
	await wait(0.4)
	game.last_attacker = z
	player.hp = 5
	player.max_hp = 100
	player.hurt(50)
	await wait(0.5)
	await snap("death_swing")
	await wait(1.2)
	await snap("death_photo")
	await wait(2.5)
	await snap("death_over")
	print("deathcam playing=", game.deathcam.playing, " state=", game.state)

func _rain() -> void:
	game.state = "stage"
	m._look_at(Vector3(10, 0.05, 28), Vector3(30, 1.5, 26))
	for k in [0.3, 1.0, 1.8]:
		game.world.rain_k = k
		game.rain_target = k
		game.rain_hold = 999.0
		await wait(1.5)
		await snap("rain_%s" % str(k))
	print("rain ratio at 1.8: ", game.world.rain.amount_ratio)

func _lamps() -> void:
	game.state = "stage"
	m._look_at(Vector3(-22, 0.05, 15), Vector3(-44, 2.0, 30))
	await wait(1.0)
	var st: Array = game.world.lamps.filter(func(l): return l.street)
	print("street lamps: ", st.size(), " energy before ", st.map(func(l): return snappedf(l.light.light_energy, 0.01)))
	await snap("lamps_before")
	game.world.street_surge(0.0)
	await wait(3.0)
	print("energy after ", st.map(func(l): return snappedf(l.light.light_energy, 0.01)))
	await snap("lamps_after")

# ---------------------------------------------------------------- intro students
func _intro() -> void:
	game.state = "menu"
	game.hud.visible = true
	var t := 0.0
	game.cutscene.infection()
	var marks := [5.5, 9.0, 20.8, 21.6, 22.0, 23.5, 26.5]
	var k := 0
	while k < marks.size():
		await get_tree().process_frame
		t += get_process_delta_time()
		if t >= marks[k]:
			await snap("intro_%d" % k)
			k += 1
	while game.cutscene.playing:
		await get_tree().process_frame
