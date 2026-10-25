extends Node2D
## Builds a maze from a text grid at scene load: '#' = wall (a Wall prefab —
## real collision + light occluder + art), anything else = walkable floor.
## 'E' marks the entrance and 'X' the exit purely as bookkeeping (both are
## still plain floor); read entrance_pos/exit_pos/bounds after _ready() to
## position the player, portal, and NavigationRegion2D outline.
##
## Two extra things beyond "one Wall prefab per '#' cell":
## - A merged collision rectangle per contiguous horizontal run of wall
##   cells, laid on top of the individual per-cell colliders. Many small
##   StaticBody2D rectangles placed edge-to-edge can let a fast-moving body
##   catch on the seam between them and tunnel through — a real, known
##   Godot/Box2D-style physics quirk, not just theoretical. The per-cell
##   colliders stay (for the art/occluder), this just removes the seams.
## - A sealed outer boundary a bit beyond the maze's own rectangle, so
##   walking out through the entrance/exit doorway doesn't mean walking
##   forever into the void — there's a small vestibule, then a hard wall.

const CELL := 64.0
const BOUNDARY_MARGIN := 64.0

const WALL_SCENE: PackedScene = preload("res://scenes/world/wall.tscn")
const FLOOR_TEXTURE: Texture2D = preload("res://assets/sprites/dungeon/tile.png")

@export var layout: PackedStringArray = []

var entrance_pos := Vector2.ZERO
var exit_pos := Vector2.ZERO
var bounds := Rect2()


func _ready() -> void:
	build()


func build() -> void:
	var height := layout.size()
	var width := 0
	for row in layout:
		width = max(width, row.length())

	for y in height:
		var row: String = layout[y]
		var run_start := -1

		# One extra iteration past the last column, always treated as "not a
		# wall", so a run touching the row's right edge still gets flushed.
		for x in width + 1:
			var is_wall := x < width and (row[x] if x < row.length() else ".") == "#"

			if is_wall and run_start == -1:
				run_start = x
			elif not is_wall and run_start != -1:
				_add_merged_wall_collider(run_start, x - 1, y)
				run_start = -1

			if x >= width:
				continue

			var c: String = row[x] if x < row.length() else "."
			var center := Vector2(x, y) * CELL + Vector2(CELL, CELL) * 0.5
			if is_wall:
				var w: Node2D = WALL_SCENE.instantiate()
				add_child(w)
				w.size = Vector2(CELL, CELL)
				w.position = center
			else:
				var floor_sprite := Sprite2D.new()
				floor_sprite.texture = FLOOR_TEXTURE
				floor_sprite.position = center
				floor_sprite.z_index = -1
				add_child(floor_sprite)
				if c == "E":
					entrance_pos = center
				elif c == "X":
					exit_pos = center

	bounds = Rect2(Vector2.ZERO, Vector2(width, height) * CELL)
	_build_outer_boundary(width, height)


## One invisible StaticBody2D spanning [x_start, x_end] on row y — collision
## only, no art/occluder (the per-cell Wall instances already provide those).
func _add_merged_wall_collider(x_start: int, x_end: int, y: int) -> void:
	var run_cells := x_end - x_start + 1
	var run_width := run_cells * CELL
	var center := Vector2(x_start * CELL + run_width * 0.5, y * CELL + CELL * 0.5)

	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center
	add_child(body)

	var shape := RectangleShape2D.new()
	shape.size = Vector2(run_width, CELL)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)


## A sealed frame outside the maze's own rectangle so there's a short
## vestibule past each doorway, then a hard stop instead of open void.
func _build_outer_boundary(width: int, height: int) -> void:
	var outer := Rect2(
		Vector2(-BOUNDARY_MARGIN, -BOUNDARY_MARGIN),
		Vector2(width, height) * CELL + Vector2(BOUNDARY_MARGIN, BOUNDARY_MARGIN) * 2.0
	)
	_add_boundary_strip(
		Vector2(outer.position.x + outer.size.x * 0.5, outer.position.y + BOUNDARY_MARGIN * 0.5),
		Vector2(outer.size.x, BOUNDARY_MARGIN)
	)
	_add_boundary_strip(
		Vector2(outer.position.x + outer.size.x * 0.5, outer.end.y - BOUNDARY_MARGIN * 0.5),
		Vector2(outer.size.x, BOUNDARY_MARGIN)
	)
	_add_boundary_strip(
		Vector2(outer.position.x + BOUNDARY_MARGIN * 0.5, outer.position.y + outer.size.y * 0.5),
		Vector2(BOUNDARY_MARGIN, outer.size.y)
	)
	_add_boundary_strip(
		Vector2(outer.end.x - BOUNDARY_MARGIN * 0.5, outer.position.y + outer.size.y * 0.5),
		Vector2(BOUNDARY_MARGIN, outer.size.y)
	)


func _add_boundary_strip(center: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center
	add_child(body)

	var shape := RectangleShape2D.new()
	shape.size = size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)
