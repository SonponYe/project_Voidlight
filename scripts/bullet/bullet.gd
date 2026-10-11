extends Area2D
## Pooled projectile. Travels straight, damages the first enemy it touches,
## and deactivates on contact with an enemy or a wall.

@export var speed := 640.0
@export var lifetime := 1.2

var _velocity := Vector2.ZERO
var _life := 0.0
var _damage := 1
var _active := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func activate(global_pos: Vector2, direction: Vector2, damage: int) -> void:
	global_position = global_pos
	rotation = direction.angle()
	_velocity = direction.normalized() * speed
	_life = 0.0
	_damage = damage
	_active = true
	visible = true
	set_physics_process(true)
	monitoring = true
	monitorable = true


## deactivate() can run from inside this Area2D's own body_entered signal
## (physics in/out flush), where toggling monitoring/monitorable directly is
## blocked by the engine — defer them so it's safe from any call site.
func deactivate() -> void:
	_active = false
	visible = false
	set_physics_process(false)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)


func _physics_process(delta: float) -> void:
	if not _active:
		return
	global_position += _velocity * delta
	_life += delta
	if _life >= lifetime:
		deactivate()


func _on_body_entered(body: Node) -> void:
	if not _active:
		return
	if body.is_in_group("enemies") and body.has_method("hit"):
		body.hit(_damage)
		deactivate()
	elif body.is_in_group("walls"):
		deactivate()
