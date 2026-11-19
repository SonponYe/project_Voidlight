extends Node2D
class_name NetMap
## The online arena's map, built and drawn entirely in code — no texture files,
## so nothing can go missing in an export. Characters in `layout`:
##   #  wall          c  cover block        .  floor
##   r  rug (floor)   o  floor vent (floor)
## Walls and cover are merged into the fewest rectangles; each gets a collider
## (layer 1, what shots and line of sight test against) and a light occluder
## (so Blackout's personal glow casts real shadows).

const CELL := 64.0
const SOLID := "#c"

const OUTSIDE := Color(0.27, 0.20, 0.16)
const FLOOR_COLOR := Color(0.87, 0.78, 0.60)
const GRID_COLOR := Color(0.0, 0.0, 0.0, 0.05)
const WALL_TOP := Color(0.63, 0.65, 0.70)
const WALL_SIDE := Color(0.37, 0.39, 0.45)
const WALL_EDGE := Color(0.20, 0.21, 0.25)
const COVER_TOP := Color(0.89, 0.62, 0.57)
const COVER_SIDE := Color(0.62, 0.40, 0.38)
const COVER_EDGE := Color(0.38, 0.24, 0.23)
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.22)
const EXTRUDE := 9.0
const SHADOW_OFFSET := Vector2(10.0, 13.0)

# No "= []" here: an exported PackedStringArray with that initializer loses
# its saved value in an exported build (see the Maze fix).
@export var layout: PackedStringArray

var bounds := Rect2()
var _blocks: Array = []  # [{"rect": Rect2, "cover": bool}]
var _width := 0
var _height := 0


func _ready() -> void:
	_height = layout.size()
	for row in layout:
		_width = maxi(_width, row.length())
	bounds = Rect2(Vector2.ZERO, Vector2(_width, _height) * CELL)
	_merge_blocks()
	for block in _blocks:
		_add_body(block["rect"])
	queue_redraw()


func _cell(x: int, y: int) -> String:
	if y < 0 or y >= _height or x < 0:
		return "#"
	var row: String = layout[y]
	return row[x] if x < row.length() else "."


## Greedy rectangle merge: grow right as far as the same kind continues, then
## down as long as the whole span matches.
func _merge_blocks() -> void:
	var used := {}
	for y in _height:
		for x in _width:
			var kind := _cell(x, y)
			if kind not in SOLID or used.has(Vector2i(x, y)):
				continue
			var w := 1
			while x + w < _width and _cell(x + w, y) == kind and not used.has(Vector2i(x + w, y)):
				w += 1
			var h := 1
			var grow := true
			while grow and y + h < _height:
				for dx in w:
					if _cell(x + dx, y + h) != kind or used.has(Vector2i(x + dx, y + h)):
						grow = false
						break
				if grow:
					h += 1
			for dy in h:
				for dx in w:
					used[Vector2i(x + dx, y + dy)] = true
			_blocks.append({
				"rect": Rect2(Vector2(x, y) * CELL, Vector2(w, h) * CELL),
				"cover": kind == "c",
			})


func _add_body(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = rect.get_center()
	body.add_to_group("walls")
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)
	var half := rect.size * 0.5
	var occluder := OccluderPolygon2D.new()
	occluder.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	var light_occluder := LightOccluder2D.new()
	light_occluder.occluder = occluder
	body.add_child(light_occluder)
	add_child(body)


func _draw() -> void:
	# Ground outside the building, then the floor.
	draw_rect(Rect2(bounds.position - Vector2(1500, 1500), bounds.size + Vector2(3000, 3000)), OUTSIDE)
	draw_rect(bounds, FLOOR_COLOR)

	for y in _height:
		for x in _width:
			var origin := Vector2(x, y) * CELL
			var shade := 0.965 + 0.07 * float(((x * 73856093) ^ (y * 19349663)) & 255) / 255.0
			draw_rect(Rect2(origin, Vector2(CELL, CELL)), Color(FLOOR_COLOR.r * shade, FLOOR_COLOR.g * shade, FLOOR_COLOR.b * shade))
			draw_rect(Rect2(origin, Vector2(CELL, CELL)), GRID_COLOR, false, 1.0)
			match _cell(x, y):
				"r":
					draw_rect(Rect2(origin + Vector2(7, 7), Vector2(CELL - 14, CELL - 14)), Color(0.60, 0.29, 0.27, 0.9))
					draw_rect(Rect2(origin + Vector2(13, 13), Vector2(CELL - 26, CELL - 26)), Color(0.90, 0.74, 0.40, 0.9), false, 2.0)
				"o":
					var c := origin + Vector2(CELL, CELL) * 0.5
					draw_circle(c, 25.0, Color(0.24, 0.25, 0.28))
					draw_arc(c, 25.0, 0.0, TAU, 28, Color(0.12, 0.12, 0.14), 2.0)
					for i in range(-3, 4):
						draw_line(c + Vector2(-17, i * 6.0), c + Vector2(17, i * 6.0), Color(0.45, 0.46, 0.5), 2.0)

	# Shadows first so no block's shadow paints over another block.
	for block in _blocks:
		draw_rect(Rect2(block["rect"].position + SHADOW_OFFSET, block["rect"].size), SHADOW_COLOR)
	for block in _blocks:
		var rect: Rect2 = block["rect"]
		var cover: bool = block["cover"]
		draw_rect(Rect2(rect.position + Vector2(0, EXTRUDE), rect.size), COVER_SIDE if cover else WALL_SIDE)
		draw_rect(rect, COVER_TOP if cover else WALL_TOP)
		draw_line(rect.position + Vector2(1, 1.5), rect.position + Vector2(rect.size.x - 1, 1.5), Color(1, 1, 1, 0.35), 2.0)
		draw_rect(rect, COVER_EDGE if cover else WALL_EDGE, false, 1.5)
