extends Camera2D
## Shared camera for local multiplayer: both players have owns_camera = false
## (their own Camera2D disabled), and this one frames all of them instead —
## sits at their midpoint, zooms out as they spread apart so neither drops
## off-screen.

@export var targets: Array[Node2D] = []
@export var min_zoom := 1.0
@export var max_zoom := 2.2
@export var padding := 220.0  ## World units from center before zooming out starts.
@export var zoom_lerp_speed := 4.0

var _target_zoom := 1.0


func _ready() -> void:
	current = true


func _process(delta: float) -> void:
	var alive: Array[Node2D] = []
	for t in targets:
		if is_instance_valid(t):
			alive.append(t)
	if alive.is_empty():
		return

	var center := Vector2.ZERO
	for t in alive:
		center += t.global_position
	center /= alive.size()
	global_position = center

	var max_dist := 0.0
	for t in alive:
		max_dist = max(max_dist, t.global_position.distance_to(center))
	var needed_zoom: float = clamp(max_dist / padding, min_zoom, max_zoom)
	_target_zoom = needed_zoom
	var z: float = lerp(zoom.x, 1.0 / _target_zoom, clamp(zoom_lerp_speed * delta, 0.0, 1.0))
	zoom = Vector2(z, z)
