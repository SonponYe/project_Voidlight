extends Node
## Persistent state across scenes. Registered as the "Globals" autoload.

const STARTING_AMMO := 12
const STARTING_HP := 3
const STARTING_LIGHTER_CHARGES := 3
const AMMO_PICKUP_AMOUNT := 6
const SAVE_PATH := "user://voidlight_save.save"

var current_level := 1
var player_hp := STARTING_HP
var ammo := STARTING_AMMO
var lighter_charges := STARTING_LIGHTER_CHARGES
var score := 0
var total_kills := 0
var high_score := 0


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
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f:
		high_score = f.get_32()
		f.close()
