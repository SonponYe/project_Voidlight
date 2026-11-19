extends Node2D
class_name NetMap
## The online arena's map: a ruined, war-torn district, built and drawn entirely
## in code — no texture files, so nothing can go missing in an export. All the
## grime is drawn from a fixed random seed, so every player sees the identical
## ruins. Characters in `layout`:
##   #  ruined wall       c  cover (sandbags or crates, picked per block)
##   v  vehicle wreck     B  barrel            .  floor
##   k  crater   d  rubble   x  scorch mark   (all three are floor decoration)
##   S  free-for-all spawn    1 / 2  team A / team B spawn   (floor)
## Walls, cover and wrecks are merged into the fewest rectangles; barrels are
## round. Each gets a collider (layer 1, what shots and line of sight test
## against) and a light occluder (so Blackout's glow casts real shadows).

const CELL := 64.0
const SOLID := "#cvB"
const MERGED := "#cv"

const BARREL_RADIUS := 24.0

# No "= []" here: an exported PackedStringArray with that initializer loses
# its saved value in an exported build (see the Maze fix).
@export var layout: PackedStringArray

var bounds := Rect2()
## [{"rect": Rect2, "kind": "#" | "c" | "v"}] — also what the minimap draws.
var blocks: Array = []
var barrels: Array = []  # Vector2 centers

var _width := 0
var _height := 0
var _spawns := {"S": [], "1": [], "2": []}
var _decor := {"k": [], "d": [], "x": []}


func _ready() -> void:
	_height = layout.size()
	for row in layout:
		_width = maxi(_width, row.length())
	bounds = Rect2(Vector2.ZERO, Vector2(_width, _height) * CELL)
	for y in _height:
		for x in _width:
			var c := _cell(x, y)
			var center := (Vector2(x, y) + Vector2(0.5, 0.5)) * CELL
			if _spawns.has(c):
				_spawns[c].append(center)
			elif _decor.has(c):
				_decor[c].append(center)
			elif c == "B":
				barrels.append(center)
	_merge_blocks()
	for block in blocks:
		_add_rect_body(block["rect"])
	for center in barrels:
		_add_barrel_body(center)
	_bake()
	queue_redraw()


## World positions of a spawn kind: "S" free-for-all, "1" team A, "2" team B.
func spawn_cells(kind: String) -> Array:
	return _spawns.get(kind, [])


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
			if kind not in MERGED or used.has(Vector2i(x, y)):
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
			blocks.append({"rect": Rect2(Vector2(x, y) * CELL, Vector2(w, h) * CELL), "kind": kind})


func _add_rect_body(rect: Rect2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var half := rect.size * 0.5
	var polygon := PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	_add_body(rect.get_center(), shape, polygon)


func _add_barrel_body(center: Vector2) -> void:
	var shape := CircleShape2D.new()
	shape.radius = BARREL_RADIUS + 2.0
	var polygon := PackedVector2Array()
	for i in 12:
		polygon.append(Vector2.from_angle(TAU * i / 12.0) * (BARREL_RADIUS + 2.0))
	_add_body(center, shape, polygon)


func _add_body(center: Vector2, shape: Shape2D, polygon: PackedVector2Array) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center
	body.add_to_group("walls")
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)
	var occluder := OccluderPolygon2D.new()
	occluder.polygon = polygon
	var light_occluder := LightOccluder2D.new()
	light_occluder.occluder = occluder
	body.add_child(light_occluder)
	add_child(body)


# ---------------------------------------------------------------------------
# Look
# ---------------------------------------------------------------------------
# The ruins are thousands of small shapes — far too many to redraw every frame
# on modest graphics hardware (it measured under 2 fps). The map never changes,
# so it is painted ONCE into a texture and shown as a single image.

func _bake() -> void:
	var painter := NetMapPainter.new()
	painter.setup(bounds, _width, _height, blocks, barrels, _decor, _spawns)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(bounds.size)
	viewport.transparent_bg = false
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.add_child(painter)
	add_child(viewport)
	var picture := Sprite2D.new()
	picture.centered = false
	picture.texture = viewport.get_texture()
	add_child(picture)


func _draw() -> void:
	# The ground beyond the building, behind the baked picture.
	draw_rect(Rect2(bounds.position - Vector2(1500, 1500), bounds.size + Vector2(3000, 3000)), Color(0.09, 0.08, 0.075))
