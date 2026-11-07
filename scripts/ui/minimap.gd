extends Control
## Minimap: maps world-space positions into this panel's local rect.
## Player dot = white, enemy dots = red, landmark dots (fireplaces, pickups)
## get their own colors. Also draws the maze's wall layout as small filled
## rects so the panel reads as an actual map, not just a blank panel with
## moving dots. Placeholder visuals (flat ColorRects) — swap for real
## art/UI later.

@export var world_bounds := Rect2(Vector2.ZERO, Vector2(1280, 720))
@export var dot_size := Vector2(7, 7)

@onready var player_dot: ColorRect = $PlayerDot

var _player: Node2D
var _enemy_dots: Dictionary = {}  # Enemy -> ColorRect
var _landmark_dots: Dictionary = {}  # Node2D -> ColorRect; auto-removed if the node is freed (pickups)


func setup(player: Node2D, monsters: Node, bounds: Rect2) -> void:
	_player = player
	world_bounds = bounds
	for enemy in monsters.get_children():
		register_enemy(enemy)


## Draws the maze's wall cells onto the panel so it actually looks like a
## map. Call this before register_enemy/register_landmark so the walls end
## up underneath every dot in the draw order (both are plain child nodes
## added in sequence — later children draw on top).
func draw_maze_layout(layout: PackedStringArray, cell_size: float) -> void:
	var cell_local_size := (Vector2(cell_size, cell_size) / world_bounds.size) * size
	for y in layout.size():
		var row: String = layout[y]
		for x in row.length():
			if row[x] != "#":
				continue
			var world_pos := Vector2(x, y) * cell_size
			var rect := ColorRect.new()
			rect.color = Color(0.5, 0.46, 0.4, 0.9)
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rect.size = cell_local_size
			rect.position = _world_to_local(world_pos)
			add_child(rect)


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
## fireplaces, pickups. Position is set once (these don't move); the dot
## disappears on its own once the node is freed (e.g. a pickup collected).
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

	for landmark in _landmark_dots.keys().duplicate():
		if not is_instance_valid(landmark):
			_landmark_dots[landmark].queue_free()
			_landmark_dots.erase(landmark)


func _world_to_local(world_pos: Vector2) -> Vector2:
	var t := (world_pos - world_bounds.position) / world_bounds.size
	t = t.clamp(Vector2.ZERO, Vector2.ONE)
	return t * size
