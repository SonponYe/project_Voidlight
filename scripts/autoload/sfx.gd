extends Node
## Sound effects for the online game (autoload `Sfx`).
##
##   Sfx.play("ui_click")             heard the same everywhere (interface, your own Gens)
##   Sfx.play_at("shot", position)    heard from where it happened: louder when near,
##                                    panned left/right, silent when far
##
## The files are built from the CC0 sound packs by tools/build_sfx.py. A name in
## SOUNDS with a missing file is simply silent, so a bad path never breaks a
## match, and a dedicated server (which has no speakers) skips everything.
##
## To change how something sounds: swap its file names in SOUNDS, or tune `db`
## (volume, in decibels: -6 is half as loud) and `range` (how far away it can be
## heard, in pixels; the arena is about 2700 x 1800).

const DIR := "res://assets/audio/sfx/"
const BUS := "Sfx"
const SETTINGS_PATH := "user://akira_settings.cfg"

## "files": variants, one picked at random each time. "jitter": random pitch
## wobble so repeats don't sound identical. "range": hearing distance for play_at().
const SOUNDS := {
	"shot": {"files": ["shot_1", "shot_2", "shot_3"], "db": -3.0, "jitter": 0.06, "range": 1100.0},
	"impact": {"files": ["impact_1", "impact_2", "impact_3"], "db": -9.0, "jitter": 0.1, "range": 450.0},
	"hurt": {"files": ["hurt_1", "hurt_2", "hurt_3"], "db": -3.0, "jitter": 0.05, "range": 700.0},
	"hurt_me": {"files": ["hurt_3", "hurt_1"], "db": 0.0, "jitter": 0.03},
	"death": {"files": ["death"], "db": -1.0, "jitter": 0.04, "range": 900.0},
	"explosion": {"files": ["explosion"], "db": 0.0, "jitter": 0.04, "range": 1800.0},
	"bomb_place": {"files": ["bomb_place"], "db": -6.0},
	"shield_on": {"files": ["shield_on"], "db": -4.0},
	"shield_break": {"files": ["shield_break"], "db": -2.0, "range": 700.0},
	"camo_on": {"files": ["camo_on"], "db": -5.0},
	"camo_off": {"files": ["camo_off"], "db": -5.0},
	"haunt": {"files": ["haunt"], "db": -4.0},
	"decoy": {"files": ["decoy"], "db": -4.0},
	"blackout_on": {"files": ["blackout_on"], "db": -2.0},
	"blackout_off": {"files": ["blackout_off"], "db": -2.0},
	"start": {"files": ["start"], "db": -2.0},
	"win": {"files": ["win"], "db": -2.0},
	"defeat": {"files": ["defeat"], "db": -3.0},
	"ui_click": {"files": ["ui_click"], "db": -7.0, "jitter": 0.03},
	"ui_confirm": {"files": ["ui_confirm"], "db": -6.0},
	"ui_back": {"files": ["ui_back"], "db": -7.0},
	"step": {"files": ["step_1", "step_2", "step_3", "step_4"], "db": -9.0, "jitter": 0.08, "range": 330.0},
}

const AMBIENT_FILE := "ambient"
const AMBIENT_DB := -17.0
const RUMBLE_DB := -13.0
const RUMBLE_EVERY := Vector2(22.0, 50.0)  # seconds between far-off thuds

const POOL_2D := 20
const POOL_FLAT := 8
## The same sound is not restarted more often than this (seconds), so a burst of
## simultaneous events doesn't stack into a roar. Footsteps are exempt: many
## people walking at once is meant to be busy.
const MIN_REPEAT := 0.035

## 0..1, applied to the whole Sfx bus. Saved between sessions.
var volume := 1.0

var _streams := {}  # file name -> AudioStream
var _flat: Array[AudioStreamPlayer] = []
var _spatial: Array[AudioStreamPlayer2D] = []
var _next_flat := 0
var _next_spatial := 0
var _last_played := {}
var _silent := false
var _ambient: AudioStreamPlayer
var _rumble: AudioStreamPlayer
var _rumble_timer: Timer


func _ready() -> void:
	_silent = DisplayServer.get_name() == "headless"
	if _silent:
		return
	process_mode = Node.PROCESS_MODE_ALWAYS  # the pause menu is a UI overlay; sound carries on
	if AudioServer.get_bus_index(BUS) == -1:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, BUS)
		AudioServer.set_bus_send(index, "Master")
	_load_settings()
	_apply_volume()
	for i in POOL_FLAT:
		var player := AudioStreamPlayer.new()
		player.bus = BUS
		add_child(player)
		_flat.append(player)
	for i in POOL_2D:
		var player := AudioStreamPlayer2D.new()
		player.bus = BUS
		player.attenuation = 1.6
		player.panning_strength = 0.8
		add_child(player)
		_spatial.append(player)
	_ambient = AudioStreamPlayer.new()
	_ambient.bus = BUS
	_ambient.volume_db = AMBIENT_DB
	add_child(_ambient)
	_rumble = AudioStreamPlayer.new()
	_rumble.bus = BUS
	_rumble.volume_db = RUMBLE_DB
	add_child(_rumble)
	_rumble_timer = Timer.new()
	_rumble_timer.one_shot = true
	_rumble_timer.timeout.connect(_on_rumble_timer)
	add_child(_rumble_timer)
	# Every button in the game gets a click, without each scene having to ask.
	get_tree().node_added.connect(_on_node_added)


# ---------------------------------------------------------------------------
# Playing
# ---------------------------------------------------------------------------

func play(sound: String, extra_db := 0.0) -> void:
	var picked := _pick(sound)
	if picked.is_empty():
		return
	var player := _flat[_next_flat]
	_next_flat = (_next_flat + 1) % _flat.size()
	player.stream = picked["stream"]
	player.volume_db = float(picked["db"]) + extra_db
	player.pitch_scale = picked["pitch"]
	player.play()


func play_at(sound: String, at: Vector2, extra_db := 0.0) -> void:
	var picked := _pick(sound)
	if picked.is_empty():
		return
	var player := _spatial[_next_spatial]
	_next_spatial = (_next_spatial + 1) % _spatial.size()
	player.stream = picked["stream"]
	player.global_position = at
	player.max_distance = float(picked["range"])
	player.volume_db = float(picked["db"]) + extra_db
	player.pitch_scale = picked["pitch"]
	player.play()


## A footstep for something that just stepped at `at` — used by players and decoys.
func step_at(at: Vector2) -> void:
	play_at("step", at)


func _pick(sound: String) -> Dictionary:
	if _silent or not SOUNDS.has(sound):
		return {}
	var def: Dictionary = SOUNDS[sound]
	var now := Time.get_ticks_msec() / 1000.0
	if sound != "step" and now - float(_last_played.get(sound, -1.0)) < MIN_REPEAT:
		return {}
	var files: Array = def["files"]
	var stream := _stream(files[randi() % files.size()])
	if stream == null:
		return {}
	_last_played[sound] = now
	var jitter := float(def.get("jitter", 0.0))
	return {
		"stream": stream, "db": def.get("db", 0.0), "range": def.get("range", 1000.0),
		"pitch": 1.0 + randf_range(-jitter, jitter),
	}


func _stream(file: String) -> AudioStream:
	if _streams.has(file):
		return _streams[file]
	var path := DIR + file + ".ogg"
	var stream: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_streams[file] = stream
	return stream


# ---------------------------------------------------------------------------
# The world: a quiet wind bed and the odd far-off thud
# ---------------------------------------------------------------------------

func start_ambient() -> void:
	if _silent:
		return
	var bed := _stream(AMBIENT_FILE)
	if bed is AudioStreamOggVorbis:
		(bed as AudioStreamOggVorbis).loop = true
	if bed != null and not _ambient.playing:
		_ambient.stream = bed
		_ambient.play()
	_rumble_timer.start(randf_range(RUMBLE_EVERY.x, RUMBLE_EVERY.y))


func stop_ambient() -> void:
	if _silent:
		return
	_ambient.stop()
	_rumble.stop()
	_rumble_timer.stop()


func _on_rumble_timer() -> void:
	var stream := _stream("rumble")
	if stream != null:
		_rumble.stream = stream
		_rumble.pitch_scale = randf_range(0.85, 1.1)
		_rumble.play()
	_rumble_timer.start(randf_range(RUMBLE_EVERY.x, RUMBLE_EVERY.y))


# ---------------------------------------------------------------------------
# Interface clicks
# ---------------------------------------------------------------------------

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).pressed.connect(_on_button_pressed.bind(node))


func _on_button_pressed(button: BaseButton) -> void:
	var label := button.name.to_lower()
	if "start" in label or "host" in label or "connect" in label or "rematch" in label or "playagain" in label \
			or "retry" in label or "return" in label:
		play("ui_confirm")
	elif "back" in label or "leave" in label or "cancel" in label or "resume" in label or "quit" in label \
			or "menu" in label:
		play("ui_back")
	else:
		play("ui_click")


# ---------------------------------------------------------------------------
# Volume (a slider in the pause menu)
# ---------------------------------------------------------------------------

func set_volume(linear: float) -> void:
	volume = clampf(linear, 0.0, 1.0)
	_apply_volume()
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("audio", "volume", volume)
	config.save(SETTINGS_PATH)


func _apply_volume() -> void:
	var index := AudioServer.get_bus_index(BUS)
	if index == -1:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(index, volume <= 0.001)


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		volume = clampf(float(config.get_value("audio", "volume", 1.0)), 0.0, 1.0)
