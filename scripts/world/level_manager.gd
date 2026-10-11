extends Node2D
## Level manager (attached to a level's World root): tracks kill count and
## loads the next scene once the player reaches the exit.
##
## The goal is traversal, not extermination — enter the maze, get to the far
## side alive. require_all_kills_to_exit defaults off so the exit is open
## from the start; flip it per-level (e.g. a boss room) if a level should
## gate on clearing it instead.

@export var level_bounds := Rect2(Vector2.ZERO, Vector2(1280, 720))
@export var require_all_kills_to_exit := false
@export_file("*.tscn") var next_level_path := ""
@export_file("*.tscn") var win_screen_path := "res://scenes/ui/win_screen.tscn"
@export_file("*.tscn") var game_over_path := "res://scenes/ui/game_over.tscn"

@onready var player: Node2D = $Player
@onready var monsters: Node2D = $Monsters
@onready var hud: CanvasLayer = $HUD
@onready var exit_portal: Area2D = $ExitPortal
@onready var ambient_drone: AudioStreamPlayer = get_node_or_null("AmbientDrone")

var _total_monsters := 0
var _kills := 0


func _ready() -> void:
	Globals.begin_level()
	_total_monsters = monsters.get_child_count()

	for enemy in monsters.get_children():
		if enemy.has_signal("killed"):
			enemy.killed.connect(_on_enemy_killed)

	if player.has_signal("hp_changed"):
		player.hp_changed.connect(hud.on_hp_changed)
	if player.has_signal("ammo_changed"):
		player.ammo_changed.connect(hud.on_ammo_changed)
	if player.has_signal("died"):
		player.died.connect(_on_player_died)

	hud.set_total_monsters(_total_monsters)
	hud.minimap.setup(player, monsters, level_bounds)

	exit_portal.body_entered.connect(_on_exit_entered)
	exit_portal.monitoring = not require_all_kills_to_exit


func _process(_delta: float) -> void:
	if ambient_drone == null or ambient_drone.stream == null:
		return
	var nearest := _nearest_enemy_distance()
	if nearest < INF:
		var t: float = clamp(1.0 - nearest / 600.0, 0.0, 1.0)
		ambient_drone.pitch_scale = lerp(0.9, 1.4, t)


func _nearest_enemy_distance() -> float:
	var nearest := INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var d: float = player.global_position.distance_to(enemy.global_position)
		if d < nearest:
			nearest = d
	return nearest


func _on_enemy_killed(_enemy: Node) -> void:
	_kills += 1
	Globals.total_kills += 1
	hud.on_kill_registered(_kills)
	if require_all_kills_to_exit and _kills >= _total_monsters:
		_unlock_exit()


func _unlock_exit() -> void:
	exit_portal.set_deferred("monitoring", true)


# _on_exit_entered and _on_player_died both run nested inside a physics
# body_entered callback (exit portal's own, or the enemy HitArea -> player ->
# died chain). change_scene_to_file() frees the whole current scene tree,
# including CollisionObject2D nodes, which the engine blocks while still
# inside that physics in/out flush — so the actual scene change is deferred.
func _on_exit_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if next_level_path.is_empty():
		get_tree().call_deferred("change_scene_to_file", win_screen_path)
	else:
		Globals.current_level += 1
		get_tree().call_deferred("change_scene_to_file", next_level_path)


func _on_player_died() -> void:
	get_tree().call_deferred("change_scene_to_file", game_over_path)
