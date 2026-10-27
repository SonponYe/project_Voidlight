extends Control
## Minimap: maps world-space positions into this panel's local rect.
## Player dot = white, enemy dots = red; a dot is removed when its enemy dies.
## Placeholder visuals (flat ColorRects) — swap for real art/UI later.

@export var world_bounds := Rect2(Vector2.ZERO, Vector2(1280, 720))
@export var dot_size := Vector2(7, 7)

@onready var player_dot: ColorRect = $PlayerDot

var _player: Node2D
var _enemy_dots: Dictionary = {}  # Enemy -> ColorRect
var _landmark_dots: Dictionary = {}  # Node2D -> ColorRect, static position, never removed


func setup(player: Node2D, monsters: Node, bounds: Rect2) -> void:
	_player = player
	world_bounds = bounds
	for enemy in monsters.get_children():
		register_enemy(enemy)


func register_enemy(enemy: Node) -> void:
	if not (enemy is Node2D) or not enemy.has_signal("killed"):
		return
	var dot := ColorRect.new()
	dot.color = Color(0.85, 0.15, 0.15, 1.0)
	dot.size = dot_size
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dot)
	_enemy_dots[enemy] = dot
	enemy.killed.connect(_on_enemy_killed)


## For things that aren't enemies but are still worth finding on the map —
## fireplaces, etc. Fixed position, fixed color, never removed.
func register_landmark(landmark: Node2D, color: Color) -> void:
	var dot := ColorRect.new()
	dot.color = color
	dot.size = dot_size
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dot)
	_landmark_dots[landmark] = dot
	dot.position = _world_to_local(landmark.global_position) - dot_size / 2.0


func _on_enemy_killed(enemy: Node) -> void:
	if _enemy_dots.has(enemy):
		_enemy_dots[enemy].queue_free()
		_enemy_dots.erase(enemy)


func _process(_delta: float) -> void:
	if not (_player and is_instance_valid(_player)):
		return

	# Light off == blind: no maze layout, no enemy positions, nothing.
	var light_on: bool = _player.is_light_on() if _player.has_method("is_light_on") else true
	visible = light_on
	if not light_on:
		return

	player_dot.position = _world_to_local(_player.global_position) - player_dot.size / 2.0
	for enemy in _enemy_dots.keys():
		if is_instance_valid(enemy):
			_enemy_dots[enemy].position = _world_to_local(enemy.global_position) - dot_size / 2.0


func _world_to_local(world_pos: Vector2) -> Vector2:
	var t := (world_pos - world_bounds.position) / world_bounds.size
	t = t.clamp(Vector2.ZERO, Vector2.ONE)
	return t * size
