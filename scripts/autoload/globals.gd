extends Node
## Persistent state across scenes. Registered as the "Globals" autoload.

const STARTING_AMMO := 12
const STARTING_HP := 3
const STARTING_LIGHTER_CHARGES := 3
const AMMO_PICKUP_AMOUNT := 6
const SAVE_PATH := "user://akira_save.save"
## The game's old name; read once so an existing high score survives the rename.
const LEGACY_SAVE_PATH := "user://voidlight_save.save"

## The 5 named superpowers (a 6th slot is reserved, not yet named) — one
## shared table so the lobby (power_select.gd) and the match (versus_
## manager.gd) always agree on what each power actually does. Keyed by the
## same effect name player.gd's apply_powerup()/_end_effect() switch on.
const POWER_DEFS := {
	"camouflage": {"label": "Camouflage", "duration": 6.0, "strength": 1.0, "cooldown": 14.0},
	"invincible": {"label": "Shield", "duration": 4.0, "strength": 1.0, "cooldown": 14.0},
	"decoy": {"label": "Decoy", "duration": 0.0, "strength": 1.0, "cooldown": 18.0},
	"damage_boost": {"label": "Heavy Gunner", "duration": 6.0, "strength": 2.0, "cooldown": 14.0},
	"blackout": {"label": "Blackout", "duration": 15.0, "strength": 1.0, "cooldown": 25.0},
}
const DEFAULT_POWER_P1 := "damage_boost"
const DEFAULT_POWER_P2 := "camouflage"

var current_level := 1
var player_hp := STARTING_HP
var ammo := STARTING_AMMO
var lighter_charges := STARTING_LIGHTER_CHARGES
var score := 0
var total_kills := 0
var high_score := 0

## Lobby selections (power_select.gd writes these; versus_manager.gd reads
## them when a match loads). match_mode is stored but doesn't change
## gameplay yet — team battles need 3+ players, which needs the real
## networking layer, not the current 2-player local arena.
var match_mode := "ffa"
var selected_power_p1 := DEFAULT_POWER_P1
var selected_power_p2 := DEFAULT_POWER_P2


func _ready() -> void:
	load_high_score()


func reset_run() -> void:
	current_level = 1
	player_hp = STARTING_HP
	ammo = STARTING_AMMO
	lighter_charges = STARTING_LIGHTER_CHARGES
	score = 0
	total_kills = 0


func begin_level() -> void:
	player_hp = STARTING_HP
	ammo = STARTING_AMMO
	lighter_charges = STARTING_LIGHTER_CHARGES


func register_score(points: int) -> void:
	score += points
	if score > high_score:
		high_score = score
		save_high_score()


func save_high_score() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_32(high_score)
		f.close()


func load_high_score() -> void:
	var path := SAVE_PATH if FileAccess.file_exists(SAVE_PATH) else LEGACY_SAVE_PATH
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f:
		high_score = f.get_32()
		f.close()
