extends Enemy
class_name Lurker
## Teleports to a random nearby position every few seconds while AWARE
## (introduced Level 3). Unpredictable positioning — the deadliest type.

@export var teleport_interval := 4.0
@export var teleport_range := 160.0

var _teleport_timer := 0.0


func _process_aware(delta: float) -> void:
	super._process_aware(delta)
	_teleport_timer += delta
	if _teleport_timer >= teleport_interval:
		_teleport_timer = 0.0
		_teleport()


func _teleport() -> void:
	var angle := randf() * TAU
	var dist := randf_range(teleport_range * 0.4, teleport_range)
	global_position += Vector2.RIGHT.rotated(angle) * dist
