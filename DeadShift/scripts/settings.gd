extends Node
## Player settings, high scores and unlocks, saved to user://deadshift.cfg

const PATH := "user://deadshift.cfg"
const UNLOCKS := [
	{"id": "revolver", "kind": "gun", "name": ".357 MAGNUM START", "need": "Reach wave 5", "wave": 5},
	{"id": "sawed", "kind": "gun", "name": "SAWED-OFF START", "need": "Reach wave 10", "wave": 10},
	{"id": "rotten", "kind": "skin", "name": "ROTTEN ZOMBIES", "need": "Reach wave 8", "wave": 8},
	{"id": "glow", "kind": "skin", "name": "RED-EYED ZOMBIES", "need": "Kill 250 zombies (all time)", "kills": 250},
]

var s := {
	"sens": 1.0, "fov": 72.0, "master": 0.85, "music": 0.7, "sfx": 1.0, "fullscreen": false,
	"pixel": 2, "physics": 1.0, "start_gun": "pistol", "skin": "normal", "invert_y": false, "pad_sens": 1.0, "aim_assist": 1.0, "pad_dead": 0.15,
}
var scores := {"best_wave": 0, "best_kills": 0, "best_points": 0, "total_kills": 0, "games": 0,
	"escapes": 0, "best_escape_points": 0, "fastest_escape": 0.0, "escape_wave": 0, "escaped_from": ""}

func _ready() -> void:
	load_all()

func load_all() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for k in s:
		s[k] = cf.get_value("settings", k, s[k])
	for k in scores:
		scores[k] = cf.get_value("scores", k, scores[k])

func save_all() -> void:
	var cf := ConfigFile.new()
	for k in s:
		cf.set_value("settings", k, s[k])
	for k in scores:
		cf.set_value("scores", k, scores[k])
	cf.save(PATH)

func unlocked(id: String) -> bool:
	if id == "pistol" or id == "normal":
		return true
	for u in UNLOCKS:
		if u.id == id:
			if u.has("wave"):
				return scores.best_wave >= u.wave
			if u.has("kills"):
				return scores.total_kills >= u.kills
	return false

## returns the unlocks this run just earned (for the game-over screen)
func record(wave: int, kills: int, points: int) -> Dictionary:
	var before := {}
	for u in UNLOCKS:
		before[u.id] = unlocked(u.id)
	var best: bool = wave > scores.best_wave
	scores.best_wave = maxi(scores.best_wave, wave)
	scores.best_kills = maxi(scores.best_kills, kills)
	scores.best_points = maxi(scores.best_points, points)
	scores.total_kills += kills
	scores.games += 1
	var fresh: Array = []
	for u in UNLOCKS:
		if not before[u.id] and unlocked(u.id):
			fresh.append(u.name)
	save_all()
	return {"best": best, "unlocks": fresh}

## an escape counts as a game, and gets its own badge and records (kept apart from best wave)
func record_escape(wave: int, kills: int, points: int, time: float, from_map: String) -> Dictionary:
	var rec := record(wave, kills, points)
	var first: bool = scores.escapes == 0
	var fastest: bool = scores.fastest_escape <= 0.0 or time < scores.fastest_escape
	scores.escapes += 1
	scores.best_escape_points = maxi(scores.best_escape_points, points)
	if fastest:
		scores.fastest_escape = time
		scores.escape_wave = wave
	scores.escaped_from = from_map      # where the bus left from (for linking maps later)
	save_all()
	rec["first_escape"] = first
	rec["fastest"] = fastest and not first
	return rec

## push the settings into the running game
func apply(main) -> void:
	var master := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master, linear_to_db(maxf(s.master, 0.001)))
	var mb := AudioServer.get_bus_index("Music")
	if mb >= 0:
		AudioServer.set_bus_volume_db(mb, linear_to_db(maxf(s.music, 0.001)) - 5.0)
	var sb := AudioServer.get_bus_index("SFX")
	if sb >= 0:
		AudioServer.set_bus_volume_db(sb, linear_to_db(maxf(s.sfx, 0.001)))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if s.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	if main:
		main.container.stretch_shrink = int(s.pixel)
		main.hud_box.stretch_shrink = clampi(int(s.pixel), 1, 2)
		if main.game and main.game.physics:
			main.game.physics.detail = s.physics
