extends CanvasLayer
## Main menu (over a slow fly-through of the school), pause menu, settings, unlocks and records.

const INK := Color8(230, 220, 203)
const DIM := Color8(138, 130, 115)
const BLOOD := Color8(179, 18, 27)
const AMBER := Color8(217, 164, 65)

signal play_pressed

var main
var st                      # settings.gd
var display: FontFile
var mono: FontFile
var root: Control
var shade: ColorRect
var pages := {}
var page := ""
var in_game := false
var t := 0.0
var cam_t := 0.0
var focus_list: Array = []

func setup(m, settings) -> void:
	main = m
	st = settings
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	display = load("res://assets/fonts/BlackOpsOne-Regular.ttf")
	mono = load("res://assets/fonts/VT323-Regular.ttf")
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	shade = ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.55)
	root.add_child(shade)
	_build_main()
	_build_pause()
	_build_settings()
	_build_unlocks()
	nav_lbl = RichTextLabel.new()
	nav_lbl.bbcode_enabled = true
	nav_lbl.scroll_active = false
	nav_lbl.add_theme_font_override("normal_font", mono)
	nav_lbl.add_theme_font_size_override("normal_font_size", 26)
	nav_lbl.add_theme_color_override("default_color", Color8(138, 130, 115))
	nav_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav_lbl.anchor_left = 0.5
	nav_lbl.anchor_right = 1.0
	nav_lbl.anchor_top = 1.0
	nav_lbl.anchor_bottom = 1.0
	nav_lbl.offset_top = -46
	nav_lbl.offset_right = -30
	root.add_child(nav_lbl)
	visible = false

var nav_lbl: RichTextLabel
## "A select  B back" / "ENTER select  ESC back", following the last device used
func nav_hint() -> void:
	if nav_lbl == null or main.hud == null:
		return
	var t := "{select} select"
	if page != "main":
		t += "    {back} back"
	nav_lbl.text = "[right]" + main.hud.keys(t) + "[/right]"

# ---------------------------------------------------------------- widgets
func _label(parent: Control, text: String, f: Font, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 3)
	parent.add_child(l)
	return l

func _button(parent: Control, text: String, cb: Callable, disabled := false) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", display)
	b.add_theme_font_size_override("font_size", 34)
	b.add_theme_color_override("font_color", DIM if disabled else INK)
	b.add_theme_color_override("font_hover_color", BLOOD)
	b.add_theme_color_override("font_focus_color", BLOOD)
	b.add_theme_color_override("font_pressed_color", AMBER)
	b.add_theme_color_override("font_disabled_color", DIM)
	b.add_theme_color_override("font_outline_color", Color.BLACK)
	b.add_theme_constant_override("outline_size", 6)
	var empty := StyleBoxEmpty.new()
	for k in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(k, empty)
	b.disabled = disabled
	b.pressed.connect(func():
		main.audio.play("click", null, -6)
		cb.call())
	b.mouse_entered.connect(func(): b.grab_focus())
	b.focus_entered.connect(func(): main.audio.play("lclick", null, -14, 1.4))
	parent.add_child(b)
	return b

func _page(name: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.anchor_left = 0.0
	box.anchor_top = 0.0
	box.anchor_bottom = 1.0
	box.offset_left = 70
	box.offset_top = 70
	box.offset_right = 760
	box.offset_bottom = -40
	box.add_theme_constant_override("separation", 6)
	box.visible = false
	root.add_child(box)
	pages[name] = box
	return box

func _slider(parent: Control, text: String, key: String, lo: float, hi: float, step: float, fmt: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	parent.add_child(row)
	var l := _label(row, text, mono, 30, INK)
	l.custom_minimum_size = Vector2(250, 0)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = float(st.s[key])
	sl.custom_minimum_size = Vector2(260, 30)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sl)
	var v := _label(row, fmt % sl.value, mono, 30, AMBER)
	sl.value_changed.connect(func(x):
		st.s[key] = x
		v.text = fmt % x
		st.apply(main)
		main.on_settings_changed())

func _choice(parent: Control, text: String, key: String, opts: Array, names: Array, locked := []) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	parent.add_child(row)
	var l := _label(row, text, mono, 30, INK)
	l.custom_minimum_size = Vector2(250, 0)
	var b := Button.new()
	b.flat = true
	b.add_theme_font_override("font", mono)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", AMBER)
	b.add_theme_color_override("font_hover_color", BLOOD)
	b.add_theme_color_override("font_focus_color", BLOOD)
	var empty := StyleBoxEmpty.new()
	for k in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(k, empty)
	row.add_child(b)
	var refresh := func():
		var i := opts.find(st.s[key])
		b.text = "< " + names[maxi(i, 0)] + " >"
	refresh.call()
	b.pressed.connect(func():
		var i := opts.find(st.s[key])
		for k in opts.size():
			i = (i + 1) % opts.size()
			if not (opts[i] in locked) or st.unlocked(opts[i]):
				break
		st.s[key] = opts[i]
		refresh.call()
		main.audio.play("click", null, -6)
		st.apply(main)
		main.on_settings_changed())
	b.mouse_entered.connect(func(): b.grab_focus())

# ---------------------------------------------------------------- pages
var best_lbl: Label

func _build_main() -> void:
	var p := _page("main")
	var title := _label(p, "DEAD SHIFT", display, 78, BLOOD)
	title.rotation = deg_to_rad(-2)
	_label(p, "WESTFIELD HIGH", display, 36, INK)
	best_lbl = _label(p, "", mono, 26, AMBER)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 30)
	p.add_child(sp)
	_button(p, "PLAY", func(): play_pressed.emit())
	_button(p, "MAP: WESTFIELD HIGH", func(): pass)
	_button(p, "BUNKER 9 (COMING SOON)", func(): pass, true)
	_button(p, "LOADOUT & UNLOCKS", func(): show_page("unlocks"))
	_button(p, "SETTINGS", func(): show_page("settings"))
	_button(p, "QUIT", func(): get_tree().quit())

func _build_pause() -> void:
	var p := _page("pause")
	_label(p, "PAUSED", display, 70, BLOOD)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 20)
	p.add_child(sp)
	_button(p, "RESUME", func(): close())
	_button(p, "SETTINGS", func(): show_page("settings"))
	_button(p, "QUIT TO MENU", func():
		get_tree().paused = false
		Engine.set_meta("skip_menu", false)
		get_tree().reload_current_scene())
	_button(p, "QUIT GAME", func(): get_tree().quit())

func _build_settings() -> void:
	var p := _page("settings")
	_label(p, "SETTINGS", display, 60, BLOOD)
	_slider(p, "MOUSE SENSITIVITY", "sens", 0.2, 3.0, 0.05, "%.2f")
	_slider(p, "CONTROLLER LOOK", "pad_sens", 0.3, 2.5, 0.05, "%.2f")
	_choice(p, "AIM ASSIST", "aim_assist", [0.0, 0.5, 1.0, 1.4], ["OFF", "LOW", "NORMAL", "STRONG"])
	_slider(p, "STICK DEADZONE", "pad_dead", 0.03, 0.35, 0.01, "%.2f")
	_slider(p, "FIELD OF VIEW", "fov", 60, 100, 1, "%d")
	_slider(p, "MASTER VOLUME", "master", 0, 1, 0.05, "%.2f")
	_slider(p, "MUSIC VOLUME", "music", 0, 1, 0.05, "%.2f")
	_slider(p, "EFFECTS VOLUME", "sfx", 0, 1, 0.05, "%.2f")
	_choice(p, "PS2-NESS", "pixel", [1, 2, 3], ["CRISP", "PS2", "CRUNCHY"])
	_choice(p, "PHYSICS DETAIL", "physics", [0.5, 1.0], ["LOW", "NORMAL"])
	_choice(p, "INVERT LOOK Y", "invert_y", [false, true], ["OFF", "ON"])
	_choice(p, "FULLSCREEN", "fullscreen", [false, true], ["OFF", "ON"])
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 14)
	p.add_child(sp)
	_button(p, "BACK", func():
		st.save_all()
		show_page("pause" if in_game else "main"))

var unl_box: VBoxContainer

func _build_unlocks() -> void:
	var p := _page("unlocks")
	_label(p, "LOADOUT", display, 60, BLOOD)
	_choice(p, "STARTING GUN", "start_gun", ["pistol", "revolver", "sawed"], ["PISTOL", ".357 MAGNUM", "SAWED-OFF"], ["revolver", "sawed"])
	_choice(p, "ZOMBIES", "skin", ["normal", "rotten", "glow"], ["NORMAL", "ROTTEN", "RED-EYED"], ["rotten", "glow"])
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 14)
	p.add_child(sp)
	_label(p, "UNLOCKS", display, 40, INK)
	unl_box = VBoxContainer.new()
	p.add_child(unl_box)
	_button(p, "BACK", func():
		st.save_all()
		show_page("main"))

func _refresh() -> void:
	var sc: Dictionary = st.scores
	best_lbl.text = "BEST: WAVE %d   %d KILLS   %d POINTS" % [sc.best_wave, sc.best_kills, sc.best_points] if sc.games > 0 else "NO RECORDS YET"
	if int(sc.get("escapes", 0)) > 0:
		var ft: float = sc.get("fastest_escape", 0.0)
		best_lbl.text += "\n[ESCAPED x%d]  FASTEST %d:%02d" % [int(sc.escapes), int(ft) / 60, int(ft) % 60]
	for c in unl_box.get_children():
		c.queue_free()
	for u in st.UNLOCKS:
		var ok: bool = st.unlocked(u.id)
		_label(unl_box, ("[x] " if ok else "[ ] ") + u.name + ("" if ok else "  -  " + u.need), mono, 28, AMBER if ok else DIM)

# ---------------------------------------------------------------- flow
func show_page(name: String) -> void:
	page = name
	nav_hint()
	_refresh()
	for k in pages:
		pages[k].visible = k == name
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().process_frame
	for c in pages[name].get_children():
		if c is Button and not c.disabled:
			c.grab_focus()
			break
		if c is HBoxContainer:
			for cc in c.get_children():
				if cc is Range or cc is Button:
					cc.grab_focus()
					return

func open_main() -> void:
	in_game = false
	shade.color = Color(0, 0, 0, 0.35)
	show_page("main")

func open_pause() -> void:
	in_game = true
	shade.color = Color(0, 0, 0, 0.6)
	get_tree().paused = true
	show_page("pause")

func close() -> void:
	visible = false
	get_tree().paused = false
	st.save_all()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(e: InputEvent) -> void:
	if not visible or not (e.is_action_pressed("pause") or e.is_action_pressed("ui_cancel")):
		return
	if e.is_action_pressed("ui_cancel") and page == "main":
		return
	get_viewport().set_input_as_handled()
	if page == "pause":
		close()
	elif page == "settings":
		st.save_all()
		show_page("pause" if in_game else "main")
	elif page == "unlocks":
		show_page("main")

func _process(dt: float) -> void:
	if not visible or in_game:
		return
	# the menu background: a slow loop through the school
	cam_t += dt
	var cs = main.game.cutscene
	var path := [Vector3(-8, 15, 50), Vector3(8, 8, 44), Vector3(16, 3, 32), Vector3(0, 2.4, 22), Vector3(0, 2.4, 16), Vector3(0, 2.8, 6), Vector3(-8, 2.6, -3),
		Vector3(-14, 2.4, -7.25), Vector3(-28, 2.4, -7.25), Vector3(-40, 4, -4), Vector3(-50, 4.5, -2), Vector3(-46, 3, 8), Vector3(-40, 6, 20), Vector3(-25, 12, 40), Vector3(-8, 15, 50)]
	var k := fmod(cam_t / 70.0, 1.0)
	cs.cam.current = true
	cs.cam.fov = 66
	cs.cam.global_position = cs._catmull(path, k)
	cs.cam.look_at(cs._catmull(path, fmod(k + 0.02, 1.0)) + Vector3(0, -0.4, 0), Vector3.UP)
