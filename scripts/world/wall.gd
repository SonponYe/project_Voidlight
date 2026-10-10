extends StaticBody2D
## Reusable wall block: set `size` in the Inspector and this builds its own
## collision shape, light occluder (for real flashlight shadows), and a flat
## placeholder visual — no per-wall scene editing or art needed yet.

@export var size := Vector2(64, 64):
	set(value):
		size = value
		_apply_size()

@onready var visual: Polygon2D = $Visual
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var occluder: LightOccluder2D = $LightOccluder2D


func _ready() -> void:
	add_to_group("walls")
	_apply_size()


func _apply_size() -> void:
	if not is_node_ready():
		return
	var half_v := size / 2.0
	visual.polygon = PackedVector2Array([
		Vector2(-half_v.x, -half_v.y), Vector2(half_v.x, -half_v.y),
		Vector2(half_v.x, half_v.y), Vector2(-half_v.x, half_v.y),
	])

	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape

	var half := size / 2.0
	var poly := PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	var occ_poly := OccluderPolygon2D.new()
	occ_poly.polygon = poly
	occ_poly.closed = true
	occluder.occluder = occ_poly
