extends Node
## The death cam: when you go down, a record scratch, the camera swings round to the zombie that got you,
## and it gets its yearbook photo with a superlative.

const CAPTIONS := {
	"walker": ["MOST LIKELY TO EAT YOU", "CLASS OF FOREVER"],
	"runner": ["VARSITY TRACK. UNDEFEATED.", "NEVER SKIPPED LEG DAY"],
	"armored": ["BEST DRESSED (RIOT GEAR)", "HARDEST WORKER"],
	"bloater": ["MOST LIKELY TO EXPLODE", "LIFE OF THE PARTY"],
	"spitter": ["SAID IT WITH ITS MOUTH", "MOST OUTSPOKEN"],
	"monitor": ["DID YOU HAVE A PASS?", "MOST RESPONSIBLE"],
	"mascot": ["SCHOOL SPIRIT AWARD", "GO WILDCATS!"],
	"crawler": ["MOST IMPROVED (NO LEGS)", "STAYED GROUNDED"],
	"coach": ["WALKED IT OFF. YOU DIDN'T.", "COACH OF THE YEAR"],
	"principal": ["SEE ME IN MY OFFICE. FOREVER.", "PRINCIPAL OF THE YEAR (AGAIN)"],
	"chem": ["YOU FAILED THE LAB.", "TEACHER OF THE MONTH"],
	"lunch": ["SECONDS? NO. LASTS.", "LUNCH LADY OF THE DECADE"],
}
const NAMES := {"walker": "THE WALKER", "runner": "THE RUNNER", "armored": "THE RIOT COP", "bloater": "THE BLOATER", "spitter": "THE SPITTER",
	"monitor": "THE HALL MONITOR", "mascot": "THE MASCOT", "crawler": "THE CRAWLER"}

var game
var playing := false
var skip := false
var frame: Control
var caption: Label
var title: Label
var flash: ColorRect

func setup(g) -> void:
	game = g
	var hud = game.hud
	frame = Control.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.visible = false
	hud.root.add_child(frame)
	# a yearbook photo border: thick cream frame with a dark edge, around the middle of the screen
	var cream := Color8(236, 228, 208)
	for r in [[0.0, 0.0, 1.0, 0.1], [0.0, 0.72, 1.0, 1.0], [0.0, 0.0, 0.2, 1.0], [0.8, 0.0, 1.0, 1.0]]:
		var c := ColorRect.new()
		c.color = cream
		c.anchor_left = r[0]
		c.anchor_top = r[1]
		c.anchor_right = r[2]
		c.anchor_bottom = r[3]
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(c)
	for r in [[0.2, 0.1, 0.8, 0.104], [0.2, 0.716, 0.8, 0.72], [0.2, 0.1, 0.203, 0.72], [0.797, 0.1, 0.8, 0.72]]:
		var c := ColorRect.new()
		c.color = Color8(40, 34, 28)
		c.anchor_left = r[0]
		c.anchor_top = r[1]
		c.anchor_right = r[2]
		c.anchor_bottom = r[3]
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(c)
	title = hud._label(frame, hud.display, 24, Color8(60, 50, 40), Vector2.ZERO, Vector2(10, 10))
	title.anchor_left = 0.2
	title.anchor_right = 0.8
	title.anchor_top = 0.74
	title.anchor_bottom = 0.74
	title.offset_bottom = 34
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	caption = hud._label(frame, hud.display, 38, Color8(150, 24, 30), Vector2.ZERO, Vector2(10, 10))
	caption.anchor_left = 0.05
	caption.anchor_right = 0.95
	caption.anchor_top = 0.81
	caption.anchor_bottom = 0.81
	caption.offset_bottom = 60
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	var head: Label = hud._label(frame, hud.mono, 22, Color8(110, 96, 80), Vector2.ZERO, Vector2(10, 10))
	head.text = "WESTFIELD HIGH YEARBOOK  -  SENIOR SUPERLATIVES"
	head.anchor_left = 0.2
	head.anchor_right = 0.8
	head.anchor_top = 0.03
	head.anchor_bottom = 0.03
	head.offset_bottom = 30
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	flash = ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1, 1, 1, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.root.add_child(flash)

func request_skip() -> void:
	if playing:
		skip = true

## who gets the photo: the last zombie to hurt us, else whoever is closest
func killer():
	var z = game.last_attacker
	if z != null and is_instance_valid(z) and z.alive and z.global_position.distance_to(game.player.global_position) < 30:
		return z
	var best = null
	var bd := 12.0
	for o in game.zombies:
		if is_instance_valid(o) and o.alive:
			var d: float = o.global_position.distance_to(game.player.global_position)
			if d < bd:
				bd = d
				best = o
	return best

func _key(z) -> String:
	if z.kind == "boss":
		return z.bt
	if z.crawler:
		return "crawler"
	return z.kind

func _wait(t: float) -> void:
	var left := t
	while left > 0 and not skip:
		await get_tree().process_frame
		left -= get_process_delta_time() / maxf(Engine.time_scale, 0.001)

func play(z) -> void:
	if z == null or not is_instance_valid(z):
		return
	playing = true
	skip = false
	var key := _key(z)
	var cap: Array = CAPTIONS.get(key, CAPTIONS.walker)
	var cam: Camera3D = game.cutscene.cam
	var P = game.player
	var head: Vector3 = (z.joints["head"].global_position if z.joints.has("head") else z.global_position + Vector3(0, 1.6, 0)) + Vector3(0, 0.05 * z.bscale, 0)
	var to_p: Vector3 = P.global_position - z.global_position
	to_p.y = 0
	if to_p.length() < 0.1:
		to_p = -z.global_transform.basis.z
	to_p = to_p.normalized()
	var side := to_p.cross(Vector3.UP) * 0.35
	var a: Vector3 = head + to_p * 2.6 * maxf(z.bscale, 1.0) + Vector3(0, 0.5, 0) + side
	var b: Vector3 = head + to_p * 1.05 * maxf(z.bscale, 1.0) + Vector3(0, 0.08, 0) + side * 0.3
	# keep the camera out of walls
	var space: PhysicsDirectSpaceState3D = P.get_world_3d().direct_space_state
	for which in [0, 1]:
		var pt: Vector3 = a if which == 0 else b
		var r: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(head, pt, 1))
		if not r.is_empty():
			pt = head.lerp(r.position, 0.85)
		if which == 0:
			a = pt
		else:
			b = pt
	game.audio.play("scratch", null, 0)
	game.audio.set_track("")
	Engine.time_scale = 0.3
	game.hitstop_until = Time.get_ticks_msec() + 4000      # keep game.gd from snapping time back to normal
	cam.global_position = a
	cam.look_at(head, Vector3.UP)
	cam.fov = 50
	cam.current = true
	game.hud.letterbox(true)
	# swing in, slowed down
	var t := 0.0
	while t < 0.75 and not skip:
		await get_tree().process_frame
		t += get_process_delta_time() / maxf(Engine.time_scale, 0.001)
		var k := clampf(t / 0.75, 0, 1)
		k = 1.0 - (1.0 - k) * (1.0 - k)
		cam.global_position = a.lerp(b, k)
		cam.look_at(head, Vector3.UP)
		cam.fov = lerpf(50.0, 30.0, k)
	# freeze frame: snap the photo
	for o in game.zombies:
		if is_instance_valid(o):
			o.process_mode = Node.PROCESS_MODE_DISABLED
	Engine.time_scale = 1.0
	if not skip:
		game.audio.play("lclick", null, 4, 0.6)
		flash.color.a = 0.85
		create_tween().tween_property(flash, "color:a", 0.0, 0.35)
		game.hud.letterbox(false)
		title.text = NAMES.get(key, game.BOSSES[key].name if game.BOSSES.has(key) else "THE ZOMBIE")
		caption.text = '"' + cap[0] + '"'
		frame.visible = true
		frame.scale = Vector2(1.08, 1.08)
		frame.pivot_offset = frame.size / 2.0
		create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(frame, "scale", Vector2.ONE, 0.25)
		await _wait(2.6)
	frame.visible = false
	game.hud.letterbox(false)
	for o in game.zombies:
		if is_instance_valid(o):
			o.process_mode = Node.PROCESS_MODE_INHERIT
	P.cam.current = true
	game.hitstop_until = 0
	Engine.time_scale = 1.0
	playing = false
