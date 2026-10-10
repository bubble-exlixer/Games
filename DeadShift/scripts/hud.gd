extends CanvasLayer
## The web game's HUD: painted red tags, Black Ops One numbers, VT323 text, scanlines and vignette,
## and all its punches: jolts, point pops, combo counter, callouts.

const INK := Color8(230, 220, 203)
const DIM := Color8(138, 130, 115)
const BLOOD := Color8(179, 18, 27)
const BLOOD2 := Color8(110, 8, 14)
const AMBER := Color8(217, 164, 65)
const GOLD := Color8(255, 211, 107)

var display: FontFile
var mono: FontFile
var root: Control
var game                       # game.gd (set by game.setup)
var tl: Control
var tr: Control
var round_lbl: Label
var hp_fill: ColorRect
var hp_ghost: ColorRect
var pts_lbl: Label
var gun_lbl: RichTextLabel
var ammo_lbl: Label
var nade_lbl: Label
var x2_lbl: Label
var prompt_lbl: RichTextLabel
var hint_lbl: RichTextLabel
var banner_t: Label
var banner_s: RichTextLabel
var np_lbl: Label
var call_lbl: Label
var call_sub: Label
var small_lbl: Label
var combo_box: Control
var combo_n: Label
var combo_bar: ColorRect
var combo_tag: PanelContainer
var cross: Control
var cross_bits: Array = []
var hit_bits: Array = []
var hurt: ColorRect
var bile: ColorRect
var vig: TextureRect
var over: ColorRect
var over_t: Label
var over_s: RichTextLabel
var scope: Control
var load_panel: ColorRect
var load_sub: Label
var banner_token := 0
var hit_t := -10.0
var hit_kill := false
var ui_t := 0.0
var shake := 0.0
var disp_pts := 0.0
var pts_punch := 0.0
var ammo_punch := 0.0
var round_punch_t := 0.0
var call_t := 9.0
var small_t := 9.0
var combo_bump := 0.0
var combo_end_t := 0.0
var last_mag := -1
var last_nades := -1
var nade_punch := 0.0
var pops: Array = []
var bars: Array = []
var cut_t: Label
var cut_s: Label
var cut_tw: Tween
var boss_box: Control
var boss_name: Label
var boss_fill: ColorRect
var boss_ghost: ColorRect

func _ready() -> void:
	layer = 5
	display = load("res://assets/fonts/BlackOpsOne-Regular.ttf").duplicate()
	mono = load("res://assets/fonts/VT323-Regular.ttf").duplicate()
	for f in [display, mono]:
		f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		f.hinting = TextServer.HINTING_NONE
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		f.multichannel_signed_distance_field = false
		f.oversampling = 0.5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# screen-space effects: hurt flash, bile flash, vignette + scanlines
	hurt = _rect(Color(BLOOD, 0))
	bile = _rect(Color(0.47, 0.67, 0.12, 0))
	vig = TextureRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 0.62))
	g.add_point(0.55, Color(0, 0, 0, 0))
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 1.0)
	vig.texture = gt
	root.add_child(vig)
	var scan := ColorRect.new()
	scan.set_anchors_preset(Control.PRESET_FULL_RECT)
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = "shader_type canvas_item; void fragment(){ float l = mod(FRAGCOORD.y, 2.0); COLOR = vec4(0.0, 0.0, 0.0, l < 1.0 ? 0.14 : 0.0); }"
	var sm := ShaderMaterial.new()
	sm.shader = sh
	scan.material = sm
	root.add_child(scan)
	# top left: wave + health (one group so it can jolt and sway together)
	tl = Control.new()
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.position = Vector2(0, 0)
	tl.size = Vector2(260, 140)
	tl.pivot_offset = Vector2(20, 20)
	root.add_child(tl)
	_tag(tl, "WAVE", Vector2(16, 12))
	round_lbl = _label(tl, display, 52, BLOOD, Vector2(18, 30), Vector2(200, 60))
	round_lbl.pivot_offset = Vector2(14, 34)
	round_lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
	round_lbl.add_theme_constant_override("outline_size", 0)
	_tag(tl, "HEALTH", Vector2(16, 94))
	var hb := ColorRect.new()
	hb.color = Color(0, 0, 0, 0.65)
	hb.position = Vector2(18, 120)
	hb.size = Vector2(170, 11)
	tl.add_child(hb)
	hp_ghost = ColorRect.new()
	hp_ghost.color = Color(1, 0.9, 0.8, 0.85)
	hp_ghost.size = Vector2(170, 11)
	hb.add_child(hp_ghost)
	hp_fill = ColorRect.new()
	hp_fill.color = BLOOD
	hp_fill.size = Vector2(170, 11)
	hb.add_child(hp_fill)
	# top right: points, weapon, ammo, grenades
	tr = Control.new()
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.anchor_left = 1
	tr.anchor_right = 1
	tr.offset_left = -440
	tr.offset_right = 0
	tr.offset_bottom = 220
	tr.pivot_offset = Vector2(420, 20)
	root.add_child(tr)
	_tag(tr, "POINTS", Vector2(440 - 16 - 96, 12))
	pts_lbl = _label(tr, display, 42, INK, Vector2(124, 30), Vector2(300, 52))
	pts_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pts_lbl.pivot_offset = Vector2(280, 26)
	gun_lbl = RichTextLabel.new()
	gun_lbl.bbcode_enabled = true
	gun_lbl.fit_content = true
	gun_lbl.scroll_active = false
	gun_lbl.add_theme_font_override("normal_font", mono)
	gun_lbl.add_theme_font_size_override("normal_font_size", 24)
	gun_lbl.add_theme_constant_override("outline_size", 6)
	gun_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	gun_lbl.position = Vector2(24, 84)
	gun_lbl.size = Vector2(400, 26)
	gun_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.add_child(gun_lbl)
	ammo_lbl = _label(tr, display, 36, INK, Vector2(124, 106), Vector2(300, 44))
	ammo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_lbl.pivot_offset = Vector2(280, 22)
	nade_lbl = _label(tr, mono, 24, AMBER, Vector2(124, 150), Vector2(300, 26))
	nade_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	nade_lbl.pivot_offset = Vector2(280, 13)
	x2_lbl = _label(tr, display, 22, GOLD, Vector2(124, 178), Vector2(300, 30))
	x2_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# combo counter (left, mid-screen)
	combo_box = Control.new()
	combo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combo_box.anchor_top = 0.38
	combo_box.anchor_bottom = 0.38
	combo_box.offset_left = 22
	combo_box.offset_right = 260
	combo_box.offset_bottom = 120
	combo_box.pivot_offset = Vector2(0, 40)
	combo_box.modulate.a = 0
	root.add_child(combo_box)
	combo_n = _label(combo_box, display, 66, INK, Vector2(0, 0), Vector2(240, 72))
	combo_n.pivot_offset = Vector2(20, 40)
	combo_n.add_theme_color_override("font_shadow_color", BLOOD2)
	combo_n.add_theme_constant_override("shadow_offset_x", 5)
	combo_n.add_theme_constant_override("shadow_offset_y", 5)
	combo_n.add_theme_color_override("font_outline_color", Color.BLACK)
	combo_n.add_theme_constant_override("outline_size", 6)
	combo_tag = _tag(combo_box, "COMBO", Vector2(4, 72))
	var bb := ColorRect.new()
	bb.color = Color(0, 0, 0, 0.8)
	bb.position = Vector2(6, 104)
	bb.size = Vector2(152, 7)
	combo_box.add_child(bb)
	combo_bar = ColorRect.new()
	combo_bar.color = INK
	combo_bar.position = Vector2(4, 102)
	combo_bar.size = Vector2(150, 5)
	combo_box.add_child(combo_bar)
	# boss health bar, top centre
	boss_box = Control.new()
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_box.anchor_left = 0.5
	boss_box.anchor_right = 0.5
	boss_box.offset_left = -230
	boss_box.offset_right = 230
	boss_box.offset_top = 14
	boss_box.offset_bottom = 70
	boss_box.visible = false
	root.add_child(boss_box)
	boss_name = _label(boss_box, display, 26, INK, Vector2(0, 0), Vector2(460, 30))
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bbg := ColorRect.new()
	bbg.color = Color(0, 0, 0, 0.75)
	bbg.position = Vector2(0, 34)
	bbg.size = Vector2(460, 14)
	boss_box.add_child(bbg)
	boss_ghost = ColorRect.new()
	boss_ghost.color = Color(1, 0.9, 0.8, 0.85)
	boss_ghost.position = Vector2(2, 36)
	boss_ghost.size = Vector2(456, 10)
	boss_box.add_child(boss_ghost)
	boss_fill = ColorRect.new()
	boss_fill.color = BLOOD
	boss_fill.position = Vector2(2, 36)
	boss_fill.size = Vector2(456, 10)
	boss_box.add_child(boss_fill)
	# center: crosshair, hitmarker, prompt, hint
	cross = Control.new()
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cross)
	for i in 4:
		var c := ColorRect.new()
		c.color = Color(INK, 0.85)
		c.size = Vector2(2, 7) if i < 2 else Vector2(7, 2)
		cross.add_child(c)
		cross_bits.append(c)
	for i in 4:
		var h := ColorRect.new()
		h.color = Color(1, 1, 1, 0)
		h.size = Vector2(3, 11)
		h.pivot_offset = Vector2(1.5, 5.5)
		cross.add_child(h)
		hit_bits.append(h)
	prompt_lbl = _center_rich(mono, 28, INK, 0.62)
	hint_lbl = _center_rich(mono, 24, AMBER, 0.56)
	skip_lbl = _center_rich(mono, 20, DIM, 0.955)
	skip_lbl.visible = false
	banner_t = _center_label(display, 48, BLOOD, 0.24)
	banner_s = _center_rich(mono, 26, INK, 0.32)
	banner_t.modulate.a = 0
	banner_s.modulate.a = 0
	banner_t.pivot_offset = Vector2(620, 30)
	call_lbl = _center_label(display, 34, AMBER, 0.36)
	call_lbl.modulate.a = 0
	call_sub = _center_label(mono, 26, INK, 0.41)
	call_sub.modulate.a = 0
	small_lbl = _center_label(display, 20, INK, 0.455)
	small_lbl.modulate.a = 0
	np_lbl = _label(root, mono, 24, INK, Vector2(18, -84), Vector2(500, 60))
	np_lbl.anchor_top = 1
	np_lbl.anchor_bottom = 1
	np_lbl.modulate.a = 0
	# marksman scope
	scope = Control.new()
	scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope.visible = false
	var ssh := Shader.new()
	ssh.code = "shader_type canvas_item; void fragment(){ vec2 res = 1.0 / SCREEN_PIXEL_SIZE; vec2 p = (FRAGCOORD.xy - res * 0.5) / res.y; float r = length(p); float a = r > 0.42 ? 1.0 : 0.0; if (abs(p.x) < 0.0015 || abs(p.y) < 0.0015) a = 1.0; COLOR = vec4(0.0, 0.0, 0.0, a); }"
	var ssm := ShaderMaterial.new()
	ssm.shader = ssh
	var sr := ColorRect.new()
	sr.set_anchors_preset(Control.PRESET_FULL_RECT)
	sr.material = ssm
	sr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope.add_child(sr)
	root.add_child(scope)
	# cutscene letterbox and title card
	for top in [true, false]:
		var b := ColorRect.new()
		b.color = Color.BLACK
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.anchor_right = 1
		b.anchor_top = 0.0 if top else 1.0
		b.anchor_bottom = 0.0 if top else 1.0
		b.offset_top = -90 if top else 0
		b.offset_bottom = 0 if top else 90
		root.add_child(b)
		bars.append(b)
	cut_t = _center_label(display, 58, BLOOD, 0.72)
	cut_s = _center_label(mono, 28, INK, 0.81)
	cut_t.modulate.a = 0
	cut_s.modulate.a = 0
	# game over
	over = _rect(Color(0.24, 0, 0, 0))
	over.visible = false
	over_t = _center_label(display, 64, INK, 0.3)
	over_s = _center_rich(mono, 30, INK, 0.42)
	over_t.reparent(over)
	over_s.reparent(over)
	over_s.offset_bottom = 270
	# loading
	load_panel = _rect(Color8(10, 9, 8))
	var lt := _center_label(display, 54, INK, 0.4)
	lt.text = "WESTFIELD HIGH"
	lt.reparent(load_panel)
	load_sub = _center_label(mono, 26, DIM, 0.5)
	load_sub.text = "unlocking the doors..."
	load_sub.reparent(load_panel)

func _rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(r)
	return r

func _label(parent: Control, f: Font, size: int, col: Color, pos: Vector2, sz: Vector2) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = pos
	l.size = sz
	parent.add_child(l)
	return l

func _center_label(f: Font, size: int, col: Color, y: float) -> Label:
	var l := _label(root, f, size, col, Vector2.ZERO, Vector2(10, 10))
	l.anchor_left = 0
	l.anchor_right = 1
	l.anchor_top = y
	l.anchor_bottom = y
	l.offset_left = 20
	l.offset_right = -20
	l.offset_top = -30
	l.offset_bottom = 30
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _center_rich(f: Font, size: int, col: Color, y: float) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.scroll_active = false
	l.add_theme_font_override("normal_font", f)
	l.add_theme_font_size_override("normal_font_size", size)
	l.add_theme_color_override("default_color", col)
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	l.anchor_left = 0
	l.anchor_right = 1
	l.anchor_top = y
	l.anchor_bottom = y
	l.offset_left = 20
	l.offset_right = -20
	l.offset_top = -30
	l.offset_bottom = 40
	return l

# ---------------------------------------------------------------- device-aware button prompts
## {action} tokens in any HUD text become the key (keyboard) or a coloured Xbox badge (controller)
const BTN := {
	"use": ["F", "X"], "reload": ["R", "X"], "nade": ["G", "RB"], "nade2": ["E", "RB"], "pause": ["ESC", "START"],
	"swap": ["Q", "Y"], "melee": ["V", "B"], "jump": ["SPACE", "A"], "ads": ["RMB", "LT"], "fire": ["LMB", "RT"],
	"sprint": ["SHIFT", "L3"], "torch": ["L", "D-PAD UP"], "move": ["WASD", "LS"], "look": ["MOUSE", "RS"],
	"back": ["ESC", "B"], "select": ["ENTER", "A"], "any": ["ANY KEY", "A"], "nades": ["E/G", "RB"],
}
const PAD_COL := {"A": "#2f9e3f", "B": "#c8302c", "X": "#2f6fd6", "Y": "#d9b21c"}
var skip_lbl: RichTextLabel
var _rt_cache := {}

func pad() -> bool:
	return game != null and game.pad

func badge(action: String) -> String:
	var b: Array = BTN.get(action, [action, action])
	if not pad():
		return "[color=#ffcf5a]" + b[0] + "[/color]"
	var n: String = b[1]
	var bg: String = PAD_COL.get(n, "#3b3b40")
	var fg := "#111111" if n == "Y" else "#ffffff"
	return "[bgcolor=%s][color=%s] %s [/color][/bgcolor]" % [bg, fg, n]

func keys(t: String) -> String:
	t = t.replace("[", "[lb]")
	if t.find("{") < 0:
		return t
	for a in BTN:
		var tok: String = "{" + a + "}"
		if t.find(tok) >= 0:
			t = t.replace(tok, badge(a))
	return t

## set a centred rich label from plain text with {action} tokens (only re-parses when it changes)
func rset(l: RichTextLabel, t: String) -> void:
	var key := t + ("#p" if pad() else "#k")
	if _rt_cache.get(l, "") == key:
		return
	_rt_cache[l] = key
	l.text = "[center]" + keys(t) + "[/center]" if t != "" else ""

func controls_hint() -> String:
	if pad():
		return "{move} move  {sprint} sprint  {ads} aim  {fire} shoot  {use} reload/buy  {nade} grenade  {swap} swap  {melee} knife"
	return "{move} move  {sprint} sprint  {ads} aim  {reload} reload  {use} buy  {nades} grenade  {swap} swap  {melee} knife  {torch} light"

var _over_txt := ""
var _banner_txt := ""
func device_changed() -> void:
	if over_s and _over_txt != "":
		rset(over_s, _over_txt)
	if banner_s and _banner_txt != "":
		rset(banner_s, _banner_txt)
	if skip_lbl and skip_lbl.visible:
		rset(skip_lbl, "{any} to skip")
	if game and game.menu_hint_cb.is_valid():
		game.menu_hint_cb.call()

## a tilted red label box, like the web HUD
func _tag(parent: Control, text: String, pos: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(122, 14, 20)
	sb.shadow_color = Color(0, 0, 0, 0.9)
	sb.shadow_offset = Vector2(3, 3)
	sb.shadow_size = 1
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", display)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", INK)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.rotation = deg_to_rad(-3)
	p.position = pos
	parent.add_child(p)
	return p

func set_loading(text: String, done := false) -> void:
	load_sub.text = text
	if done:
		var tw := create_tween()
		tw.tween_interval(0.6)
		tw.tween_property(load_panel, "modulate:a", 0.0, 0.8)
		tw.tween_callback(func(): load_panel.visible = false)

func banner(title: String, sub := "", dur := 2.5) -> void:
	banner_token += 1
	var tok := banner_token
	banner_t.text = title
	_banner_txt = sub
	rset(banner_s, sub)
	banner_t.modulate.a = 1
	banner_s.modulate.a = 1
	banner_t.pivot_offset = Vector2(banner_t.size.x / 2.0, 30)
	banner_t.scale = Vector2(1.5, 1.5)
	banner_t.rotation = deg_to_rad(-4)
	var tw0 := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw0.tween_property(banner_t, "scale", Vector2.ONE, 0.35)
	tw0.tween_property(banner_t, "rotation", 0.0, 0.35)
	await get_tree().create_timer(dur, true, false, true).timeout
	if tok != banner_token:
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(banner_t, "modulate:a", 0.0, 0.5)
	tw.tween_property(banner_s, "modulate:a", 0.0, 0.5)

func now_playing(name: String) -> void:
	np_lbl.text = "NOW PLAYING\n" + name
	np_lbl.modulate.a = 1
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(np_lbl, "modulate:a", 0.0, 1.0)

func hit(killed: bool) -> void:
	hit_t = Time.get_ticks_msec() / 1000.0
	hit_kill = killed

func hurt_flash(dmg: float, acid := false) -> void:
	hurt.color.a = clampf(0.15 + dmg / 40.0, 0.15, 0.55)
	if acid:
		bile.color.a = 0.4

## shove the HUD panels around (hits taken, explosions, kills)
func jolt(k: float) -> void:
	shake = minf(1.0, shake + k)

## the points counter pops and a little "+100" flies off it
func points_pop(n: int) -> void:
	if n == 0:
		return
	if absi(n) >= 100 or n < 0:
		pts_punch = 1.0
	var l := Label.new()
	l.text = ("+%d" % n) if n > 0 else str(n)
	l.add_theme_font_override("font", display)
	l.add_theme_font_size_override("font_size", 26 if absi(n) >= 100 else 20)
	l.add_theme_color_override("font_color", GOLD if n >= 100 else (INK if n > 0 else BLOOD))
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(randf_range(150, 230), randf_range(40, 60))
	tr.add_child(l)
	pops.append({"l": l, "t": 0.0, "vx": randf_range(-50, -20), "vy": randf_range(-70, -40)})
	if pops.size() > 14:
		pops.pop_front().l.queue_free()

func callout(name: String, sub := "") -> void:
	call_lbl.text = name
	call_sub.text = sub
	call_t = 0.0

func callout_small(text: String) -> void:
	small_lbl.text = text
	small_t = 0.0

func combo(n: int, k: float) -> void:
	if n < 2:
		if combo_end_t <= 0:
			combo_box.modulate.a = 0
		return
	if combo_n.text != "%dX" % n:
		combo_n.text = "%dX" % n
		combo_bump = 1.0
	combo_end_t = 0.0
	combo_box.modulate.a = 1
	combo_tag.visible = true
	combo_bar.visible = true
	combo_bar.size.x = 150.0 * k

func combo_end(bonus: int) -> void:
	combo_n.text = "+%d" % bonus
	combo_bump = 1.0
	combo_end_t = 1.0
	combo_bar.visible = false
	pts_punch = 1.0

func boss_bar(name: String, k: float) -> void:
	boss_box.visible = name != ""
	if name == "":
		return
	boss_name.text = name
	boss_fill.size.x = 456.0 * clampf(k, 0, 1)
	boss_ghost.size.x = maxf(boss_fill.size.x, boss_ghost.size.x - get_process_delta_time() / maxf(Engine.time_scale, 0.001) * 120.0)

func letterbox(on: bool) -> void:
	var tw := create_tween().set_parallel(true).set_ignore_time_scale(true)
	tw.tween_property(bars[0], "offset_bottom", 80.0 if on else 0.0, 0.4)
	tw.tween_property(bars[0], "offset_top", 0.0 if on else -90.0, 0.4)
	tw.tween_property(bars[1], "offset_top", -80.0 if on else 0.0, 0.4)
	tw.tween_property(bars[1], "offset_bottom", 0.0 if on else 90.0, 0.4)
	for c in [tl, tr, cross, prompt_lbl, hint_lbl, boss_box]:
		c.modulate.a = 0.0 if on else 1.0
	combo_box.visible = not on
	skip_lbl.visible = on
	if on:
		skip_lbl.move_to_front()
		rset(skip_lbl, "{any} to skip")

func cut_title(title: String, sub: String) -> void:
	if cut_tw and cut_tw.is_valid():
		cut_tw.kill()
	if title == "" and sub == "":
		var tw := create_tween().set_parallel(true)
		cut_tw = tw
		tw.tween_property(cut_t, "modulate:a", 0.0, 0.4)
		tw.tween_property(cut_s, "modulate:a", 0.0, 0.4)
		return
	cut_t.text = title
	cut_s.text = sub
	cut_t.pivot_offset = Vector2(cut_t.size.x / 2.0, 30)
	cut_t.scale = Vector2(1.6, 1.6)
	cut_t.modulate.a = 1
	cut_s.modulate.a = 0
	var tw2 := create_tween()
	cut_tw = tw2
	tw2.tween_property(cut_t, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw2.tween_property(cut_s, "modulate:a", 1.0, 0.3)

func round_punch() -> void:
	round_punch_t = 1.0

func game_over(wave: int, kills: int, points: int, rec := {}, sc := {}) -> void:
	over.visible = true
	over.color.a = 0.0
	create_tween().tween_property(over, "color:a", 0.75, 1.2)
	over_t.text = "YOU DIED"
	banner_token += 1
	banner_t.modulate.a = 0
	banner_s.modulate.a = 0
	var extra := ""
	if rec.get("best", false):
		extra += "\nNEW BEST WAVE!"
	elif not sc.is_empty():
		extra += "\nbest: wave %d" % sc.best_wave
	for u in rec.get("unlocks", []):
		extra += "\nUNLOCKED: " + u
	_over_txt = "survived %d %s\n%d kills    %d points%s\n\npress {reload} to go again\n{pause} for the menu" % [wave, "round" if wave == 1 else "rounds", kills, points, extra]
	rset(over_s, _over_txt)

## the bus made it out
func escaped(wave: int, kills: int, points: int, time: float, rec := {}) -> void:
	over.visible = true
	over.color = Color(0.02, 0.1, 0.05, 0.85)
	over_t.text = "ESCAPED"
	banner_token += 1
	banner_t.modulate.a = 0
	banner_s.modulate.a = 0
	over_t.add_theme_color_override("font_color", GOLD)
	var extra := ""
	if rec.get("first_escape", false):
		extra += "\nFIRST ESCAPE!"
	elif rec.get("fastest", false):
		extra += "\nFASTEST ESCAPE!"
	for u in rec.get("unlocks", []):
		extra += "\nUNLOCKED: " + u
	_over_txt = "wave %d    %d kills    %d points\ntime %d:%02d%s\n\nback to the menu..." % [wave, kills, points, int(time) / 60, int(time) % 60, extra]
	rset(over_s, _over_txt)
	over_t.scale = Vector2(1.6, 1.6)
	over_t.pivot_offset = Vector2(over_t.size.x / 2.0, 30)
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(over_t, "scale", Vector2.ONE, 0.5)
	for c in [tl, tr, cross, prompt_lbl, hint_lbl, boss_box]:
		c.modulate.a = 0.0

func update(_dt: float, p: Dictionary) -> void:
	# HUD runs on real time so it keeps moving through hitstop
	var dt := minf(get_process_delta_time() / maxf(Engine.time_scale, 0.001), 0.1)
	ui_t += dt
	shake = maxf(0.0, shake - dt * 2.2)
	var k := shake * shake * 18.0
	var low: bool = p.hp / p.max_hp < 0.3
	var hb := 1.0 + maxf(0.0, sin(ui_t * 7.0)) * 0.04 if low else 1.0
	tl.position = Vector2(randf_range(-0.5, 0.5) * k, randf_range(-0.5, 0.5) * k)
	tl.rotation = deg_to_rad(-1.5 + sin(ui_t * 0.9) * 0.8)
	tl.scale = Vector2(hb, hb)
	tr.position.y = randf_range(-0.5, 0.5) * k
	tr.offset_left = -440 + randf_range(-0.5, 0.5) * k
	tr.offset_right = tr.offset_left + 440
	tr.rotation = deg_to_rad(1.2 + sin(ui_t * 0.75 + 1.3) * 0.8)
	# wave number
	var rtxt := str(p.round) if p.round > 0 else ""
	round_lbl.text = rtxt
	round_punch_t = maxf(0.0, round_punch_t - dt * 1.4)
	var rp := round_punch_t * round_punch_t
	round_lbl.scale = Vector2.ONE * (1.0 + rp * 1.2)
	round_lbl.rotation = -rp * 0.3
	round_lbl.add_theme_color_override("font_color", BLOOD.lerp(Color.WHITE, rp))
	# health with a pale "ghost" that drains after the hit
	var hk: float = clampf(p.hp / p.max_hp, 0, 1)
	hp_fill.size.x = 170.0 * hk
	hp_ghost.size.x = maxf(hp_fill.size.x, hp_ghost.size.x - dt * 90.0)
	# points roll up instead of jumping
	disp_pts += (p.points - disp_pts) * minf(1.0, dt * 9.0)
	if absf(p.points - disp_pts) < 1.0:
		disp_pts = p.points
	pts_lbl.text = str(int(round(disp_pts)))
	pts_punch = maxf(0.0, pts_punch - dt / 0.35)
	var pp := pts_punch * pts_punch
	pts_lbl.scale = Vector2.ONE * (1.0 + pp * 0.5)
	pts_lbl.rotation = -pp * 0.12
	pts_lbl.add_theme_color_override("font_color", INK.lerp(GOLD, pp))
	for i in range(pops.size() - 1, -1, -1):
		var o = pops[i]
		o.t += dt
		o.l.position += Vector2(o.vx, o.vy) * dt
		o.vy += 60 * dt
		o.l.modulate.a = clampf(1.0 - (o.t - 0.5) / 0.4, 0, 1)
		if o.t > 0.9:
			o.l.queue_free()
			pops.remove_at(i)
	# weapon + ammo (ammo punches on every shot)
	gun_lbl.text = "[right][color=#d9a441]%s[/color]%s[/right]" % [p.gun, (" [color=#8a8273]/ " + p.other + "[/color]") if p.other != "" else ""]
	if p.mag != last_mag:
		if p.mag < last_mag:
			ammo_punch = 1.0
		last_mag = p.mag
	ammo_punch = maxf(0.0, ammo_punch - dt * 8.0)
	ammo_lbl.text = "MELEE" if p.get("melee", false) else "%d | %s" % [p.mag, "∞" if p.res < 0 else str(p.res)]
	ammo_lbl.scale = Vector2.ONE * (1.0 + ammo_punch * 0.12)
	ammo_lbl.add_theme_color_override("font_color", BLOOD if p.low_ammo else INK)
	var nd: int = p.get("nades", 0)
	if nd != last_nades:
		nade_punch = 1.0
		last_nades = nd
	nade_punch = maxf(0.0, nade_punch - dt * 3.0)
	nade_lbl.text = "%d %s" % [nd, "GRENADE" if nd == 1 else "GRENADES"]
	nade_lbl.scale = Vector2.ONE * (1.0 + nade_punch * 0.3)
	var x2t: float = p.get("x2", 0.0)
	x2_lbl.visible = x2t > 0
	x2_lbl.text = "2X  %d" % ceili(x2t)
	# callouts
	call_t += dt
	var ca := 0.0
	if call_t < 0.18:
		ca = call_t / 0.18
	elif call_t < 1.1:
		ca = 1.0
	elif call_t < 1.5:
		ca = 1.0 - (call_t - 1.1) / 0.4
	call_lbl.modulate.a = ca
	call_sub.modulate.a = ca
	var cs := 1.0 + maxf(0.0, 1.0 - call_t / 0.18) * 0.6
	call_lbl.pivot_offset = Vector2(call_lbl.size.x / 2.0, 20)
	call_lbl.scale = Vector2(cs, cs)
	small_t += dt
	small_lbl.modulate.a = clampf(1.0 - (small_t - 0.5) / 0.3, 0, 1)
	small_lbl.position.y = small_lbl.get_parent_area_size().y * 0.455 - 30 - small_t * 18.0
	# combo
	combo_bump = maxf(0.0, combo_bump - dt / 0.32)
	var cb := combo_bump * combo_bump
	combo_n.scale = Vector2.ONE * (1.0 + cb * 0.7)
	combo_n.rotation = -cb * 0.16 - 0.08 + sin(ui_t * 1.4) * 0.03
	combo_n.add_theme_color_override("font_color", INK.lerp(BLOOD, cb))
	combo_box.position.x = 22 + randf_range(-0.5, 0.5) * k
	if combo_end_t > 0:
		combo_end_t -= dt
		combo_tag.visible = false
		combo_box.modulate.a = clampf(combo_end_t / 0.4, 0, 1)
	# screen
	rset(prompt_lbl, p.prompt)
	rset(hint_lbl, p.hint)
	hurt.color.a = maxf(0.0, hurt.color.a - dt * 1.6)
	bile.color.a = maxf(0.0, bile.color.a - dt * 0.6)
	vig.modulate = Color(1, 1, 1, 1) if hk > 0.35 else Color(1.0, 0.3, 0.3, 0.8 + sin(ui_t * 5.0) * 0.2)
	var gap: float = 4.0 + p.spread * 260.0
	cross.visible = p.show_cross
	cross_bits[0].position = Vector2(-1, -gap - 7)
	cross_bits[1].position = Vector2(-1, gap)
	cross_bits[2].position = Vector2(-gap - 7, -1)
	cross_bits[3].position = Vector2(gap, -1)
	var ht := Time.get_ticks_msec() / 1000.0 - hit_t
	var hk2 := clampf(1.0 - ht / 0.22, 0, 1)
	var r := 9.0 + (1.0 - hk2) * 4.0 + (4.0 if hit_kill else 0.0)
	for i in 4:
		var h: ColorRect = hit_bits[i]
		var a := deg_to_rad(45 + 90 * i)
		h.size = Vector2(3, 14) if hit_kill else Vector2(2, 9)
		h.pivot_offset = h.size / 2.0
		h.position = Vector2(sin(a) * r, -cos(a) * r) - h.size / 2.0
		h.rotation = a
		h.color = Color(BLOOD if hit_kill else Color.WHITE, hk2)
	scope.visible = p.scoped
