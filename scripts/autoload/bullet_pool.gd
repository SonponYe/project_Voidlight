extends Node
## Pre-instantiated bullet pool — no runtime instantiate/free during play.
## Registered as the "BulletPool" autoload.

const BULLET_SCENE: PackedScene = preload("res://scenes/bullet/bullet.tscn")
const POOL_SIZE := 32

var _pool: Array[Node2D] = []
var _next := 0


func _ready() -> void:
	for _i in POOL_SIZE:
		var b: Node2D = BULLET_SCENE.instantiate()
		add_child(b)
		b.deactivate()
		_pool.append(b)


## Fire one bullet from the pool toward `direction` (normalized internally).
func spawn(global_pos: Vector2, direction: Vector2, damage: int = 1) -> void:
	var b: Node2D = _pool[_next]
	_next = (_next + 1) % _pool.size()
	b.activate(global_pos, direction, damage)
