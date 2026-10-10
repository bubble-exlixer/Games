extends Node
## Dead Shift: Westfield High. Builds the game, renders the 3D at low resolution for the PS2 look,
## and (for testing) can play itself: run with  -- --bot --time=60 --shots=5

var view: SubViewport
var container: SubViewportContainer
var world
var player
var game
var hud
var fx
var audio
var zroot: Node3D
var hud_box: SubViewportContainer
var settings
var menu
var hud_view: SubViewport
var bot := false
var stage := false
var rules := false
var chase := false
var extras := false
var tour := ""
var topdown := ""
var t3 := ""
var powertest := false
var bot_time := 0.0
var shot_every := 0.0
var shot_t := 0.0
var shot_n := 0
var run_for := 0.0
var stats_t := 0.0
var bot_target = null
var bot_wander := Vector3.ZERO
var bot_wander_t := 0.0

func _actions() -> void:
	var keys := {"fwd": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D, "jump": KEY_SPACE, "sprint": KEY_SHIFT,
		"reload": KEY_R, "use": KEY_F, "nade": KEY_G, "nade2": KEY_E, "swap": KEY_Q, "slot1": KEY_1, "slot2": KEY_2, "melee": KEY_V, "torch": KEY_L, "pause": KEY_ESCAPE}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		var e := InputEventKey.new()
		e.physical_keycode = keys[a]
		InputMap.action_add_event(a, e)
	for a in [["fire", MOUSE_BUTTON_LEFT], ["ads", MOUSE_BUTTON_RIGHT]]:
		if not InputMap.has_action(a[0]):
			InputMap.add_action(a[0])
		var m := InputEventMouseButton.new()
		m.button_index = a[1]
		InputMap.action_add_event(a[0], m)
	# controller (Xbox layout): sticks, triggers, face buttons
	for a in [["left", JOY_AXIS_LEFT_X, -1.0], ["right", JOY_AXIS_LEFT_X, 1.0], ["fwd", JOY_AXIS_LEFT_Y, -1.0], ["back", JOY_AXIS_LEFT_Y, 1.0],
			["fire", JOY_AXIS_TRIGGER_RIGHT, 1.0], ["ads", JOY_AXIS_TRIGGER_LEFT, 1.0]]:
		var jm := InputEventJoypadMotion.new()
		jm.axis = a[1]
		jm.axis_value = a[2]
		InputMap.action_add_event(a[0], jm)
	# menus: A selects, B backs out, the left stick moves the focus too (Godot's defaults only have the D-pad)
	for a in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B]]:
		var ub := InputEventJoypadButton.new()
		ub.button_index = a[1]
		InputMap.action_add_event(a[0], ub)
	for a in [["ui_left", JOY_AXIS_LEFT_X, -1.0], ["ui_right", JOY_AXIS_LEFT_X, 1.0], ["ui_up", JOY_AXIS_LEFT_Y, -1.0], ["ui_down", JOY_AXIS_LEFT_Y, 1.0]]:
		var um := InputEventJoypadMotion.new()
		um.axis = a[1]
		um.axis_value = a[2]
		InputMap.action_add_event(a[0], um)
	for a in [["jump", JOY_BUTTON_A], ["use_reload", JOY_BUTTON_X], ["melee", JOY_BUTTON_B], ["melee", JOY_BUTTON_RIGHT_STICK], ["swap", JOY_BUTTON_Y],
			["nade", JOY_BUTTON_RIGHT_SHOULDER], ["sprint_pad", JOY_BUTTON_LEFT_STICK], ["pause", JOY_BUTTON_START], ["torch", JOY_BUTTON_DPAD_UP]]:
		if not InputMap.has_action(a[0]):
			InputMap.add_action(a[0])
		var jb := InputEventJoypadButton.new()
		jb.button_index = a[1]
		InputMap.action_add_event(a[0], jb)

func _ready() -> void:
	randomize()
	_actions()
	for a in OS.get_cmdline_user_args():
		if a == "--bot":
			bot = true
		elif a.begins_with("--time="):
			run_for = float(a.substr(7))
		elif a == "--rules":
			rules = true
		elif a == "--probe":
			_probe.call_deferred()
		elif a == "--newtest":
			_newtest.call_deferred()
		elif a == "--phystest":
			_phystest.call_deferred()
		elif a == "--powertest":
			powertest = true
		elif a.begins_with("--topdown="):
			topdown = a.substr(10)
		elif a.begins_with("--t3="):
			t3 = a.substr(5)
		elif a.begins_with("--tour="):
			tour = a.substr(7)
		elif a == "--extras":
			extras = true
		elif a == "--chase":
			chase = true
		elif a == "--stage":
			stage = true
		elif a.begins_with("--shots="):
			shot_every = float(a.substr(8))
	# low-res 3D, upscaled with hard pixels
	container = SubViewportContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.stretch_shrink = 2
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(container)
	view = SubViewport.new()
	view.audio_listener_enable_3d = true
	view.positional_shadow_atlas_size = 2048
	container.add_child(view)
	audio = preload("res://scripts/audio.gd").new()
	add_child(audio)
	# the HUD draws into its own half-resolution layer too, so the type comes out chunky like the 3D
	hud_box = SubViewportContainer.new()
	hud_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_box.stretch = true
	hud_box.stretch_shrink = 2
	hud_box.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hud_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud_box)
	hud_view = SubViewport.new()
	hud_view.transparent_bg = true
	hud_view.size_2d_override_stretch = true
	hud_view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	hud_view.gui_disable_input = true
	hud_box.add_child(hud_view)
	hud = preload("res://scripts/hud.gd").new()
	hud_view.add_child(hud)
	get_viewport().size_changed.connect(_fit_hud)
	_fit_hud.call_deferred()
	world = preload("res://scripts/world.gd").new()
	view.add_child(world)
	audio.world_root = world
	fx = preload("res://scripts/fx.gd").new()
	world.add_child(fx)
	zroot = Node3D.new()
	zroot.name = "Zombies"
	world.add_child(zroot)
	settings = preload("res://scripts/settings.gd").new()
	add_child(settings)
	game = preload("res://scripts/game.gd").new()
	add_child(game)
	game.settings = settings
	game.skin = settings.s.skin
	player = preload("res://scripts/player.gd").new()
	world.add_child(player)
	player.bot = bot
	game.setup(world, player, hud, fx, audio, zroot)
	player.setup(game, world.data.start)
	player.cam.current = true
	menu = preload("res://scripts/menu.gd").new()
	add_child(menu)
	menu.setup(self, settings)
	game.menu_hint_cb = menu.nav_hint
	menu.play_pressed.connect(_start_game)
	settings.apply(self)
	on_settings_changed()
	if not world.nav_baked_once:
		await world.nav_ready
	audio.start_ambience()
	hud.set_loading("", true)
	if not bot:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if stage:
		_stage()
	if rules:
		_rules()
	if chase:
		_chase()
	if extras:
		_extras()
	if tour != "":
		_tour()
	if t3 != "":
		if not (t3 in ["intro", "lamps"]):
			world.power_on(Vector3.ZERO)
		var tt = preload("res://scripts/tests3.gd").new()
		add_child(tt)
		tt.run(self, Array(t3.split(",")))
		return
	if topdown != "":
		_topdown()
	if powertest:
		_powertest()
	elif "--phystest" in OS.get_cmdline_user_args() or "--newtest" in OS.get_cmdline_user_args():
		world.power_on(Vector3.ZERO)
	elif bot or stage or rules or chase or extras or tour != "" or topdown != "":
		world.power_on(Vector3.ZERO)
	elif "--menutest" in OS.get_cmdline_user_args():
		game.state = "menu"
		hud.visible = false
		menu.open_main()
		_menutest()
	elif Engine.get_meta("skip_menu", false):
		_start_game()
	else:
		_boot()

## the first launch of a session plays the "how it started" cutscene, then the main menu
func _boot() -> void:
	game.state = "menu"
	if not Engine.get_meta("seen_intro", false):
		Engine.set_meta("seen_intro", true)
		hud.visible = true
		await game.cutscene.infection()
		game.state = "menu"
	hud.visible = false
	menu.open_main()

func _start_game() -> void:
	menu.close()
	hud.visible = true
	game.state = "inter"
	game.inter_t = 3.0
	player.set_start_gun(settings.s.start_gun)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	game.cutscene.intro()

func on_settings_changed() -> void:
	player.sens_k = settings.s.sens
	player.pad_k = settings.s.pad_sens
	player.assist_k = float(settings.s.aim_assist)
	player.pad_dead = float(settings.s.pad_dead)
	player.invert = settings.s.invert_y
	player.base_fov = settings.s.fov
	game.skin = settings.s.skin

func _fit_hud() -> void:
	hud_view.size_2d_override = Vector2i(get_viewport().get_visible_rect().size)

func _input(e: InputEvent) -> void:
	# which device is the player using? (button prompts + aim assist follow it)
	if e is InputEventJoypadButton or (e is InputEventJoypadMotion and absf(e.axis_value) > 0.4):
		if not game.pad:
			game.pad = true
			game.hud.device_changed()
	elif e is InputEventKey or e is InputEventMouseButton or (e is InputEventMouseMotion and e.relative.length() > 3.0):
		if game.pad:
			game.pad = false
			game.hud.device_changed()
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player.on_mouse(e.relative)
		return
	# in a browser frame that refuses pointer lock, still steer with the mouse
	if e is InputEventMouseMotion and OS.has_feature("web") and not menu.visible and (game.state == "play" or game.state == "inter"):
		player.on_mouse(e.relative)
		return
	if menu.visible:
		return
	var pressed: bool = e.is_pressed() and not e.is_echo()
	if game.deathcam.playing:
		if pressed and not (e is InputEventJoypadMotion):
			game.deathcam.request_skip()
		return
	if game.cutscene.playing:
		if pressed and not (e is InputEventJoypadMotion) and not (e is InputEventKey and e.keycode == KEY_F11):
			game.cutscene.request_skip()
		return
	if e.is_action_pressed("pause"):
		if game.state == "over":
			Engine.set_meta("skip_menu", false)
			get_tree().reload_current_scene()
		elif game.state == "play" or game.state == "inter":
			menu.open_pause()
		# don't let the same press reach the menu (it would close the pause menu straight away)
		get_viewport().set_input_as_handled()
		return
	if e is InputEventMouseButton and e.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and game.state != "over" and game.state != "menu":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F11:
		settings.s.fullscreen = DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN
		settings.apply(self)
		return
	if game.state == "menu" or not pressed:
		return
	if game.state == "over" and game.escape.escaped:
		if game.escape.can_leave and not (e is InputEventMouseMotion or e is InputEventJoypadMotion):
			game.escape._to_menu()
		return
	if e.is_action_pressed("reload") and game.state == "over":
		Engine.set_meta("skip_menu", true)
		get_tree().reload_current_scene()
	elif e.is_action_pressed("use"):
		game.interact()
	elif e.is_action_pressed("use_reload"):
		if game.state == "over":
			Engine.set_meta("skip_menu", true)
			get_tree().reload_current_scene()
		elif not game.interact_target.is_empty():
			game.interact()
		else:
			player.reload()
	elif e.is_action_pressed("nade") or e.is_action_pressed("nade2"):
		game.throw_nade()
	elif e.is_action_pressed("reload"):
		player.reload()
	elif e.is_action_pressed("swap"):
		player.swap()
	elif e.is_action_pressed("slot1") and player.cur != 0:
		player.swap()
	elif e.is_action_pressed("slot2") and player.cur != 1:
		player.swap()
	elif e.is_action_pressed("melee"):
		player.melee()
	elif e.is_action_pressed("torch"):
		player.torch_on = not player.torch_on
	elif e is InputEventMouseButton and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			player.swap()

func _process(dt: float) -> void:
	if bot:
		_bot(dt)
	bot_time += dt
	if shot_every > 0:
		shot_t += dt
		if shot_t >= shot_every:
			shot_t = 0
			shot_n += 1
			get_viewport().get_texture().get_image().save_png("user://bot_%02d.png" % shot_n)
	stats_t += dt
	if bot and stats_t > 5:
		stats_t = 0
		print("proc=%.1fms phys=%.1fms nades=%d parts=%d decals=%d | " % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000, game.grenades, fx.parts.size(), fx.decals.size()], "t=%.0f fps=%d wave=%d alive=%d kills=%d hp=%d pts=%d gun=%s pos=%s" % [bot_time, Engine.get_frames_per_second(), game.wave, game.zombies.size(), game.kills, player.hp, game.points, player.slots[player.cur].id, str(player.global_position.snapped(Vector3(0.1, 0.1, 0.1)))])
	if run_for > 0 and bot_time > run_for:
		print("DONE wave=%d kills=%d hp=%d dead=%s" % [game.wave, game.kills, player.hp, str(player.dead)])
		get_tree().quit()

## a crude test player: turns to the nearest zombie it can see and shoots; otherwise wanders
func _bot(dt: float) -> void:
	var p = player
	var best = null
	var bd := 40.0
	for z in game.zombies:
		if not z.alive:
			continue
		var d: float = z.global_position.distance_to(p.global_position)
		if d < bd:
			var q := PhysicsRayQueryParameters3D.create(p.cam.global_position, z.global_position + Vector3(0, 1.3, 0), 1)
			if world.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				best = z
				bd = d
	p.bot_input.fire = false
	p.bot_input.look = Vector2.ZERO
	if best:
		var to: Vector3 = best.global_position + Vector3(0, 1.3 if not best.crawler else 0.4, 0) - p.cam.global_position
		var want_yaw := atan2(-to.x, -to.z)
		var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
		var dy: float = wrapf(want_yaw - p.yaw, -PI, PI)
		var dp: float = want_pitch - p.pitch
		p.bot_input.look = Vector2(-dy * minf(1.0, dt * 10), -dp * minf(1.0, dt * 10))
		var wd: Dictionary = p.w()
		p.bot_input.fire = absf(dy) < 0.08 and (wd.auto or Engine.get_process_frames() % 2 == 0)
		p.bot_input.move = Vector2(0, 0.6) if bd < 4 else Vector2.ZERO
		var close := 0
		for z in game.zombies:
			if z.alive and z.global_position.distance_to(p.global_position) < 12:
				close += 1
		if close >= 4 and bd > 5 and absf(dy) < 0.1:
			game.throw_nade()
	else:
		bot_wander_t -= dt
		if bot_wander_t <= 0:
			bot_wander_t = 3
			bot_wander = Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
		var to2: Vector3 = Vector3(world.data.start[0], 0, world.data.start[2]) + bot_wander - p.global_position
		var dy2: float = wrapf(atan2(-to2.x, -to2.z) - p.yaw, -PI, PI)
		p.bot_input.look = Vector2(-dy2 * minf(1.0, dt * 4), p.pitch * minf(1.0, dt * 4))
		p.bot_input.move = Vector2(0, -1) if to2.length() > 2 else Vector2.ZERO
	# keep points flowing into something useful
	if game.points >= 1200 and p.owns("ak") < 0 and game.wave >= 2:
		game.points -= 1200
		p.give("ak", 120)

## test staging: line up zombies in the cafeteria and shoot some of them
func _stage() -> void:
	game.state = "stage"
	player.global_position = Vector3(0, 0.05, 6)
	player.yaw = 0
	game.wave = 6
	var kinds := ["walker", "runner", "armored", "bloater", "spitter", "walker"]
	for i in kinds.size():
		var z = preload("res://scripts/zombie.gd").new()
		zroot.add_child(z)
		z.setup(game, kinds[i], Vector3(-5 + i * 2.0, 0.05, -4), 6)
		z.emerge = 0
		z.rotation.y = 0
		game.zombies.append(z)
	player.dead = true      # keep them standing still: they ignore a dead player
	await get_tree().create_timer(1.5).timeout
	get_viewport().get_texture().get_image().save_png("user://stage_1.png")
	# shoot: headshot, arm, and a shotgun blast
	var zs: Array = game.zombies.duplicate()
	zs[0].damage(500, "head", Vector3(0, 0, -1), 4)
	zs[1].damage(5, "armL", Vector3(0, 0, -1), 4)
	zs[1].lost = {}
	zs[1]._sever("armL", Vector3(0, 0, -1))
	zs[2].damage(5, "body", Vector3(0, 0, -1), 4)
	zs[3].damage(900, "body", Vector3(0, 0, -1), 8)
	zs[5]._make_crawler(Vector3(0, 0, -1))
	await get_tree().create_timer(0.25).timeout
	get_viewport().get_texture().get_image().save_png("user://stage_2.png")
	await get_tree().create_timer(1.2).timeout
	get_viewport().get_texture().get_image().save_png("user://stage_3.png")
	# a barrel next to more zombies, then a grenade
	var bar = game.barrels[4]
	var view_dir := Vector3(0, 0, 1)
	for k in 8:
		var dd := Vector3(sin(k * PI / 4), 0, cos(k * PI / 4))
		var q := PhysicsRayQueryParameters3D.create(bar.pos + Vector3(0, 1.4, 0) + dd * 0.6, bar.pos + Vector3(0, 1.4, 0) + dd * 8.0, 1)
		if world.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			view_dir = dd
			break
	player.global_position = bar.pos + Vector3(0, 0.05, 0) + view_dir * 7.0
	player.yaw = atan2(view_dir.x, view_dir.z)
	player.pitch = -0.15
	var side := view_dir.cross(Vector3.UP)
	for i in 4:
		var z2 = preload("res://scripts/zombie.gd").new()
		zroot.add_child(z2)
		z2.setup(game, "walker", bar.pos + side * (-2 + i * 1.3) + view_dir * 1.5 + Vector3(0, 0.05, 0), 6)
		z2.emerge = 0
		game.zombies.append(z2)
	await get_tree().create_timer(0.8).timeout
	game.damage_barrel(bar, 100, bar.pos + Vector3(0, 0.6, 0), Vector3(0, 0, -1))
	await get_tree().create_timer(0.12, true, false, true).timeout
	get_viewport().get_texture().get_image().save_png("user://stage_4.png")
	await get_tree().create_timer(0.5, true, false, true).timeout
	get_viewport().get_texture().get_image().save_png("user://stage_5.png")
	await get_tree().create_timer(2.0).timeout
	get_viewport().get_texture().get_image().save_png("user://stage_6.png")
	# the box
	var b = world.data.boxes[game.box_spot]
	player.global_position = Vector3(b.pos[0], b.pos[1] + 0.05, b.pos[2]) + Vector3(0, 0, 2.6).rotated(Vector3.UP, b.ry)
	player.yaw = b.ry
	player.pitch = -0.25
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png("user://stage_7.png")
	game._box_roll()
	await get_tree().create_timer(1.5).timeout
	get_viewport().get_texture().get_image().save_png("user://stage_8.png")
	await get_tree().create_timer(2.6).timeout
	get_viewport().get_texture().get_image().save_png("user://stage_9.png")
	print("box state=", game.box_state, " weapon=", game.box_weapon)
	# grenade: thrown down the cafeteria
	player.dead = false
	player.global_position = Vector3(0, 0.05, 8)
	player.yaw = 0
	player.pitch = 0.15
	game.state = "inter"
	game.inter_t = 999
	await get_tree().create_timer(0.3).timeout
	game.throw_nade()
	for i in 8:
		await get_tree().create_timer(0.25, true, false, true).timeout
		if game.nades.size() > 0:
			print("nade t=%.2f pos=%s rest=%s" % [i * 0.25, str(game.nades[0].n.global_position.snapped(Vector3(0.01, 0.01, 0.01))), str(game.nades[0].rest)])
		else:
			print("nade gone at t=%.2f" % (i * 0.25))
			get_viewport().get_texture().get_image().save_png("user://stage_10.png")
			break
	get_tree().quit()

## test the shop: every door, every wall-buy, the box
func _rules() -> void:
	game.state = "stage"
	game.points = 100000
	await get_tree().create_timer(0.5).timeout
	for d in world.data.doors:
		var s: Array = d.spots[0]
		player.global_position = Vector3(s[0], s[1] + 0.05, s[2])
		await get_tree().physics_frame
		game.interact_target = game._find_interact()
		var kind: String = game.interact_target.get("kind", "none")
		game.interact()
		print("door %s prompt=%s open=%s" % [d.id, kind, str(world.doors[d.id].open)])
	for wb in world.data.wallbuys:
		var s: Array = wb.spot
		player.global_position = Vector3(s[0], s[1] + 0.05, s[2])
		await get_tree().physics_frame
		game.interact_target = game._find_interact()
		var kind: String = game.interact_target.get("kind", "none")
		game.interact()
		print("wallbuy %s prompt=%s slots=%s" % [wb.id, kind, str(player.slots.map(func(x): return x.id))])
	var b = world.data.boxes[game.box_spot]
	player.global_position = Vector3(b.pos[0], b.pos[1] + 0.05, b.pos[2]) + Vector3(0, 0, 1.2).rotated(Vector3.UP, b.ry)
	await get_tree().physics_frame
	game.interact_target = game._find_interact()
	print("box prompt=", game.interact_target.get("kind", "none"))
	game.interact()
	await get_tree().create_timer(4.0).timeout
	print("box state=", game.box_state)
	game.interact_target = game._find_interact()
	print("box prompt2=", game.interact_target.get("text", "none"))
	game.interact()
	await get_tree().create_timer(0.5).timeout
	print("after box slots=", player.slots.map(func(x): return x.id), " points=", game.points)
	# navmesh after all doors: can a zombie path from the yard to the library?
	await get_tree().create_timer(2.0).timeout
	var map_rid: RID = world.nav.get_navigation_map()
	var path := NavigationServer3D.map_get_path(map_rid, Vector3(-50, 0, 30), Vector3(-27, 4, -38), true)
	print("path yard->library points=", path.size(), " end=", path[path.size() - 1] if path.size() > 0 else "none")
	path = NavigationServer3D.map_get_path(map_rid, Vector3(16, 0, 31), Vector3(3, 4, -30), true)
	print("path start->upstairs points=", path.size(), " end=", path[path.size() - 1] if path.size() > 0 else "none")
	get_tree().quit()

## pathing test: every door open, a player who can't die, a crowd from every spawn; who gets there?
func _chase() -> void:
	game.state = "stage"
	for d in world.data.doors:
		game.open_areas[d.id] = true
		world.open_door(d.id)
	await get_tree().create_timer(3.0).timeout
	for spot in [Vector3(16, 0.05, 31.5), Vector3(0, 0.05, 6), Vector3(3, 4.05, -30), Vector3(-27, 4.05, -38), Vector3(-58, 0.05, 6)]:
		for z in game.zombies:
			z.queue_free()
		game.zombies.clear()
		player.global_position = spot
		player.hp = 1e9
		player.max_hp = 1e9
		game.respawns = 0
		var spawns: Array = world.data.spawns.duplicate()
		spawns.shuffle()
		for i in 18:
			var sp = spawns[i % spawns.size()]
			var z = preload("res://scripts/zombie.gd").new()
			zroot.add_child(z)
			z.setup(game, "walker", Vector3(sp.pos[0], sp.pos[1], sp.pos[2]), 3)
			z.speed = 4.0
			game.zombies.append(z)
		var t := 0.0
		var reached := {}
		while t < 40.0:
			await get_tree().create_timer(1.0).timeout
			t += 1.0
			for z in game.zombies:
				if z.global_position.distance_to(player.global_position) < 2.5:
					reached[z] = true
		var far := []
		for z in game.zombies:
			if not reached.has(z):
				far.append(str(z.global_position.snapped(Vector3(0.5, 0.5, 0.5))))
		print("chase %s reached=%d/%d respawns=%d stuck_at=%s" % [str(spot), reached.size(), game.zombies.size(), game.respawns, ", ".join(far)])
	get_tree().quit()

## test: the three bosses, the knife, and Hammy
func _extras() -> void:
	game.state = "play"
	game.to_spawn = 0
	game.wave = 5
	game.boss_spawned = true
	player.hp = 1e9
	player.max_hp = 1e9
	player.global_position = Vector3(0, 0.05, 8)
	player.yaw = 0
	player.pitch = -0.05
	await get_tree().create_timer(0.5).timeout
	var n := 0
	for t in ["coach", "principal", "chem"]:
		print("extras: spawning ", t)
		game.spawn_boss(t)
		print("extras: spawned ", t)
		var b = game.boss
		b.global_position = Vector3(0, 0.05, 2.5)
		b.emerge = 0
		b.rotation.y = 0
		await get_tree().create_timer(1.2).timeout
		n += 1
		get_viewport().get_texture().get_image().save_png("user://extra_%d.png" % n)
		await get_tree().create_timer(2.5).timeout
		n += 1
		get_viewport().get_texture().get_image().save_png("user://extra_%d.png" % n)
		print("boss %s hp=%d alive=%s flasks=%d shutters=%d zombies=%d" % [t, b.hp, str(b.alive), game.flasks.size(), game.shutters.size(), game.zombies.size()])
		print("extras: killing boss")
		b.damage(99999, "body", Vector3(0, 0, -1), 8)
		print("extras: boss killed")
		await get_tree().create_timer(0.3, true, false, true).timeout
		n += 1
		get_viewport().get_texture().get_image().save_png("user://extra_%d.png" % n)
		for z in game.zombies.duplicate():
			z.damage(99999, "body", Vector3(0, 0, -1), 4)
		await get_tree().create_timer(1.5).timeout
	# knife: one zombie in front, stab mid-swing screenshot
	var z = preload("res://scripts/zombie.gd").new()
	zroot.add_child(z)
	z.setup(game, "walker", player.global_position + Vector3(0, 0, -1.4), 5)
	z.emerge = 0
	game.zombies.append(z)
	await get_tree().create_timer(0.3).timeout
	player.melee()
	await get_tree().create_timer(0.12, true, false, true).timeout
	n += 1
	get_viewport().get_texture().get_image().save_png("user://extra_%d.png" % n)
	await get_tree().create_timer(0.5).timeout
	print("knife: zombie killed=", not is_instance_valid(z) or not z.alive)
	# Hammy
	player.global_position = Vector3(29.5, 0.05, -3.3)
	player.yaw = -PI / 2
	player.pitch = -0.35
	game.points = 5000
	await get_tree().create_timer(0.5).timeout
	game.interact_target = game._find_interact()
	print("hammy prompt=", game.interact_target.get("text", "none"))
	n += 1
	get_viewport().get_texture().get_image().save_png("user://extra_%d.png" % n)
	for i in 3:
		game.interact_target = game._find_interact()
		game.interact()
		await get_tree().create_timer(0.3).timeout
	await get_tree().create_timer(2.5).timeout
	print("hammy free=", game.hammy.free)
	var z2 = preload("res://scripts/zombie.gd").new()
	zroot.add_child(z2)
	z2.setup(game, "walker", player.global_position + Vector3(-3, 0, 0), 5)
	z2.emerge = 0
	game.zombies.append(z2)
	await get_tree().create_timer(2.5).timeout
	n += 1
	get_viewport().get_texture().get_image().save_png("user://extra_%d.png" % n)
	print("hammy bit: zombie killed=", not is_instance_valid(z2) or not z2.alive)
	get_tree().quit()

## screenshots from fixed spots: --tour=x,y,z,yaw,pitch;x,y,z,yaw,pitch;...
func _tour() -> void:
	game.state = "stage"
	player.dead = true
	var i := 0
	for spec in tour.split(";"):
		var v := spec.split(",")
		player.global_position = Vector3(float(v[0]), float(v[1]), float(v[2]))
		player.velocity = Vector3.ZERO
		player.yaw = deg_to_rad(float(v[3]))
		player.pitch = deg_to_rad(float(v[4]))
		player.rotation.y = player.yaw
		player.cam.rotation = Vector3(player.pitch, 0, 0)
		await get_tree().create_timer(1.0).timeout
		i += 1
		get_viewport().get_texture().get_image().save_png("user://tour_%02d.png" % i)
	get_tree().quit()

## overhead orthographic shot for level planning: --topdown=x,z,size,camera_y,near
func _probe() -> void:
	await get_tree().create_timer(1.0).timeout
	while world.baking or not world.nav_baked_once:
		await get_tree().create_timer(0.5).timeout
	await get_tree().create_timer(1.0).timeout
	var mp: RID = world.nav.get_navigation_map()
	for q in [Vector3(-56, 4.1, -19), Vector3(-45, 4.1, -19), Vector3(-53, 4.1, -19.1), Vector3(-49.7, 2.0, -19.1), Vector3(-48.5, 1.85, -19.6), Vector3(-16, 4.1, -35), Vector3(0, 4.1, -38.5), Vector3(-50.5, 3, -19.1), Vector3(-17.5, 4.1, -35), Vector3(-14.5, 4.1, -35)]:
		print("closest nav to ", q, " = ", NavigationServer3D.map_get_closest_point(mp, q))
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for y in [4.1, 4.5, 5.5, 6.2]:
		for zz in [-35.8, -35.0, -34.2]:
			var hr := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-17.5, y, zz), Vector3(-14.5, y, zz), 1))
			print("door ray y=%.1f z=%.1f -> %s %s" % [y, zz, str(hr.get("position", "clear")), str(hr.get("collider", ""))])
	for x in [-48.5, -49.5, -50.5, -51.5, -52.5]:
		var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 3.7, -19.1), Vector3(x, -1, -19.1), 1))
		var r2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 6.0, -19.1), Vector3(x, 3.75, -19.1), 1))
		print("x=%.1f below-balcony hit y=%s   from-above hit y=%s" % [x, str(r.get("position", Vector3.ZERO).y), str(r2.get("position", Vector3.ZERO).y)])
	var map_rid: RID = world.nav.get_navigation_map()
	var path := NavigationServer3D.map_get_path(map_rid, Vector3(-45, 0, -8), Vector3(-56, 4, -19), true)
	print("path gym->balcony points=", path.size(), " end=", path[path.size() - 1] if path.size() > 0 else "none")
	var mx := -1.0
	for p in path:
		if p.x < -48 and p.x > -53:
			print("  via ", p)
	path = NavigationServer3D.map_get_path(map_rid, Vector3(-20, 4, -36), Vector3(-8, 4, -38), true)
	print("path library->lab points=", path.size(), " ", path)
	get_tree().quit()

func _topdown() -> void:
	game.state = "stage"
	player.dead = true
	var v := topdown.split(",")
	var c := Camera3D.new()
	c.projection = Camera3D.PROJECTION_ORTHOGONAL
	c.size = float(v[2])
	c.near = float(v[4]) if v.size() > 4 else 0.05
	c.far = 30
	world.add_child(c)
	c.global_position = Vector3(float(v[0]), float(v[3]), float(v[1]))
	c.rotation = Vector3(-PI / 2, 0, 0)
	c.current = true
	world.env.ambient_light_energy = 2.5
	world.env.fog_enabled = false
	hud.visible = false
	await get_tree().create_timer(1.5).timeout
	get_viewport().get_texture().get_image().save_png("user://topdown.png")
	get_tree().quit()

## test: walk up to the breaker, pull it, film the cutscene; then a boss entrance
func _powertest() -> void:
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png("user://pw_00.png")
	await get_tree().create_timer(6.0).timeout
	player.global_position = game.level.SWITCH_SPOT + Vector3(0, 0.05, 0)
	player.yaw = -PI / 2
	player.pitch = 0.0
	await get_tree().create_timer(0.6).timeout
	game.interact_target = game._find_interact()
	print("power prompt=", game.interact_target.get("text", "none"))
	get_viewport().get_texture().get_image().save_png("user://pw_01.png")
	game.interact()
	for i in 6:
		await get_tree().create_timer(1.0).timeout
		get_viewport().get_texture().get_image().save_png("user://pw_%02d.png" % (i + 2))
	print("powered=", world.powered, " state=", game.state)
	while game.cutscene.playing:
		await get_tree().process_frame
	player.global_position = Vector3(0, 0.05, 8)
	player.yaw = 0
	game.state = "play"
	game.wave = 5
	game.to_spawn = 0
	game.spawn_boss("principal")
	for i in 3:
		await get_tree().create_timer(1.0).timeout
		get_viewport().get_texture().get_image().save_png("user://pw_%02d.png" % (i + 8))
	await get_tree().create_timer(1.5).timeout
	print("after boss cut state=", game.state)
	get_tree().quit()

func _look_at(from: Vector3, target: Vector3) -> void:
	player.global_position = from
	var to := target - (from + Vector3(0, 1.6, 0))
	player.yaw = atan2(-to.x, -to.z)
	player.pitch = atan2(to.y, Vector2(to.x, to.z).length())

func _snap(n: int) -> void:
	get_viewport().get_texture().get_image().save_png("user://ph_%02d.png" % n)

func _fire_at(target: Vector3, gun := "ak") -> void:
	var o: Vector3 = player.cam.global_position
	game.shoot_ray(o, (target - o).normalized(), world.data.weapons[gun])

## test: ragdolls, props, glass, lockers, vending, extinguisher, lamps, bookshelf
func _phystest() -> void:
	await get_tree().create_timer(2.0).timeout
	while not world.nav_baked_once:
		await get_tree().process_frame
	game.state = "stage"
	player.hp = 1e9
	# ragdolls in the cafeteria
	_look_at(Vector3(0, 0.05, 9), Vector3(0, 1, 2))
	var zs := []
	for i in 4:
		var z = preload("res://scripts/zombie.gd").new()
		zroot.add_child(z)
		z.setup(game, "walker", Vector3(-2 + i * 1.3, 0.05, 6.5 - (i % 2) * 1.5), 3)
		z.emerge = 0
		game.zombies.append(z)
		zs.append(z)
	await get_tree().create_timer(0.6).timeout
	for z in zs:
		z.damage(999, "body", Vector3(0, 0.1, -1), 6)
	await get_tree().create_timer(0.25, true, false, true).timeout
	_snap(1)
	await get_tree().create_timer(1.5).timeout
	_snap(2)
	# a grenade by the chairs
	game.explode(Vector3(0, 0.4, -1.0), 6.0, 1.0)
	await get_tree().create_timer(0.4, true, false, true).timeout
	_snap(3)
	await get_tree().create_timer(1.5).timeout
	_snap(4)
	# vending machine
	_look_at(Vector3(8.5, 0.05, 11.0), Vector3(10, 1.0, 13.7))
	await get_tree().create_timer(0.3).timeout
	for i in 4:
		_fire_at(Vector3(10, 1.0, 13.7))
		await get_tree().create_timer(0.2).timeout
	await get_tree().create_timer(0.8).timeout
	print("vending left=", game.physics.vending.left)
	_look_at(Vector3(8.5, 0.05, 11.0), Vector3(10, 0.2, 13.0))
	await get_tree().create_timer(0.2).timeout
	_snap(5)
	# extinguisher on the cafeteria wall
	_look_at(Vector3(-10, 0.05, 9.5), Vector3(-13.4, 1.1, 9.5))
	await get_tree().create_timer(0.3).timeout
	_fire_at(Vector3(-13.4, 1.15, 9.5))
	await get_tree().create_timer(1.2).timeout
	_snap(6)
	# trophy case
	_look_at(Vector3(-19.5, 0.05, -8.0), Vector3(-19.5, 1.4, -5.4))
	await get_tree().create_timer(0.3).timeout
	_snap(7)
	_fire_at(Vector3(-19.5, 1.4, -5.31))
	await get_tree().create_timer(0.6).timeout
	_snap(8)
	# upstairs lockers
	_look_at(Vector3(-7.5, 4.05, -29.2), Vector3(-7.5, 5.0, -31.3))
	await get_tree().create_timer(0.3).timeout
	for x in [-9.25, -8.25, -6.75]:
		_fire_at(Vector3(x, 5.0, -31.24))
		await get_tree().create_timer(0.1).timeout
	await get_tree().create_timer(0.6).timeout
	_snap(9)
	# bookshelf
	_look_at(Vector3(-17.6, 4.05, -35.2), Vector3(-16.5, 5, -37.6))
	await get_tree().create_timer(0.3).timeout
	game.interact_target = game._find_interact()
	print("shelf prompt=", game.interact_target.get("text", "none"), " direct=", game.physics.shelf_prompt(), " state=", game.physics.shelf.get("state"), " shelfpos=", game.physics.shelf.body.global_position, " player=", player.global_position)
	game.interact()
	await get_tree().create_timer(1.3).timeout
	_look_at(Vector3(-14.0, 4.05, -35.0), Vector3(-16.5, 5, -35))
	await get_tree().create_timer(0.3).timeout
	_snap(10)
	# lamps: shoot a pendant in the hall
	_look_at(Vector3(-20, 0.05, -7.25), Vector3(-24, 2.6, -7.25))
	await get_tree().create_timer(0.3).timeout
	var lamp_y: float = game.physics.lamps[5].arm.global_position.y - game.physics.lamps[5].len
	_fire_at(Vector3(-24, lamp_y, -7.25))
	await get_tree().create_timer(0.5).timeout
	_snap(11)
	print("props=", game.physics.props.size(), " ragdolls=", game.physics.ragdolls.size(), " glass left=", game.physics.glass_list.size(), " lamp swing=", game.physics.lamps[5].v)
	get_tree().quit()

func _menutest() -> void:
	await get_tree().create_timer(3.0).timeout
	_snap(31)
	menu.show_page("settings")
	await get_tree().create_timer(0.5).timeout
	_snap(32)
	game.pad = true
	game.hud.device_changed()
	await get_tree().create_timer(0.3).timeout
	_snap(38)
	game.pad = false
	game.hud.device_changed()
	menu.show_page("unlocks")
	await get_tree().create_timer(0.5).timeout
	_snap(33)
	menu.show_page("main")
	menu.play_pressed.emit()
	await get_tree().create_timer(3.0).timeout
	_snap(34)
	await get_tree().create_timer(5.0).timeout
	_snap(35)
	menu.open_pause()
	await get_tree().create_timer(0.5).timeout
	_snap(36)
	menu.close()
	await get_tree().create_timer(0.5).timeout
	player.hurt(99999)
	await get_tree().create_timer(2.0).timeout
	_snap(37)
	print("state=", game.state, " scores=", settings.scores)
	get_tree().quit()

func _newtest() -> void:
	await get_tree().create_timer(2.0).timeout
	while not world.nav_baked_once:
		await get_tree().process_frame
	game.state = "stage"
	player.hp = 1e9
	player.max_hp = 1e9
	game.points = 50000
	# Pack-a-Punch the Staple Cannon
	player.give("staple", 360)
	_look_at(game.shop.PAP_SPOT + Vector3(0, 0.05, 0.3), game.shop.PAP_POS + Vector3(0, 1.3, 0))
	await get_tree().create_timer(0.5).timeout
	game.interact_target = game._find_interact()
	print("pap prompt=", game.interact_target.get("text", "none"))
	_snap(41)
	game.interact()
	await get_tree().create_timer(1.5).timeout
	_snap(42)
	await get_tree().create_timer(2.5).timeout
	print("upgraded=", player.slots[player.cur].get("up"), " name=", player.w().name, " mag=", player.slots[player.cur].mag, " res=", player.slots[player.cur].res)
	_snap(43)
	# staple a zombie to the cafeteria wall
	_look_at(Vector3(-9, 0.05, 0), Vector3(-13.7, 1.2, 0))
	var z = preload("res://scripts/zombie.gd").new()
	zroot.add_child(z)
	z.setup(game, "walker", Vector3(-12.6, 0.05, 0), 3)
	z.emerge = 0
	game.zombies.append(z)
	await get_tree().create_timer(0.4).timeout
	for i in 6:
		if is_instance_valid(z) and z.alive:
			_fire_at(z.global_position + Vector3(0, 1.2, 0), "staple")
		await get_tree().create_timer(0.1).timeout
	await get_tree().create_timer(1.5).timeout
	_snap(44)
	# upstairs wall-buy display
	_look_at(Vector3(7.5, 4.05, -41.2), Vector3(7.5, 5.4, -43.7))
	await get_tree().create_timer(0.5).timeout
	game.interact_target = game._find_interact()
	print("office prompt=", game.interact_target.get("text", "none"))
	_snap(45)
	# hall monitor
	game.state = "play"
	game.to_spawn = 0
	game.wave = 4
	_look_at(Vector3(0, 0.05, 10), Vector3(0, 1, 2))
	var mon = preload("res://scripts/zombie.gd").new()
	zroot.add_child(mon)
	mon.setup(game, "monitor", Vector3(0, 0.05, 4), 4)
	mon.emerge = 0
	mon.whistle_cd = 0.5
	game.zombies.append(mon)
	var others := []
	for i in 3:
		var w = preload("res://scripts/zombie.gd").new()
		zroot.add_child(w)
		w.setup(game, "walker", Vector3(-6 + i * 3, 0.05, -4), 4)
		w.emerge = 0
		game.zombies.append(w)
		others.append(w)
	await get_tree().create_timer(1.2).timeout
	_snap(46)
	print("monitor whistled: rush=", others.map(func(o): return snappedf(o.rush_t, 0.1)))
	for o in game.zombies.duplicate():
		o.damage(99999, "body", Vector3(0, 0, -1), 4)
	await get_tree().create_timer(1.0).timeout
	# the Lunch Lady
	game.boss_spawned = true
	game.state = "play"
	game.spawn_boss("lunch")
	var b = game.boss
	b.global_position = Vector3(2, 0.05, -2)
	while game.cutscene.playing:
		await get_tree().process_frame
	_snap(47)
	await get_tree().create_timer(6.0).timeout
	_snap(48)
	print("lunch lady: hp=", b.hp, " projectiles=", game.spits.size(), " puddles=", game.puddles.size(), " player slow=", player.slow_t)
	get_tree().quit()
