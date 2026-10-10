extends Node
## The web game's own sounds (rendered to .ogg) and music loops.

var world_root: Node3D
var cache := {}
var music_a: AudioStreamPlayer
var amb: AudioStreamPlayer
var current := ""
var lowpass: AudioEffectLowPassFilter
var music_bus := 0
var on_track: Callable

func _ready() -> void:
	AudioServer.add_bus()
	music_bus = AudioServer.bus_count - 1
	AudioServer.set_bus_name(music_bus, "Music")
	AudioServer.set_bus_send(music_bus, "Master")
	lowpass = AudioEffectLowPassFilter.new()
	lowpass.cutoff_hz = 20000
	AudioServer.add_bus_effect(music_bus, lowpass)
	AudioServer.set_bus_volume_db(music_bus, -5.0)
	AudioServer.add_bus()
	var sb := AudioServer.bus_count - 1
	AudioServer.set_bus_name(sb, "SFX")
	AudioServer.set_bus_send(sb, "Master")
	music_a = AudioStreamPlayer.new()
	music_a.bus = "Music"
	music_a.volume_db = -60
	add_child(music_a)
	amb = AudioStreamPlayer.new()
	amb.bus = "SFX"
	amb.volume_db = -60
	add_child(amb)

func stream(name: String) -> AudioStream:
	if cache.has(name):
		return cache[name]
	var p := "res://assets/audio/sfx/%s.ogg" % name
	var s: AudioStream = load(p) if ResourceLoader.exists(p) else null
	cache[name] = s
	return s

# Voice limiting. A machine gun fires every 0.065 s but its shot sample rings for 1.5-2.5 s, so dozens of
# copies of the same sound used to stack up a few % apart in pitch: that phasing was the "feedback" whine.
# Each sound now gets a few voices; when a new one starts the oldest is faded out quickly.
var voices := {}      # name -> Array of players, oldest first
func _cap(name: String) -> int:
	if name.begins_with("shot_"):
		return 2
	match name:
		"hitmark", "killmark", "crackle", "lowAmmo":
			return 1
		"hit", "head", "casing", "ric", "tink", "splat", "wood", "clang", "chip", "pstep", "step", "thud":
			return 4
	return 6

func _claim(name: String, p: Node) -> void:
	var lst: Array = voices.get(name, [])
	lst = lst.filter(func(v): return is_instance_valid(v) and v.playing)
	var cap := _cap(name)
	while lst.size() >= cap:
		var old = lst.pop_front()
		var tw: Tween = old.create_tween()
		tw.tween_property(old, "volume_db", -60.0, 0.05)
		tw.tween_callback(old.queue_free)
	lst.append(p)
	voices[name] = lst

## 2D when pos is null, positional otherwise
func play(name: String, pos = null, vol_db := 0.0, pitch := 1.0) -> void:
	var s := stream(name)
	if s == null:
		return
	if pos == null or world_root == null:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.stream = s
		p.volume_db = vol_db
		p.pitch_scale = pitch * randf_range(0.97, 1.03)
		add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
		_claim(name, p)
	else:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "SFX"
		p3.stream = s
		p3.volume_db = vol_db
		p3.unit_size = 6.0
		p3.max_distance = 70.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.pitch_scale = pitch * randf_range(0.97, 1.03)
		world_root.add_child(p3)
		p3.global_position = pos
		p3.play()
		p3.finished.connect(p3.queue_free)
		_claim(name, p3)

func _loop(name: String) -> AudioStream:
	var s = load("res://assets/audio/music/%s.ogg" % name)
	if s is AudioStreamOggVorbis:
		s.loop = true
	return s

func start_ambience() -> void:
	amb.stream = _loop("ambience")
	amb.play()
	create_tween().tween_property(amb, "volume_db", -6.0, 3.0)

func set_track(name: String) -> void:
	if name == current:
		return
	current = name
	var tw := create_tween()
	tw.tween_property(music_a, "volume_db", -60.0, 1.2)
	tw.tween_callback(func():
		if current != name:
			return
		if name == "":
			music_a.stop()
			return
		music_a.stream = _loop(name)
		music_a.play()
		create_tween().tween_property(music_a, "volume_db", 0.0, 0.6)
		if on_track.is_valid():
			on_track.call(name))

## between rounds the music sinks behind a wall, like the web game
func set_calm(calm: bool) -> void:
	var want := 900.0 if calm else 20000.0
	if absf(lowpass.cutoff_hz - want) > 1.0:
		create_tween().tween_property(lowpass, "cutoff_hz", want, 1.0 if calm else 0.4)
