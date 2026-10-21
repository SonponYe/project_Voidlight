extends Node2D
## Builds a maze from a text grid at scene load: '#' = wall (a Wall prefab —
## real collision + light occluder + art), anything else = walkable floor.
## 'E' marks the entrance and 'X' the exit purely as bookkeeping (both are
## still plain floor); read entrance_pos/exit_pos/bounds after _ready() to
## position the player, portal, and NavigationRegion2D outline.

const CELL := 64.0

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
		for x in width:
			var c: String = row[x] if x < row.length() else "."
			var center := Vector2(x, y) * CELL + Vector2(CELL, CELL) * 0.5
			if c == "#":
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
